// `dartvel analyze performance`.
//
// The specification has it aggregating window degradations per call site so
// a site that always degrades is one finding, not a thousand log lines. The
// running application publishes its measurements beside its live window
// list; this reads them while they are fresh and says otherwise when they
// are not, rather than reporting a stopped app's last numbers as live.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/analyze_command.dart';
import 'package:dartvel_core/dartvel.dart' show dvLiveWindowsPathFor;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> runAnalyze(List<String> args, Directory root) async {
  final Directory previous = Directory.current;
  Directory.current = root;
  final StringBuffer out = StringBuffer();
  try {
    await runZoned(
      () async {
        final CommandRunner<void> runner =
            CommandRunner<void>('dartvel', 'Test runner')..addCommand(AnalyzeCommand());
        await runner.run(<String>['analyze', ...args]);
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone _, ZoneDelegate __, Zone ___, String line) => out.writeln(line),
      ),
    );
  } finally {
    Directory.current = previous;
  }
  return out.toString();
}

Directory project() {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_analyze_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: analyze_app\n');
  return root;
}

String live(DateTime at) => jsonEncode(<String, Object?>{
      'app': 'analyze_app',
      'at': at.toUtc().toIso8601String(),
      'windows': <Object?>[],
      'performance': <String, Object?>{
        'opens': <Object?>[
          <String, Object?>{'route': '/orders', 'virtual': true, 'micros': 1200, 'code': 'DV-WINDOW-001'},
          <String, Object?>{'route': '/stock', 'virtual': false, 'micros': 8000},
        ],
        'tearOuts': <Object?>[
          <String, Object?>{'route': '/stock', 'micros': 15000},
        ],
        'restores': <Object?>[
          <String, Object?>{'name': 'main', 'tabs': 3, 'micros': 640000},
        ],
        'ownedCloses': <Object?>[],
        'degradations': <String, Object?>{
          '/orders': <String, Object?>{'opens': 3, 'degraded': 3, 'codes': <String, Object?>{'DV-WINDOW-001': 3}},
          '/stock': <String, Object?>{'opens': 2, 'degraded': 0, 'codes': <String, Object?>{}},
        },
        'store': <String, Object?>{
          'writes': 40,
          'flushes': 8,
          'coalescingRatio': 0.8,
          'sizeBytes': 2048,
          'spills': 1,
          'burstWrites': <String, Object?>{'cursor': 12},
        },
        'findings': <Object?>[
          <String, Object?>{
            'kind': 'alwaysDegrades',
            'subject': '/orders',
            'count': 3,
            'message': 'every open of /orders degraded (DV-WINDOW-001); the call site never gets a window',
          },
          <String, Object?>{
            'kind': 'restoreOverBudget',
            'subject': 'main',
            'count': 3,
            'message': 'restoring workspace "main" (3 tab(s)) took 640ms, over the 500ms startup budget',
          },
        ],
      },
    });

void main() {
  late String livePath;
  setUp(() {
    livePath = dvLiveWindowsPathFor('analyze_app');
    addTearDown(() {
      final File f = File(livePath);
      if (f.existsSync()) f.deleteSync();
    });
  });

  test('no running instance is said, not shown as zero findings', () async {
    final String text = await runAnalyze(<String>['performance'], project());
    expect(text, contains('not running'));
    expect(text, isNot(contains('findings: 0')));
  });

  test('a stale file is a stopped app', () async {
    File(livePath).writeAsStringSync(live(DateTime.now().subtract(const Duration(minutes: 5))));
    final String text = await runAnalyze(<String>['performance'], project());
    expect(text, contains('not running'));
    expect(text, contains('last seen'));
  });

  test('degradations are aggregated per call site, worst first', () async {
    File(livePath).writeAsStringSync(live(DateTime.now()));
    final String text = await runAnalyze(<String>['performance'], project());

    final int orders = text.indexOf('/orders');
    final int stock = text.indexOf('/stock');
    expect(orders, greaterThanOrEqualTo(0));
    expect(stock, greaterThan(orders));
    expect(text, contains('3/3 degraded'));
    expect(text, contains('DV-WINDOW-001'));
    expect(text, contains('0/2 degraded'));
  });

  test('the measurements and findings are printed', () async {
    File(livePath).writeAsStringSync(live(DateTime.now()));
    final String text = await runAnalyze(<String>['performance'], project());

    expect(text, contains('open to ready'));
    expect(text, contains('tear-out'));
    expect(text, contains('40 writes, 8 flushes'));
    expect(text, contains('80%'));
    expect(text, contains('1 spill'));
    expect(text, contains('findings: 2'));
    expect(text, contains('the call site never gets a window'));
    expect(text, contains('over the 500ms startup budget'));
  });

  test('--json is the published block with the app and time', () async {
    File(livePath).writeAsStringSync(live(DateTime.now()));
    final String json = await runAnalyze(<String>['performance', '--json'], project());
    final Map<String, Object?> decoded = (jsonDecode(json) as Map).cast<String, Object?>();
    expect(decoded['app'], 'analyze_app');
    expect(decoded['at'], isNotNull);
    final Map<String, Object?> perf = (decoded['performance']! as Map).cast<String, Object?>();
    expect((perf['findings']! as List).length, 2);
    expect(((perf['degradations']! as Map)['/orders'] as Map)['degraded'], 3);
  });

  test('an unknown analysis is a usage error', () async {
    expect(runAnalyze(<String>['weather'], project()), throwsA(isA<UsageException>()));
  });
}
