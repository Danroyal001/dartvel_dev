// `dartvel compatibility-check` holds the build's protocol against the clients
// an environment actually serves.
//
// Protocol Versioning and Client Compatibility: the candidate's window is
// compared with the live client histogram, and the deploy is refused when a
// version outside the window carries more than `protocol.strandThreshold` of
// the last seven days' sessions. An override takes an explicit reason and is
// logged with the histogram it overrode.
//
// The failures worth testing are the ones that pass quietly: a project with no
// recorded protocol reported as compatible, a hand-edited lockfile trusted, a
// missing histogram read as nobody stranded, and an override that leaves no
// record.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/compatibility_check_command.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVProtocolContract, DVProtocolField, DVProtocolLock, DVProtocolModel;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final DateTime now = DateTime.utc(2026, 9, 16, 12);

DVProtocolModel model(String name) => DVProtocolModel(
  name,
  const <DVProtocolField>[DVProtocolField('id', 'String')],
);

/// Three versions, each adding a model, which an old client never calls.
DVProtocolLock lock({bool lossy = false}) {
  final DVProtocolContract v1 = DVProtocolContract(
    models: <DVProtocolModel>[model('User')],
  );
  final DVProtocolContract v2 = DVProtocolContract(
    models: <DVProtocolModel>[model('User'), model('Order')],
  );
  // Dropping User is a change an adapter may not make on an old client's
  // behalf without a declared adapter.
  final DVProtocolContract v3 = DVProtocolContract(
    models: <DVProtocolModel>[
      if (!lossy) model('User'),
      model('Order'),
      model('Invoice'),
    ],
  );
  return const DVProtocolLock(<Never>[])
      .bump(v1, at: DateTime.utc(2026, 1, 1))
      .bump(v2, at: DateTime.utc(2026, 2, 1))
      .bump(v3, at: DateTime.utc(2026, 3, 1));
}

void main() {
  late Directory root;
  late List<String> out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_compat_check_');
    out = <String>[];
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String rel, String content) {
    File(p.join(root.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// A window of the current version and one before it, with no age floor
  /// long enough to keep protocol 1.
  void project({DVProtocolLock? recorded}) {
    write(
      'pubspec.yaml',
      'name: shop\n'
          'dartvel:\n'
          '  protocol:\n'
          '    window: 1\n'
          '    minimumAge: 1d\n',
    );
    if (recorded != null) {
      write(DVProtocolLock.fileName, recorded.encode());
    }
  }

  String histogram(Map<int, int> sessions, {int daysAgo = 1}) {
    final DateTime day = now.subtract(Duration(days: daysAgo));
    final String date = day.toIso8601String().substring(0, 10);
    return jsonEncode(<String, Object?>{
      'samples': <Object?>[
        for (final MapEntry<int, int> e in sessions.entries)
          <String, Object?>{
            'protocol': e.key,
            'day': date,
            'sessions': e.value,
          },
      ],
    });
  }

  Future<int> run({
    String? against,
    String? histogramFile,
    String? overrideReason,
  }) => dvRunCompatibilityCheck(
    root.path,
    against: against,
    histogramPath: histogramFile,
    overrideReason: overrideReason,
    now: now,
    out: out.add,
  );

  Map<String, String> snapshot() => <String, String>{
    for (final FileSystemEntity e in root.listSync(
      recursive: true,
      followLinks: false,
    ))
      if (e is File) p.relative(e.path, from: root.path): e.readAsStringSync(),
  };

  group('the build on its own', () {
    test('reports the protocol and what each served version gets', () async {
      project(recorded: lock());
      expect(await run(), 0);
      final String printed = out.join('\n');
      expect(printed, contains('protocol 3'));
      expect(printed, contains('protocol 2: degraded'));
      expect(
        printed,
        isNot(contains('protocol 1:')),
        reason: 'protocol 1 is outside a window of one version and a day',
      );
    });

    test('no recorded protocol is refused, not passed', () async {
      project();
      expect(await run(), 1);
      expect(out.join('\n'), contains(DVProtocolLock.fileName));
    });

    test('a hand-edited lockfile is refused', () async {
      project(recorded: lock());
      final File file = File(p.join(root.path, DVProtocolLock.fileName));
      final Map<String, Object?> json =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      ((json['releases']! as List<Object?>).last
              as Map<String, Object?>)['shape'] =
          '00000000';
      file.writeAsStringSync(jsonEncode(json));
      expect(await run(), 1);
      expect(out.join('\n'), contains('records shape 00000000'));
    });

    test('a lossy change inside the window fails with DV-PROTO-004', () async {
      project(recorded: lock(lossy: true));
      expect(await run(), 1);
      expect(out.join('\n'), contains('DV-PROTO-004'));
      expect(out.join('\n'), contains('User'));
    });

    test('an unreadable protocol config is refused, not defaulted', () async {
      project(recorded: lock());
      write(
        'pubspec.yaml',
        'name: shop\ndartvel:\n  protocol:\n    minimumAge: soon\n',
      );
      expect(await run(), 1);
      expect(out.join('\n'), contains('minimumAge'));
    });
  });

  group('--against an environment', () {
    test(
      'without a histogram it refuses and says where one comes from',
      () async {
        project(recorded: lock());
        expect(await run(against: 'production'), 1);
        final String printed = out.join('\n');
        expect(printed, contains('production'));
        expect(printed, contains('--histogram'));
      },
    );

    test(
      'refuses a deploy that strands a version above the threshold',
      () async {
        project(recorded: lock());
        write('h.json', histogram(<int, int>{1: 10, 3: 990}));
        expect(await run(against: 'production', histogramFile: 'h.json'), 1);
        final String printed = out.join('\n');
        expect(printed, contains('DV-PROTO-005'));
        expect(printed, contains('protocol 1 carries 1.00%'));
      },
    );

    test(
      'passes when what is outside the window is under the threshold',
      () async {
        project(recorded: lock());
        write('h.json', histogram(<int, int>{1: 2, 2: 100, 3: 898}));
        final Map<String, String> before = snapshot();
        expect(await run(against: 'production', histogramFile: 'h.json'), 0);
        expect(snapshot(), before, reason: 'a passing check writes nothing');
        expect(out.join('\n'), contains('production'));
      },
    );

    test(
      'a histogram with no sessions in the last seven days is refused',
      () async {
        project(recorded: lock());
        write('h.json', histogram(<int, int>{3: 1000}, daysAgo: 30));
        expect(await run(against: 'production', histogramFile: 'h.json'), 1);
        expect(out.join('\n'), contains('no client sessions'));
      },
    );

    test(
      'an override lets it through and is logged with the histogram',
      () async {
        project(recorded: lock());
        write('h.json', histogram(<int, int>{1: 10, 3: 990}));
        expect(
          await run(
            against: 'production',
            histogramFile: 'h.json',
            overrideReason: 'protocol 1 is the recalled 2.1 build',
          ),
          0,
        );
        expect(
          out.join('\n'),
          contains('protocol 1 is the recalled 2.1 build'),
        );
        final File log = File(
          p.join(root.path, '.dartvel', 'compatibility-overrides.jsonl'),
        );
        expect(log.existsSync(), isTrue);
        final Map<String, Object?> record =
            jsonDecode(log.readAsLinesSync().single) as Map<String, Object?>;
        expect(record['environment'], 'production');
        expect(record['override'], 'protocol 1 is the recalled 2.1 build');
        expect(record['histogram'], <String, Object?>{'1': 10, '3': 990});
      },
    );

    test('a blank override is not a reason', () async {
      project(recorded: lock());
      write('h.json', histogram(<int, int>{1: 10, 3: 990}));
      expect(
        await run(
          against: 'production',
          histogramFile: 'h.json',
          overrideReason: '   ',
        ),
        1,
      );
      expect(
        File(
          p.join(root.path, '.dartvel', 'compatibility-overrides.jsonl'),
        ).existsSync(),
        isFalse,
      );
    });

    test('a histogram that cannot be read is refused by name', () async {
      project(recorded: lock());
      write('h.json', '{"samples": [{"protocol": "3", "day": "x"}]}');
      expect(await run(against: 'production', histogramFile: 'h.json'), 1);
      expect(out.join('\n'), contains('h.json'));
    });
  });

  test('the command takes --against, --histogram and --override', () {
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 't')
      ..addCommand(CompatibilityCheckCommand());
    final Command<void> command = runner.commands['compatibility-check']!;
    expect(
      command.argParser.options.keys,
      containsAll(<String>['against', 'histogram', 'override']),
    );
  });
}
