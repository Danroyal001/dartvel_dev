@TestOn('windows')
library;

// The Win32 bindings against the real Win32.
//
// The companion suite asserts the capability list from any host, which proves
// what Windows claims and nothing about whether the FFI is right. Clipboard
// handling in particular is easy to get plausibly wrong — the global-memory
// ownership rules mean a mistake produces a use-after-free or an empty paste
// rather than a compile error.
//
// Only the bindings that work without a window are exercised. setTitle,
// maximize, minimize and restore all act on the process's own top-level
// window, and a test harness has none; they return false by design, and
// asserting that here would be asserting the harness.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    expect(DVWindowsBindings.register(), isTrue,
        reason: 'user32 and kernel32 must open on Windows');
  });

  tearDownAll(DVWindowsBindings.unregister);

  test('a clipboard round trip survives non-ASCII text', () async {
    // The point of CF_UNICODETEXT over the ANSI format: anything outside the
    // active code page would come back mangled, and a plain-ASCII test would
    // never notice.
    const value = 'Dartvel — clipboard round trip · 日本語 · 🎯';

    await DVNativeBridge.require<bool>(
        'clipboard.copy', <String, Object?>{'text': value});
    final pasted = await DVNativeBridge.require<String?>('clipboard.paste');

    expect(pasted, value);
  });

  test('an empty string is copyable, and comes back empty', () {
    // The terminator-only allocation is its own case: an off-by-one in the
    // byte count corrupts the heap rather than returning the wrong string.
    expect(
      () async {
        await DVNativeBridge.require<bool>(
            'clipboard.copy', <String, Object?>{'text': ''});
        expect(await DVNativeBridge.require<String?>('clipboard.paste'), '');
      },
      returnsNormally,
    );
  });

  test('screen.geometry reports a real display', () async {
    final geometry =
        await DVNativeBridge.require<Map<String, Object?>>('screen.geometry');
    expect(geometry['width'] as int, greaterThan(0));
    expect(geometry['height'] as int, greaterThan(0));
  });

  test('setSize refuses a nonsensical size rather than clamping it', () async {
    // A resize to zero or a negative is a caller mistake. Clamping hides it
    // behind a window that is the wrong size for reasons nobody can see, so
    // the argument is rejected before Win32 is asked.
    for (final bad in <Map<String, Object?>>[
      <String, Object?>{'width': 0, 'height': 600},
      <String, Object?>{'width': 800, 'height': -1},
      <String, Object?>{'width': 'wide', 'height': 600},
    ]) {
      await expectLater(
        DVNativeBridge.require<bool>('window.setSize', bad),
        throwsA(isA<ArgumentError>()),
        reason: '$bad should be refused',
      );
    }
  });

  group('kiosk', () {
    // RegisterHotKey with no window binds to the calling thread, so the
    // harness can hold a combo without a window. Ctrl+Alt+Delete is the
    // secure attention sequence and no process may take it: it has to come
    // back unenforced, with Win32's reason, rather than as a silent success
    // that would let a kiosk claim to block what it cannot.
    tearDown(() => DVNativeBridge.require<bool>('kiosk.release'));

    test('an escape combo is held, and the secure attention sequence is not', () async {
      final Map<String, Object?> result = (await DVNativeBridge.require<Map<Object?, Object?>>(
        'kiosk.enforce',
        <String, Object?>{
          'combos': <String>['Alt+F4', 'Ctrl+Alt+Delete'],
          'fullscreen': false,
          'confinePointer': false,
          'suppressNotifications': true,
        },
      )).cast<String, Object?>();

      expect(result['blocked'], contains('Alt+F4'));
      final Map<Object?, Object?> unenforced = result['unenforced']! as Map<Object?, Object?>;
      expect(unenforced.keys, contains('Ctrl+Alt+Delete'));
      expect('${unenforced['Ctrl+Alt+Delete']}', contains('RegisterHotKey'));
      // Focus Assist has no public API; a kiosk must not claim to hold
      // notifications back on Windows.
      expect(result['notificationsSuppressed'], isFalse);
    });

    test('the pointer is confined to the screen when there is no window, and let go on release', () async {
      final Map<String, Object?> result = (await DVNativeBridge.require<Map<Object?, Object?>>(
        'kiosk.enforce',
        <String, Object?>{
          'combos': <String>[],
          'fullscreen': false,
          'confinePointer': true,
          'suppressNotifications': false,
        },
      )).cast<String, Object?>();
      expect(result['confined'], isTrue, reason: DVWindowsKiosk.lastConfineError);
      expect(DVWindowsKiosk.confined, isTrue);

      expect(await DVNativeBridge.require<bool>('kiosk.release'), isTrue);
      expect(DVWindowsKiosk.confined, isFalse);
    });

    test('enforcing twice holds each combo once', () async {
      for (var i = 0; i < 2; i++) {
        final Map<String, Object?> result = (await DVNativeBridge.require<Map<Object?, Object?>>(
          'kiosk.enforce',
          <String, Object?>{
            'combos': <String>['Alt+F4'],
            'fullscreen': false,
            'confinePointer': false,
            'suppressNotifications': false,
          },
        )).cast<String, Object?>();
        expect(result['blocked'], <Object?>['Alt+F4'], reason: 'pass $i');
        expect(result['unenforced'], isEmpty, reason: 'pass $i');
      }
    });

    test('fullscreen without a window is not claimed', () async {
      final Map<String, Object?> result = (await DVNativeBridge.require<Map<Object?, Object?>>(
        'kiosk.enforce',
        <String, Object?>{
          'combos': <String>[],
          'fullscreen': true,
          'confinePointer': false,
          'suppressNotifications': false,
        },
      )).cast<String, Object?>();
      expect(result['fullscreen'], isFalse);
    });
  });

  test('an unimplemented binding still throws', () async {
    // Notifications are deliberately absent; see the capability list.
    await expectLater(
      DVNativeBridge.require<bool>('notifications.sendLocal',
          <String, Object?>{'title': 't', 'body': 'b'}),
      throwsA(isA<Object>()),
    );
  });
}
