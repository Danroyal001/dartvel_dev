// Drag and drop on Linux, against the real GTK.
//
// A file dragged from the file manager onto the window arrives as GTK's
// `drag-data-received` on a widget that was made a drop target. Both halves
// are checked here against real GTK: the window really is a drop target for
// the types that were asked for, and a real GtkSelectionData carrying a
// uri-list, emitted the way GTK emits one, reaches Dart as paths.
//
// The selection data is built through the clipboard, because GtkSelectionData
// is opaque in GTK 3 and there is no constructor: what is put on the
// clipboard comes back as one, which is the same structure the drag would
// deliver. What is not exercised is another application doing the dragging;
// a runner has one process.
import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_dnd_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _InitCheckN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _InitCheckD = int Function(Pointer<Void>, Pointer<Void>);
typedef _WindowNewN = Pointer<Void> Function(Int32);
typedef _WindowNewD = Pointer<Void> Function(int);
typedef _ListN = Pointer<Void> Function();
typedef _ListD = Pointer<Void> Function();
typedef _ListLenN = Uint32 Function(Pointer<Void>);
typedef _ListLenD = int Function(Pointer<Void>);
typedef _ListNthN = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _ListNthD = Pointer<Void> Function(Pointer<Void>, int);
typedef _WidgetShowN = Void Function(Pointer<Void>);
typedef _WidgetShowD = void Function(Pointer<Void>);

class _Gtk {
  _Gtk()
      : gtk = DynamicLibrary.open('libgtk-3.so.0'),
        glib = DynamicLibrary.open('libglib-2.0.so.0');
  final DynamicLibrary gtk;
  final DynamicLibrary glib;

  void initAndOpenWindow() {
    gtk.lookupFunction<_InitCheckN, _InitCheckD>('gtk_init_check')(nullptr, nullptr);
    final Pointer<Void> window = gtk.lookupFunction<_WindowNewN, _WindowNewD>('gtk_window_new')(0);
    gtk.lookupFunction<_WidgetShowN, _WidgetShowD>('gtk_widget_show')(window);
  }

  Pointer<Void> toplevel() {
    final Pointer<Void> list = gtk.lookupFunction<_ListN, _ListD>('gtk_window_list_toplevels')();
    final int n = glib.lookupFunction<_ListLenN, _ListLenD>('g_list_length')(list);
    expect(n, greaterThan(0), reason: 'a toplevel exists');
    return glib.lookupFunction<_ListNthN, _ListNthD>('g_list_nth_data')(list, 0);
  }
}

void main() {
  // Parsing is a fact about the format rather than about the desktop, so it
  // is checked wherever the suite runs.
  group('what the desktop sends becomes paths', () {
    test('a uri-list is the files it names, decoded', () {
      expect(
        DVLinuxDragDrop.pathsFromUriList('file:///tmp/a%20b.txt\r\nfile:///home/ada/caf%C3%A9.png\r\n'),
        <String>['/tmp/a b.txt', '/home/ada/café.png'],
      );
    });

    test('a comment line is a comment, not a file', () {
      // RFC 2483: a line beginning # is a comment. Taken as a path it would
      // be a file nobody dropped.
      expect(DVLinuxDragDrop.pathsFromUriList('# dropped\r\nfile:///tmp/a.txt\r\n'), <String>['/tmp/a.txt']);
    });

    test('a URI that is not a file is not a path', () {
      // A drag from a browser sends http URIs. Handed on as a path they
      // would be a file that does not exist.
      expect(DVLinuxDragDrop.pathsFromUriList('https://dartvel.dev/x.png\r\nfile:///tmp/a.txt'), <String>['/tmp/a.txt']);
    });

    test('a host in the URI is not part of the path', () {
      expect(DVLinuxDragDrop.pathsFromUriList('file://localhost/tmp/a.txt'), <String>['/tmp/a.txt']);
    });

    test('nothing at all is no paths, not an empty one', () {
      expect(DVLinuxDragDrop.pathsFromUriList('\r\n \r\n'), isEmpty);
    });
  });

  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test('linux drag and drop (skipped: no X display)', () {},
        skip: 'Run under an X server (xvfb-run works) to exercise GTK.');
    return;
  }

  late _Gtk gtk;
  setUpAll(() {
    expect(DVLinuxBindings.register(), isTrue);
    gtk = _Gtk()..initAndOpenWindow();
  });
  tearDownAll(DVLinuxBindings.unregister);
  setUp(DVDragDrop.reset);
  tearDown(() async => const DVDragDrop().stop());

  test('drag and drop is among what the Linux bindings implement', () {
    expect(DVLinuxBindings.implemented, containsAll(<String>['dragDrop.accept', 'dragDrop.stop']));
  });

  test('accepting makes the real window a drop target for what was asked for', () async {
    expect(DVLinuxDragDrop.targetsOf(gtk.toplevel()), isNot(contains('text/uri-list')),
        reason: 'nothing takes files until it is asked to');

    await const DVDragDrop().accept();

    expect(DVLinuxDragDrop.targetsOf(gtk.toplevel()), containsAll(<String>['text/uri-list', 'text/plain']));
  });

  test('what GTK already took is kept, and given back on stop', () async {
    // A GtkWindow arrives with a target list of GTK's own. Replacing it
    // wholesale would take away drops GTK set up for itself, and an
    // application that had set its own targets would lose them too.
    final List<String> before = DVLinuxDragDrop.targetsOf(gtk.toplevel());
    expect(before, isNotEmpty, reason: 'GTK gives a toplevel its own targets');

    await const DVDragDrop().accept();
    expect(DVLinuxDragDrop.targetsOf(gtk.toplevel()), containsAll(before));

    await const DVDragDrop().stop();
    expect(DVLinuxDragDrop.targetsOf(gtk.toplevel()), before);
  });

  test('files only leaves text out of the target list', () async {
    await const DVDragDrop().accept(types: const <DVDropType>[DVDropType.files]);
    final List<String> targets = DVLinuxDragDrop.targetsOf(gtk.toplevel());
    expect(targets, contains('text/uri-list'));
    expect(targets, isNot(contains('text/plain')));
  });

  test('a real drop of files reaches Dart as paths', () async {
    final List<DVDropEvent> got = <DVDropEvent>[];
    await const DVDragDrop().accept(onDrop: got.add);

    DVLinuxDragDrop.emitDropForTest(
      gtk.toplevel(),
      uriList: 'file:///tmp/dropped%20one.txt\r\nfile:///tmp/two.png\r\n',
      x: 40,
      y: 60,
    );

    expect(got.single.paths, <String>['/tmp/dropped one.txt', '/tmp/two.png']);
    expect(got.single.x, 40);
    expect(got.single.y, 60);
  });

  test('a real drop of text reaches Dart as text', () async {
    final List<DVDropEvent> got = <DVDropEvent>[];
    await const DVDragDrop().accept(onDrop: got.add);

    DVLinuxDragDrop.emitDropForTest(gtk.toplevel(), text: 'https://dartvel.dev');

    expect(got.single.text, 'https://dartvel.dev');
    expect(got.single.paths, isEmpty);
  });

  test('stopping takes the window back out of the drop targets', () async {
    await const DVDragDrop().accept();
    await const DVDragDrop().stop();

    expect(DVLinuxDragDrop.targetsOf(gtk.toplevel()), isNot(contains('text/uri-list')));
  });
}
