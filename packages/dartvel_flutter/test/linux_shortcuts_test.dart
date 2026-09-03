// A global shortcut on Linux, grabbed through X11 and pressed through XTest.
//
// Only under an X server: XGrabKey needs a display, and a keyboard event has
// to come from somewhere. XTest is that somewhere -- the extension real
// automation tools use -- so the press here is a press the X server delivered
// to a grab, not a call into the handler from the test.
//
// What the suite holds: a registered shortcut fires its handler when its keys
// are pressed; a press with an extra modifier does not; and unregistering
// releases the grab so the same keys then fire nothing. The last is the one
// that matters most: a grab left behind eats a key combination from every
// other application on the desktop until the process dies.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _XOpenDisplayN = Pointer<Void> Function(Pointer<Utf8>);
typedef _XOpenDisplayD = Pointer<Void> Function(Pointer<Utf8>);
typedef _XCloseDisplayN = Int32 Function(Pointer<Void>);
typedef _XCloseDisplayD = int Function(Pointer<Void>);
typedef _XFlushN = Int32 Function(Pointer<Void>);
typedef _XFlushD = int Function(Pointer<Void>);
typedef _XStringToKeysymN = Uint64 Function(Pointer<Utf8>);
typedef _XStringToKeysymD = int Function(Pointer<Utf8>);
typedef _XKeysymToKeycodeN = Uint8 Function(Pointer<Void>, Uint64);
typedef _XKeysymToKeycodeD = int Function(Pointer<Void>, int);
typedef _XTestFakeKeyEventN = Int32 Function(
    Pointer<Void>, Uint32, Int32, Uint64);
typedef _XTestFakeKeyEventD = int Function(Pointer<Void>, int, int, int);

/// Presses and releases a chord through XTest, on its own connection.
class _Keyboard {
  _Keyboard()
      : _x11 = DynamicLibrary.open('libX11.so.6'),
        _xtst = DynamicLibrary.open('libXtst.so.6') {
    _display = _x11.lookupFunction<_XOpenDisplayN, _XOpenDisplayD>(
        'XOpenDisplay')(nullptr);
    if (_display == nullptr) throw StateError('no X display');
  }

  final DynamicLibrary _x11;
  final DynamicLibrary _xtst;
  late final Pointer<Void> _display;

  int _keycode(String keysym) {
    final Pointer<Utf8> name = keysym.toNativeUtf8();
    try {
      final int sym = _x11.lookupFunction<_XStringToKeysymN,
          _XStringToKeysymD>('XStringToKeysym')(name);
      expect(sym, isNot(0), reason: '$keysym is not a keysym');
      return _x11.lookupFunction<_XKeysymToKeycodeN, _XKeysymToKeycodeD>(
          'XKeysymToKeycode')(_display, sym);
    } finally {
      calloc.free(name);
    }
  }

  void chord(List<String> keysyms) {
    final _XTestFakeKeyEventD fake = _xtst.lookupFunction<
        _XTestFakeKeyEventN, _XTestFakeKeyEventD>('XTestFakeKeyEvent');
    final _XFlushD flush =
        _x11.lookupFunction<_XFlushN, _XFlushD>('XFlush');
    final List<int> codes = <int>[for (final String k in keysyms) _keycode(k)];
    for (final int c in codes) {
      fake(_display, c, 1, 0);
    }
    for (final int c in codes.reversed) {
      fake(_display, c, 0, 0);
    }
    flush(_display);
  }

  void close() {
    _x11.lookupFunction<_XCloseDisplayN, _XCloseDisplayD>('XCloseDisplay')(
        _display);
  }
}

Future<bool> fires(Future<void> Function() press, Completer<void> signal) async {
  await press();
  try {
    await signal.future.timeout(const Duration(seconds: 3));
    return true;
  } on TimeoutException {
    return false;
  }
}

void main() {
  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test('linux shortcuts (skipped: no X display)', () {},
        skip: 'Run under an X server (xvfb-run works) to exercise XGrabKey.');
    return;
  }

  late _Keyboard keyboard;

  setUpAll(() {
    expect(DVLinuxBindings.register(), isTrue);
    keyboard = _Keyboard();
  });

  tearDownAll(() {
    keyboard.close();
    DVLinuxBindings.unregister();
  });

  setUp(DVShortcuts.reset);

  test('shortcuts are among what the Linux bindings implement', () {
    expect(DVLinuxBindings.implemented,
        containsAll(<String>['shortcuts.register', 'shortcuts.unregister']));
  });

  test('pressing the registered keys fires the handler', () async {
    final Completer<void> pressed = Completer<void>();
    await const DVShortcuts().register(
      const DVGlobalShortcut(id: 'open', accelerator: 'Ctrl+K'),
      onPressed: () {
        if (!pressed.isCompleted) pressed.complete();
      },
    );

    // Grabs are asynchronous on the wire; give the server a moment.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final bool fired = await fires(
        () async => keyboard.chord(<String>['Control_L', 'k']), pressed);

    expect(fired, isTrue);
  });

  test('the same keys with an extra modifier do not', () async {
    var count = 0;
    await const DVShortcuts().register(
      const DVGlobalShortcut(id: 'open', accelerator: 'Ctrl+K'),
      onPressed: () => count++,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    keyboard.chord(<String>['Control_L', 'Shift_L', 'k']);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(count, 0, reason: 'Ctrl+Shift+K is a different shortcut');
  });

  test('unregistering releases the grab', () async {
    var count = 0;
    await const DVShortcuts().register(
      const DVGlobalShortcut(id: 'open', accelerator: 'Ctrl+K'),
      onPressed: () => count++,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await const DVShortcuts().unregister('open');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    keyboard.chord(<String>['Control_L', 'k']);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(count, 0, reason: 'a grab left behind eats the keys for every '
        'other application until the process dies');
  });

  test('a key that does not exist is refused, not silently grabbed as nothing',
      () async {
    await expectLater(
      const DVShortcuts().register(
          const DVGlobalShortcut(id: 'x', accelerator: 'Ctrl+NoSuchKey')),
      throwsA(isA<StateError>()),
    );
  });
}
