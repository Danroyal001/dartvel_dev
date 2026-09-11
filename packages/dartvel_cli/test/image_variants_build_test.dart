// `dartvel build web` writes each declared image at the configured widths, so
// a static site has variants with no server to make them.
//
// A web-server build can resize on request; a static host cannot run
// anything. So the build does it once: every raster image the project
// declares under flutter.assets, at every configured width narrower than the
// image, into assets/_dartvel/img/<width>/<the image's own path>. The widths
// of the sources travel to the application with the rest of the variants,
// because a widget that asked for a width the build did not write would get
// a 404 -- and whether the build wrote it is a fact only the build has.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/image_variants_build.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

List<int> png(int width) => img.encodePng(
    img.fill(img.Image(width: width, height: width ~/ 2),
        color: img.ColorRgb8(200, 100, 50)));

List<int> jpeg(int width) => img.encodeJpg(img.fill(
    img.Image(width: width, height: width ~/ 2),
    color: img.ColorRgb8(20, 120, 220)));

void main() {
  late Directory project;
  late Directory web;

  void put(String path, List<int> bytes) => File(p.join(project.path, path))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_img_build_');
    addTearDown(() => project.deleteSync(recursive: true));
    web = Directory(p.join(project.path, 'build', 'web'))
      ..createSync(recursive: true);
    put('assets/hero.png', png(1600));
    put('assets/photo.jpg', jpeg(1000));
    put('assets/tiny.png', png(200));
    put('assets/anim.gif', img.encodeGif(img.Image(width: 900, height: 450)));
    put('assets/notes.txt', 'not an image'.codeUnits);
    put('assets/sub/nested.png', png(900));
    put('assets/2.0x/hero.png', png(3200));
    put('icons/logo.png', png(512));
    put('more/wide.png', png(1200));
  });

  group('the images a project declares', () {
    late Map<String, int> widths;
    setUp(() {
      widths = dvDeclaredImageWidths(project.path, <Object?>[
        'assets/',
        'icons/logo.png',
        <String, Object?>{'path': 'more/'},
      ]);
    });

    test('are keyed by the path the site serves each at, with its width', () {
      expect(widths['assets/assets/hero.png'], 1600);
      expect(widths['assets/assets/photo.jpg'], 1000);
      expect(widths['assets/icons/logo.png'], 512);
      expect(widths['assets/more/wide.png'], 1200,
          reason: 'a map entry names its path under "path"');
    });

    test('a directory is its own files, as Flutter reads it', () {
      // Flutter does not descend into a declared directory, so neither does
      // this: a nested image is not an asset unless declared itself.
      expect(widths.containsKey('assets/assets/sub/nested.png'), isFalse);
      expect(widths.containsKey('assets/assets/2.0x/hero.png'), isFalse);
    });

    test('only what can be resized is listed', () {
      expect(widths.containsKey('assets/assets/notes.txt'), isFalse);
      // A GIF is passed through: resizing it keeps one frame of an
      // animation. Listing it would send the widget to a file never written.
      expect(widths.containsKey('assets/assets/anim.gif'), isFalse);
    });

    test('a project that declares nothing has nothing', () {
      expect(dvDeclaredImageWidths(project.path, null), isEmpty);
    });
  });

  group('writing the variants', () {
    DVImageVariants variants() => DVImageVariants(
          widths: const <int>[320, 640, 2048],
          assetWidths: dvDeclaredImageWidths(
              project.path, const <Object?>['assets/']),
        );

    test('every width narrower than the image, and none wider', () {
      dvWriteStaticImageVariants(
          projectRoot: project.path, webRoot: web.path, variants: variants());

      File variant(int width, String src) =>
          File(p.join(web.path, dvStaticImageVariantDir, '$width', src));
      expect(variant(320, 'assets/assets/hero.png').existsSync(), isTrue);
      expect(variant(640, 'assets/assets/hero.png').existsSync(), isTrue);
      expect(variant(2048, 'assets/assets/hero.png').existsSync(), isFalse,
          reason: 'wider than the image: the image itself is used');
      expect(
          img
              .decodePng(Uint8List.fromList(
                  variant(320, 'assets/assets/hero.png').readAsBytesSync()))!
              .width,
          320);
      // Narrower than every width: nothing written, the image used as is.
      expect(variant(320, 'assets/assets/tiny.png').existsSync(), isFalse);
    });

    test('each keeps its format, since the address keeps its name', () {
      dvWriteStaticImageVariants(
          projectRoot: project.path, webRoot: web.path, variants: variants());

      final List<int> bytes = File(p.join(web.path, dvStaticImageVariantDir,
              '640', 'assets/assets/photo.jpg'))
          .readAsBytesSync();
      expect(img.findFormatForData(Uint8List.fromList(bytes)),
          img.ImageFormat.jpg);
    });

    test('a variant is never a bigger download than its source', () {
      // Found on a real build: the example's 1200-wide social card came out
      // 290,580 bytes at 1080 against 289,804 for the original. Re-encoding
      // at the configured quality can undo compression the source already
      // had, and a variant bigger than its source is a download that costs
      // more than not having variants at all. A hard-squeezed JPEG re-encoded
      // at 90 is the reliable way to see it.
      final img.Image noisy = img.Image(width: 1000, height: 500);
      for (final img.Pixel pixel in noisy) {
        final int x = pixel.x;
        final int y = pixel.y;
        pixel.setRgb((x * 7919 + y * 104729) & 255, (x * y + 31) & 255,
            (x * 131 ^ y * 17) & 255);
      }
      put('assets/squeezed.jpg', img.encodeJpg(noisy, quality: 5));
      final DVImageVariants built = DVImageVariants(
        widths: const <int>[640],
        quality: 90,
        assetWidths:
            dvDeclaredImageWidths(project.path, const <Object?>['assets/']),
      );

      dvWriteStaticImageVariants(
          projectRoot: project.path, webRoot: web.path, variants: built);

      final int source =
          File(p.join(project.path, 'assets/squeezed.jpg')).lengthSync();
      final File variant = File(p.join(web.path, dvStaticImageVariantDir,
          '640', 'assets/assets/squeezed.jpg'));
      // Still there: the widget asks for every width narrower than the image,
      // and a missing file is a broken image rather than a larger one.
      expect(variant.existsSync(), isTrue);
      expect(variant.lengthSync(), lessThanOrEqualTo(source));
    });

    test('every variant the widget can ask for exists', () {
      // The widget and the build agree through DVImageVariants.variantUrl.
      // Asked for at every width the configuration has, it names either a
      // file the build wrote or nothing at all -- never a 404.
      final DVImageVariants built = variants();
      dvWriteStaticImageVariants(
          projectRoot: project.path, webRoot: web.path, variants: built);

      for (final String src in built.assetWidths.keys) {
        for (final double pixels in <double>[1, 300, 320, 641, 1999, 5000]) {
          final String? url = built.variantUrl(src, pixels);
          if (url == null) continue;
          expect(File(p.join(web.path, url)).existsSync(), isTrue,
              reason: '$src at $pixels names $url');
        }
      }
    });

    test('a second build writes nothing it already has', () {
      final DVStaticVariantSummary first = dvWriteStaticImageVariants(
          projectRoot: project.path, webRoot: web.path, variants: variants());
      final DVStaticVariantSummary second = dvWriteStaticImageVariants(
          projectRoot: project.path, webRoot: web.path, variants: variants());

      expect(first.written, greaterThan(0));
      expect(second.written, 0);
      expect(second.images, first.images);
    });
  });
}
