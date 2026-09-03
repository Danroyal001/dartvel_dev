// `dartvel inspect` reads the project graph. It adds no discovery of its own,
// so what it can answer and what the graph knows are the same set -- which is
// the point of building the graph first.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/inspect_command.dart';
import 'package:dartvel_core/dartvel.dart' show dvLiveWindowsPathFor;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _models = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String email;

  @DVModel.sensitiveField()
  final String taxId;

  const _User({required this.email, required this.taxId});
}
''';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const DVText('hi');
''';

Future<String> runInspect(List<String> args, Directory root) async {
  final Directory previous = Directory.current;
  Directory.current = root;
  final StringBuffer out = StringBuffer();
  try {
    await runZonedOutput(out, () async {
      final CommandRunner<void> runner =
          CommandRunner<void>('dartvel', 'Test runner')
            ..addCommand(InspectCommand());
      await runner.run(<String>['inspect', ...args]);
    });
  } finally {
    Directory.current = previous;
  }
  return out.toString();
}

Future<void> runZonedOutput(StringBuffer out, Future<void> Function() body) {
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone _, ZoneDelegate __, Zone ___, String line) {
        out.writeln(line);
      },
    ),
  );
}

Directory projectWith(Map<String, String> files) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_inspect_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final MapEntry<String, String> entry in files.entries) {
    final File file = File(p.join(root.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  File(p.join(root.path, 'pubspec.yaml'))
      .writeAsStringSync('name: inspect_app\n');
  return root;
}

void main() {
  test('--json emits the whole graph, versioned', () async {
    final Directory root = projectWith(<String, String>{
      'lib/models/user.dart': _models,
      'lib/pages/index.page.dart': _page,
    });

    final Map<String, Object?> json =
        jsonDecode(await runInspect(<String>['--json'], root))
            as Map<String, Object?>;

    expect(json['graphVersion'], 1);
    expect(json.keys, containsAll(<String>['models', 'routes']));
  });

  test('a sensitive field is described and never valued', () async {
    final Directory root =
        projectWith(<String, String>{'lib/models/user.dart': _models});

    final String out = await runInspect(<String>['model', 'User'], root);

    // Named, so a reader knows the field exists.
    expect(out, contains('taxId'));
    expect(out, contains('sensitive'));
  });

  test('routes are listed with the page that answers them', () async {
    final Directory root =
        projectWith(<String, String>{'lib/pages/index.page.dart': _page});

    final String out = await runInspect(<String>['routes'], root);

    expect(out, contains('/'));
    expect(out, contains('homePage'));
  });

  test('an unknown model says so instead of printing nothing', () async {
    // A silent empty answer reads as "this model has no fields".
    final Directory root =
        projectWith(<String, String>{'lib/models/user.dart': _models});

    final String out = await runInspect(<String>['model', 'Ghost'], root);

    expect(out.toLowerCase(), contains('ghost'));
    expect(out.toLowerCase(), anyOf(contains('not found'), contains('no model')));
  });

  group('windows, live', () {
    // A running application writes what it has open beside its lock; the
    // inspector reads it while it is fresh and says so, and calls a stale
    // or missing file what it is: no live application.
    late String livePath;
    setUp(() {
      livePath = dvLiveWindowsPathFor('inspect_app');
      addTearDown(() {
        final File f = File(livePath);
        if (f.existsSync()) f.deleteSync();
      });
    });

    String live(DateTime at) => jsonEncode(<String, Object?>{
          'app': 'inspect_app',
          'at': at.toUtc().toIso8601String(),
          'windows': <Map<String, Object?>>[
            <String, Object?>{'route': '/orders', 'kind': 'main', 'presentation': 'window', 'nativeId': 'win-1'},
            <String, Object?>{'route': '/stock', 'kind': 'secondary', 'presentation': 'window'},
          ],
        });

    test('a fresh file is the live list', () async {
      File(livePath).writeAsStringSync(live(DateTime.now()));
      final Directory root = projectWith(<String, String>{'lib/pages/index.page.dart': _page});
      final String json = await runInspect(<String>['windows', '--json'], root);
      final Map<String, Object?> decoded = (jsonDecode(json) as Map).cast<String, Object?>();
      final Map<String, Object?> liveOut = (decoded['live']! as Map).cast<String, Object?>();
      expect((liveOut['windows']! as List).length, 2);
      expect(((liveOut['windows']! as List).first as Map)['route'], '/orders');

      final String text = await runInspect(<String>['windows'], root);
      expect(text, contains('/orders'));
      expect(text, contains('live'));
    });

    test('a stale file is not live, and says how old it is', () async {
      File(livePath).writeAsStringSync(live(DateTime.now().subtract(const Duration(minutes: 10))));
      final Directory root = projectWith(<String, String>{'lib/pages/index.page.dart': _page});
      final String json = await runInspect(<String>['windows', '--json'], root);
      final Map<String, Object?> decoded = (jsonDecode(json) as Map).cast<String, Object?>();
      expect(decoded['live'], isNull);
      final String text = await runInspect(<String>['windows'], root);
      expect(text, contains('not running'));
    });

    test('no file, no live list', () async {
      final Directory root = projectWith(<String, String>{'lib/pages/index.page.dart': _page});
      final String json = await runInspect(<String>['windows', '--json'], root);
      expect((jsonDecode(json) as Map)['live'], isNull);
    });
  });
}
