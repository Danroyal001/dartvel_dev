// A Dartvel web build never ships Flutter's template branding.
//
// The live sites showed it: favicon.png byte-identical to Flutter's template
// on four of them, manifests named after the package ("danieleffiong_dv"),
// "A new Flutter project." as the description and Flutter blue (#0175C2) as
// the theme colour. The icons were only generated for the manifest, never for
// the tab, and a project with no icon got nothing at all -- so Flutter's logo
// was what a browser tab showed for every one of them.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:dartvel_cli/src/build/web_branding.dart';
import 'package:test/test.dart';

void main() {
  group('the brand a build uses', () {
    test('the name comes from pwa, then seo, never the package name as written', () {
      expect(dvWebBrand(const {'pwa': {'name': 'Payseal'}}, 'payseal').name, 'Payseal');
      expect(dvWebBrand(const {'seo': {'siteName': 'Daniel Effiong'}}, 'danieleffiong_dv').name, 'Daniel Effiong');
      // With nothing configured, the package name is made readable rather than
      // shipped as an identifier.
      expect(dvWebBrand(const {}, 'danieleffiong_dv').name, 'Danieleffiong Dv');
    });

    test('the description and colours come from settings, never Flutter defaults', () {
      final DVWebBrand brand = dvWebBrand(const {
        'seo': {'description': 'Get paid safely.', 'accent': '#0F766E'},
        'splash': {'color': '#FAFAF7'},
      }, 'payseal');
      expect(brand.description, 'Get paid safely.');
      expect(brand.themeColor, '#0F766E');
      expect(brand.backgroundColor, '#FAFAF7');
      final DVWebBrand bare = dvWebBrand(const {}, 'x_app');
      expect(bare.description, isNot(contains('Flutter')));
      expect(bare.themeColor.toUpperCase(), isNot('#0175C2'));
      expect(bare.backgroundColor.toUpperCase(), isNot('#0175C2'));
    });
  });

  group('Flutter template files', () {
    test('are recognised by their bytes', () {
      final File template = File('${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/snap/flutter/common/flutter'}/packages/flutter_tools/templates/app/web/favicon.png.copy.tmpl');
      if (template.existsSync()) {
        expect(dvIsFlutterTemplateIcon(template.readAsBytesSync()), isTrue);
      }
      expect(dvFlutterTemplateIconMd5s, contains('5dcef449791fa27946b3d35ad8803796'));
      expect(dvIsFlutterTemplateIcon(dvPngEncode(DVRgbaImage(4, 4))), isFalse);
    });
  });

  group('index.html', () {
    const String flutterPage = '''<!DOCTYPE html><html><head>
  <meta name="description" content="A new Flutter project.">
  <meta name="apple-mobile-web-app-title" content="payseal">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <title>payseal</title>
</head><body></body></html>''';

    test('carries the brand instead of the package name and Flutter text', () {
      final String out = dvBrandIndexHtml(flutterPage, dvWebBrand(const {'pwa': {'name': 'Payseal', 'description': 'Get paid safely.'}}, 'payseal'));
      expect(out, contains('<title>Payseal</title>'));
      expect(out, contains('content="Get paid safely."'));
      expect(out, contains('apple-mobile-web-app-title" content="Payseal"'));
      expect(out, isNot(contains('A new Flutter project.')));
      expect(out, contains('href="apple-touch-icon.png"'));
      expect(out, contains('rel="icon" type="image/png" href="favicon.png"'));
    });

    test('a page title the project wrote itself is left alone', () {
      final String own = flutterPage.replaceFirst('<title>payseal</title>', '<title>My own title</title>');
      expect(dvBrandIndexHtml(own, dvWebBrand(const {'pwa': {'name': 'Payseal'}}, 'payseal')), contains('<title>My own title</title>'));
    });
  });

  group('the tab icon', () {
    test('is generated with the app icons: favicon and apple-touch-icon too', () {
      final Directory into = Directory.systemTemp.createTempSync('brand');
      final File source = File('${into.path}/src.png')..writeAsBytesSync(dvPngEncode(solid(64, 0, 128, 255)));
      final List<String> written = dvGenerateWebIcons(source: dvPngDecode(source.readAsBytesSync()), into: into, background: 0xFFFFFFFF);
      expect(written, containsAll(<String>['favicon.png', 'apple-touch-icon.png', 'icons/Icon-192.png', 'icons/Icon-512.png']));
      final DVRgbaImage favicon = dvPngDecode(File('${into.path}/favicon.png').readAsBytesSync());
      expect(favicon.width, 32);
      expect(dvPngDecode(File('${into.path}/apple-touch-icon.png').readAsBytesSync()).width, 180);
      expect(dvIsFlutterTemplateIcon(File('${into.path}/favicon.png').readAsBytesSync()), isFalse);
      into.deleteSync(recursive: true);
    });

    test('a project with no icon gets a monogram of its name, not Flutter\'s logo', () {
      final DVRgbaImage icon = dvMonogramIcon('Payseal', accent: 0xFF0F766E, size: 64);
      expect(icon.width, 64);
      // The background is the accent and the letter is drawn in contrast.
      expect(icon.get(1, 1).sublist(0, 3), <int>[0x0F, 0x76, 0x6E]);
      final Set<String> colours = <String>{
        for (var y = 0; y < 64; y++)
          for (var x = 0; x < 64; x++) icon.get(x, y).sublist(0, 3).join(','),
      };
      expect(colours.length, greaterThan(1), reason: 'a letter is drawn');
      expect(md5.convert(dvPngEncode(icon)).toString(), isNot(dvFlutterTemplateIconMd5s.first));
    });

    test('monogram initials come from the name\'s words', () {
      expect(dvMonogramLetters('Payseal'), 'P');
      expect(dvMonogramLetters('Daniel Effiong'), 'DE');
      expect(dvMonogramLetters('jobs_dv'), 'JD');
      expect(dvMonogramLetters('  '), 'D');
    });
  });
}

DVRgbaImage solid(int size, int r, int g, int b) {
  final DVRgbaImage image = DVRgbaImage(size, size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.set(x, y, r: r, g: g, b: b);
    }
  }
  return image;
}
