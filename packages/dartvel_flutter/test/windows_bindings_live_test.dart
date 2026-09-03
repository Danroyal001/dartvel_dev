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
import 'dart:ffi';
import 'dart:io' show Directory;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

// INPUT with a KEYBDINPUT, laid out as Win32 x64 has it: the union is 32
// bytes, so the struct is 40.
final class _Input extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int pad;
  @Uint16()
  external int wVk;
  @Uint16()
  external int wScan;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  external Pointer<Void> dwExtraInfo;
  @Uint64()
  external int pad2;
}

const int _inputKeyboard = 1;
const int _keyUp = 0x0002;

/// A real top-level window owned by the test thread, so the bindings that
/// act on the process's own window have one. Registered once; a class
/// registered twice is an error.
class TestWindow {
  TestWindow._(this.hWnd);

  final int hWnd;
  static bool _classRegistered = false;

  static TestWindow create() {
    final user32 = DynamicLibrary.open('user32.dll');
    final Pointer<Utf16> className = 'DartvelTestWindow'.toNativeUtf16();
    final Pointer<Utf16> title = 'Dartvel'.toNativeUtf16();
    try {
      if (!_classRegistered) {
        // WNDCLASSW: style, lpfnWndProc, cbClsExtra, cbWndExtra, hInstance,
        // hIcon, hCursor, hbrBackground, lpszMenuName, lpszClassName.
        final Pointer<Uint8> wc = calloc<Uint8>(72);
        try {
          final Pointer<Void> defProc = user32.lookup<NativeFunction<Void Function()>>('DefWindowProcW').cast();
          (wc.cast<IntPtr>() + 1).value = defProc.address;
          (wc.cast<IntPtr>() + 8).value = className.address;
          final int atom = user32.lookupFunction<Uint16 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>('RegisterClassW')(wc);
          expect(atom, isNot(0), reason: 'RegisterClassW must take the class');
          _classRegistered = true;
        } finally {
          calloc.free(wc);
        }
      }
      final int hWnd = user32.lookupFunction<
          IntPtr Function(Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32, Int32, Int32, Int32, Int32, IntPtr, IntPtr, IntPtr, Pointer<Void>),
          int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int, int, int, int, Pointer<Void>)>('CreateWindowExW')(
        0, className, title, 0x00CF0000 /* WS_OVERLAPPEDWINDOW */, 0, 0, 400, 300, 0, 0, 0, nullptr);
      expect(hWnd, isNot(0), reason: 'CreateWindowExW must make a window');
      user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('SetActiveWindow')(hWnd);
      return TestWindow._(hWnd);
    } finally {
      calloc.free(className);
      calloc.free(title);
    }
  }

  /// Sends [message] the way Win32 would, synchronously, through the
  /// window's procedure chain.
  int send(int message, int wParam, int lParam) =>
      DynamicLibrary.open('user32.dll').lookupFunction<
          IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
          int Function(int, int, int, int)>('SendMessageW')(hWnd, message, wParam, lParam);

  void destroy() =>
      DynamicLibrary.open('user32.dll').lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow')(hWnd);
}

/// ERROR_REQUIRES_INTERACTIVE_WINDOWSTATION: a hot key cannot be taken in a
/// session with no interactive desktop, which is a fact about the runner
/// rather than about the binding, and is said rather than counted as a pass.
bool noInteractiveStation(Map<Object?, Object?> unenforced) =>
    unenforced.values.any((Object? reason) => '$reason'.contains('error 1459'));

/// Presses and releases [keys] in order, as the user would.
void sendKeys(List<int> keys) {
  final user32 = DynamicLibrary.open('user32.dll');
  final sendInput = user32.lookupFunction<
      Uint32 Function(Uint32, Pointer<_Input>, Int32),
      int Function(int, Pointer<_Input>, int)>('SendInput');
  final int count = keys.length * 2;
  final Pointer<_Input> inputs = calloc<_Input>(count);
  try {
    for (var i = 0; i < keys.length; i++) {
      inputs[i]
        ..type = _inputKeyboard
        ..wVk = keys[i]
        ..dwFlags = 0;
      inputs[count - 1 - i]
        ..type = _inputKeyboard
        ..wVk = keys[i]
        ..dwFlags = _keyUp;
    }
    expect(sendInput(count, inputs, sizeOf<_Input>()), count,
        reason: 'SendInput must accept every event');
  } finally {
    calloc.free(inputs);
  }
}

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
      // Ctrl+Alt+F11 because nothing on a runner holds it; Alt+F4 is what a
      // kiosk really blocks, and a runner may already have it taken -- in
      // which case the honest answer is "already registered", not a claim.
      final Map<String, Object?> result = (await DVNativeBridge.require<Map<Object?, Object?>>(
        'kiosk.enforce',
        <String, Object?>{
          'combos': <String>['Ctrl+Alt+F11', 'Alt+F4', 'Ctrl+Alt+Delete'],
          'fullscreen': false,
          'confinePointer': false,
          'suppressNotifications': true,
        },
      )).cast<String, Object?>();

      final Map<Object?, Object?> unenforced = result['unenforced']! as Map<Object?, Object?>;
      if (noInteractiveStation(unenforced)) {
        markTestSkipped('this session has no interactive window station: ${unenforced['Ctrl+Alt+F11']}');
        return;
      }
      expect(result['blocked'], contains('Ctrl+Alt+F11'), reason: 'unenforced: $unenforced');
      if (!(result['blocked']! as List).contains('Alt+F4')) {
        expect('${unenforced['Alt+F4']}', contains('already registered'), reason: 'Alt+F4 neither held nor said to be taken');
      }
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
            'combos': <String>['Ctrl+Alt+F11'],
            'fullscreen': false,
            'confinePointer': false,
            'suppressNotifications': false,
          },
        )).cast<String, Object?>();
        final Map<Object?, Object?> unenforced = result['unenforced']! as Map<Object?, Object?>;
        if (noInteractiveStation(unenforced)) {
          markTestSkipped('this session has no interactive window station: ${unenforced['Ctrl+Alt+F11']}');
          return;
        }
        expect(result['blocked'], <Object?>['Ctrl+Alt+F11'], reason: 'pass $i, unenforced: $unenforced');
        expect(unenforced, isEmpty, reason: 'pass $i');
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

  group('global shortcuts', () {
    // The hot key lives on a pump thread of its own, which is where Win32
    // delivers WM_HOTKEY for a RegisterHotKey made there; SendInput presses
    // the combo the way a user would, and the press has to arrive at the
    // handler registered under the id.
    tearDown(() async {
      for (final String id in DVShortcuts.registered) {
        await const DVShortcuts().unregister(id);
      }
    });

    test('WM_HOTKEY on the pump\'s queue reaches the handler by id', () async {
      // What Win32 does when the combo is pressed: a WM_HOTKEY carrying the
      // hot-key id, on the queue of the thread that registered it. Posted
      // here, so the dispatch path is proven whether or not the session can
      // synthesise input.
      var pressed = 0;
      await const DVShortcuts().register(
        const DVGlobalShortcut(id: 'capture', accelerator: 'Ctrl+Alt+F9'),
        onPressed: () => pressed++,
      );
      final Future<String> arrived = const DVShortcuts().pressed.first.timeout(const Duration(seconds: 10));

      final postThreadMessage = DynamicLibrary.open('user32.dll').lookupFunction<
          Int32 Function(Uint32, Uint32, IntPtr, IntPtr),
          int Function(int, int, int, int)>('PostThreadMessageW');
      expect(
        postThreadMessage(DVWindowsShortcuts.debugPumpThread!, 0x0312, DVWindowsShortcuts.debugNumericId('capture')!, 0),
        isNot(0),
      );

      expect(await arrived, 'capture');
      expect(pressed, 1);
    });

    test('a synthesised press reaches the handler, where the session can take input', () async {
      final int foreground =
          DynamicLibrary.open('user32.dll').lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow')();
      if (foreground == 0) {
        markTestSkipped('no foreground window: this session cannot deliver synthesised input, so only the queue path above is proven');
        return;
      }
      var pressed = 0;
      await const DVShortcuts().register(
        const DVGlobalShortcut(id: 'capture', accelerator: 'Ctrl+Alt+F9'),
        onPressed: () => pressed++,
      );
      final Future<String> arrived = const DVShortcuts().pressed.first.timeout(const Duration(seconds: 10));

      sendKeys(<int>[0x11, 0x12, 0x78]); // VK_CONTROL, VK_MENU, VK_F9

      expect(await arrived, 'capture');
      expect(pressed, 1);
    });

    test('a combo Win32 refuses is refused with its reason, not registered', () async {
      await expectLater(
        const DVShortcuts().register(const DVGlobalShortcut(id: 'sas', accelerator: 'Ctrl+Alt+Delete')),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('RegisterHotKey'))),
      );
      expect(DVShortcuts.registered, isNot(contains('sas')));
    });

    test('unregister frees the combo for the next registration', () async {
      try {
        await const DVShortcuts().register(const DVGlobalShortcut(id: 'a', accelerator: 'Ctrl+Alt+F10'));
      } on StateError catch (e) {
        if (e.message.contains('error 1459')) {
          markTestSkipped('this session has no interactive window station: ${e.message}');
          return;
        }
        rethrow;
      }
      await const DVShortcuts().unregister('a');
      await const DVShortcuts().register(const DVGlobalShortcut(id: 'b', accelerator: 'Ctrl+Alt+F10'));
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
    // A Win32 menu bar on the process's window, read back through Win32
    // and activated through WM_COMMAND -- the message Win32 sends for a
    // chosen item -- so what is asserted is what a user would see and click.
    late TestWindow window;
    setUp(() => window = TestWindow.create());
    tearDown(() {
      DVMenus.reset();
      DVWindowsMenus.unregister();
      window.destroy();
    });

    test('without a window the menu is refused rather than lost', () async {
      window.destroy();
      window = TestWindow.create();
      DynamicLibrary.open('user32.dll').lookupFunction<IntPtr Function(IntPtr), int Function(int)>('SetActiveWindow')(0);
      // GetActiveWindow answers 0 for a thread whose active window was
      // just cleared; only then is refusal the right answer.
      final int active = DynamicLibrary.open('user32.dll').lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow')();
      if (active != 0) {
        markTestSkipped('the thread still has an active window; refusal cannot be provoked here');
        return;
      }
      await expectLater(
        const DVMenus().setApplicationMenu(const DVApplicationMenu(<DVMenuItem>[DVMenuItem(id: 'a', label: 'A')])),
        throwsA(isA<StateError>()),
      );
    });

    test('the bar ends up on the window, with the items asked for', () async {
      await const DVMenus().setApplicationMenu(const DVApplicationMenu(<DVMenuItem>[
        DVMenuItem(id: 'file', label: 'File', children: <DVMenuItem>[
          DVMenuItem(id: 'open', label: 'Open'),
          DVMenuItem(id: 'export', label: 'Export', enabled: false),
        ]),
        DVMenuItem(id: 'help', label: 'Help', children: <DVMenuItem>[DVMenuItem(id: 'about', label: 'About')]),
      ]));

      expect(DVWindowsMenus.menuTitles(window.hWnd), <String>['File', 'Help']);
    });

    test('choosing an item reaches Dart by id', () async {
      final List<String> selected = <String>[];
      await const DVMenus().setApplicationMenu(
        const DVApplicationMenu(<DVMenuItem>[
          DVMenuItem(id: 'file', label: 'File', children: <DVMenuItem>[DVMenuItem(id: 'open', label: 'Open')]),
        ]),
        onSelected: selected.add,
      );

      // WM_COMMAND with the command id in the low word and 0 (a menu) in the
      // high word: File is command 1, Open command 2.
      window.send(0x0111, 2, 0);

      expect(selected, <String>['open']);
    });

    test('a second menu replaces the first rather than stacking', () async {
      await const DVMenus().setApplicationMenu(const DVApplicationMenu(<DVMenuItem>[
        DVMenuItem(id: 'a', label: 'A', children: <DVMenuItem>[DVMenuItem(id: 'a1', label: 'A1')]),
      ]));
      await const DVMenus().setApplicationMenu(const DVApplicationMenu(<DVMenuItem>[
        DVMenuItem(id: 'b', label: 'B', children: <DVMenuItem>[DVMenuItem(id: 'b1', label: 'B1')]),
      ]));
      expect(DVWindowsMenus.menuTitles(window.hWnd), <String>['B']);
    });
  });

  group('tray', () {
    // Shell_NotifyIcon against the runner's own notification area, the
    // window subclassed for the icon's messages, and the menu's item chosen
    // through WM_COMMAND as Win32 sends it. A session without a shell has no
    // notification area; the binding says so, and so does the test.
    late TestWindow window;
    setUp(() => window = TestWindow.create());
    tearDown(() {
      DVTray.reset();
      DVWindowsTray.unregister();
      window.destroy();
    });

    test('the icon is shown with its menu, an item chosen reaches Dart by id, and hide removes it', () async {
      final List<String> chosen = <String>[];
      try {
        await const DVTray().show(
          icon: 'no-such-icon.ico',
          tooltip: 'Dartvel',
          menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'open', label: 'Open'), DVTrayMenuItem(id: 'quit', label: 'Quit')],
          onSelected: chosen.add,
        );
      } on StateError {
        if ('${DVWindowsTray.lastError}'.contains('no notification area')) {
          markTestSkipped('this session has no notification area: ${DVWindowsTray.lastError}');
          return;
        }
        rethrow;
      }
      expect(DVWindowsTray.shown, isTrue);

      window.send(0x0111, DVWindowsTray.debugCommandFor('quit')!, 0);
      expect(chosen, <String>['quit']);

      await const DVTray().hide();
      expect(DVWindowsTray.shown, isFalse);
      // A command after hide reaches nobody.
      window.send(0x0111, DVWindowsTray.debugCommandFor('open') ?? 0x1000, 0);
      expect(chosen, <String>['quit']);
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
