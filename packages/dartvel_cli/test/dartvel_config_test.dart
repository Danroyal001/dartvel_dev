import 'dart:io';

import 'package:dartvel_cli/src/config/dartvel_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DartvelConfig', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('dartvel_config_test');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test('loads typed defaults and YAML overrides from pubspec', () async {
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: typed_app
dartvel:
  pagesDir: lib/app_pages
  modelsDir: lib/app_models
  backendDir: lib/server
  backendPort: "4040"
  apiBasePath: /rpc
  envFiles:
    - .env
    - .env.test
  seo:
    siteName: Typed App
    defaultTitle: Home
  transitions:
    default: slideLeft
    durationMs: 300
  plugins:
    - auth
  webPrerender: yes
  ota: true
''');

      final config = await DartvelConfig.load(temp);

      expect(config.packageName, 'typed_app');
      expect(config.pagesDir, 'lib/app_pages');
      expect(config.modelsDir, 'lib/app_models');
      expect(config.backendDir, 'lib/server');
      expect(config.backendPort, 4040);
      expect(config.apiBasePath, '/rpc');
      expect(config.envFiles, <String>['.env', '.env.test']);
      expect(config.seo.siteName, 'Typed App');
      expect(config.seo.title, 'Home');
      expect(config.transitions.defaultTransition, 'slideLeft');
      expect(config.transitions.durationMs, 300);
      expect(config.plugins, <String>['auth']);
      expect(config.webPrerender, isTrue);
      expect(config.ota, isTrue);
    });

    test('validates dart config file reference', () async {
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: dart_config_app
dartvel: dartvel_config.dart
''');
      File(p.join(temp.path, 'dartvel_config.dart')).writeAsStringSync('''
class AppConfig extends DartvelConfig {
  const AppConfig();
}
''');

      final config = await DartvelConfig.load(temp);

      expect(config.dartConfigReference?.relativePath, 'dartvel_config.dart');
      expect(config.dartConfigReference?.className, 'AppConfig');
    });

    test('rejects private dart config classes', () async {
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: bad_config_app
dartvel: dartvel_config.dart
''');
      File(p.join(temp.path, 'dartvel_config.dart')).writeAsStringSync('''
class _AppConfig extends DartvelConfig {}
''');

      // Awaited: load() is async, so an un-awaited expect lets the test
      // finish before the expectation is ever checked.
      await expectLater(
        () => DartvelConfig.load(temp),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
