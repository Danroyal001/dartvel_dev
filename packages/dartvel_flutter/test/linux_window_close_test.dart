// A tray-resident application's window on Linux, against real GTK.
//
// Closing the window the way a window manager's close button does --
// gtk_window_close, which sends the same delete-event -- must hide it and
// keep it alive under exitPolicy explicit, and close it under every other
// policy. Hide and show from the tray are GTK's own calls, read back
// through GTK rather than from the binding's bookkeeping.
import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_window_gtk.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _InitCheckN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _InitCheckD = int Function(Pointer<Void>, Pointer<Void>);
typedef _WindowNewN = Pointer<Void> Function(Int32);
typedef _WindowNewD = Pointer<Void> Function(int);
typedef _WidgetN = Void Function(Pointer<Void>);
typedef _WidgetD = void Function(Pointer<Void>);
typedef _IterationN = Int32 Function(Int32);
typedef _IterationD = int Function(int);

void main() {
  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test('linux window close (skipped: no X display)', () {},
        skip: 'Run under an X server (xvfb-run works) to exercise GTK.');
    return;
  }

  final DynamicLibrary gtk = DynamicLibrary.open('libgtk-3.so.0');
  void pump() {
    final _IterationD iterate = gtk.lookupFunction<_IterationN, _IterationD>('gtk_main_iteration_do');
    for (var i = 0; i < 50; i++) {
      iterate(0);
    }
  }

  late Pointer<Void> window;
  setUpAll(() {
    expect(DVLinuxBindings.register(), isTrue);
    gtk.lookupFunction<_InitCheckN, _InitCheckD>('gtk_init_check')(nullptr, nullptr);
    window = gtk.lookupFunction<_WindowNewN, _WindowNewD>('gtk_window_new')(0);
  });
  tearDownAll(DVLinuxBindings.unregister);
  setUp(() {
    DVWindowManager.reset();
    gtk.lookupFunction<_WidgetN, _WidgetD>('gtk_widget_show')(window);
    pump();
  });

  test('the bindings implement hide and show', () {
    expect(DVLinuxBindings.implemented, containsAll(<String>['window.hide', 'window.show']));
    expect(DVLinuxWindow.mainWindow(), window);
  });

  test('hide and show from the tray are what GTK reports', () async {
    expect(DVLinuxWindow.isVisible, isTrue);
    await DV.Platform.window.hide();
    pump();
    expect(DVLinuxWindow.isVisible, isFalse);
    await DV.Platform.window.show();
    pump();
    expect(DVLinuxWindow.isVisible, isTrue);
  });

  test('under exitPolicy explicit, closing the window hides it and it survives', () async {
    expect(DVLinuxWindow.ensureCloseHook(), isTrue);
    DVWindowManager.exitPolicy = .explicit;

    gtk.lookupFunction<_WidgetN, _WidgetD>('gtk_window_close')(window);
    pump();

    expect(DVLinuxWindow.mainWindow(), window, reason: 'the window was not destroyed');
    expect(DVLinuxWindow.isVisible, isFalse);

    await DV.Platform.window.show();
    pump();
    expect(DVLinuxWindow.isVisible, isTrue);
  });

  // Last: it destroys the window the suite shares.
  test('under the default policy, closing the window closes it', () async {
    expect(DVLinuxWindow.ensureCloseHook(), isTrue);

    gtk.lookupFunction<_WidgetN, _WidgetD>('gtk_window_close')(window);
    pump();

    expect(DVLinuxWindow.mainWindow(), isNull, reason: 'GTK destroyed it, as before');
  });
}
