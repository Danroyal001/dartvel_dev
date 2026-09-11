/// Image variants for a web build: each raster image the project declares,
/// written at every configured width narrower than it.
///
/// A web-server build can resize on request; a static host cannot run
/// anything, so the build does it once, into
/// `assets/_dartvel/img/<width>/<the image's own path>`. The widths of the
/// sources travel to the application with the rest of [DVImageVariants],
/// because a widget that asked for a width the build did not write would get
/// a 404, and whether the build wrote it is a fact only the build has.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// What [dvWriteStaticImageVariants] did.
class DVStaticVariantSummary {
  const DVStaticVariantSummary({required this.images, required this.written});

  /// Images with variants.
  final int images;

  /// Files written this time; zero when every variant was already current.
  final int written;
}

/// Not GIF: resizing one keeps the first frame of an animation, so it is
/// served as it is and never listed.
const Set<String> _resizable = <String>{'png', 'jpg', 'jpeg', 'webp', 'bmp'};

/// The raster images [flutterAssets] (pubspec.yaml's `flutter.assets`)
/// declares, by the path the site serves each at (`assets/<asset key>`), with
/// their widths.
///
/// A declared directory is its own files and no deeper, which is how Flutter
/// reads it: an image in a subdirectory is not an asset unless declared
/// itself, and a resolution variant under `2.0x/` is Flutter's own business.
Map<String, int> dvDeclaredImageWidths(String projectRoot, Object? flutterAssets) {
  if (flutterAssets is! List) return const <String, int>{};
  final Map<String, int> widths = <String, int>{};
  for (final Object? entry in flutterAssets) {
    final String? declared = switch (entry) {
      final String path => path,
      {'path': final String path} => path,
      _ => null,
    };
    if (declared == null || declared.isEmpty) continue;
    final String path = declared.replaceAll(r'\', '/');

    final List<String> keys;
    if (path.endsWith('/')) {
      final Directory directory = Directory(p.join(projectRoot, path));
      if (!directory.existsSync()) continue;
      keys = <String>[
        for (final FileSystemEntity file in directory.listSync())
          if (file is File) '$path${p.basename(file.path)}',
      ]..sort();
    } else {
      keys = <String>[path];
    }

    for (final String key in keys) {
      final String extension =
          p.extension(key).replaceFirst('.', '').toLowerCase();
      if (!_resizable.contains(extension)) continue;
      final File file = File(p.join(projectRoot, key));
      if (!file.existsSync()) continue;
      final int? width = _widthOf(file.readAsBytesSync());
      if (width != null && width > 0) widths['assets/$key'] = width;
    }
  }
  return widths;
}

/// The width in an image's header, without decoding the pixels.
int? _widthOf(Uint8List bytes) =>
    img.findDecoderForData(bytes)?.startDecode(bytes)?.width;

/// Writes every variant [variants] can ask for into [webRoot].
///
/// Each image at each configured width narrower than it -- a variant as wide
/// as the image or wider is never written, and never asked for. In the
/// image's own format, because the address keeps the image's name and a
/// static host picks the content type from it. A variant newer than its
/// source is left alone, so a rebuild resizes only what changed.
DVStaticVariantSummary dvWriteStaticImageVariants({
  required String projectRoot,
  required String webRoot,
  required DVImageVariants variants,
}) {
  var written = 0;
  for (final MapEntry<String, int> image in variants.assetWidths.entries) {
    final String src = image.key;
    if (!src.startsWith('assets/')) continue;
    final File source =
        File(p.join(projectRoot, src.substring('assets/'.length)));
    if (!source.existsSync()) continue;
    final DateTime changed = source.lastModifiedSync();

    img.Image? decoded;
    for (final int width in variants.widths) {
      if (width >= image.value) break;
      final File out =
          File(p.join(webRoot, dvStaticImageVariantDir, '$width', src));
      if (out.existsSync() && !out.lastModifiedSync().isBefore(changed)) {
        continue;
      }
      decoded ??= img.decodeImage(source.readAsBytesSync());
      if (decoded == null) break;
      final img.Image sized = img.copyResize(decoded,
          width: width, interpolation: img.Interpolation.average);
      out
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(_encode(sized, p.extension(src), variants.quality));
      written++;
    }
  }
  return DVStaticVariantSummary(
    images: variants.assetWidths.length,
    written: written,
  );
}

List<int> _encode(img.Image image, String extension, int quality) =>
    switch (extension.toLowerCase()) {
      '.jpg' || '.jpeg' => img.encodeJpg(image, quality: quality),
      '.webp' => img.encodeWebP(image),
      '.bmp' => img.encodeBmp(image),
      _ => img.encodePng(image),
    };
