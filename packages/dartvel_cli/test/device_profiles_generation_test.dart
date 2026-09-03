// Device profile display names reach the generated client.
//
// `dartvel.deviceProfiles.<id>.displays` names displays by index, and
// DVDisplayHint.byName('Customer') resolves through
// DVWindowManager.displayProfile. The CLI read the names (dartvel inspect
// windows listed them) and nothing carried them into the app, so the profile
// had to be set by hand in main -- a declared name that did not work was the
// silent failure: the hint matched nothing and the OS placed the window.
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'kiosk_policies_generation_test.dart' show generatedFor;

Future<String> profiled() => generatedFor('profiled_app', YamlMap.wrap(<String, Object?>{
      'deviceProfiles': <String, Object?>{
        'frontDesk': <String, Object?>{
          'displays': <String, Object?>{
            'Customer': <String, Object?>{'index': 1},
            'Staff': <String, Object?>{'index': 0},
          },
        },
        'warehouse': <String, Object?>{
          'arch': 'arm64',
        },
      },
    }));

Future<String> plain() => generatedFor('plain_app', YamlMap());

void main() {
  test('every profile with displays is generated, keyed by its id', () async {
    final String out = await profiled();
    expect(out, contains('class DVDeviceProfiles'));
    expect(out, contains("'frontDesk': <String, int>{'Customer': 1, 'Staff': 0}"));
    // A profile that names no displays is not an entry of nothing.
    expect(out, isNot(contains("'warehouse'")));
  });

  test('the build selects the profile through DARTVEL_DEVICE_PROFILE', () async {
    final String out = await profiled();
    expect(out, contains("String.fromEnvironment('DARTVEL_DEVICE_PROFILE'"));
    expect(out, contains('static Map<String, int> get displayNames'));
  });

  test('the runtime installs the selected profile before any window opens', () async {
    final String out = await profiled();
    expect(out, contains('DVWindowManager.displayProfile = DVDeviceProfiles.displayNames;'));
    expect(out, contains('DVWindowManager'));
  });

  test('a project without profiles generates none of it', () async {
    final String out = await plain();
    expect(out, isNot(contains('DVDeviceProfiles')));
    expect(out, isNot(contains('displayProfile')));
  });
}
