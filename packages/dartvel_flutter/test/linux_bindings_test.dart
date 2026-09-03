// Real Linux native bindings over dart:ffi — libX11 and libgtk-3, no
// platform channels and no fakes. Runs only where an X display exists;
// elsewhere it skips visibly rather than passing on a stub.
@TestOn('linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _GtkInitCheckNative = Int32 Function(
  Pointer<Int32>,
  Pointer<Pointer<Pointer<Utf8>>>,
);
typedef _GtkInitCheckDart = int Function(
  Pointer<Int32>,
  Pointer<Pointer<Pointer<Utf8>>>,
);
typedef _GtkWindowNewNative = Pointer<Void> Function(Int32);
typedef _GtkWindowNewDart = Pointer<Void> Function(int);

/// Creates a real GtkWindow, the same kind the Flutter Linux embedder makes,
/// so the window bindings can be exercised on their success path rather than
/// only their no-window failure path.
void createRealToplevel() {
  final gtk = DynamicLibrary.open('libgtk-3.so.0');
  gtk.lookupFunction<_GtkInitCheckNative, _GtkInitCheckDart>('gtk_init_check')(
    nullptr,
    nullptr,
  );
  gtk.lookupFunction<_GtkWindowNewNative, _GtkWindowNewDart>('gtk_window_new')(
    0,
  );
}

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
      <String>{
        'clipboard.copy',
        'clipboard.paste',
        'screen.geometry',
        'notifications.sendLocal',
        'window.setTitle',
        'window.maximize',
        'window.minimize',
        'window.restore',
        'window.setSize',
        'shortcuts.register',
        'shortcuts.unregister',
      },
    );
    expect(DVLinuxBindings.isRegistered, isTrue);
  });

  test('a desktop notification reaches the notification service', () async {
    // Requires a session bus with a notification daemon; the harness starts
    // dbus and dunst. Without one there is nothing to deliver to, and
    // reporting success would be the lie this design exists to avoid.
    final hasBus =
        Platform.environment['DBUS_SESSION_BUS_ADDRESS']?.isNotEmpty ?? false;
    if (!hasBus) {
      markTestSkipped('no session bus; start dbus-launch and a notifier');
      return;
    }

    final id = await DVNativeBridge.require<int>(
      'notifications.sendLocal',
      <String, Object?>{'title': 'Dartvel', 'body': 'binding test'},
    );

    // A real daemon answers with the id it assigned.
    expect(id, greaterThan(0));
  });

  test('a quote in notification text does not break the GVariant parse',
      () async {
    final hasBus =
        Platform.environment['DBUS_SESSION_BUS_ADDRESS']?.isNotEmpty ?? false;
    if (!hasBus) {
      markTestSkipped('no session bus');
      return;
    }

    // The content is interpolated into a GVariant text literal; an unescaped
    // apostrophe would end the string early and the call would fail.
    final id = await DVNativeBridge.require<int>(
      'notifications.sendLocal',
      <String, Object?>{
        'title': "Ada's build",
        'body': r"path\to\thing 'quoted'",
      },
    );

    expect(id, greaterThan(0));
  });

  group('window control', () {
    test('reports failure honestly when there is no window yet', () async {
      // Before any toplevel exists the binding must say so, not pretend.
      expect(DVLinuxBindings.currentWindowTitle(), isNull);
      expect(
        await DVNativeBridge.require<bool>(
          'window.setTitle',
          <String, Object?>{'title': 'ignored'},
        ),
        isFalse,
      );
    });

    test('drives a real GTK window once one exists', () async {
      createRealToplevel();

      expect(
        await DVNativeBridge.require<bool>(
          'window.setTitle',
          <String, Object?>{'title': 'Dartvel Window'},
        ),
        isTrue,
      );
      // Read back through GTK, not from our own state.
      expect(DVLinuxBindings.currentWindowTitle(), 'Dartvel Window');

      expect(await DVNativeBridge.require<bool>('window.maximize'), isTrue);
      expect(await DVNativeBridge.require<bool>('window.minimize'), isTrue);
      expect(await DVNativeBridge.require<bool>('window.restore'), isTrue);
    });
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
