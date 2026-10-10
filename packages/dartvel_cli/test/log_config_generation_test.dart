// dartvel.logging is checked where the client is generated, and the runtime
// installs DV.log's destinations from the declaration the build checked.
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

void main() {
  final List<Directory> made = <Directory>[];
  tearDown(() {
    for (final Directory directory in made) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
    made.clear();
  });

  Directory project(String logging) {
    final Directory directory =
        Directory.systemTemp.createTempSync('dv_log_config_');
    made.add(directory);
    File(p.join(directory.path, 'lib', 'pages', 'index.page.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_indexPage);
    File(p.join(directory.path, 'pubspec.yaml')).writeAsStringSync('''
name: log_config_probe
version: 3.1.0
environment:
  sdk: ^3.13.0
dartvel:
$logging
''');
    return directory;
  }

  File runtimeOf(Directory directory) => File(
      p.join(directory.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'));

  for (final (String key, String yaml) in <(String, String)>[
    ('dartvel.logging.level', '  logging:\n    level: loud'),
    ('dartvel.logging.ship.level', '  logging:\n    ship:\n      level: debug'),
    ('dartvel.logging.file.maxBytes', '  logging:\n    file:\n      maxBytes: 12'),
  ]) {
    test('refuses $key, naming it, and writes no runtime', () async {
      final Directory directory = project(yaml);
      await expectLater(
        routes.generate(root_: directory.path),
        throwsA(predicate((Object error) => '$error'.contains(key), 'names $key')),
      );
      expect(runtimeOf(directory).existsSync(), isFalse);
    });
  }

  test('the runtime installs logging from the declaration, after crashes',
      () async {
    final Directory directory = project('''
  logging:
    level: debug
    ship:
      enabled: true
''');
    await routes.generate(root_: directory.path);

    final String source = runtimeOf(directory).readAsStringSync();
    final int crashes = source.indexOf('  installDartvelCrashReporting();');
    final int logging = source.indexOf('  dvInstallApplicationLogging(');
    expect(logging, greaterThan(crashes),
        reason: 'warnings become crash breadcrumbs only once crashes exist');
    expect(source, contains("'level': 'debug'"));
    expect(source, contains("'enabled': true"));
    expect(source, contains("release: '3.1.0'"));
  });

  test('the generated runtime imports every DV.log installer it calls',
      () async {
    // The runtime calls dvInstallApplicationLogging; if the generated
    // flutter import omits it from its show list the client does not
    // compile. The refusal tests above never generate a compilable runtime,
    // so this is the check that caught the omission.
    final Directory directory = project('''
  logging:
    level: info
''');
    await routes.generate(root_: directory.path);

    final String source = runtimeOf(directory).readAsStringSync();
    final String flutterImport = source
        .split('\n')
        .firstWhere((String line) =>
            line.contains("import 'package:dartvel_flutter/dartvel_flutter.dart'"));
    expect(flutterImport, contains('dvInstallApplicationLogging'));
  });
}
