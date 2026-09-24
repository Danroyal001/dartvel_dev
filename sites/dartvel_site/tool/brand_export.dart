// Writes every raster in assets/brand, and the site's own icons, from the
// same geometry the SVGs carry.
//
//   flutter test tool/brand_export.dart
//
// The SVGs are the originals and nothing here parses them: the shapes are
// drawn in Dart, and `brand_geometry_test.dart` holds the two to the same
// numbers so they cannot drift. That is the repository's one-language rule
// doing real work. The alternative was an SVG renderer on the PATH, and the
// one that is on this machine renders the gradient as flat black.
//
// Rasterising needs a Flutter engine, which is why this is run through
// `flutter test` rather than `dart run`: nothing else here is headless and
// has a canvas.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'brand_art.dart';

/// Where the originals and their exports live, from the site's directory.
const String kBrand = '../../assets/brand';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The social card sets its tagline in the site's own face. A system
    // stack would render it differently on every machine that exported it,
    // and the stack the SVG carried named Helvetica and Arial.
    final FontLoader loader = FontLoader('Manrope')
      ..addFont(Future<ByteData>.value(
        ByteData.sublistView(File('fonts/Manrope.ttf').readAsBytesSync()),
      ));
    await loader.load();
  });

  test('every brand raster', () async {
    // Flutter encodes PNG and nothing else, so the handful of JPEGs are
    // converted from the PNG beside them. Raster to raster, which is the
    // part ImageMagick does correctly; it is its SVG renderer that draws
    // this gradient as flat black, which is the whole reason the artwork is
    // redrawn in Dart rather than exported from the originals.
    final bool canJpeg =
        Process.runSync('sh', <String>['-c', 'command -v convert']).exitCode == 0;
    final List<String> skipped = <String>[];

    Future<void> write(String path, ui.Image image, {bool jpeg = false}) async {
      final ByteData? png =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final File out = File(path)..parent.createSync(recursive: true);
      out.writeAsBytesSync(png!.buffer.asUint8List());
      if (!jpeg) return;
      final String target = '${path.substring(0, path.length - 4)}.jpg';
      if (!canJpeg) {
        skipped.add(target);
        return;
      }
      // Flattened onto the ink: a JPEG has no transparency, and the default
      // is black behind a mark drawn to sit on a page.
      final ProcessResult result = Process.runSync('convert', <String>[
        path,
        '-background', '#0B1020',
        '-flatten',
        '-quality', '92',
        target,
      ]);
      if (result.exitCode != 0) skipped.add(target);
    }

    Future<ui.Image> render(
      void Function(Canvas canvas, Size size) paint,
      Size box,
      int width,
    ) async {
      final double scale = width / box.width;
      final int height = (box.height * scale).round();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      )..scale(scale);
      paint(canvas, box);
      return recorder.endRecording().toImage(width, height);
    }

    // The mark, transparent, at every size the repository carries.
    for (final int size in <int>[16, 32, 64, 128, 256, 512, 1024]) {
      final ui.Image image = await render(paintMark, kMarkBox, size);
      await write('$kBrand/dartvel-mark-$size.png', image, jpeg: size == 1024);
      image.dispose();
    }

    // The app icon: the mark knocked out of a gradient tile.
    for (final int size in <int>[64, 120, 180, 256, 512, 1024]) {
      final ui.Image image = await render(paintBadge, kMarkBox, size);
      await write('$kBrand/dartvel-badge-$size.png', image, jpeg: size == 1024);
      image.dispose();
    }

    // The maskable form: no rounded corner and a smaller mark, because the
    // launcher decides the shape and crops into the edge.
    final ui.Image maskable = await render(paintMaskableBadge, kMarkBox, 512);
    await write('$kBrand/dartvel-badge-maskable-512.png', maskable);

    for (final int size in <int>[800, 1600]) {
      final ui.Image image =
          await render((Canvas c, Size s) => paintLockup(c, s, onDark: false),
              kLockupBox, size);
      await write('$kBrand/dartvel-logo-$size.png', image, jpeg: size == 1600);
      image.dispose();
    }
    final ui.Image onDark = await render(
        (Canvas c, Size s) => paintLockup(c, s, onDark: true), kLockupBox, 1600);
    await write('$kBrand/dartvel-logo-on-dark-1600.png', onDark, jpeg: true);

    final ui.Image card = await render(paintSocialCard, kCardBox, 1200);
    await write('$kBrand/dartvel-social-card-1200.png', card, jpeg: true);

    // The site's own icons are the same artwork at the sizes the web
    // manifest names, written here so the two cannot fall out of step.
    await write('web/favicon.png', await render(paintMark, kMarkBox, 16));
    await write('web/icon.png', await render(paintBadge, kMarkBox, 512));
    await write('web/icons/Icon-192.png', await render(paintBadge, kMarkBox, 192));
    await write('web/icons/Icon-512.png', await render(paintBadge, kMarkBox, 512));
    await write('web/icons/Icon-maskable-192.png',
        await render(paintMaskableBadge, kMarkBox, 192));
    await write('web/icons/Icon-maskable-512.png',
        await render(paintMaskableBadge, kMarkBox, 512));
    await write('web/social-card.png', await render(paintSocialCard, kCardBox, 1200));

    maskable.dispose();
    onDark.dispose();
    card.dispose();

    // Not a claim that the pictures are right, only that they were written.
    expect(File('$kBrand/dartvel-mark-512.png').lengthSync(), greaterThan(0));
    // A JPEG that was not rewritten still carries the last export, which
    // after a recolour is the old brand beside the new one.
    expect(skipped, isEmpty,
        reason: 'not written: ${skipped.join(', ')}');
  });
}
