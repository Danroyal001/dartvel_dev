// dartvel.crashes is checked where the client is generated.
//
// The runtime parses the same declaration again at startup, and refusing
// there is too late: the application is already on a device, and a
// configuration it cannot honour takes its crash reporting down with it, on
// the one launch that nobody is watching. So `dartvel routes` refuses first,
// naming the key, and writes nothing a build could ship.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

Directory project(String crashes) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_crash_config_');
  File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(_indexPage);
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: crash_config_probe
version: 1.0.0
environment:
  sdk: ^3.12.0
dartvel:
$crashes
''');
  return dir;
}

void main() {
  final List<Directory> made = <Directory>[];
  tearDown(() {
    for (final Directory d in made) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    made.clear();
  });

  Future<Directory> generate(String crashes) async {
    final Directory dir = project(crashes);
    made.add(dir);
    await routes.generate(root_: dir.path);
    return dir;
  }

  String runtime(Directory dir) => File(
        p.join(dir.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'),
      ).readAsStringSync();

  for (final (String key, String yaml) in <(String, String)>[
    ('dartvel.crashes.nonFatalSampleRate', '  crashes:\n    nonFatalSampleRate: 25'),
    ('dartvel.crashes.enabled', '  crashes:\n    enabled: "no"'),
    ('dartvel.crashes.breadcrumb', '  crashes:\n    breadcrumb: 16'),
    ('dartvel.crashes.sink', '  crashes:\n    sink: sentry'),
    ('dartvel.crashes.identity.consent', '  crashes:\n    identity:\n      consent: ""'),
  ]) {
    test('refuses $key, naming it', () async {
      final Directory dir = project(yaml);
      made.add(dir);

      await expectLater(
        routes.generate(root_: dir.path),
        throwsA(predicate((Object e) => '$e'.contains(key), 'names $key')),
      );
      expect(
        File(p.join(dir.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
            .existsSync(),
        isFalse,
        reason: 'a refused configuration must not leave a runtime to ship',
      );
    });
  }

  test('a valid declaration is what the runtime parses at startup', () async {
    final Directory dir = await generate('''
  crashes:
    disabledIn: [debug]
    nonFatalSampleRate: 0.25
    breadcrumbs: 16
    fullReportsPerRelease: 3
    identity:
      consent: crash_identity
''');

    final String source = runtime(dir);
    expect(source, contains('config: DVCrashConfig.parse('));
    expect(source, contains("'nonFatalSampleRate': 0.25"));
    expect(source, contains("'consent': 'crash_identity'"));
  });

  test('no declaration is the defaults, parsed the same way', () async {
    final Directory dir = await generate('  backendPort: 8080');
    expect(runtime(dir), contains('config: DVCrashConfig.parse('));
  });
}
