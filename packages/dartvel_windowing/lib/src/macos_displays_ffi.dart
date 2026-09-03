part of '../dartvel_windowing.dart';

// CGRect, by value. Struct returns from plain C are supported by dart:ffi;
// it is Objective-C's objc_msgSend that needs a different entry point for
// them, and CoreGraphics is plain C.
final class _CGRect extends ffi.Struct {
  @ffi.Double()
  external double x;
  @ffi.Double()
  external double y;
  @ffi.Double()
  external double width;
  @ffi.Double()
  external double height;
}

/// Display enumeration on macOS: CGGetActiveDisplayList, CGDisplayBounds in
/// points, the pixel width for the scale, CGMainDisplayID for the primary.
class _DVMacosDisplays {
  const _DVMacosDisplays._();

  static const int _maxDisplays = 16;

  static List<Map<String, Object?>> enumerate() {
    final ffi.DynamicLibrary cg;
    try {
      cg = ffi.DynamicLibrary.open('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
    } on ArgumentError {
      return const <Map<String, Object?>>[];
    }
    final activeList = cg.lookupFunction<
        ffi.Int32 Function(ffi.Uint32, ffi.Pointer<ffi.Uint32>, ffi.Pointer<ffi.Uint32>),
        int Function(int, ffi.Pointer<ffi.Uint32>, ffi.Pointer<ffi.Uint32>)>('CGGetActiveDisplayList');
    final bounds = cg.lookupFunction<_CGRect Function(ffi.Uint32), _CGRect Function(int)>('CGDisplayBounds');
    final pixelsWide = cg.lookupFunction<ffi.IntPtr Function(ffi.Uint32), int Function(int)>('CGDisplayPixelsWide');
    final mainDisplay = cg.lookupFunction<ffi.Uint32 Function(), int Function()>('CGMainDisplayID')();

    final ids = ffi.calloc<ffi.Uint32>(_maxDisplays);
    final count = ffi.calloc<ffi.Uint32>();
    try {
      if (activeList(_maxDisplays, ids, count) != 0) return const <Map<String, Object?>>[];
      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < count.value; i++) {
        final int id = ids[i];
        final _CGRect r = bounds(id);
        final double scale = r.width > 0 ? pixelsWide(id) / r.width : 1.0;
        rows.add(<String, Object?>{
          'id': 'cg-$id',
          'name': id == mainDisplay ? 'Main' : 'Display $id',
          'x': r.x,
          'y': r.y,
          'width': r.width,
          'height': r.height,
          'devicePixelRatio': scale,
          'isPrimary': id == mainDisplay,
        });
      }
      return rows;
    } finally {
      ffi.calloc.free(ids);
      ffi.calloc.free(count);
    }
  }
}
