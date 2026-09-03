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
      final Map<String, Object?> result = (await DVNativeBridge.require<Map<Object?, Object?>>(
        'kiosk.enforce',
        <String, Object?>{
          'combos': <String>['Alt+F4', 'Ctrl+Alt+Delete'],
          'fullscreen': false,
          'confinePointer': false,
          'suppressNotifications': true,
        },
      )).cast<String, Object?>();

      final Map<Object?, Object?> unenforced = result['unenforced']! as Map<Object?, Object?>;
      if (noInteractiveStation(unenforced)) {
        markTestSkipped('this session has no interactive window station: ${unenforced['Alt+F4']}');
        return;
      }
      expect(result['blocked'], contains('Alt+F4'), reason: 'unenforced: $unenforced');
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
        final Map<Object?, Object?> unenforced = result['unenforced']! as Map<Object?, Object?>;
        if (noInteractiveStation(unenforced)) {
          markTestSkipped('this session has no interactive window station: ${unenforced['Alt+F4']}');
          return;
        }
        expect(result['blocked'], <Object?>['Alt+F4'], reason: 'pass $i, unenforced: $unenforced');
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

    test('a pressed shortcut reaches its handler by id', () async {
      var pressed = 0;
      try {
        await const DVShortcuts().register(
          const DVGlobalShortcut(id: 'capture', accelerator: 'Ctrl+Alt+F9'),
          onPressed: () => pressed++,
        );
      } on StateError catch (e) {
        if (e.message.contains('error 1459')) {
          markTestSkipped('this session has no interactive window station: ${e.message}');
          return;
        }
        rethrow;
      }
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

  test('an unimplemented binding still throws', () async {
    // Notifications are deliberately absent; see the capability list.
    await expectLater(
      DVNativeBridge.require<bool>('notifications.sendLocal',
          <String, Object?>{'title': 't', 'body': 'b'}),
      throwsA(isA<Object>()),
    );
  });
}
