// `@DVMeter` declarations become the typed `Meters` accessors, and a meter
// recorded from client-reachable code stops the build (DV-METER-001).
//
// A meter named by a string can be misspelt, and a misspelt meter does not
// throw: it is a second meter that counts and that nobody bills. So the
// generated surface is compiled and run here, not read as text. And a usage
// number recorded by the client is a number the customer controls, so that
// is refused before anything ships.
// Each probe compiles a program against dartvel_core, which takes tens of
// seconds on a loaded machine.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:dartvel_cli/src/generators/meter_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String declared = '''
import 'package:dartvel_core/dartvel.dart';

abstract class _Meters {
  /// Calls to the public API.
  @DVMeter(
    unit: 'call',
    limit: DVLimit.fixed(3),
    atLimit: DVQuota.block,
    notifyAt: <double>[0.8, 1.0],
  )
  static const apiCalls = DVMeter.counter;

  @DVMeter(unit: 'GB-month', gaugeBilling: DVGaugeBilling.peak)
  static const DVMeterKind storedBytes = DVMeter.gauge;

  @DVMeter(unit: 'token', grace: Duration(hours: 6))
  static const aiTokens = DVMeter.counter;
}
''';

/// A project under a fresh temporary directory with [files] (relative path
/// to contents) written into it.
Directory project(Map<String, String> files) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_meter_test_');
  files.forEach((String relative, String contents) {
    final File file = File(p.joinAll(<String>[root.path, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return root;
}

Future<void> generate(Directory root) => MeterGenerator.generate(
      root: root.path,
      pkgName: 'meter_app',
      backendDir: 'lib/backend',
    );

/// Compiles and runs [main] beside the generated `meters.g.dart`, inside this
/// package so `package:dartvel_core` resolves, and returns what it printed.
Future<String> runBeside(String generated, String main) async {
  final Directory probe = Directory(p.join(
      Directory.current.path, '.dart_tool', 'dv_meter_probe_$pid'))
    ..createSync(recursive: true);
  try {
    File(p.join(probe.path, 'meters.g.dart')).writeAsStringSync(generated);
    File(p.join(probe.path, 'main.dart')).writeAsStringSync(main);
    final ProcessResult result = await Process.run(
        Platform.resolvedExecutable, <String>[p.join(probe.path, 'main.dart')]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return '${result.stdout}'.trim();
  } finally {
    probe.deleteSync(recursive: true);
  }
}

void main() {
  test('each declared meter becomes a definition that records', () async {
    final Directory root = project(<String, String>{'lib/meters.dart': declared});
    try {
      await generate(root);
      final String generated = File(
              p.join(root.path, 'lib', 'dartvel_client', 'meters.g.dart'))
          .readAsStringSync();

      final String printed = await runBeside(generated, r'''
import 'package:dartvel_core/dartvel.dart';
import 'meters.g.dart';

Future<void> main() async {
  for (final DVMeterDefinition m in Meters.all) {
    print('${m.name} ${m.unit} ${m.kind.name} ${m.limit} ${m.atLimit?.name} '
        '${m.notifyAt} ${m.grace} ${m.gaugeBilling.name}');
  }
  DVMeters.configure(DVMeters(store: DVMemoryMeterStore()));
  for (int call = 1; call <= 4; call++) {
    final DVMeterOutcome outcome =
        await Meters.apiCalls.record(1, idempotencyKey: 'req-$call');
    print('call $call admitted=${outcome.admitted}');
  }
}
''');
      expect(printed.split('\n'), <String>[
        'apiCalls call counter DVLimit.fixed(3) block [0.8, 1.0] null average',
        'storedBytes GB-month gauge null null [] null peak',
        'aiTokens token counter null null [] 6:00:00.000000 average',
        'call 1 admitted=true',
        'call 2 admitted=true',
        'call 3 admitted=true',
        'call 4 admitted=false',
      ]);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a project with no meters still gets an empty Meters', () async {
    final Directory root = project(<String, String>{'lib/main.dart': 'void main() {}\n'});
    try {
      await generate(root);
      final String printed = await runBeside(
        File(p.join(root.path, 'lib', 'dartvel_client', 'meters.g.dart'))
            .readAsStringSync(),
        "import 'meters.g.dart';\nvoid main() => print(Meters.all.length);\n",
      );
      expect(printed, '0');
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a limit with no behaviour at it stops the build (DV-METER-005)',
      () async {
    final Directory root = project(<String, String>{
      'lib/meters.dart': '''
import 'package:dartvel_core/dartvel.dart';
abstract class _Meters {
  @DVMeter(unit: 'call', limit: DVLimit.entitlement)
  static const apiCalls = DVMeter.counter;
}
''',
    });
    try {
      await expectLater(
        generate(root),
        throwsA(isA<StateError>().having(
            (StateError e) => e.message, 'message', contains('DV-METER-005'))),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a meter declared in a public class is refused', () async {
    final Directory root = project(<String, String>{
      'lib/meters.dart': declared.replaceFirst('class _Meters', 'class Meters'),
    });
    try {
      await expectLater(generate(root), throwsStateError);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a meter declared twice is refused', () async {
    final Directory root = project(<String, String>{
      'lib/meters.dart': declared,
      'lib/more_meters.dart': declared.replaceFirst('_Meters', '_MoreMeters'),
    });
    try {
      await expectLater(generate(root), throwsStateError);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  group('DV-METER-001', () {
    const String backendUse = '''
import 'package:meter_app/dartvel_client/dartvel_client.dart';
Future<void> charge() async {
  await Meters.apiCalls.record(1);
}
''';

    test('recording from the backend is the arrangement working', () async {
      final Directory root = project(<String, String>{
        'lib/meters.dart': declared,
        'lib/backend/functions/charge.post.dart': backendUse,
      });
      try {
        await generate(root);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('recording from a page stops the build, naming the file and line',
        () async {
      final Directory root = project(<String, String>{
        'lib/meters.dart': declared,
        'lib/pages/index.dart': '''
import 'package:meter_app/dartvel_client/dartvel_client.dart';

// Meters.apiCalls.record(1) in a comment is not a recording.
const String help = 'Meters.apiCalls.record(1)';

Future<void> onTap() async {
  await Meters.aiTokens
      .record(40);
}
''',
      });
      try {
        await expectLater(
          generate(root),
          throwsA(isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('DV-METER-001'), contains('lib/pages/index.dart:7'),
                contains('aiTokens'), isNot(contains('apiCalls'))),
          )),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('recording through the runtime directly is caught too', () async {
      final Directory root = project(<String, String>{
        'lib/meters.dart': declared,
        'lib/components/counter.dart': '''
import 'package:dartvel_core/dartvel.dart';
Future<void> bump(DVMeterDefinition meter) =>
    DVMeters.current.record(meter, 1, idempotencyKey: 'x');
''',
      });
      try {
        await expectLater(
          generate(root),
          throwsA(isA<StateError>().having((StateError e) => e.message,
              'message', contains('lib/components/counter.dart:3'))),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}
