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

  test('an unimplemented binding still throws', () async {
    // Notifications are deliberately absent; see the capability list.
    await expectLater(
      DVNativeBridge.require<bool>('notifications.sendLocal',
          <String, Object?>{'title': 't', 'body': 'b'}),
      throwsA(isA<Object>()),
    );
  });
}
