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
import 'dart:io' as io show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// What [dvWriteStaticImageVariants] did.
class DVStaticVariantSummary {
  const DVStaticVariantSummary(
      {required this.images, required this.written, this.reused = 0});

  /// Images with variants.
  final int images;

  /// Files written this time; zero when every variant was already current.
  final int written;

  /// Of those, files copied from the store rather than made.
  final int reused;
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
    // Read once, and only if some variant of this image needs writing.
    late final original = source.readAsBytesSync();

    img.Image? decoded;
    for (final int width in variants.widths) {
      if (width >= image.value) break;
      final File out =
          File(p.join(webRoot, dvStaticImageVariantDir, '$width', src));
      if (out.existsSync() && !out.lastModifiedSync().isBefore(changed)) {
        continue;
      }
      decoded ??= img.decodeImage(original);
      if (decoded == null) break;
      final img.Image sized = img.copyResize(decoded,
          width: width, interpolation: img.Interpolation.average);
      final List<int> encoded =
          _encode(sized, p.extension(src), variants.quality);
      // Never a bigger download than the source. Re-encoding at the
      // configured quality can undo compression the source already had -- the
      // example's 1200-wide PNG came out larger at 1080 than the original --
      // and then the source itself is the better file at this address. Still
      // written, because the widget asks for every width narrower than the
      // image, and a missing file is a broken image rather than a larger one.
      out
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(
            encoded.length < original.length ? encoded : original);
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

/// [dvWriteStaticImageVariants], with the images made on up to [workers]
/// isolates at once, and every variant kept in [store] under the content of
/// its source, its width and the quality (none read or written when [store]
/// is null: `--no-cache`).
///
/// build/web starts empty on every build, so the serial version decoded,
/// resized and encoded every image again each time, one after another. Here
/// a variant whose source is unchanged is copied from [store], and the rest
/// are made in parallel. The bytes are the same as the serial version's:
/// the same decode, resize and encode, and the same rule that a variant is
/// never a bigger download than its source.
Future<DVStaticVariantSummary> dvWriteStaticImageVariantsInParallel({
  required String projectRoot,
  required String webRoot,
  required DVImageVariants variants,
  Directory? store,
  int? workers,
}) async {
  final List<
    ({String src, Uint8List original, List<int> widths, String digest})
  >
  todo =
      <({String src, Uint8List original, List<int> widths, String digest})>[];
  int written = 0;
  int reused = 0;
  File? stored(String digest, int width, String src) => store == null
      ? null
      : File(
          p.join(
            store.path,
            '$digest-$width-q${variants.quality}${p.extension(src).toLowerCase()}',
          ),
        );
  File out(int width, String src) =>
      File(p.join(webRoot, dvStaticImageVariantDir, '$width', src));

  for (final MapEntry<String, int> image in variants.assetWidths.entries) {
    final String src = image.key;
    if (!src.startsWith('assets/')) continue;
    final File source = File(
      p.join(projectRoot, src.substring('assets/'.length)),
    );
    if (!source.existsSync()) continue;
    final List<int> widths = <int>[
      for (final int width in variants.widths)
        if (width < image.value) width,
    ];
    if (widths.isEmpty) continue;
    final Uint8List original = source.readAsBytesSync();
    final String digest = sha256.convert(original).toString();
    if (store != null &&
        widths.every((int width) => stored(digest, width, src)!.existsSync())) {
      for (final int width in widths) {
        final File target = out(width, src)..parent.createSync(recursive: true);
        stored(digest, width, src)!.copySync(target.path);
        written++;
        reused++;
      }
      continue;
    }
    todo.add((src: src, original: original, widths: widths, digest: digest));
  }

  // Largest first, so one big image does not run alone at the end.
  todo.sort((a, b) => b.original.length - a.original.length);
  final int slots = (workers ?? (io.Platform.numberOfProcessors * 3 ~/ 4))
      .clamp(1, todo.isEmpty ? 1 : todo.length);
  final int quality = variants.quality;
  int next = 0;
  Future<void> worker() async {
    while (next < todo.length) {
      final job = todo[next++];
      final Uint8List original = job.original;
      final String extension = p.extension(job.src);
      final List<int> widths = job.widths;
      final Map<int, Uint8List>? made = await Isolate.run(() {
        final img.Image? decoded = img.decodeImage(original);
        if (decoded == null) return null;
        return <int, Uint8List>{
          for (final int width in widths)
            width: () {
              final List<int> encoded = _encode(
                img.copyResize(
                  decoded,
                  width: width,
                  interpolation: img.Interpolation.average,
                ),
                extension,
                quality,
              );
              // Never a bigger download than the source.
              return Uint8List.fromList(
                encoded.length < original.length ? encoded : original,
              );
            }(),
        };
      });
      if (made == null) continue;
      store?.createSync(recursive: true);
      for (final MapEntry<int, Uint8List> variant in made.entries) {
        out(variant.key, job.src)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(variant.value);
        stored(
          job.digest,
          variant.key,
          job.src,
        )?.writeAsBytesSync(variant.value);
        written++;
      }
    }
  }

  await Future.wait(<Future<void>>[
    for (int slot = 0; slot < slots; slot++) worker(),
  ]);
  return DVStaticVariantSummary(
    images: variants.assetWidths.length,
    written: written,
    reused: reused,
  );
}
