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
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
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

/// DROPFILES, as Win32 lays it out: the offset the names start at, the
/// point of the drop, and two flags -- the second says the names are wide.
final class _DropFiles extends Struct {
  @Uint32()
  external int pFiles;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int fNC;
  @Int32()
  external int fWide;
}

/// Puts [paths] on the clipboard as CF_HDROP, the way a file manager does.
void putFilesOnClipboard(List<String> paths) {
  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final List<int> units = <int>[
    for (final String path in paths) ...path.codeUnits, 0,
    0,
  ];
  const int header = 20;
  final int bytes = header + units.length * 2;
  final int handle = kernel32.lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>('GlobalAlloc')(
      0x0002 /* GMEM_MOVEABLE */, bytes);
  expect(handle, isNot(0));
  final Pointer<Void> locked =
      kernel32.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('GlobalLock')(handle);
  expect(locked, isNot(nullptr));
  final Pointer<_DropFiles> drop = locked.cast<_DropFiles>();
  drop.ref
    ..pFiles = header
    ..x = 0
    ..y = 0
    ..fNC = 0
    ..fWide = 1;
  final Pointer<Uint16> names = (locked.cast<Uint8>() + header).cast<Uint16>();
  for (var i = 0; i < units.length; i++) {
    names[i] = units[i];
  }
  kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('GlobalUnlock')(handle);

  expect(user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('OpenClipboard')(0), isNot(0));
  user32.lookupFunction<Int32 Function(), int Function()>('EmptyClipboard')();
  user32.lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>('SetClipboardData')(
      15 /* CF_HDROP */, handle);
  user32.lookupFunction<Int32 Function(), int Function()>('CloseClipboard')();
}

/// The clipboard's contents as an IDataObject, which is the same interface
/// OLE hands a drop target.
Pointer<Void> clipboardDataObject() {
  final ole32 = DynamicLibrary.open('ole32.dll');
  ole32.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('OleInitialize')(nullptr);
  final Pointer<Pointer<Void>> out = calloc<Pointer<Void>>();
  try {
    final int hr = ole32.lookupFunction<Int32 Function(Pointer<Pointer<Void>>), int Function(Pointer<Pointer<Void>>)>(
        'OleGetClipboard')(out);
    expect(hr, 0, reason: 'OleGetClipboard must hand back the clipboard as a data object');
    return out.value;
  } finally {
    calloc.free(out);
  }
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


/// A coloured page with a line of text, as PNG bytes.
Future<Uint8List> page(Color colour, String text) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 600, 800), Paint()..color = colour);
  final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 40))
    ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)))
    ..addText(text);
  final ui.Paragraph paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 560));
  canvas.drawParagraph(paragraph, const Offset(20, 20));
  final ui.Image image = await recorder.endRecording().toImage(600, 800);
  final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
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


  group('printing', () {
    // Pictures onto pages, to a PDF the platform writes itself: the file has
    // to exist, be a PDF, and report as many pages as were sent. A page that
    // is not a picture is refused with no file left behind.
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dartvel_print_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('two pictures become a two-page PDF', () async {
      final String path = '${dir.path}${Platform.pathSeparator}out.pdf';
      final DVPrintResult result = await DV.Platform.Printing.toFile(
        path,
        pages: <Uint8List>[await page(const Color(0xFFFFEEDD), 'Page one'), await page(const Color(0xFFDDEEFF), 'Page two')],
      );
      expect(result.pages, 2);
      final File pdf = File(path);
      expect(pdf.existsSync(), isTrue);
      final Uint8List bytes = pdf.readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('a page that is not a picture is refused, and no file is written', () async {
      final String path = '${dir.path}${Platform.pathSeparator}bad.pdf';
      await expectLater(
        DV.Platform.Printing.toFile(path, pages: <Uint8List>[Uint8List.fromList(<int>[1, 2, 3])]),
        throwsA(isA<StateError>()),
      );
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('dialogs', () {
    // The real common dialogs, answered from their own hooks the way a
    // person would: a path typed, OK or Cancel pressed. What is asserted is
    // what the dialog showed and what came back.
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('dartvel_dialogs_');
      File('${dir.path}\\notes.txt').writeAsStringSync('hello');
      File('${dir.path}\\photo.png').writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47]);
    });
    tearDown(() {
      DVWindowsDialogs.automate(null);
      dir.deleteSync(recursive: true);
    });

    test('open: the user picks a file and presses Open', () async {
      late DVWindowsDialogSeen seen;
      DVWindowsDialogs.automate((DVWindowsDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}\\notes.txt');
        dialog.accept();
      });
      final List<String> picked = await DV.Platform.Dialogs.openFile(
        title: 'Pick a note',
        filters: const <DVFileFilter>[DVFileFilter(label: 'Text', extensions: <String>['txt'])],
        initialDirectory: dir.path,
      );
      // The same file, not the same string. The temp directory comes back
      // from Dart as an 8.3 short path (C:\Users\RUNNER~1\...) and the
      // dialog answers with the long one, which is the better answer of the
      // two; comparing the text would fail on a difference that is only
      // spelling.
      expect(picked, hasLength(1), reason: 'dialog: ${DVWindowsDialogs.lastError}');
      expect(
        File(picked.single).resolveSymbolicLinksSync(),
        File('${dir.path}\\notes.txt').resolveSymbolicLinksSync(),
      );
      expect(seen.title, 'Pick a note');
      expect(seen.filterLabels, <String>['Text']);
      expect(
        Directory(seen.currentFolder!).resolveSymbolicLinksSync().toLowerCase(),
        Directory(dir.path).resolveSymbolicLinksSync().toLowerCase(),
      );
    });

    test('open: cancel is no files, not an error', () async {
      DVWindowsDialogs.automate((DVWindowsDialog dialog) => dialog.cancel());
      expect(await DV.Platform.Dialogs.openFile(initialDirectory: dir.path), isEmpty);
    });

    test('save: the suggested name is offered and the chosen path returned', () async {
      late DVWindowsDialogSeen seen;
      DVWindowsDialogs.automate((DVWindowsDialog dialog) {
        seen = dialog.inspect();
        dialog.accept();
      });
      final String? path = await DV.Platform.Dialogs.saveFile(suggestedName: 'report.pdf', initialDirectory: dir.path);
      expect(seen.currentName, 'report.pdf');
      expect(path?.toLowerCase(), '${dir.path}\\report.pdf'.toLowerCase());
    });

    test('choose a directory', () async {
      DVWindowsDialogs.automate((DVWindowsDialog dialog) {
        dialog.selectPath(dir.path);
        dialog.accept();
      });
      final String? chosen = await DV.Platform.Dialogs.chooseDirectory();
      expect(chosen, isNotNull, reason: 'dialog: ${DVWindowsDialogs.lastError}');
      // The same directory, not the same spelling: see the open test above.
      expect(
        Directory(chosen!).resolveSymbolicLinksSync().toLowerCase(),
        Directory(dir.path).resolveSymbolicLinksSync().toLowerCase(),
      );
    });

    test('a message is shown with its text and dismissed', () async {
      late DVWindowsDialogSeen seen;
      DVWindowsDialogs.automate((DVWindowsDialog dialog) {
        seen = dialog.inspect();
        dialog.accept();
      });
      await DV.Platform.Dialogs.message(title: 'Saved', text: 'Your report was saved.', kind: DVDialogKind.info);
      expect(seen.title, 'Saved');
      expect(seen.messageText, contains('Your report was saved.'));
    });

    test('media.pick is the open dialog with the kind\'s filters', () async {
      late DVWindowsDialogSeen seen;
      DVWindowsDialogs.automate((DVWindowsDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}\\photo.png');
        dialog.accept();
      });
      final List<Map<String, Object?>> picked = await DV.Platform.media.pick(type: 'image');
      expect(picked.single['path'], '${dir.path}\\photo.png');
      expect(picked.single['type'], 'image');
      expect(picked.single['name'], 'photo.png');
      expect(seen.filterLabels, <String>['Images']);
    });
  });

  group('drag and drop', () {
    // A drop arrives through COM: OLE calls the registered IDropTarget with
    // an IDataObject holding what is being dragged. The data object here is
    // a real one -- the clipboard's, which is the same interface Explorer
    // hands over -- and it is given to the target the way OLE gives it. What
    // a runner cannot do is drag from another application, so the drag
    // itself is not exercised; everything the drop does is.
    late TestWindow window;
    setUp(() => window = TestWindow.create());
    tearDown(() async {
      await const DVDragDrop().stop();
      DVDragDrop.reset();
      window.destroy();
    });

    test('the window registers as a drop target, and stops being one', () async {
      await const DVDragDrop().accept();
      expect(DVWindowsDragDrop.accepting, isTrue, reason: DVWindowsDragDrop.lastError);

      await const DVDragDrop().stop();
      expect(DVWindowsDragDrop.accepting, isFalse);
    });

    test('dropped files reach Dart as paths, where they landed', () async {
      final List<DVDropEvent> got = <DVDropEvent>[];
      await const DVDragDrop().accept(onDrop: got.add);
      putFilesOnClipboard(<String>[r'C:\Users\ada\notes.txt', r'C:\Users\ada\photo.png']);

      DVWindowsDragDrop.debugDrop(clipboardDataObject(), x: 40, y: 60);

      expect(got.single.paths, <String>[r'C:\Users\ada\notes.txt', r'C:\Users\ada\photo.png']);
      expect(got.single.x, 40);
      expect(got.single.y, 60);
    });

    test('dropped text reaches Dart as text', () async {
      final List<DVDropEvent> got = <DVDropEvent>[];
      await const DVDragDrop().accept(onDrop: got.add);
      // The clipboard binding writes CF_UNICODETEXT, which is what a
      // browser puts on a drag.
      await DVNativeBridge.require<bool>('clipboard.copy', <String, Object?>{'text': 'https://dartvel.dev'});

      DVWindowsDragDrop.debugDrop(clipboardDataObject());

      expect(got.single.text, 'https://dartvel.dev');
      expect(got.single.paths, isEmpty);
    });

    test('a drop after stop reaches nobody', () async {
      final List<DVDropEvent> got = <DVDropEvent>[];
      await const DVDragDrop().accept(onDrop: got.add);
      putFilesOnClipboard(<String>[r'C:\late.txt']);
      await const DVDragDrop().stop();

      DVWindowsDragDrop.debugDrop(clipboardDataObject());

      expect(got, isEmpty);
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
