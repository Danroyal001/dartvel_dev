/// Printing on macOS: pictures onto the pages of a PDF, through CoreGraphics.
///
/// `printing.toFile` is a CGPDFContext at the path, one page per picture,
/// each drawn scaled to fit a Letter page. Plain C, no AppKit, no run loop,
/// so it works wherever the process is. The dialog and the printer itself
/// are NSPrintOperation's, which needs a view and the application's event
/// loop; `printing.print` is not claimed here until it can be done through
/// them honestly.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../raster.dart';

final class _CGRect extends Struct {
  @Double()
  external double x;
  @Double()
  external double y;
  @Double()
  external double width;
  @Double()
  external double height;
}

const double _letterWidth = 612;
const double _letterHeight = 792;
const int _kCFStringEncodingUTF8 = 0x08000100;
const int _kCGImageAlphaLast = 3; // straight alpha, RGBA in memory

class DVMacosPrinting {
  const DVMacosPrinting._();

  static const Set<String> implemented = <String>{'printing.toFile'};

  static late DynamicLibrary _cg;
  static late DynamicLibrary _cf;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    _cg = DynamicLibrary.open('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
    _cf = DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
    bind('printing.toFile', (Object? arguments) async {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final String path = '${map['path'] ?? ''}';
      if (path.isEmpty) throw ArgumentError('printing.toFile needs a path.');
      final List<Uint8List> pages = <Uint8List>[
        for (final Object? p in (map['pages'] is List ? map['pages']! as List<Object?> : const <Object?>[]))
          if (p is Uint8List) p else if (p is List<int>) Uint8List.fromList(p),
      ];
      if (pages.isEmpty) throw ArgumentError('Nothing to print.');
      // Decoded before the file is opened: a bad page leaves no file.
      final List<DVRaster> rasters = <DVRaster>[for (final Uint8List png in pages) await DVRaster.decode(png)];
      return _write(path, rasters);
    });
  }

  static Pointer<Void> _cfString(String value) {
    final Pointer<Utf8> p = value.toNativeUtf8();
    try {
      return _cf.lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
          Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)>('CFStringCreateWithCString')(nullptr, p, _kCFStringEncodingUTF8);
    } finally {
      calloc.free(p);
    }
  }

  static void _release(Pointer<Void> ref) {
    if (ref != nullptr) _cf.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CFRelease')(ref);
  }

  static Map<String, Object?> _write(String path, List<DVRaster> pages) {
    final Pointer<Void> cfPath = _cfString(path);
    final Pointer<Void> url = _cf.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, IntPtr, Bool),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, bool)>('CFURLCreateWithFileSystemPath')(nullptr, cfPath, 0, false);
    final Pointer<_CGRect> mediaBox = calloc<_CGRect>();
    mediaBox.ref
      ..x = 0
      ..y = 0
      ..width = _letterWidth
      ..height = _letterHeight;
    final Pointer<Void> context = _cg.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<_CGRect>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<_CGRect>, Pointer<Void>)>('CGPDFContextCreateWithURL')(url, mediaBox, nullptr);
    try {
      if (context == nullptr) throw StateError('the PDF could not be created at $path');
      final beginPage = _cg.lookupFunction<Void Function(Pointer<Void>, Pointer<Void>), void Function(Pointer<Void>, Pointer<Void>)>('CGPDFContextBeginPage');
      final endPage = _cg.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CGPDFContextEndPage');
      for (final DVRaster page in pages) {
        beginPage(context, nullptr);
        _draw(context, page);
        endPage(context);
      }
      _cg.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CGPDFContextClose')(context);
      return <String, Object?>{'pages': pages.length, 'path': path};
    } finally {
      _release(context);
      calloc.free(mediaBox);
      _release(url);
      _release(cfPath);
    }
  }

  static void _draw(Pointer<Void> context, DVRaster page) {
    final Pointer<Uint8> pixels = calloc<Uint8>(page.rgba.length);
    pixels.asTypedList(page.rgba.length).setAll(0, page.rgba);
    final Pointer<Void> provider = _cg.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, IntPtr, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>)>('CGDataProviderCreateWithData')(nullptr, pixels.cast(), page.rgba.length, nullptr);
    final Pointer<Void> colorSpace = _cg.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('CGColorSpaceCreateDeviceRGB')();
    final Pointer<Void> image = _cg.lookupFunction<
        Pointer<Void> Function(IntPtr, IntPtr, IntPtr, IntPtr, IntPtr, Pointer<Void>, Uint32, Pointer<Void>, Pointer<Void>, Bool, Int32),
        Pointer<Void> Function(int, int, int, int, int, Pointer<Void>, int, Pointer<Void>, Pointer<Void>, bool, int)>('CGImageCreate')(
      page.width, page.height, 8, 32, page.width * 4, colorSpace, _kCGImageAlphaLast, provider, nullptr, false, 0);
    final Pointer<_CGRect> rect = calloc<_CGRect>();
    try {
      if (image == nullptr) throw StateError('a page could not be made into an image');
      final double scale = <double>[_letterWidth / page.width, _letterHeight / page.height].reduce((double a, double b) => a < b ? a : b);
      final double w = page.width * scale;
      final double h = page.height * scale;
      rect.ref
        ..x = (_letterWidth - w) / 2
        ..y = (_letterHeight - h) / 2
        ..width = w
        ..height = h;
      _cg.lookupFunction<Void Function(Pointer<Void>, _CGRect, Pointer<Void>), void Function(Pointer<Void>, _CGRect, Pointer<Void>)>('CGContextDrawImage')(context, rect.ref, image);
    } finally {
      _release(image);
      _release(colorSpace);
      _release(provider);
      calloc.free(rect);
      calloc.free(pixels);
    }
  }
}
