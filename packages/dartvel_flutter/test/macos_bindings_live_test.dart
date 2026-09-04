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
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/macos/macos_menus_ffi.dart' show DVMacosObjc;
import 'package:dartvel_flutter/src/platform/macos/macos_serial.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DynamicLibrary _cg = DynamicLibrary.open('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
final DynamicLibrary _appServices =
    DynamicLibrary.open('/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices');

/// Whether the isolate runs on the process's main thread, which is the one
/// whose run loop Carbon delivers hot-key events to.
bool get onMainThread =>
    DynamicLibrary.process().lookupFunction<Int32 Function(), int Function()>('pthread_main_np')() != 0;

/// Whether NSApplication's event loop is running, which is what carries a
/// Carbon hot-key event to its handler; a test harness runs no such loop.
bool get applicationRunning {
  final objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
  Pointer<Void> sel(String name) {
    final p = name.toNativeUtf8();
    try {
      return objc.lookupFunction<Pointer<Void> Function(Pointer<Utf8>), Pointer<Void> Function(Pointer<Utf8>)>('sel_registerName')(p);
    } finally {
      calloc.free(p);
    }
  }
  final Pointer<Utf8> name = 'NSApplication'.toNativeUtf8();
  try {
    final cls = objc.lookupFunction<Pointer<Void> Function(Pointer<Utf8>), Pointer<Void> Function(Pointer<Utf8>)>('objc_getClass')(name);
    final app = objc.lookupFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>), Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend')(cls, sel('sharedApplication'));
    return objc.lookupFunction<Bool Function(Pointer<Void>, Pointer<Void>), bool Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend')(app, sel('isRunning'));
  } finally {
    calloc.free(name);
  }
}

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
      if (!onMainThread) {
        markTestSkipped('the test isolate is not on the main thread, so the run loop pumped here is not the one Carbon delivers hot keys to; registration and refusal above are what this host proves');
        return;
      }
      if (!trusted) {
        markTestSkipped('this process has no Accessibility grant, so a synthesised press is dropped before it reaches anyone');
        return;
      }
      if (!applicationRunning) {
        markTestSkipped('NSApplication is not running its event loop here, and Carbon delivers hot keys only through it; registration and refusal above are what this host proves');
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

  group('tray', () {
    // A status item in the system status bar, its menu read back through
    // AppKit and an item chosen through AppKit; hide removes it.
    tearDown(() {
      DVTray.reset();
      DVMacosTray.unregister();
    });

    test('the item is shown with its menu, a chosen item reaches Dart by id, and hide removes it', () async {
      final List<String> chosen = <String>[];
      await const DVTray().show(
        icon: 'no-such-image.png',
        tooltip: 'Dartvel',
        menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'open', label: 'Open'), DVTrayMenuItem(id: 'quit', label: 'Quit')],
        onSelected: chosen.add,
      );
      expect(DVMacosTray.shown, isTrue);
      expect(DVMacosTray.menuTitles(), <String>['Open', 'Quit']);

      DVMacosTray.performAction(1);
      expect(chosen, <String>['quit']);

      await const DVTray().hide();
      expect(DVMacosTray.shown, isFalse);
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
    // The real panels, answered from their own modal loop the way a person
    // would. What is asserted is what the panel showed and what came back.
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('dartvel_dialogs_');
      File('${dir.path}/notes.txt').writeAsStringSync('hello');
      File('${dir.path}/photo.png').writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47]);
    });
    tearDown(() {
      DVMacosDialogs.automate(null);
      dir.deleteSync(recursive: true);
    });

    test('open: cancel is no files, not an error', () async {
      DVMacosDialogs.automate((DVMacosDialog dialog) => dialog.cancel());
      expect(await DV.Platform.Dialogs.openFile(initialDirectory: dir.path), isEmpty);
    });

    // An open panel is served by another process and its URLs are read-only,
    // so no automation can put a selection into one: the path here is the
    // automation's, and this test proves the plumbing around it -- the title
    // and filters the panel was given, and that a chosen file comes back as
    // a list of one -- rather than proving AppKit's file chooser.
    test('open: the user picks a file and presses Open', () async {
      late DVMacosDialogSeen seen;
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}/notes.txt');
        dialog.accept();
      });
      final List<String> picked = await DV.Platform.Dialogs.openFile(
        title: 'Pick a note',
        filters: const <DVFileFilter>[DVFileFilter(label: 'Text', extensions: <String>['txt'])],
        initialDirectory: dir.path,
      );
      expect(picked.map((String p) => p.split('/').last), <String>['notes.txt']);
      expect(seen.title, 'Pick a note');
      expect(seen.filterLabels, <String>['Text']);
      expect(seen.currentFolder?.split('/').last, dir.path.split('/').last);
    });

    test('save: the suggested name is offered and the chosen path returned', () async {
      late DVMacosDialogSeen seen;
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        seen = dialog.inspect();
        dialog.accept();
      });
      final String? path = await DV.Platform.Dialogs.saveFile(suggestedName: 'report.pdf', initialDirectory: dir.path);
      expect(seen.currentName, 'report.pdf');
      expect(path?.split('/').last, 'report.pdf');
    });

    test('choose a directory', () async {
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        dialog.selectPath('${dir.path}/');
        dialog.accept();
      });
      expect((await DV.Platform.Dialogs.chooseDirectory())?.split('/').last, dir.path.split('/').last);
    });

    test('a message is shown with its text and dismissed', () async {
      late DVMacosDialogSeen seen;
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        seen = dialog.inspect();
        dialog.accept();
      });
      await DV.Platform.Dialogs.message(title: 'Saved', text: 'Your report was saved.', kind: DVDialogKind.info);
      expect(seen.title, 'Saved');
      expect(seen.messageText, contains('Your report was saved.'));
    });

    test('media.pick is the open panel with the kind\'s filters', () async {
      late DVMacosDialogSeen seen;
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}/photo.png');
        dialog.accept();
      });
      final List<Map<String, Object?>> picked = await DV.Platform.media.pick(type: 'image');
      expect(picked.single['name'], 'photo.png');
      expect(picked.single['type'], 'image');
      expect(seen.filterLabels, <String>['Images']);
    });
  });

  // The serial port. A pseudo-terminal is not a UART, but it is a real
  // character device with real termios state, so opening it, putting the line
  // in raw mode, setting the speed, waiting with a timeout, writing and
  // closing all happen for real -- and macOS's termios is not Linux's. Its
  // flag words are eight bytes rather than four, its control array is twenty
  // rather than thirty-two, and its speeds are the numbers themselves rather
  // than small indices, so a struct copied across would read the wrong fields
  // and set a speed nobody asked for.
  group('serial', () {
    late int master;
    late String slave;

    setUp(() {
      final DynamicLibrary libc = DynamicLibrary.process();
      // O_RDWR | O_NOCTTY, and nothing else. posix_openpt takes those two on
      // macOS and refuses anything more; O_NONBLOCK, which Linux ignores
      // here, comes back as a failure to allocate a terminal at all.
      master = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
          'posix_openpt')(0x0002 | 0x20000);
      expect(master, greaterThan(0),
          reason: 'posix_openpt refused to allocate a pseudo-terminal');
      libc.lookupFunction<Int32 Function(Int32), int Function(int)>('grantpt')(master);
      libc.lookupFunction<Int32 Function(Int32), int Function(int)>('unlockpt')(master);
      slave = libc.lookupFunction<Pointer<Utf8> Function(Int32),
          Pointer<Utf8> Function(int)>('ptsname')(master).toDartString();
    });

    tearDown(() {
      DVMacosSerial.closeAll();
      DynamicLibrary.process()
          .lookupFunction<Int32 Function(Int32), int Function(int)>('close')(master);
    });

    test('a port that is not there is refused with the reason', () async {
      await expectLater(
        const DVSerial().open('/dev/cu.NotHere'),
        throwsA(predicate((Object e) => '$e'.contains('/dev/cu.NotHere'))),
      );
    });

    test('bytes written to the device arrive at the port, unaltered', () async {
      final DVSerialConnection port =
          await const DVSerial().open(slave, baud: 115200);
      addTearDown(port.close);

      final Pointer<Uint8> buffer = calloc<Uint8>(5);
      try {
        buffer.asTypedList(5).setAll(0, <int>[0x01, 0x1a, 0x0d, 0x0a, 0xff]);
        DynamicLibrary.process().lookupFunction<
            IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
            int Function(int, Pointer<Uint8>, int)>('write')(master, buffer, 5);
      } finally {
        calloc.free(buffer);
      }

      final Uint8List got = await port.read(timeout: const Duration(seconds: 2));

      // 0x1a ends a cooked terminal and 0x0d becomes 0x0a: in cooked mode
      // this frame arrives short and altered, and a text protocol on the
      // same port would never notice.
      expect(got, <int>[0x01, 0x1a, 0x0d, 0x0a, 0xff]);
    });

    test('the speed asked for is the speed the line is set to', () async {
      final DVSerialConnection port =
          await const DVSerial().open(slave, baud: 115200);
      addTearDown(port.close);

      expect(DVMacosSerial.speedOf(master), 115200);
    });

    test('a read with nothing to read comes back empty at the timeout', () async {
      final DVSerialConnection port = await const DVSerial().open(slave);
      addTearDown(port.close);

      final Stopwatch clock = Stopwatch()..start();
      final Uint8List got =
          await port.read(timeout: const Duration(milliseconds: 200));
      clock.stop();

      expect(got, isEmpty);
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(150));
      expect(clock.elapsedMilliseconds, lessThan(2000));
    });

    test('the ports it lists are ports that exist', () async {
      // A pty is not a serial port and must not be listed as one.
      final List<DVSerialPort> ports = await const DVSerial().ports();

      expect(ports.map((DVSerialPort p) => p.path), isNot(contains(slave)));
      for (final DVSerialPort port in ports) {
        expect(File(port.path).existsSync(), isTrue,
            reason: '${port.path} was listed and is not there');
      }
    });
  });

  group('drag and drop', () {
    // AppKit delivers a drop to the view under the pointer, which reads what
    // was dragged off the dragging pasteboard. The pasteboard reading is the
    // part with the bugs in it -- a file manager writes a list of paths, a
    // browser writes text, and taking the first of one as the other turns a
    // drop of three files into one wrong path -- and it is checked here
    // against a real pasteboard. Registering the view needs a window, which
    // a runner with no run loop does not have.
    tearDown(() {
      DVDragDrop.reset();
      DVMacosDragDrop.unregister();
    });

    DVMacosObjc objc() => DVMacosObjc(DynamicLibrary.open('/usr/lib/libobjc.A.dylib'));

    /// The general pasteboard, which is the one a test can fill; a drop
    /// reads the dragging pasteboard, which is the same kind of object.
    Pointer<Void> pasteboard() {
      final DVMacosObjc o = objc();
      return o.send0(o.cls('NSPasteboard'), 'generalPasteboard');
    }

    void writeFileList(List<String> paths) {
      final DVMacosObjc o = objc();
      final Pointer<Void> board = pasteboard();
      final Pointer<Void> types = o.send0(o.cls('NSMutableArray'), 'array');
      o.send1(types, 'addObject:', o.nsString('NSFilenamesPboardType'));
      o.send2(board, 'declareTypes:owner:', types, nullptr);
      final Pointer<Void> list = o.send0(o.cls('NSMutableArray'), 'array');
      for (final String path in paths) {
        o.send1(list, 'addObject:', o.nsString(path));
      }
      o.send2(board, 'setPropertyList:forType:', list, o.nsString('NSFilenamesPboardType'));
    }

    test('with no window there is nothing to take drops, and it says so', () async {
      await expectLater(const DVDragDrop().accept(), throwsA(isA<StateError>()));
      expect(DVMacosDragDrop.lastError, contains('no window'));
      expect(DVMacosDragDrop.accepting, isFalse);
    });

    test('a pasteboard of files reads as every one of them', () {
      writeFileList(<String>['/Users/ada/notes.txt', '/Users/ada/photo.png']);

      final DVDropEvent event = DVMacosDragDrop.eventFrom(pasteboard());

      expect(event.paths, <String>['/Users/ada/notes.txt', '/Users/ada/photo.png']);
      expect(event.text, isNull);
    });

    test('a pasteboard of text reads as text', () async {
      await DVNativeBridge.require<bool>('clipboard.copy', <String, Object?>{'text': 'https://dartvel.dev'});

      final DVDropEvent event = DVMacosDragDrop.eventFrom(pasteboard());

      expect(event.text, 'https://dartvel.dev');
      expect(event.paths, isEmpty);
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
