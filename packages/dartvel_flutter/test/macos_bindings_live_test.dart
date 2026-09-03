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

  group('kiosk', () {
    // NSApplication's presentation options are macOS's kiosk mechanism: the
    // Dock and menu bar hidden, process switching, force quit, session
    // termination and hiding disabled. Which escape combos that covers is a
    // matter of record -- Cmd+Tab is process switching, Cmd+Option+Esc is
    // force quit -- and what it does not cover, such as Cmd+Q, has to come
    // back unenforced rather than as a claim. The pointer cannot be confined
    // on macOS and notifications cannot be held; neither is claimed.
    tearDown(() => DVNativeBridge.require<bool>('kiosk.release'));

    test('the presentation options are set, and read back', () async {
      final Map<String, Object?> result = (await DVNativeBridge.require<Map<Object?, Object?>>(
        'kiosk.enforce',
        <String, Object?>{
          'combos': <String>['Cmd+Tab', 'Cmd+Option+Escape', 'Cmd+Q'],
          'fullscreen': true,
          'confinePointer': true,
          'suppressNotifications': true,
        },
      )).cast<String, Object?>();

      expect(DVMacosKiosk.presentationOptions, DVMacosKiosk.kioskOptions);
      expect(result['blocked'], containsAll(<String>['Cmd+Tab', 'Cmd+Option+Escape']));
      final Map<Object?, Object?> unenforced = result['unenforced']! as Map<Object?, Object?>;
      expect(unenforced.keys, contains('Cmd+Q'));
      expect('${unenforced['Cmd+Q']}', contains('terminate'));
      expect(result['confined'], isFalse);
      expect(result['notificationsSuppressed'], isFalse);
    });

    test('release restores the default presentation', () async {
      await DVNativeBridge.require<Map<Object?, Object?>>(
        'kiosk.enforce',
        <String, Object?>{'combos': <String>['Cmd+Tab'], 'fullscreen': false, 'confinePointer': false, 'suppressNotifications': false},
      );
      expect(DVMacosKiosk.presentationOptions, isNot(0));
      expect(await DVNativeBridge.require<bool>('kiosk.release'), isTrue);
      expect(DVMacosKiosk.presentationOptions, 0);
    });
  });

  test('an unimplemented binding still throws', () async {
    await expectLater(
      DVNativeBridge.require<bool>(
          'window.setTitle', <String, Object?>{'title': 'x'}),
      throwsA(isA<Object>()),
    );
  });
}
