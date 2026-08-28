import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/browser_extension.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

BrowserExtensionConfig configFrom(String yaml) =>
    BrowserExtensionConfig.fromPubspec(loadYaml(yaml) as YamlMap);

void main() {
  group('config', () {
    test('falls back to the package name and version', () {
      final config = configFrom('''
name: my_app
version: 2.3.1
description: An app
''');

      expect(config.name, 'my_app');
      expect(config.version, '2.3.1');
      expect(config.description, 'An app');
    });

    test('dartvel.extension overrides the package values', () {
      final config = configFrom('''
name: my_app
version: 1.0.0
dartvel:
  extension:
    name: My Extension
    version: 4.5.6
    permissions:
      - storage
      - tabs
    hostPermissions:
      - "https://example.com/*"
    geckoId: app@example.com
    popup: false
''');

      expect(config.name, 'My Extension');
      expect(config.version, '4.5.6');
      expect(config.permissions, <String>['storage', 'tabs']);
      expect(config.hostPermissions, <String>['https://example.com/*']);
      expect(config.geckoId, 'app@example.com');
      expect(config.usePopup, isFalse);
    });
  });

  group('version normalization', () {
    test('strips build and prerelease suffixes a browser rejects', () {
      // A store rejects these outright, so an unnormalized version produces an
      // extension that cannot be loaded.
      expect(normalizeExtensionVersion('1.2.0+3'), '1.2.0');
      expect(normalizeExtensionVersion('1.2.0-beta.1'), '1.2.0');
      expect(normalizeExtensionVersion('0.2.1'), '0.2.1');
    });

    test('caps at four parts and survives nonsense', () {
      expect(normalizeExtensionVersion('1.2.3.4.5'), '1.2.3.4');
      expect(normalizeExtensionVersion('not-a-version'), '1.0.0');
      expect(normalizeExtensionVersion(''), '1.0.0');
    });
  });

  group('manifest', () {
    const config = BrowserExtensionConfig(
      name: 'My Extension',
      version: '1.0.0',
      permissions: <String>['storage'],
    );

    test('Chromium gets a service worker background', () {
      final manifest =
          buildExtensionManifest(config, BrowserExtensionTarget.chromium);

      expect(manifest['manifest_version'], 3);
      expect(
        manifest['background'],
        <String, Object?>{'service_worker': 'background.js', 'type': 'module'},
      );
      expect(
        (manifest['action']! as Map<String, Object?>)['default_popup'],
        'index.html',
      );
    });

    test('Firefox gets background scripts, not a service worker', () {
      // Firefox runs event pages; a service_worker entry produces an extension
      // that will not load.
      final manifest = buildExtensionManifest(
        const BrowserExtensionConfig(
          name: 'My Extension',
          version: '1.0.0',
          geckoId: 'app@example.com',
        ),
        BrowserExtensionTarget.firefox,
      );

      expect(
        manifest['background'],
        <String, Object?>{
          'scripts': <String>['background.js'],
        },
      );
      expect(
        manifest['browser_specific_settings'],
        <String, Object?>{
          'gecko': <String, Object?>{'id': 'app@example.com'},
        },
      );
    });

    test('the CSP permits no inline script or eval', () {
      final manifest =
          buildExtensionManifest(config, BrowserExtensionTarget.chromium);
      final csp = manifest['content_security_policy']! as Map<String, Object?>;

      expect(csp['extension_pages'], isNot(contains('unsafe-eval')));
      expect(csp['extension_pages'], contains("script-src 'self'"));
    });

    test('no popup means the background script opens the page', () {
      const noPopup = BrowserExtensionConfig(
        name: 'My Extension',
        version: '1.0.0',
        usePopup: false,
      );

      expect(
        buildExtensionManifest(noPopup, BrowserExtensionTarget.chromium)
            .containsKey('action'),
        isFalse,
      );
      expect(buildBackgroundScript(noPopup), contains('tabs.create'));
      expect(buildBackgroundScript(noPopup), contains('index.html'));
    });

    test('the background script works on both extension APIs', () {
      // Chromium exposes `chrome`, Firefox exposes `browser`.
      final script = buildBackgroundScript(config);
      expect(script, contains('globalThis.browser ?? globalThis.chrome'));
    });
  });

  group('bundle assembly', () {
    late Directory root;
    late String webDir;
    late String outputDir;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dartvel_ext_test_');
      webDir = p.join(root.path, 'web');
      outputDir = p.join(root.path, 'out');
      Directory(p.join(webDir, 'assets')).createSync(recursive: true);
      File(p.join(webDir, 'index.html')).writeAsStringSync('<html></html>');
      File(p.join(webDir, 'main.dart.js')).writeAsStringSync('void 0;');
      File(p.join(webDir, 'assets', 'AssetManifest.json'))
          .writeAsStringSync('{}');
      File(p.join(webDir, 'flutter_service_worker.js'))
          .writeAsStringSync('// pwa');
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('copies the web bundle and writes the extension files', () {
      assembleExtensionBundle(
        webBuildDir: webDir,
        outputDir: outputDir,
        config: const BrowserExtensionConfig(name: 'E', version: '1.0.0'),
        target: BrowserExtensionTarget.chromium,
      );

      expect(File(p.join(outputDir, 'index.html')).existsSync(), isTrue);
      expect(File(p.join(outputDir, 'main.dart.js')).existsSync(), isTrue);
      expect(
        File(p.join(outputDir, 'assets', 'AssetManifest.json')).existsSync(),
        isTrue,
      );
      expect(File(p.join(outputDir, 'manifest.json')).existsSync(), isTrue);
      expect(File(p.join(outputDir, 'background.js')).existsSync(), isTrue);

      final manifest = jsonDecode(
        File(p.join(outputDir, 'manifest.json')).readAsStringSync(),
      ) as Map<String, Object?>;
      expect(manifest['name'], 'E');
    });

    test('drops the Flutter service worker', () {
      // Two service workers in one extension fight over fetch handling.
      assembleExtensionBundle(
        webBuildDir: webDir,
        outputDir: outputDir,
        config: const BrowserExtensionConfig(name: 'E', version: '1.0.0'),
        target: BrowserExtensionTarget.chromium,
      );

      expect(
        File(p.join(outputDir, 'flutter_service_worker.js')).existsSync(),
        isFalse,
      );
      expect(validateExtensionArtifacts(outputDir).isValid, isTrue);
    });

    test('a rebuild does not keep stale files from the previous one', () {
      assembleExtensionBundle(
        webBuildDir: webDir,
        outputDir: outputDir,
        config: const BrowserExtensionConfig(name: 'E', version: '1.0.0'),
        target: BrowserExtensionTarget.chromium,
      );
      File(p.join(outputDir, 'stale.js')).writeAsStringSync('old');

      assembleExtensionBundle(
        webBuildDir: webDir,
        outputDir: outputDir,
        config: const BrowserExtensionConfig(name: 'E', version: '1.0.0'),
        target: BrowserExtensionTarget.chromium,
      );

      expect(File(p.join(outputDir, 'stale.js')).existsSync(), isFalse);
    });

    test('validation reports exactly what is missing', () {
      Directory(outputDir).createSync(recursive: true);
      File(p.join(outputDir, 'index.html')).writeAsStringSync('<html></html>');

      final artifacts = validateExtensionArtifacts(outputDir);

      expect(artifacts.isValid, isFalse);
      expect(artifacts.missing, contains('manifest.json'));
      expect(artifacts.missing, contains('main.dart.js'));
      expect(artifacts.missing, contains('background.js'));
    });
  });

  group('the Firefox add-on identity', () {
    // Without browser_specific_settings.gecko.id, Firefox generates an ID at
    // install time and it changes on every reinstall. Everything keyed on the
    // add-on's identity goes with it: storage.local is emptied, the
    // moz-extension:// origin moves, and a native-messaging allowlist naming
    // the old ID stops matching.
    //
    // Chromium does not have the problem -- an unpacked extension's ID is
    // derived from its path and a packed one from its key -- which is why
    // this was easy to miss while the Chromium target worked.

    BrowserExtensionConfig configFor(String yaml) =>
        BrowserExtensionConfig.fromPubspec(loadYaml(yaml) as YamlMap);

    test('a Firefox manifest always carries an id', () {
      final config = configFor('''
name: my_app
version: 2.1.0
''');
      final manifest =
          buildExtensionManifest(config, BrowserExtensionTarget.firefox);

      final settings =
          manifest['browser_specific_settings'] as Map<String, Object?>?;
      expect(settings, isNotNull,
          reason: 'an add-on with no id is a different add-on each install');
      expect((settings!['gecko'] as Map<String, Object?>)['id'], isNotEmpty);
    });

    test('the id is derived from the package, so it is stable', () {
      // Same package, same id, on every build and every machine.
      final first = buildExtensionManifest(
          configFor('name: my_app\nversion: 1.0.0\n'),
          BrowserExtensionTarget.firefox);
      final second = buildExtensionManifest(
          configFor('name: my_app\nversion: 9.9.9\n'),
          BrowserExtensionTarget.firefox);

      String idOf(Map<String, Object?> m) =>
          ((m['browser_specific_settings'] as Map<String, Object?>)['gecko']
              as Map<String, Object?>)['id']! as String;

      expect(idOf(first), idOf(second),
          reason: 'a version bump must not move the add-on');
      expect(idOf(first), contains('my_app'));
    });

    test('two packages do not share an id', () {
      String idOf(String name) {
        final m = buildExtensionManifest(
            configFor('name: $name\nversion: 1.0.0\n'),
            BrowserExtensionTarget.firefox);
        return ((m['browser_specific_settings'] as Map<String, Object?>)['gecko']
            as Map<String, Object?>)['id']! as String;
      }

      expect(idOf('one_app'), isNot(idOf('two_app')));
    });

    test('an explicit id still wins', () {
      final config = configFor('''
name: my_app
version: 1.0.0
dartvel:
  extension:
    geckoId: chosen@example.com
''');
      final manifest =
          buildExtensionManifest(config, BrowserExtensionTarget.firefox);

      expect(
        ((manifest['browser_specific_settings'] as Map<String, Object?>)['gecko']
            as Map<String, Object?>)['id'],
        'chosen@example.com',
      );
    });

    test('Chromium gets no gecko settings', () {
      final manifest = buildExtensionManifest(
          configFor('name: my_app\nversion: 1.0.0\n'),
          BrowserExtensionTarget.chromium);

      expect(manifest.containsKey('browser_specific_settings'), isFalse);
    });
  });
}
