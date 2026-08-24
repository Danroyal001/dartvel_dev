@TestOn('mac-os')
library;

// The macOS bindings against the real Objective-C runtime.
//
// The companion suite asserts the capability list from any host, which proves
// what macOS claims and nothing about whether the messaging is right. Sending
// an Objective-C message with a mistyped signature does not fail to compile —
// it corrupts the stack or returns rubbish, so this has to run where the
// runtime is.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    expect(DVMacosBindings.register(), isTrue,
        reason: 'libobjc, AppKit and CoreGraphics must open on macOS');
  });

  tearDownAll(DVMacosBindings.unregister);

  test('a clipboard round trip survives non-ASCII text', () async {
    // The pasteboard is declared as public.utf8-plain-text, so anything that
    // silently narrowed to ASCII would come back mangled here and pass a
    // plain-ASCII test.
    const value = 'Dartvel — pasteboard · 日本語 · 🎯';

    await DVNativeBridge.require<bool>(
        'clipboard.copy', <String, Object?>{'text': value});
    expect(await DVNativeBridge.require<String?>('clipboard.paste'), value);
  });

  test('clearContents is called before writing', () async {
    // NSPasteboard rejects a write made without it, so a second copy that
    // still reads back correctly is the evidence that it happened.
    await DVNativeBridge.require<bool>(
        'clipboard.copy', <String, Object?>{'text': 'first'});
    await DVNativeBridge.require<bool>(
        'clipboard.copy', <String, Object?>{'text': 'second'});
    expect(await DVNativeBridge.require<String?>('clipboard.paste'), 'second');
  });

  test('screen.geometry reports a real display', () async {
    final geometry =
        await DVNativeBridge.require<Map<String, Object?>>('screen.geometry');
    expect(geometry['width'] as int, greaterThan(0));
    expect(geometry['height'] as int, greaterThan(0));
  });

  test('an unimplemented binding still throws', () async {
    await expectLater(
      DVNativeBridge.require<bool>(
          'window.setTitle', <String, Object?>{'title': 'x'}),
      throwsA(isA<Object>()),
    );
  });
}
