// The favicon a static build serves, derived from an image the project owns.
//
// A model could declare `@DVModel(favicon: '/icons/product.png')` and the
// value went straight into the page as an href. Whatever that file happens to
// be is then what every reader downloads to fill a 32-pixel square: a 512
// press shot is a few hundred kilobytes, and the browser asks for it on the
// first paint of every product page.
//
// So the build derives one: decoded, resized to 32, re-encoded, and named
// after a hash of its own bytes. The hash is what makes the file cacheable
// forever and what makes two models sharing a source share a file rather than
// writing the same pixels twice under two names.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/favicon_derivative.dart';
import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:test/test.dart';

/// A [size]-square image whose colours vary per pixel, so a resize that drops
/// or repeats a row changes the bytes rather than producing the same picture.
DVRgbaImage art(int size, {int shift = 0}) {
  final DVRgbaImage image = DVRgbaImage(size, size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.set(
        x,
        y,
        r: (x * 7 + shift) % 256,
        g: (y * 11 + shift) % 256,
        b: (x * y + shift) % 256,
      );
    }
  }
  return image;
}

Directory temp(String name) => Directory.systemTemp.createTempSync(name);

void main() {
  group('deriving one', () {
    test('the result is 32 square whatever the source was', () {
      final DVDerivedFavicon icon = dvDeriveFavicon(art(512));

      final DVRgbaImage decoded = dvPngDecode(icon.bytes);
      expect(decoded.width, 32);
      expect(decoded.height, 32);
    });

    test('and far smaller than the image it came from', () {
      // The whole reason the derivative exists. A page that swapped its icon
      // for a bigger download would be worse off than one wearing the
      // shell's.
      final DVRgbaImage source = art(512);
      final Uint8List original = dvPngEncode(source);

      final DVDerivedFavicon icon = dvDeriveFavicon(source);

      expect(icon.bytes.length, lessThan(original.length ~/ 10));
    });

    test('the name carries a hash of the bytes, so it can be cached forever',
        () {
      final DVDerivedFavicon icon = dvDeriveFavicon(art(64));

      expect(icon.href, startsWith('icons/favicon-'));
      expect(icon.href, endsWith('.png'));
      expect(RegExp(r'favicon-[0-9a-f]{16}\.png').hasMatch(icon.href), isTrue);
    });

    test('the same picture derives the same name twice', () {
      // Two models pointing at one source share a file instead of writing
      // the same pixels under two names.
      expect(dvDeriveFavicon(art(64)).href, dvDeriveFavicon(art(64)).href);
    });

    test('a different picture derives a different name', () {
      // The failure this guards is the silent one: a changed icon served
      // from a cache under the old name, for a year.
      expect(
        dvDeriveFavicon(art(64)).href,
        isNot(dvDeriveFavicon(art(64, shift: 40)).href),
      );
    });
  });

  group('finding the source a declared value names', () {
    test('a rooted path is looked for under web/', () {
      final Directory root = temp('dv_favicon_src_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/web/icons/product.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(dvPngEncode(art(64)));

      final File? found = dvFaviconSourceFile(root.path, '/icons/product.png');

      expect(found?.path, '${root.path}/web/icons/product.png');
    });

    test('an absolute URL is not a file and is not fetched', () {
      // Reaching out to a host mid-build makes the build depend on somebody
      // else's uptime, and on a CDN that can serve different bytes tomorrow.
      final Directory root = temp('dv_favicon_url_');
      addTearDown(() => root.deleteSync(recursive: true));

      expect(
        dvFaviconSourceFile(root.path, 'https://cdn.example.com/p.png'),
        isNull,
      );
    });

    test('a path that escapes the project is refused', () {
      final Directory root = temp('dv_favicon_escape_');
      addTearDown(() => root.deleteSync(recursive: true));

      expect(dvFaviconSourceFile(root.path, '/../../etc/passwd'), isNull);
    });
  });

  group('what the page ends up with', () {
    test('a declared file becomes the derived href and the file is written',
        () {
      final Directory root = temp('dv_favicon_build_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/web/icons/product.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(dvPngEncode(art(256)));
      final Directory web = Directory('${root.path}/build/web')
        ..createSync(recursive: true);

      final String? href = dvBuildFavicon(
        root: root.path,
        webRoot: web,
        declared: '/icons/product.png',
      );

      expect(href, isNotNull);
      expect(href, startsWith('/icons/favicon-'));
      final File written = File('${web.path}/${href!.substring(1)}');
      expect(written.existsSync(), isTrue);
      expect(dvPngDecode(written.readAsBytesSync()).width, 32);
    });

    test('deriving the same source twice writes one file', () {
      final Directory root = temp('dv_favicon_once_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/web/icons/product.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(dvPngEncode(art(256)));
      final Directory web = Directory('${root.path}/build/web')
        ..createSync(recursive: true);

      dvBuildFavicon(root: root.path, webRoot: web, declared: '/icons/x.png');
      dvBuildFavicon(
          root: root.path, webRoot: web, declared: '/icons/product.png');
      dvBuildFavicon(
          root: root.path, webRoot: web, declared: '/icons/product.png');

      final Directory icons = Directory('${web.path}/icons');
      expect(icons.listSync().whereType<File>().length, 1);
    });

    test('a value naming no file is left exactly as it was declared', () {
      // A CDN URL, or a file only the deployment has. Rewriting it to
      // something this build invented would point the page at a 404.
      final Directory root = temp('dv_favicon_passthrough_');
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory web = Directory('${root.path}/build/web')
        ..createSync(recursive: true);

      expect(
        dvBuildFavicon(
          root: root.path,
          webRoot: web,
          declared: 'https://cdn.example.com/p.png',
        ),
        'https://cdn.example.com/p.png',
      );
    });

    test('a file that is not a PNG this build can read is left alone', () {
      // An SVG or an ICO is a perfectly good favicon and this decoder reads
      // neither. Failing the build over it, or dropping the icon, would both
      // be worse than serving the file the project already has.
      final Directory root = temp('dv_favicon_svg_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/web/icon.svg')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg"/>');
      final Directory web = Directory('${root.path}/build/web')
        ..createSync(recursive: true);

      expect(
        dvBuildFavicon(root: root.path, webRoot: web, declared: '/icon.svg'),
        '/icon.svg',
      );
    });

    test('nothing declared derives nothing', () {
      final Directory root = temp('dv_favicon_none_');
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory web = Directory('${root.path}/build/web')
        ..createSync(recursive: true);

      expect(
        dvBuildFavicon(root: root.path, webRoot: web, declared: null),
        isNull,
      );
      expect(Directory('${web.path}/icons').existsSync(), isFalse);
    });
  });
}
