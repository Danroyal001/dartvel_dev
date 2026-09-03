/// Printing on Linux through GtkPrintOperation.
///
/// The export action writes a PDF with no dialog and no printer, which is
/// what makes this testable under Xvfb; the dialog action is the same
/// operation with the user in the loop. Each page is a PNG the caller
/// rendered, drawn through cairo scaled to fit the page.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _NewN = Pointer<Void> Function();
typedef _NewD = Pointer<Void> Function();
typedef _SetIntN = Void Function(Pointer<Void>, Int32);
typedef _SetIntD = void Function(Pointer<Void>, int);
typedef _RunN = Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _RunD = int Function(Pointer<Void>, int, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _UnrefN = Void Function(Pointer<Void>);
typedef _UnrefD = void Function(Pointer<Void>);
typedef _DrawPageN = Void Function(Pointer<Void>, Pointer<Void>, Int32, Pointer<Void>);
typedef _ConnectN = Uint64 Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<NativeFunction<_DrawPageN>>, Pointer<Void>, Pointer<Void>, Int32);
typedef _ConnectD = int Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<NativeFunction<_DrawPageN>>, Pointer<Void>, Pointer<Void>, int);
typedef _GetCairoN = Pointer<Void> Function(Pointer<Void>);
typedef _GetCairoD = Pointer<Void> Function(Pointer<Void>);
typedef _GetDoubleN = Double Function(Pointer<Void>);
typedef _GetDoubleD = double Function(Pointer<Void>);
typedef _FromPngN = Pointer<Void> Function(Pointer<Utf8>);
typedef _FromPngD = Pointer<Void> Function(Pointer<Utf8>);
typedef _StatusN = Int32 Function(Pointer<Void>);
typedef _StatusD = int Function(Pointer<Void>);
typedef _GetIntN = Int32 Function(Pointer<Void>);
typedef _GetIntD = int Function(Pointer<Void>);
typedef _ScaleN = Void Function(Pointer<Void>, Double, Double);
typedef _ScaleD = void Function(Pointer<Void>, double, double);
typedef _SetSourceN = Void Function(Pointer<Void>, Pointer<Void>, Double, Double);
typedef _SetSourceD = void Function(Pointer<Void>, Pointer<Void>, double, double);
typedef _PN = Void Function(Pointer<Void>);
typedef _PD = void Function(Pointer<Void>);
typedef _ValueInitN = Pointer<Void> Function(Pointer<Void>, Uint64);
typedef _ValueInitD = Pointer<Void> Function(Pointer<Void>, int);
typedef _ValueSetStrN = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _ValueSetStrD = void Function(Pointer<Void>, Pointer<Utf8>);
typedef _SetPropN = Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>);
typedef _SetPropD = void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>);
typedef _InitCheckN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _InitCheckD = int Function(Pointer<Void>, Pointer<Void>);
typedef _DoneN = Void Function(Pointer<Void>, Int32, Pointer<Void>);
typedef _ConnectDoneN = Uint64 Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<NativeFunction<_DoneN>>, Pointer<Void>, Pointer<Void>, Int32);
typedef _ConnectDoneD = int Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<NativeFunction<_DoneN>>, Pointer<Void>, Pointer<Void>, int);
typedef _IterN = Int32 Function(Pointer<Void>, Int32);
typedef _IterD = int Function(Pointer<Void>, int);

const int _actionPrintDialog = 0;
const int _actionExport = 3;
const int _resultApply = 1;
const int _unitPoints = 1;
const int _gTypeString = 16 << 2; // G_TYPE_STRING: fundamental type 16, shifted.

// The pages of the operation in progress, and the first thing that went
// wrong drawing one. The draw-page callback is a static function, so this is
// how it knows what to draw; one operation runs at a time.
List<String> _pagePaths = const <String>[];
String? _drawError;
bool _done = false;

void _onDone(Pointer<Void> op, int result, Pointer<Void> _) {
  _done = true;
}
DynamicLibrary? _gtkForDraw;
DynamicLibrary? _cairo;

void _onDrawPage(Pointer<Void> op, Pointer<Void> context, int pageNr, Pointer<Void> _) {
  final DynamicLibrary gtk = _gtkForDraw!;
  final DynamicLibrary cairo = _cairo!;
  if (pageNr < 0 || pageNr >= _pagePaths.length) return;
  final Pointer<Void> cr = gtk.lookupFunction<_GetCairoN, _GetCairoD>('gtk_print_context_get_cairo_context')(context);
  final double width = gtk.lookupFunction<_GetDoubleN, _GetDoubleD>('gtk_print_context_get_width')(context);
  final double height = gtk.lookupFunction<_GetDoubleN, _GetDoubleD>('gtk_print_context_get_height')(context);

  final Pointer<Utf8> path = _pagePaths[pageNr].toNativeUtf8();
  final Pointer<Void> surface = cairo.lookupFunction<_FromPngN, _FromPngD>('cairo_image_surface_create_from_png')(path);
  calloc.free(path);
  final int status = cairo.lookupFunction<_StatusN, _StatusD>('cairo_surface_status')(surface);
  if (status != 0) {
    _drawError ??= 'page ${pageNr + 1} is not a PNG cairo can read (status $status)';
    cairo.lookupFunction<_PN, _PD>('cairo_surface_destroy')(surface);
    return;
  }
  final int iw = cairo.lookupFunction<_GetIntN, _GetIntD>('cairo_image_surface_get_width')(surface);
  final int ih = cairo.lookupFunction<_GetIntN, _GetIntD>('cairo_image_surface_get_height')(surface);
  final double scale = math.min(width / iw, height / ih);

  cairo.lookupFunction<_PN, _PD>('cairo_save')(cr);
  cairo.lookupFunction<_ScaleN, _ScaleD>('cairo_scale')(cr, scale, scale);
  cairo.lookupFunction<_SetSourceN, _SetSourceD>('cairo_set_source_surface')(cr, surface, 0, 0);
  cairo.lookupFunction<_PN, _PD>('cairo_paint')(cr);
  cairo.lookupFunction<_PN, _PD>('cairo_restore')(cr);
  cairo.lookupFunction<_PN, _PD>('cairo_surface_destroy')(surface);
}

class DVLinuxPrinting {
  const DVLinuxPrinting._();

  static const Set<String> implemented = <String>{'printing.toFile', 'printing.print'};

  static DynamicLibrary? _gtk;
  static DynamicLibrary? _glib;
  static DynamicLibrary? _gobject;

  static void register(
    DynamicLibrary gtk,
    DynamicLibrary glib,
    void Function(String, Object? Function(Object?)) bind,
  ) {
    _gtk = gtk;
    _glib = glib;
    _gtkForDraw = gtk;
    _gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    _cairo = DynamicLibrary.open('libcairo.so.2');
    bind('printing.toFile', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final String path = '${map['path'] ?? ''}';
      if (path.isEmpty) throw ArgumentError('printing.toFile needs a path.');
      return _run(_pages(map['pages']), exportTo: path);
    });
    bind('printing.print', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      return _run(_pages(map['pages']));
    });
  }

  static List<Uint8List> _pages(Object? raw) => <Uint8List>[
        for (final Object? p in (raw is List ? raw : const <Object?>[]))
          if (p is Uint8List) p else if (p is List<int>) Uint8List.fromList(p),
      ];

  /// Runs one print operation over [pages]: to a PDF at [exportTo], or
  /// through the dialog when null. Returns `{pages: n}`; throws
  /// [StateError] when a page could not be drawn or GTK refused, and never
  /// leaves a half-written export behind.
  static Map<String, Object?> _run(List<Uint8List> pages, {String? exportTo}) {
    final DynamicLibrary gtk = _gtk!;
    final DynamicLibrary glib = _glib!;
    final DynamicLibrary gobject = _gobject!;
    if (pages.isEmpty) throw ArgumentError('Nothing to print.');
    gtk.lookupFunction<_InitCheckN, _InitCheckD>('gtk_init_check')(nullptr, nullptr);

    final Directory temp = Directory.systemTemp.createTempSync('dv_print_pages_');
    _pagePaths = <String>[
      for (int i = 0; i < pages.length; i++)
        (File('${temp.path}/page-$i.png')..writeAsBytesSync(pages[i])).path,
    ];
    _drawError = null;
    _done = false;

    final Pointer<Void> op = gtk.lookupFunction<_NewN, _NewD>('gtk_print_operation_new')();
    final Pointer<Utf8> signal = 'draw-page'.toNativeUtf8();
    final Pointer<Utf8> doneSignal = 'done'.toNativeUtf8();
    final Pointer<Pointer<Void>> error = calloc<Pointer<Void>>();
    Pointer<Utf8>? exportName;
    Pointer<Utf8>? property;
    Pointer<Void>? value;
    try {
      gtk.lookupFunction<_SetIntN, _SetIntD>('gtk_print_operation_set_n_pages')(op, pages.length);
      gtk.lookupFunction<_SetIntN, _SetIntD>('gtk_print_operation_set_unit')(op, _unitPoints);
      gobject.lookupFunction<_ConnectN, _ConnectD>('g_signal_connect_data')(
          op, signal, Pointer.fromFunction<_DrawPageN>(_onDrawPage), nullptr, nullptr, 0);
      gobject.lookupFunction<_ConnectDoneN, _ConnectDoneD>('g_signal_connect_data')(
          op, doneSignal, Pointer.fromFunction<_DoneN>(_onDone), nullptr, nullptr, 0);
      if (exportTo != null) {
        // g_object_set is variadic; the property form is not.
        exportName = exportTo.toNativeUtf8();
        property = 'export-filename'.toNativeUtf8();
        value = calloc<Uint8>(24).cast<Void>(); // a zeroed GValue
        gobject.lookupFunction<_ValueInitN, _ValueInitD>('g_value_init')(value, _gTypeString);
        gobject.lookupFunction<_ValueSetStrN, _ValueSetStrD>('g_value_set_string')(value, exportName);
        gobject.lookupFunction<_SetPropN, _SetPropD>('g_object_set_property')(op, property, value);
      }
      final int result = gtk.lookupFunction<_RunN, _RunD>('gtk_print_operation_run')(
          op, exportTo == null ? _actionPrintDialog : _actionExport, nullptr, error);
      // run() returns once the pages are drawn; the file is finished on the
      // main loop afterwards, which nothing else here is pumping. Pump it
      // until the operation says done -- bounded, so a stuck backend is an
      // error and not a hang.
      final _IterD iterate = glib.lookupFunction<_IterN, _IterD>('g_main_context_iteration');
      final Stopwatch waited = Stopwatch()..start();
      while (!_done && waited.elapsed < const Duration(seconds: 10)) {
        if (iterate(nullptr, 0) == 0) sleep(const Duration(milliseconds: 5));
      }
      final String? drawError = _drawError;
      if (drawError != null) {
        if (exportTo != null && File(exportTo).existsSync()) File(exportTo).deleteSync();
        throw StateError('Could not print: $drawError.');
      }
      if (exportTo != null && result != _resultApply) {
        if (File(exportTo).existsSync()) File(exportTo).deleteSync();
        throw StateError('GTK did not write the PDF (print operation result $result).');
      }
      return <String, Object?>{'pages': result == _resultApply ? pages.length : 0};
    } finally {
      if (value != null) {
        gobject.lookupFunction<_PN, _PD>('g_value_unset')(value);
        calloc.free(value);
      }
      if (property != null) calloc.free(property);
      if (exportName != null) calloc.free(exportName);
      calloc.free(signal);
      calloc.free(doneSignal);
      calloc.free(error);
      gobject.lookupFunction<_UnrefN, _UnrefD>('g_object_unref')(op);
      temp.deleteSync(recursive: true);
      _pagePaths = const <String>[];
    }
  }
}
