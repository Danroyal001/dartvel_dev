// What takesFocus: false does to a real GTK window on Linux: the window never
// accepts input focus (WM_HINTS input = False) and is not focused when it is
// mapped (_NET_WM_USER_TIME 0). Both have to be set before the window is first
// shown, which is when a window manager decides whether to focus it.
//
// Live: needs GTK 3 and an X display (run under Xvfb). Skipped without them.
// The two-window check -- the keyboard stays in the operator's window while a
// projector opens -- is a run of a real app on an X server with a window
// manager, recorded in the README.
@TestOn('linux')
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ffi.DynamicLibrary? gtk;
  String? skip;
  if (Platform.environment['DISPLAY'] == null) {
    skip = 'no X display';
  } else {
    try {
      gtk = ffi.DynamicLibrary.open('libgtk-3.so.0');
    } on ArgumentError {
      skip = 'no GTK 3';
    }
  }

  test('a window that takes no focus refuses it and is not focused on map', () {
    final lib = gtk!;
    final init = lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>('gtk_init_check');
    expect(init(ffi.nullptr, ffi.nullptr), isNonZero, reason: 'GTK could not open the display');
    final newWindow = lib.lookupFunction<ffi.Pointer<ffi.Void> Function(ffi.Int32),
        ffi.Pointer<ffi.Void> Function(int)>('gtk_window_new');
    final acceptsFocus = lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('gtk_window_get_accept_focus');
    final focusOnMap = lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('gtk_window_get_focus_on_map');
    final destroy = lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('gtk_widget_destroy');

    final window = newWindow(0); // GTK_WINDOW_TOPLEVEL
    expect(acceptsFocus(window), isNonZero, reason: 'GTK default');

    expect(DVWindowHost.debugSetTakesFocus(window, false), isTrue);
    expect(acceptsFocus(window), 0);
    expect(focusOnMap(window), 0);

    expect(DVWindowHost.debugSetTakesFocus(window, true), isTrue);
    expect(acceptsFocus(window), isNonZero);
    expect(focusOnMap(window), isNonZero);
    destroy(window);
  }, skip: skip ?? false);
}
