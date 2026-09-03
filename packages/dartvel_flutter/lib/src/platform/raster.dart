/// A picture as pixels: what a printing binding draws onto a page.
///
/// Pages arrive as PNG bytes. The engine decodes them, which is the one
/// decoder every Flutter target has; the binding then hands the pixels to
/// GDI or CoreGraphics, neither of which reads PNG on its own.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

class DVRaster {
  const DVRaster({required this.width, required this.height, required this.rgba});

  final int width;
  final int height;

  /// Straight RGBA, row-major, 4 bytes per pixel.
  final Uint8List rgba;

  /// Decodes [png]. Throws [StateError] when the bytes are not a picture,
  /// so a binding refuses the page rather than printing garbage.
  static Future<DVRaster> decode(Uint8List png) async {
    final ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(png);
    } catch (e) {
      throw StateError('a page is not a picture: $e');
    }
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    try {
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) throw StateError('a page could not be read back as pixels');
      return DVRaster(width: image.width, height: image.height, rgba: data.buffer.asUint8List());
    } finally {
      image.dispose();
      codec.dispose();
    }
  }
}
