// Kiosk key blocking on Linux, against a real X server.
//
// The block is a grab: the X server hands the combo to this process and to
// nobody else, which is exactly what "the window switcher does nothing"
// means. Under Xvfb there is no window manager to notice, but a grab is a
// grab -- XTest presses the keys and the kiosk reports them blocked, and
// after release() the same press reports nothing.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_kiosk_ffi.dart';
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
typedef _XTestFakeKeyEventN = Int32 Function(Pointer<Void>, Uint32, Int32, Uint64);
typedef _XTestFakeKeyEventD = int Function(Pointer<Void>, int, int, int);

class _Keyboard {
  _Keyboard()
      : _x11 = DynamicLibrary.open('libX11.so.6'),
        _xtst = DynamicLibrary.open('libXtst.so.6') {
    _display = _x11.lookupFunction<_XOpenDisplayN, _XOpenDisplayD>('XOpenDisplay')(nullptr);
    if (_display == nullptr) throw StateError('no X display');
  }

  final DynamicLibrary _x11;
  final DynamicLibrary _xtst;
  late final Pointer<Void> _display;

  int _keycode(String keysym) {
    final Pointer<Utf8> name = keysym.toNativeUtf8();
    try {
      final int sym = _x11.lookupFunction<_XStringToKeysymN, _XStringToKeysymD>('XStringToKeysym')(name);
      expect(sym, isNot(0), reason: '$keysym is not a keysym');
      return _x11.lookupFunction<_XKeysymToKeycodeN, _XKeysymToKeycodeD>('XKeysymToKeycode')(_display, sym);
    } finally {
      calloc.free(name);
    }
  }

  void chord(List<String> keysyms) {
    final _XTestFakeKeyEventD fake =
        _xtst.lookupFunction<_XTestFakeKeyEventN, _XTestFakeKeyEventD>('XTestFakeKeyEvent');
    final _XFlushD flush = _x11.lookupFunction<_XFlushN, _XFlushD>('XFlush');
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
    _x11.lookupFunction<_XCloseDisplayN, _XCloseDisplayD>('XCloseDisplay')(_display);
  }
}

DVKioskPolicy policy({String scope = 'device', Map<String, Object?> input = const <String, Object?>{}}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': scope,
        'home': '/',
        'input': input,
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

Future<String?> nextBlocked({Duration within = const Duration(seconds: 3)}) async {
  try {
    return await DVKiosk.blocked.first.timeout(within);
  } on TimeoutException {
    return null;
  }
}

void main() {
  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test('linux kiosk (skipped: no X display)', () {}, skip: 'Run under an X server (xvfb-run works).');
    return;
  }

  late _Keyboard keyboard;

  setUpAll(() {
    expect(DVLinuxBindings.register(), isTrue);
    keyboard = _Keyboard();
  });

  tearDownAll(() async {
    keyboard.close();
    await DVKiosk.release();
    DVLinuxBindings.unregister();
  });

  test('kiosk enforcement is among what the Linux bindings implement', () {
    expect(DVLinuxBindings.implemented, containsAll(<String>['kiosk.enforce', 'kiosk.release']));
  });

  test('a blocked combo is swallowed and reported; after release it is not', () async {
    final DVKioskEnforced result = await DVKiosk.enforce(policy());
    expect(result.blocked, contains('Alt+tab'));
    expect(result.blocked, isNot(contains('tab')));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final Future<String?> seen = nextBlocked();
    keyboard.chord(<String>['Alt_L', 'Tab']);
    expect(await seen, 'Alt+tab');

    await DVKiosk.release();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final Future<String?> after = nextBlocked(within: const Duration(milliseconds: 700));
    keyboard.chord(<String>['Alt_L', 'Tab']);
    expect(await after, isNull, reason: 'released means the switcher works again');
  });

  test('an exempt key is never grabbed', () async {
    await DVKiosk.enforce(policy());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final Future<String?> seen = nextBlocked(within: const Duration(milliseconds: 700));
    keyboard.chord(<String>['Tab']);
    expect(await seen, isNull);
    await DVKiosk.release();
  });

  test('a passthrough policy grabs nothing', () async {
    final DVKioskEnforced result = await DVKiosk.enforce(policy(scope: 'display'));
    expect(result.blocked, isEmpty);
    await DVKiosk.release();
  });

  test('while enforced, system notifications are suppressed; the in-app inbox is not this binding', () async {
    // The spec: system notifications are suppressed on the kiosk surface;
    // in-app inbox and model-sync delivery continue. The freedesktop
    // notification is what this binding sends, so while the kiosk holds it
    // sends nothing and counts what it held back.
    final DVKioskEnforced result = await DVKiosk.enforce(policy());
    expect(result.notificationsSuppressed, isTrue);
    final int before = DVLinuxKiosk.suppressedNotifications;
    final Object? id = await DVNativeBridge.invoke<Object?>('notifications.sendLocal', <String, Object?>{'title': 'Hi', 'body': 'there'});
    expect(id, isNull);
    expect(DVLinuxKiosk.suppressedNotifications, before + 1);

    await DVKiosk.release();
    await DVNativeBridge.invoke<Object?>('notifications.sendLocal', <String, Object?>{'title': 'Hi', 'body': 'again'});
    expect(DVLinuxKiosk.suppressedNotifications, before + 1, reason: 'released, nothing more is held back');
  });
}
