@TestOn('mac-os')
library;

// The macOS bindings against the real Objective-C runtime.
//
// The companion suite asserts the capability list from any host, which proves
// what macOS claims and nothing about whether the messaging is right. Sending
// an Objective-C message with a mistyped signature does not fail to compile —
// it corrupts the stack or returns rubbish, so this has to run where the
// runtime is.
import 'dart:async' show unawaited;
import 'dart:ffi';
import 'dart:io' show Directory;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

final DynamicLibrary _cg = DynamicLibrary.open('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
final DynamicLibrary _appServices =
    DynamicLibrary.open('/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices');

/// Whether this process may synthesise input: CGEventPost is silently dropped
/// without the Accessibility grant, which a runner may or may not hold.
bool get trusted =>
    _appServices.lookupFunction<Bool Function(), bool Function()>('AXIsProcessTrusted')();

/// Presses and releases [keyCode] with [flags], through the HID event tap.
void postKey(int keyCode, int flags) {
  final create = _cg.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Uint16, Bool),
      Pointer<Void> Function(Pointer<Void>, int, bool)>('CGEventCreateKeyboardEvent');
  final setFlags = _cg.lookupFunction<
      Void Function(Pointer<Void>, Uint64),
      void Function(Pointer<Void>, int)>('CGEventSetFlags');
  final post = _cg.lookupFunction<
      Void Function(Uint32, Pointer<Void>),
      void Function(int, Pointer<Void>)>('CGEventPost');
  final release = DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
      .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CFRelease');
  for (final bool down in <bool>[true, false]) {
    final Pointer<Void> event = create(nullptr, keyCode, down);
    setFlags(event, flags);
    post(0, event); // kCGHIDEventTap
    release(event);
  }
}

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

  group('global shortcuts', () {
    // Carbon's RegisterEventHotKey, with the press delivered from the run
    // loop by id. The harness runs no loop, so the test pumps it; the press
    // itself is synthesised through the HID tap, which macOS drops without
    // the Accessibility grant -- a runner without it proves registration
    // and refusal and says why delivery was not proven.
    tearDown(() async {
      for (final String id in DVShortcuts.registered) {
        await const DVShortcuts().unregister(id);
      }
    });

    test('a registration is taken, and the same combo twice is refused with the reason', () async {
      await const DVShortcuts().register(const DVGlobalShortcut(id: 'capture', accelerator: 'Ctrl+Option+F9'));
      expect(DVShortcuts.registered, contains('capture'));

      await expectLater(
        const DVShortcuts().register(const DVGlobalShortcut(id: 'again', accelerator: 'Ctrl+Option+F9')),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('RegisterEventHotKey'))),
      );
      expect(DVShortcuts.registered, isNot(contains('again')));
    });

    test('a pressed shortcut reaches its handler by id', () async {
      var pressed = 0;
      await const DVShortcuts().register(
        const DVGlobalShortcut(id: 'capture', accelerator: 'Ctrl+Option+F9'),
        onPressed: () => pressed++,
      );
      if (!trusted) {
        markTestSkipped('this process has no Accessibility grant, so a synthesised press is dropped before it reaches anyone');
        return;
      }
      String? arrived;
      unawaited(const DVShortcuts().pressed.first.then((String id) => arrived = id));

      postKey(0x65, 0x40000 | 0x80000); // kVK_F9 with control and option
      final Stopwatch clock = Stopwatch()..start();
      while (arrived == null && clock.elapsed < const Duration(seconds: 5)) {
        DVMacosShortcuts.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(Duration.zero);
      }

      expect(arrived, 'capture');
      expect(pressed, 1);
    });

    test('unregister frees the combo for the next registration', () async {
      await const DVShortcuts().register(const DVGlobalShortcut(id: 'a', accelerator: 'Ctrl+Option+F10'));
      await const DVShortcuts().unregister('a');
      await const DVShortcuts().register(const DVGlobalShortcut(id: 'b', accelerator: 'Ctrl+Option+F10'));
      expect(DVShortcuts.registered, <String>['b']);
    });
  });

  group('device', () {
    // The shared runtime reading through this platform's probes: the numbers
    // a fleet console shows have to be real ones, from the machine itself.
    late Directory state;
    setUp(() {
      state = Directory.systemTemp.createTempSync('dartvel_device_');
      DVDeviceRuntime.stateDirectory = state.path;
    });
    tearDown(() {
      DVDeviceRuntime.resetWatchdogForTest();
      DVDeviceRuntime.stateDirectory = null;
      state.deleteSync(recursive: true);
    });

    test('the manifest names this machine and what it can do', () async {
      final DVHardwareCapabilityManifest manifest = await const DVDeviceControls().capabilityManifest();
      expect(manifest.deviceId, isNotEmpty);
      Map<String, String> meta(String id) =>
          manifest.capabilities.singleWhere((DVHardwareCapability c) => c.id == id).metadata;
      expect(int.parse(meta('cpu.cores')['count']!), greaterThan(0));
      expect(int.parse(meta('memory')['totalBytes']!), greaterThan(0));
      expect(int.parse(meta('memory')['availableBytes']!), greaterThan(0));
      expect(meta('os')['arch'], anyOf('x64', 'arm64'));
      expect(manifest.capabilities.singleWhere((DVHardwareCapability c) => c.id == 'display').available, isTrue);
    });

    test('health is a verdict with real numbers behind it', () async {
      final DVDeviceHealth health = await const DVDeviceControls().health();
      expect(health.healthy, isA<bool>());
      expect(double.parse(health.diagnostics['uptimeSeconds']!), greaterThan(0));
      expect(int.parse(health.diagnostics['memoryTotalBytes']!), greaterThan(0));
      expect(int.parse(health.diagnostics['diskFreeBytes']!), greaterThan(0));
    });
  });

  group('application menu', () {
    // NSMenu as NSApp's main menu, read back through AppKit and activated
    // through AppKit, so what is asserted is what a user would see and
    // click rather than what Dart remembers asking for.
    tearDown(DVMenus.reset);

    test('the menu ends up as the main menu, with the items asked for', () async {
      await const DVMenus().setApplicationMenu(const DVApplicationMenu(<DVMenuItem>[
        DVMenuItem(id: 'file', label: 'File', children: <DVMenuItem>[
          DVMenuItem(id: 'open', label: 'Open'),
          DVMenuItem(id: 'export', label: 'Export', enabled: false),
        ]),
        DVMenuItem(id: 'help', label: 'Help', children: <DVMenuItem>[DVMenuItem(id: 'about', label: 'About')]),
      ]));

      expect(DVMacosMenus.mainMenuTitles(), <String>['File', 'Help']);
    });

    test('activating an item reaches Dart by id', () async {
      final List<String> selected = <String>[];
      await const DVMenus().setApplicationMenu(
        const DVApplicationMenu(<DVMenuItem>[
          DVMenuItem(id: 'file', label: 'File', children: <DVMenuItem>[DVMenuItem(id: 'open', label: 'Open')]),
        ]),
        onSelected: selected.add,
      );

      DVMacosMenus.performAction(0, 0);

      expect(selected, <String>['open']);
    });

    test('a second menu replaces the first rather than stacking', () async {
      await const DVMenus().setApplicationMenu(const DVApplicationMenu(<DVMenuItem>[
        DVMenuItem(id: 'a', label: 'A', children: <DVMenuItem>[DVMenuItem(id: 'a1', label: 'A1')]),
      ]));
      await const DVMenus().setApplicationMenu(const DVApplicationMenu(<DVMenuItem>[
        DVMenuItem(id: 'b', label: 'B', children: <DVMenuItem>[DVMenuItem(id: 'b1', label: 'B1')]),
      ]));
      expect(DVMacosMenus.mainMenuTitles(), <String>['B']);
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
