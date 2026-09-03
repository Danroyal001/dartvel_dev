/// Printing on Windows: pictures onto pages through GDI.
///
/// `printing.toFile` opens a device context on "Microsoft Print to PDF",
/// which every Windows 10 and later has, names the output file in the
/// document so no dialog asks for it, and draws each page's pixels scaled
/// to fit the printable area. `printing.print` does the same on the default
/// printer, whose own dialog, if it has one, is the printer's. A page that
/// is not a picture is refused before the document starts, so no half
/// document is left behind.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../raster.dart';

final class _DocInfo extends Struct {
  @Int32()
  external int cbSize;
  external Pointer<Utf16> lpszDocName;
  external Pointer<Utf16> lpszOutput;
  external Pointer<Utf16> lpszDatatype;
  @Uint32()
  external int fwType;
}

final class _BitmapInfoHeader extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

const int _horzRes = 8;
const int _vertRes = 10;
const int _dibRgbColors = 0;
const int _srcCopy = 0x00CC0020;
const String _pdfPrinter = 'Microsoft Print to PDF';

class DVWindowsPrinting {
  const DVWindowsPrinting._();

  static const Set<String> implemented = <String>{'printing.toFile', 'printing.print'};

  static late DynamicLibrary _gdi32;
  static late DynamicLibrary _winspool;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    _gdi32 = DynamicLibrary.open('gdi32.dll');
    _winspool = DynamicLibrary.open('winspool.drv');
    bind('printing.toFile', (Object? arguments) async {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final String path = '${map['path'] ?? ''}';
      if (path.isEmpty) throw ArgumentError('printing.toFile needs a path.');
      final List<DVRaster> pages = await _decode(map['pages']);
      return _run(pages, printer: _pdfPrinter, output: path, title: '${map['title'] ?? 'Dartvel'}');
    });
    bind('printing.print', (Object? arguments) async {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final List<DVRaster> pages = await _decode(map['pages']);
      final String? printer = _defaultPrinter();
      if (printer == null) throw StateError('no default printer');
      return _run(pages, printer: printer, output: null, title: '${map['title'] ?? 'Dartvel'}');
    });
  }

  static Future<List<DVRaster>> _decode(Object? raw) async {
    final List<Uint8List> pages = <Uint8List>[
      for (final Object? p in (raw is List ? raw : const <Object?>[]))
        if (p is Uint8List) p else if (p is List<int>) Uint8List.fromList(p),
    ];
    if (pages.isEmpty) throw ArgumentError('Nothing to print.');
    // Every page decoded before the document starts: a bad third page must
    // not leave a two-page document behind.
    return <DVRaster>[for (final Uint8List png in pages) await DVRaster.decode(png)];
  }

  static String? _defaultPrinter() {
    final get = _winspool.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Uint32>),
        int Function(Pointer<Utf16>, Pointer<Uint32>)>('GetDefaultPrinterW');
    final Pointer<Uint32> size = calloc<Uint32>()..value = 256;
    final Pointer<Utf16> name = calloc<Uint16>(256).cast<Utf16>();
    try {
      if (get(name, size) == 0) return null;
      return name.toDartString();
    } finally {
      calloc.free(size);
      calloc.free(name);
    }
  }

  static Map<String, Object?> _run(List<DVRaster> pages, {required String printer, required String? output, required String title}) {
    final createDC = _gdi32.lookupFunction<
        IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Void>),
        int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Void>)>('CreateDCW');
    final deleteDC = _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
    final startDoc = _gdi32.lookupFunction<Int32 Function(IntPtr, Pointer<_DocInfo>), int Function(int, Pointer<_DocInfo>)>('StartDocW');
    final endDoc = _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndDoc');
    final abortDoc = _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('AbortDoc');
    final startPage = _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('StartPage');
    final endPage = _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndPage');
    final deviceCaps = _gdi32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('GetDeviceCaps');
    final stretch = _gdi32.lookupFunction<
        Int32 Function(IntPtr, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Pointer<Void>, Pointer<_BitmapInfoHeader>, Uint32, Uint32),
        int Function(int, int, int, int, int, int, int, int, int, Pointer<Void>, Pointer<_BitmapInfoHeader>, int, int)>('StretchDIBits');

    final Pointer<Utf16> driver = 'WINSPOOL'.toNativeUtf16();
    final Pointer<Utf16> device = printer.toNativeUtf16();
    final Pointer<Utf16> docName = title.toNativeUtf16();
    final Pointer<Utf16> outputName = output?.toNativeUtf16() ?? nullptr;
    final Pointer<_DocInfo> info = calloc<_DocInfo>();
    try {
      final int dc = createDC(driver, device, nullptr, nullptr);
      if (dc == 0) throw StateError('the printer "$printer" is not available');
      try {
        info.ref
          ..cbSize = sizeOf<_DocInfo>()
          ..lpszDocName = docName
          ..lpszOutput = outputName;
        if (startDoc(dc, info) <= 0) throw StateError('the printer "$printer" refused the document');
        final int pageWidth = deviceCaps(dc, _horzRes);
        final int pageHeight = deviceCaps(dc, _vertRes);
        var drawn = 0;
        try {
          for (final DVRaster page in pages) {
            if (startPage(dc) <= 0) throw StateError('the printer refused page ${drawn + 1}');
            _draw(page, dc, pageWidth, pageHeight, stretch);
            if (endPage(dc) <= 0) throw StateError('the printer refused page ${drawn + 1}');
            drawn++;
          }
        } catch (_) {
          abortDoc(dc);
          rethrow;
        }
        if (endDoc(dc) <= 0) throw StateError('the printer refused the document at the end');
        return <String, Object?>{'pages': drawn, if (output != null) 'path': output};
      } finally {
        deleteDC(dc);
      }
    } finally {
      calloc.free(driver);
      calloc.free(device);
      calloc.free(docName);
      if (outputName != nullptr) calloc.free(outputName);
      calloc.free(info);
    }
  }

  /// The page scaled to fit and centred, as a top-down 32-bit DIB. GDI wants
  /// BGRA, so the channels are swapped on the way in.
  static void _draw(DVRaster page, int dc, int pageWidth, int pageHeight,
      int Function(int, int, int, int, int, int, int, int, int, Pointer<Void>, Pointer<_BitmapInfoHeader>, int, int) stretch) {
    final double scale = <double>[pageWidth / page.width, pageHeight / page.height].reduce((double a, double b) => a < b ? a : b);
    final int w = (page.width * scale).round();
    final int h = (page.height * scale).round();
    final int x = (pageWidth - w) ~/ 2;
    final int y = (pageHeight - h) ~/ 2;

    final Pointer<Uint8> pixels = calloc<Uint8>(page.rgba.length);
    final Pointer<_BitmapInfoHeader> header = calloc<_BitmapInfoHeader>();
    try {
      final Uint8List src = page.rgba;
      for (var i = 0; i + 3 < src.length; i += 4) {
        pixels[i] = src[i + 2];
        pixels[i + 1] = src[i + 1];
        pixels[i + 2] = src[i];
        pixels[i + 3] = src[i + 3];
      }
      header.ref
        ..biSize = sizeOf<_BitmapInfoHeader>()
        ..biWidth = page.width
        ..biHeight = -page.height // top-down
        ..biPlanes = 1
        ..biBitCount = 32
        ..biCompression = 0;
      stretch(dc, x, y, w, h, 0, 0, page.width, page.height, pixels.cast(), header, _dibRgbColors, _srcCopy);
    } finally {
      calloc.free(pixels);
      calloc.free(header);
    }
  }
}
