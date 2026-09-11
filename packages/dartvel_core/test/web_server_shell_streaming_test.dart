// `dartvel.web.server.streaming: shell`: the settings value, and the split of
// a page's head into what no render changes and what page data writes.
//
// The web server sends the shell's head before a route's data resolves, so
// the browser can start on main.dart.js, the renderer and the page's parts
// while the server queries. That is only safe if the part sent early is
// identical in every render of the shell -- otherwise the page the browser
// assembles is not the page that was rendered. dvHeadParts is the rule for
// which part that is, and the last test here is the property it rests on.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String shell = '<!DOCTYPE html>\n<html>\n<head>\n'
    '<base href="/">\n'
    '<meta charset="UTF-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    '<link rel="icon" type="image/png" href="favicon.png"/>\n'
    '<link rel="manifest" href="manifest.json">\n'
    '<!-- dartvel:seo -->\n<title>Shell</title>\n'
    '<meta name="description" content="The site">\n<!-- /dartvel:seo -->\n'
    '<link rel="preconnect" href="https://www.gstatic.com" crossorigin>\n'
    '<link rel="preload" href="main.dart.js_2.part.js" as="script">\n'
    '<style id="dartvel-splash-style">#s{background:#fff}</style>\n'
    '</head>\n<body><script src="flutter_bootstrap.js" async></script>'
    '</body>\n</html>\n';

void main() {
  group('the setting', () {
    test('shell is a value of its own', () {
      final DVWebServerSettings s =
          DVWebServerSettings.parse(<String, Object?>{'streaming': 'shell'});
      expect(s.streamingMode, DVPageStreaming.shell);
      expect(s.streaming, isTrue, reason: 'it is a kind of streaming');
    });

    test('true and false read exactly as they did', () {
      expect(
          DVWebServerSettings.parse(<String, Object?>{'streaming': true})
              .streamingMode,
          DVPageStreaming.head);
      expect(
          DVWebServerSettings.parse(<String, Object?>{'streaming': false})
              .streamingMode,
          DVPageStreaming.off);
      expect(DVWebServerSettings.parse(null).streamingMode,
          DVPageStreaming.off);
      // An unknown word is not a way to turn it on.
      expect(
          DVWebServerSettings.parse(<String, Object?>{'streaming': 'yes'})
              .streamingMode,
          DVPageStreaming.off);
      expect(const DVWebServerSettings(streaming: true).streamingMode,
          DVPageStreaming.head);
    });

    test('it survives the manifest', () {
      for (final DVPageStreaming mode in DVPageStreaming.values) {
        final DVWebServerSettings s =
            DVWebServerSettings(streamingMode: mode);
        expect(DVWebServerSettings.parse(s.toJson()).streamingMode, mode);
      }
      // The two old values are written as they always were, so a manifest
      // an older server reads still means what it meant.
      expect(const DVWebServerSettings(streaming: true).toJson()['streaming'],
          true);
      expect(const DVWebServerSettings().toJson()['streaming'], false);
      expect(
          const DVWebServerSettings(streamingMode: DVPageStreaming.shell)
              .toJson()['streaming'],
          'shell');
    });
  });

  group('a head, split', () {
    test('what data writes is kept apart from what it never touches', () {
      final DVHeadParts parts = dvHeadParts(shell)!;
      expect(parts.opening, endsWith('<head>'));
      expect(parts.fixed, contains('<base href="/">'));
      expect(parts.fixed, contains('main.dart.js_2.part.js'));
      expect(parts.fixed, contains('rel="preconnect"'));
      expect(parts.fixed, contains('dartvel-splash-style'));
      expect(parts.fixed, isNot(contains('<title>')));
      expect(parts.fixed, isNot(contains('name="description"')));
      // A page can wear its own icon, so the icon is the data's to write.
      expect(parts.fixed, isNot(contains('rel="icon"')));

      expect(parts.written, contains('<title>Shell</title>'));
      expect(parts.written, contains('rel="icon"'));
      expect(parts.rest, startsWith('</head>'));
      expect(parts.rest, contains('flutter_bootstrap.js'));
    });

    test('nothing is lost or repeated in the split', () {
      final DVHeadParts parts = dvHeadParts(shell)!;
      String sorted(String html) =>
          (html.split('\n').map((String l) => l.trim()).toList()..sort())
              .join('\n');
      expect(sorted(parts.opening + parts.fixed + parts.written + parts.rest),
          sorted(shell));
    });

    test('a page with no head is not split', () {
      expect(dvHeadParts('<p>hello</p>'), isNull);
    });

    test('the early part is the same in every render of the shell', () {
      // The property the whole mode rests on. The early part comes from a
      // render with nothing in it, sent before the data exists; the rest
      // comes from the real render. If the two disagreed about anything in
      // the early part, the browser would assemble a page nobody rendered.
      final String empty = dvRenderRoute(shell: shell, path: '/p/1', title: '');
      final String full = dvRenderPage(
        shell: shell,
        path: '/p/1',
        siteUrl: 'https://example.com',
        siteName: 'Example',
        data: const DVPageData(
          title: 'A product',
          description: 'Its description',
          image: 'img/p1.png',
          favicon: '/icons/product.png',
          text: <String>['In stock'],
          structuredData: <String, Object?>{'@type': 'Product'},
        ),
      );
      expect(dvHeadParts(full)!.fixed, dvHeadParts(empty)!.fixed);
      expect(dvHeadParts(full)!.opening, dvHeadParts(empty)!.opening);
      expect(dvHeadParts(full)!.written, contains('<title>A product</title>'));
      expect(dvHeadParts(full)!.written, contains('application/ld+json'));
      expect(dvHeadParts(full)!.written, contains('/icons/product.png'));
    });
  });
}
