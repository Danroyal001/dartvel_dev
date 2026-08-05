// Real Linux native bindings over dart:ffi — libX11 and libgtk-3, no
// platform channels and no fakes. Runs only where an X display exists;
// elsewhere it skips visibly rather than passing on a stub.
@TestOn('linux')
library;

import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test(
      'linux bindings (skipped: no X display)',
      () {},
      skip: 'Run under an X server (Xvfb :99 works) to exercise the real '
          'X11/GTK bindings.',
    );
    return;
  }

  setUpAll(() {
    expect(
      DVLinuxBindings.register(),
      isTrue,
      reason: 'libX11/libgtk-3 should load on a Linux desktop host',
    );
  });

  tearDownAll(DVLinuxBindings.unregister);

  test('registers only what it actually implements', () {
    // The point of the design: an unimplemented binding must keep throwing,
    // not return a plausible lie.
    expect(
      DVLinuxBindings.implemented,
      <String>{'clipboard.copy', 'clipboard.paste', 'screen.geometry'},
    );
    expect(DVLinuxBindings.isRegistered, isTrue);
  });

  test('DV.Clipboard round-trips through the real GTK clipboard', () async {
    const value = 'dartvel-linux-binding-test';

    await DV.Clipboard.copy(value);

    expect(await DV.Clipboard.paste(), value);
  });

  test('a second copy replaces the first', () async {
    await DV.Clipboard.copy('first');
    await DV.Clipboard.copy('second');

    expect(await DV.Clipboard.paste(), 'second');
  });

  test('unicode survives the native round-trip', () async {
    // UTF-8 across the FFI boundary: a byte-length mistake corrupts this.
    const value = 'naïve — 😀 clipboard';

    await DV.Clipboard.copy(value);

    expect(await DV.Clipboard.paste(), value);
  });

  test('screen.geometry reports the real X display size', () async {
    final geometry =
        await DVNativeBridge.require<Map<String, Object?>>('screen.geometry');

    // Whatever the display actually is — under Xvfb the harness knows the
    // exact geometry it started, and asserts on it below.
    expect(geometry['width'], isA<int>());
    expect(geometry['height'], isA<int>());
    expect((geometry['width']! as int) > 0, isTrue);
    expect((geometry['height']! as int) > 0, isTrue);

    final expectedWidth = Platform.environment['DARTVEL_TEST_SCREEN_WIDTH'];
    if (expectedWidth != null) {
      expect(geometry['width'], int.parse(expectedWidth));
    }
    final expectedHeight = Platform.environment['DARTVEL_TEST_SCREEN_HEIGHT'];
    if (expectedHeight != null) {
      expect(geometry['height'], int.parse(expectedHeight));
    }
  });

  test('an unimplemented binding still throws, naming what is missing',
      () async {
    // Camera has no Linux implementation; it must fail loudly rather than
    // return a fake photo.
    await expectLater(
      DV.Platform.Camera.takePhoto(),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('camera.takePhoto'),
        ),
      ),
    );
  });
}
