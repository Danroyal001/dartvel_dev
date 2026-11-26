// SSR-first: `dartvel.web.ssrFirst: true` shows the server-rendered document
// as the page from the first paint, instead of the splash, and Flutter takes
// over in place at its first frame.
//
// Off by default. With it off, every page is byte for byte what it was.
import 'dart:io';

import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/ssr_first_capture.dart' show dvSsrFirstDefaultWidths;
import 'package:dartvel_core/dartvel.dart'
    show dvApplyPageHtml, dvApplyPageText, dvSsrFirstHead, dvSsrFirstMarker, dvSsrFirstThemeStyle, dvWithoutSsrFirst;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '''
<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <title>app</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

DVSplash _splash({bool ssrFirst = false}) => DVSplash(
      color: '#FFFFFF',
      darkColor: '#0A0A0A',
      ssrFirst: ssrFirst,
    );

void main() {
  group('the option', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('dv_ssr_first_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('is on by default (3.47.11): a project that says nothing gets it', () {
      final DVSplash nothing = DVSplash.fromConfig(const <String, Object?>{}, root: root.path);
      expect(nothing.ssrFirst, isTrue);
      expect(nothing.ssrFirstWidths, dvSsrFirstDefaultWidths);
      expect(
          DVSplash.fromConfig(const <String, Object?>{'web': <String, Object?>{}}, root: root.path).ssrFirst,
          isTrue);
      expect(
          DVSplash.fromConfig(const <String, Object?>{
            'web': <String, Object?>{'ssrFirst': null},
          }, root: root.path)
              .ssrFirst,
          isTrue);
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\ndartvel:\n  pwa: true\n');
      expect(DVSplash.of(root.path).ssrFirst, isTrue);
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
      expect(DVSplash.of(root.path).ssrFirst, isTrue);
    });

    test('false opts out, and so does a map with enabled: false', () {
      expect(
          DVSplash.fromConfig(const <String, Object?>{
            'web': <String, Object?>{'ssrFirst': <String, Object?>{'enabled': false}},
          }, root: root.path)
              .ssrFirst,
          isFalse);
      File(p.join(root.path, 'pubspec.yaml'))
          .writeAsStringSync('name: app\ndartvel:\n  web:\n    ssrFirst: false\n');
      expect(DVSplash.of(root.path).ssrFirst, isFalse);
      expect(DVSplash.of(root.path).ssrFirstWidths, isEmpty);
      expect(
          DVSplash.fromConfig(const <String, Object?>{
            'web': <String, Object?>{'ssrFirst': false},
          }, root: root.path)
              .ssrFirst,
          isFalse);
    });

    test('is dartvel.web.ssrFirst: true', () {
      expect(
          DVSplash.fromConfig(const <String, Object?>{
            'web': <String, Object?>{'ssrFirst': true},
          }, root: root.path)
              .ssrFirst,
          isTrue);
    });

    test('is read from pubspec.yaml', () {
      File(p.join(root.path, 'pubspec.yaml'))
          .writeAsStringSync('name: app\ndartvel:\n  web:\n    ssrFirst: true\n');
      expect(DVSplash.of(root.path).ssrFirst, isTrue);
    });
  });

  group('off', () {
    test('the shell is what it was', () {
      final String off = dvWebSplashApply(_shell, _splash());
      expect(off, isNot(contains(dvSsrFirstMarker)));
      expect(off, isNot(contains('data-dv-app')));
    });

    test('the document goes where it went, at the end of the body', () {
      final String page = dvApplyPageHtml(
          dvWebSplashApply(_shell, _splash()), '<h1>Pricing</h1>',
          path: '/pricing');
      expect(page.indexOf('class="dv-fallback"'),
          greaterThan(page.indexOf('flutter_bootstrap.js')));
      expect(page.indexOf('class="dv-fallback"'),
          greaterThan(page.indexOf('id="dartvel-splash"')));
    });
  });

  group('on', () {
    final String shell = dvWebSplashApply(_shell, _splash(ssrFirst: true));

    test('the head carries the document\'s screen styles and the handover', () {
      final int head = shell.indexOf('</head>');
      expect(shell.indexOf(dvSsrFirstMarker), inInclusiveRange(0, head));
      expect(shell, contains('dartvel-first-frame'));
    });

    test('the document goes first in the body, before the splash', () {
      // Parsed before the splash, so the splash is never painted over it,
      // even when the first paint comes before the parser reaches the end.
      for (final String page in <String>[
        dvApplyPageHtml(shell, '<h1>Pricing</h1>', path: '/pricing'),
        dvApplyPageText(shell, <String>['Pricing', 'Plans'], path: '/pricing'),
      ]) {
        final int body = page.indexOf('<body>');
        final int block = page.indexOf('class="dv-fallback"');
        expect(block, greaterThan(body));
        expect(block, lessThan(page.indexOf('id="dartvel-splash"')));
        expect(block, lessThan(page.indexOf('flutter_bootstrap.js')));
      }
    });

    test('rendering again replaces the document rather than adding one', () {
      final String once =
          dvApplyPageHtml(shell, '<h1>Pricing</h1>', path: '/pricing');
      final String twice =
          dvApplyPageHtml(once, '<h1>Pricing</h1>', path: '/pricing');
      expect(twice, once);
      expect('class="dv-fallback"'.allMatches(twice), hasLength(1));
    });

    test('the logo is not fetched behind a document', () {
      final String withLogo = dvWebSplashApply(_shell, _splash(ssrFirst: true),
          imageUrl: 'dartvel-splash.png', darkImageUrl: 'dartvel-splash-dark.png');
      expect(withLogo, isNot(contains('rel="preload" href="dartvel-splash')));
      expect(withLogo, contains('<img src="dartvel-splash.png" alt="" loading="lazy">'));
      // Off, as before.
      final String off = dvWebSplashApply(_shell, _splash(),
          imageUrl: 'dartvel-splash.png', darkImageUrl: 'dartvel-splash-dark.png');
      expect(off, contains('rel="preload" href="dartvel-splash.png"'));
      expect(off, isNot(contains('loading="lazy"')));
    });

    test('the splash is hidden only behind a document', () {
      // A route with nothing to show (no text, no capture) keeps the splash.
      final String css = RegExp(r'<style id="dartvel-ssr-first">(.*?)</style>',
              dotAll: true)
          .firstMatch(shell)!
          .group(1)!;
      expect(css, contains('.dv-fallback~#dartvel-splash{display:none}'));
    });

    test('the document is in the app\'s colours, light and dark', () {
      final String css = RegExp(r'<style id="dartvel-ssr-first">(.*?)</style>',
              dotAll: true)
          .firstMatch(shell)!
          .group(1)!;
      expect(css, contains('background:#FFFFFF'));
      expect(css, contains('prefers-color-scheme:dark'));
      expect(css, contains('background:#0A0A0A'));
    });

    test('everything it shows is screen-only and lifted at the first frame', () {
      final String css = RegExp(r'<style id="dartvel-ssr-first">(.*?)</style>',
              dotAll: true)
          .firstMatch(shell)!
          .group(1)!;
      // Printing keeps the block's own print rules.
      expect(css, isNot(contains('@media print')));
      // Every rule that puts the document on screen is keyed to the app not
      // having taken over yet.
      for (final Match rule
          in RegExp(r'([^{}]*\.dv-fallback[^{}]*)\{').allMatches(css)) {
        final String selector = rule.group(1)!;
        if (selector.contains('#dartvel-splash')) continue;
        // The handover's own rules hide it; they put nothing on screen.
        if (selector.contains('data-dv-handover')) continue;
        expect(selector, contains('html:not([data-dv-app])'),
            reason: selector);
      }
    });
  });

  group('dvSsrFirstHead', () {
    test('a link colour that does not read on the background is not used', () {
      // #FFFF00 on white is 1.07:1.
      final String head = dvSsrFirstHead(
          background: '#FFFFFF', darkBackground: '#FFFFFF', accent: '#FFFF00');
      expect(head, isNot(contains('color:#FFFF00')));
    });

    test('one that does is', () {
      final String head = dvSsrFirstHead(
          background: '#FFFFFF', darkBackground: '#FFFFFF', accent: '#1D4ED8');
      expect(head, contains('color:#1D4ED8'));
    });
  });

  // DARTVEL_OFF=ssr-first: the web-server turns SSR-first off at start, from
  // the SSR-first shell the build wrote, without a rebuild. What it serves
  // must be what a build with ssrFirst: false would have written.
  group('switched off at runtime', () {
    DVSplash splash({required bool ssrFirst, bool enabled = true, bool progress = true, String? loadingText = 'Loading'}) =>
        DVSplash(color: '#FFFFFF', darkColor: '#0A0A0A', ssrFirst: ssrFirst, enabled: enabled, progress: progress, loadingText: loadingText);

    final Map<String, ({String? image, String? dark})> logos = <String, ({String? image, String? dark})>{
      'no logo': (image: null, dark: null),
      'a logo': (image: 'splash/logo.png', dark: null),
      'a logo and a dark one': (image: 'splash/logo.png', dark: 'splash/logo-dark.png'),
      'a logo carried in the page': (image: 'data:image/png;base64,AAAA', dark: null),
      'a fetched logo and a dark one in the page': (image: 'splash/logo.png', dark: 'data:image/png;base64,AAAA'),
    };
    for (final MapEntry<String, ({String? image, String? dark})> logo in logos.entries) {
      for (final (bool enabled, bool progress, String? text) in <(bool, bool, String?)>[
        (true, true, 'Loading'),
        (true, false, null),
        (false, true, null),
      ]) {
        // With the splash off the logo is not in the shell, so its preload (which
        // a non-SSR-first build still writes) cannot be put back: that one
        // link is the difference, and only with a logo and no splash.
        if (!enabled && logo.value.image != null) continue;
        test('${logo.key}, splash $enabled, progress $progress: the shell a non-SSR-first build writes', () {
          String shellFor(bool ssrFirst) => dvWebSplashApply(_shell,
              splash(ssrFirst: ssrFirst, enabled: enabled, progress: progress, loadingText: text),
              imageUrl: logo.value.image, darkImageUrl: logo.value.dark);
          // The build also writes the theme for pages it could not capture.
          final String on = shellFor(true).replaceFirst('</head>', '${dvSsrFirstThemeStyle('.dvt h1{font:700 2rem serif}')}</head>');
          expect(on, contains(dvSsrFirstMarker));
          expect(dvWithoutSsrFirst(on), shellFor(false));
          expect(dvApplyPageHtml(dvWithoutSsrFirst(on), '<h1>Pricing</h1>', path: '/pricing'),
              dvApplyPageHtml(shellFor(false), '<h1>Pricing</h1>', path: '/pricing'));
        });
      }
    }

    test('a shell that is not SSR-first is left as it is', () {
      final String off = dvWebSplashApply(_shell, splash(ssrFirst: false), imageUrl: 'splash/logo.png');
      expect(dvWithoutSsrFirst(off), same(off));
    });
  });
}
