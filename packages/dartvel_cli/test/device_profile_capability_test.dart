// Whether the device being built for can run what is being built.
//
// The specification names device-profile compatibility among the things a
// build validates before it starts, and gives the message: "The selected
// application requires Bluetooth, but the sony-elinux device profile does not
// provide a Bluetooth adapter or fallback implementation."
//
// A module says what it needs -- a federated one in its signed manifest -- and
// nothing read it against the profile being built for. The check existed in
// the manifest verifier and no caller ever passed it a target, so a kiosk
// image would build happily around a module that cannot run on it, and the
// first anyone knew was a device in a lobby with a dead section.
import 'dart:io';

import 'package:dartvel_cli/src/build/device_profile_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory project(String dartvel) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_profile_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml'))
      .writeAsStringSync('name: shopfront\ndartvel:\n$dartvel');
  return root;
}

/// A project whose one module needs [needs], built for a profile that
/// provides [provides].
Directory needing(String needs, {required String provides}) => project('''
  deviceProfiles:
    lobby-display:
      platform: sony-elinux
      architecture: arm64
$provides
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      requires: [$needs]
''');

void main() {
  test('a profile that provides what the module needs builds', () {
    final DVDeviceProfileCheck check = DVDeviceProfileCheck.run(
      needing('bluetooth', provides: '      provides: [bluetooth, touch]').path,
      profile: 'lobby-display',
    );

    expect(check.ok, isTrue);
    expect(check.lines, isEmpty);
  });

  test('a profile that cannot is refused, in the specification\'s words', () {
    final DVDeviceProfileCheck check = DVDeviceProfileCheck.run(
      needing('bluetooth', provides: '      provides: [touch]').path,
      profile: 'lobby-display',
    );

    expect(check.ok, isFalse);
    final String said = check.lines.join('\n');
    expect(said, contains('bluetooth'));
    expect(said, contains('lobby-display'));
    expect(said, contains('fallback'));
  });

  test('a fallback the profile declares satisfies the requirement', () {
    // The specification's own wording allows one: "does not provide a
    // Bluetooth adapter or fallback implementation".
    final DVDeviceProfileCheck check = DVDeviceProfileCheck.run(
      needing('bluetooth',
              provides: '      fallbacks: [bluetooth]\n      provides: [touch]')
          .path,
      profile: 'lobby-display',
    );

    expect(check.ok, isTrue);
  });

  test('the input a profile declares is a capability like any other', () {
    // The profile shape in the specification says touch and keyboard under
    // input, so a module needing a keyboard on a touch-only display is the
    // same question in different words.
    final DVDeviceProfileCheck check = DVDeviceProfileCheck.run(
      needing('keyboard',
              provides: '      input: { touch: true, keyboard: false }')
          .path,
      profile: 'lobby-display',
    );

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('keyboard'));
  });

  test('no profile selected is no question asked', () {
    // A desktop build is not being made for a named device, and refusing it
    // for a capability nobody declared would stop every build that mounts a
    // module needing anything.
    final DVDeviceProfileCheck check = DVDeviceProfileCheck.run(
      needing('bluetooth', provides: '      provides: [touch]').path,
      profile: null,
    );

    expect(check.ok, isTrue);
    expect(check.lines, isEmpty);
  });

  test('a profile that is not declared is refused rather than assumed empty', () {
    // Assuming it provides nothing would refuse every module; assuming it
    // provides everything would defeat the check. A profile nobody declared
    // is a mistake in the command.
    final DVDeviceProfileCheck check = DVDeviceProfileCheck.run(
      needing('bluetooth', provides: '      provides: [bluetooth]').path,
      profile: 'no-such-display',
    );

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('no-such-display'));
  });

  test('a module that needs nothing runs anywhere', () {
    final DVDeviceProfileCheck check = DVDeviceProfileCheck.run(
      project('''
  deviceProfiles:
    lobby-display:
      platform: sony-elinux
  modules:
    store:
      source: { path: modules/store }
      mount: /store
''').path,
      profile: 'lobby-display',
    );

    expect(check.ok, isTrue);
  });
}
