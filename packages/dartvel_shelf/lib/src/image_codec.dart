/// Decoding, resizing and encoding an image: the image endpoint's heavy half.
///
/// package:image is a third of a web-server binary's compiled code, and
/// most requests never resize anything. The endpoint imports this library
/// `deferred`, so a binary compiled in loading units carries it as a unit
/// of its own and maps it the first time an image is asked for.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The format [bytes] are in -- `png`, `jpg`, `gif`, `webp`, ... -- or null
/// when they are no image this can read.
String? dvImageFormatOf(Uint8List bytes) {
  final img.ImageFormat format = img.findFormatForData(bytes);
  return format == img.ImageFormat.invalid ? null : format.name;
}

/// [source] at most [width] pixels wide, as [format] (`jpeg`, `webp`, or
/// `png`), or null when it cannot be decoded.
Uint8List? dvResizeImage(
  Uint8List source, {
  required int width,
  required int quality,
  required String format,
}) {
  final img.Image? decoded = img.decodeImage(source);
  if (decoded == null) return null;
  // Never larger than it is: an upscaled copy is bigger and no sharper.
  final img.Image sized = decoded.width > width
      ? img.copyResize(decoded, width: width, interpolation: img.Interpolation.average)
      : decoded;
  return switch (format) {
    'jpeg' => img.encodeJpg(sized, quality: quality),
    'webp' => img.encodeWebP(sized),
    _ => img.encodePng(sized),
  };
}
