import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: 'Home')\n"
    "Widget _homePage(BuildContext context) => const DVText('hi');\n";

/// Every generated file for a project with the given `dartvel:` section,
/// joined: the config and the runtime live apart.
Future<String> generatedFor(String pkgName, YamlMap dv) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_kiosk_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(_page);
  await ClientGenerator.generate(
    root: root.path, pagesDir: 'lib/pages', pkgName: pkgName, buildId: 'b',
    backendHost: '127.0.0.1', backendPort: 3000, devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://example.com', apiBasePath: '/api', envFiles: const <String>[],
    seoSiteName: 'app', seoTitle: 'app', seoDesc: 'app', seoImage: '', seoTwitter: '',
    defaultTransition: 'none', durationMs: 200, curve: 'linear', normalizeTrailing: true,
    notFoundRedirect: '/', plugins: const <String>[], webPrerender: false, ota: false, dv: dv,
  );
  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

Future<String> configFor() => generatedFor('reg_app', YamlMap.wrap(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'display',
        'home': '/welcome',
        'exit': <String, Object?>{'method': 'adminAuth'},
        'policies': <String, Object?>{
          'customerDisplay': <String, Object?>{
            'home': '/customer-display',
            'routes': <String, Object?>{'allow': <String>['/customer-display/**']},
            'session': <String, Object?>{'idleTimeout': '60s', 'onIdle': 'reset'},
          },
          'staffTerminal': <String, Object?>{'home': '/staff'},
        },
      },
    }));

Future<String> plainConfig() => generatedFor('plain_app', YamlMap());

Future<String> deviceConfig() => generatedFor('device_app', YamlMap.wrap(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': '/welcome',
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:KIOSK_PIN'},
      },
    }));

// Named policies are available to code as DVKioskPolicies.<name>, so a kiosk
// window opened at runtime uses a declared policy rather than an ad-hoc one.
// There is no policy that is not in the declaration: each is the kiosk
// section's own settings with the named entry's over them, parsed by the
// same parser dartvel doctor checks. The section itself is the device
// policy, installed at start when its scope is device.
void main() {
  late String config;
  setUpAll(() async => config = await configFor());

  test('every declared policy is a member', () {
    expect(config, contains('class DVKioskPolicies'));
    expect(config, contains('static DVKioskPolicy get customerDisplay'));
    expect(config, contains('static DVKioskPolicy get staffTerminal'));
    expect(config, contains("static const List<String> names = <String>['customerDisplay', 'staffTerminal'];"));
  });

  test('a policy is the section with the named entry over it', () {
    final int start = config.indexOf('get customerDisplay');
    final String body = config.substring(start, config.indexOf('get staffTerminal'));
    expect(body, contains("'home': '/customer-display'"));
    expect(body, contains("'scope': 'display'"), reason: 'inherited from the section');
    expect(body, contains("'method': 'adminAuth'"), reason: 'inherited too');
    expect(body, contains("'onIdle': 'reset'"));
    expect(body, isNot(contains("'policies'")), reason: 'a policy does not carry its siblings');
  });

  test('with no policies declared there is still a class, and it is empty', () async {
    final String plain = await plainConfig();
    expect(plain, contains('class DVKioskPolicies'));
    expect(plain, contains('static const List<String> names = <String>[];'));
    expect(plain, isNot(contains('installKioskPolicy')));
  });

  test('the section itself is the device policy, and the runtime installs it at start', () async {
    final String withDevice = await deviceConfig();
    expect(withDevice, contains('static DVKioskPolicy get device'));
    expect(withDevice, contains("'scope': 'device'"));
    expect(withDevice, contains('DVPlatform.installKioskPolicy('));
    expect(withDevice, contains('DVKioskPolicies.device,'));
    expect(withDevice, contains('startDartvelKiosk()'));
  });

  test('a display-scope declaration installs no device kiosk', () {
    expect(config, isNot(contains('installKioskPolicy')));
    expect(config, isNot(contains('get device')));
  });

  profileOverrideTests();
}

// deviceProfiles.<profile>.kiosk overrides dartvel.kiosk, and the build's
// --device-profile selects the profile. The override was parsed by nothing:
// a front-desk profile's home page was ignored and every machine booted to
// the section's default. Runtime never changes policy, so the choice is a
// switch on the build's define, not a lookup that could be edited on device.
Future<String> profiledDeviceConfig() => generatedFor('profiled_kiosk_app', YamlMap.wrap(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': '/welcome',
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:KIOSK_PIN'},
      },
      'deviceProfiles': <String, Object?>{
        'frontDesk': <String, Object?>{
          'kiosk': <String, Object?>{'home': '/front'},
        },
        'warehouse': <String, Object?>{'arch': 'arm64'},
      },
    }));

void profileOverrideTests() {
  test('a profile kiosk override is the device policy when that profile is selected', () async {
    final String out = await profiledDeviceConfig();
    expect(out, contains('class DVDeviceProfiles'));
    expect(out, contains("String.fromEnvironment('DARTVEL_DEVICE_PROFILE'"));
    expect(out, contains('static DVKioskPolicy get device => switch (DVDeviceProfiles.selected) {'));
    final int start = out.indexOf("'frontDesk' => DVKioskPolicy.parse(");
    expect(start, greaterThanOrEqualTo(0));
    final String arm = out.substring(start, out.indexOf('_ => DVKioskPolicy.parse(', start));
    expect(arm, contains("'home': '/front'"));
    expect(arm, contains("'method': 'pin'"), reason: 'the section is inherited under the override');
    expect(out, isNot(contains("'warehouse' =>")), reason: 'a profile with no kiosk entry is the default');
  });

  test('without profile overrides the device policy is the section alone', () async {
    final String out = await deviceConfig();
    expect(out, isNot(contains('switch (DVDeviceProfiles.selected)')));
  });
}
