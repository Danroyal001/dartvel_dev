// A built web page needs a viewport meta, or it is not responsive at all.
//
// Without `<meta name="viewport">` a phone browser lays the page out at a
// notional ~980 CSS pixels and scales the result down. The app is not narrow;
// it is a shrunken desktop. Everything downstream of a width -- Dartvel's own
// breakpoints included -- then reports "desktop" on a phone, so responsive
// layout is not merely absent, it is actively wrong.
//
// Flutter's scaffolded index.html does not carry one, so every Dartvel web
// application shipped without it. This is the framework's job rather than the
// application's: it is true of every web build and there is no case where it
// is not wanted.
import 'dart:io';

import 'package:dartvel_cli/src/build/seo_head.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _template = '''
<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <title>dartvel_site</title>
</head>
<body></body>
</html>
''';

RegExp get _viewport =>
    RegExp(r'''<meta\s+name=["']viewport["'][^>]*>''', caseSensitive: false);

void main() {
  test('a page without one gets one', () {
    final String out = dvViewportApply(_template);
    expect(_viewport.allMatches(out).length, 1);
    expect(out, contains('width=device-width'));
    expect(out, contains('initial-scale=1'));
  });

  test('it goes inside the head', () {
    final String out = dvViewportApply(_template);
    expect(out.indexOf('name="viewport"'), lessThan(out.indexOf('</head>')));
  });

  test('it covers the notch', () {
    // Pairs with DV.Platform.screen.safeAreaBounds: without viewport-fit the
    // safe-area insets a phone reports are all zero, so honouring them does
    // nothing on the one class of device that has them.
    expect(dvViewportApply(_template), contains('viewport-fit=cover'));
  });

  test('a page that already has one is left alone', () {
    // A developer who wrote their own meant it. Two viewport metas is not
    // additive -- which one the browser honours is not something to guess at.
    const String custom = '<html><head>'
        '<meta name="viewport" content="width=device-width, initial-scale=2">'
        '</head><body></body></html>';

    final String out = dvViewportApply(custom);
    expect(_viewport.allMatches(out).length, 1);
    expect(out, contains('initial-scale=2'));
  });

  test('running twice adds one, not two', () {
    // A build often runs over the previous build's output.
    final String out = dvViewportApply(dvViewportApply(_template));
    expect(_viewport.allMatches(out).length, 1);
  });

  test('it does not zoom-lock the page', () {
    // user-scalable=no and maximum-scale=1 stop a low-vision reader pinching
    // to zoom. Some Flutter templates ship them; a framework should not put
    // them there on the developer's behalf.
    final String out = dvViewportApply(_template);
    expect(out, isNot(contains('user-scalable=no')));
    expect(out, isNot(contains('maximum-scale')));
  });

  test('a page with no head is returned unchanged', () {
    // Better than inventing structure around someone's template.
    const String odd = '<div>not a document</div>';
    expect(dvViewportApply(odd), odd);
  });

  test('it survives the SEO block being applied too', () {
    // Both rewrite the head, and the order they run in should not matter.
    final String out = dvSeoApply(
      dvViewportApply(_template),
      dvSeoHead(title: 'Dartvel', description: 'Flutter\'s Laravel'),
    );

    expect(_viewport.allMatches(out).length, 1);
    expect(out, contains('<title>Dartvel</title>'));
  });

  test('applying the SEO head alone is enough to get a viewport', () {
    // The integration point. Every path that writes a built page calls
    // dvSeoApply, and a viewport that needs a second call remembered at each
    // of them is a viewport that goes missing again -- silently, because the
    // page is perfect in a desktop browser.
    final String out = dvSeoApply(_template, dvSeoHead(title: 'Dartvel'));
    expect(_viewport.allMatches(out).length, 1);
    expect(out, contains('width=device-width'));
  });
  group('the project template', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('dv_viewport_'));
    tearDown(() => root.deleteSync(recursive: true));

    File writeIndex(String html) {
      final File file = File(p.join(root.path, 'web', 'index.html'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(html);
      return file;
    }

    test('a scaffolded project gets a viewport in its source index', () {
      final File index = writeIndex(_template);

      expect(dvEnsureProjectViewport(root.path), isTrue);
      expect(index.readAsStringSync(), contains('width=device-width'));
    });

    test('it reports doing nothing when there is already one', () {
      writeIndex('<html><head><meta name="viewport" content="width=device-width">'
          '</head><body></body></html>');

      expect(dvEnsureProjectViewport(root.path), isFalse);
    });

    test('a project with no web directory is not an error', () {
      // A mobile-only or server-only project. Reporting a problem here would
      // be noise on every build of one.
      expect(dvEnsureProjectViewport(root.path), isFalse);
    });

    test('it leaves the rest of the file alone', () {
      final File index = writeIndex(_template);
      dvEnsureProjectViewport(root.path);
      final String out = index.readAsStringSync();

      expect(out, contains('<base href="/">'));
      expect(out, contains('<title>dartvel_site</title>'));
      expect(out, contains('<body></body>'));
    });
  });

}

// The dev server serves web/index.html straight from the project, so fixing
// only the built output leaves `dartvel run web` laying out a phone at 980px
// -- the mode a developer is actually looking at when they check a layout.