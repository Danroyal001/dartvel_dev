// Pointer confinement on Linux, against a real X server.
//
// A kiosk keeps the pointer inside its window: a grab on the application's
// own X connection with the window as the confine-to, so events still
// reach the application (it is the grabbing client) and the pointer cannot
// leave. Under Xvfb the test makes a GTK window of its own, asks the kiosk
// to confine, warps the pointer far outside with XTest, and reads where it
// actually is; after release the same warp lands outside.
import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_kiosk_ffi.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _InitCheckN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _InitCheckD = int Function(Pointer<Void>, Pointer<Void>);
typedef _WindowNewN = Pointer<Void> Function(Int32);
typedef _WindowNewD = Pointer<Void> Function(int);
typedef _SetSizeN = Void Function(Pointer<Void>, Int32, Int32);
typedef _SetSizeD = void Function(Pointer<Void>, int, int);
typedef _PN = Void Function(Pointer<Void>);
typedef _PD = void Function(Pointer<Void>);
typedef _IterN = Int32 Function(Int32);
typedef _IterD = int Function(int);
typedef _XOpenDisplayN = Pointer<Void> Function(Pointer<Utf8>);
typedef _XOpenDisplayD = Pointer<Void> Function(Pointer<Utf8>);
typedef _XDefaultRootN = Uint64 Function(Pointer<Void>);
typedef _XDefaultRootD = int Function(Pointer<Void>);
typedef _XQueryPointerN = Int32 Function(Pointer<Void>, Uint64, Pointer<Uint64>, Pointer<Uint64>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, Pointer<Uint32>);
typedef _XQueryPointerD = int Function(Pointer<Void>, int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, Pointer<Uint32>);
typedef _XTestMotionN = Int32 Function(Pointer<Void>, Int32, Int32, Int32, Uint64);
typedef _XTestMotionD = int Function(Pointer<Void>, int, int, int, int);
typedef _XSyncN = Int32 Function(Pointer<Void>, Int32);
typedef _XSyncD = int Function(Pointer<Void>, int);

DVKioskPolicy policy() => DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': '/',
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test('linux kiosk pointer (skipped: no X display)', () {}, skip: 'Run under an X server (xvfb-run works).');
    return;
  }

  late DynamicLibrary gtk;
  late DynamicLibrary x11;
  late DynamicLibrary xtst;
  late Pointer<Void> display;

  void pump([int times = 20]) {
    final _IterD iterate = gtk.lookupFunction<_IterN, _IterD>('gtk_main_iteration_do');
    for (int i = 0; i < times; i++) {
      iterate(0);
    }
  }

  (int, int) pointer() {
    final Pointer<Uint64> w = calloc<Uint64>(2);
    final Pointer<Int32> xy = calloc<Int32>(4);
    final Pointer<Uint32> mask = calloc<Uint32>();
    try {
      final int root = x11.lookupFunction<_XDefaultRootN, _XDefaultRootD>('XDefaultRootWindow')(display);
      x11.lookupFunction<_XQueryPointerN, _XQueryPointerD>('XQueryPointer')(display, root, w, w + 1, xy, xy + 1, xy + 2, xy + 3, mask);
      return (xy[0], xy[1]);
    } finally {
      calloc.free(w);
      calloc.free(xy);
      calloc.free(mask);
    }
  }

  void warp(int x, int y) {
    xtst.lookupFunction<_XTestMotionN, _XTestMotionD>('XTestFakeMotionEvent')(display, -1, x, y, 0);
    x11.lookupFunction<_XSyncN, _XSyncD>('XSync')(display, 0);
    pump();
  }

  setUpAll(() {
    gtk = DynamicLibrary.open('libgtk-3.so.0');
    x11 = DynamicLibrary.open('libX11.so.6');
    xtst = DynamicLibrary.open('libXtst.so.6');
    expect(gtk.lookupFunction<_InitCheckN, _InitCheckD>('gtk_init_check')(nullptr, nullptr), isNot(0));
    // The kiosk's window: 300 by 200 at the top-left, mapped and drawn.
    final Pointer<Void> window = gtk.lookupFunction<_WindowNewN, _WindowNewD>('gtk_window_new')(0);
    gtk.lookupFunction<_SetSizeN, _SetSizeD>('gtk_window_set_default_size')(window, 300, 200);
    gtk.lookupFunction<_PN, _PD>('gtk_widget_show_all')(window);
    pump(50);
    display = x11.lookupFunction<_XOpenDisplayN, _XOpenDisplayD>('XOpenDisplay')(nullptr);
    expect(display, isNot(nullptr));
    expect(DVLinuxBindings.register(), isTrue);
  });
  tearDownAll(() async {
    await DVKiosk.release();
    DVLinuxBindings.unregister();
  });

  test('confined, the pointer cannot leave the window; released, it can', () async {
    final DVKioskEnforced result = await DVKiosk.enforce(policy());
    expect(result.confined, isTrue, reason: DVLinuxKiosk.lastConfineError ?? 'the grab was refused');
    pump();

    warp(900, 700);
    final (int x, int y) inside = pointer();
    expect(inside.$1, lessThan(300), reason: 'x stayed inside the 300-wide window');
    expect(inside.$2, lessThan(200), reason: 'y stayed inside the 200-high window');

    await DVKiosk.release();
    pump();
    warp(900, 700);
    final (int x2, int y2) outside = pointer();
    expect(outside.$1, greaterThanOrEqualTo(300));
    expect(outside.$2, greaterThanOrEqualTo(200));
  });

  test('a policy that is not a kiosk confines nothing', () async {
    final DVKioskEnforced result = await DVKiosk.enforce(DVKioskPolicy.parse(null));
    expect(result.confined, isFalse);
    await DVKiosk.release();
  });
}
