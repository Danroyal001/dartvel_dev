// `dartvel.theme` reaches every place the build writes a colour: the
// generated app root, the splash and its loading bar, the SSR-first first
// screen, the page a reader with scripting off gets, the web manifest and
// the browser's theme-color. Before it existed a pure app could not set its
// colours at all: the generated root hard-coded Dartvel's theme, and focus
// rings, selection and the loading bar stayed Dartvel blue (ChopDesk,
// 25 Nov 2026).
import 'dart:io';

import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/web_branding.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_core/dartvel.dart' show DVThemeConfig;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const Map<String, Object?> _chopTheme = <String, Object?>{
  'seed': '#B83A12',
  'mode': 'light',
  'colors': <String, Object?>{
    'background': <String, Object?>{'light': '#FAF7F2', 'dark': '#141210'},
    'accent': <String, Object?>{'light': '#B83A12', 'dark': '#FF8A5C'},
  },
};

const String _webIndex = '''
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

Future<String> _applicationFor(Map<String, Object?> dartvel) async {
  final Directory root = Directory.systemTemp.createTempSync('dv-theme-app');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: theme_app\n');
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage() Widget _index() => DVText("Home");
''');
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'theme_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Theme App',
    seoTitle: 'Theme App',
    seoDesc: 'Theme App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(dartvel),
  );
  return File(p.join(root.path, 'lib/dartvel_client/application.g.dart')).readAsStringSync();
}

void main() {
  group('the generated root', () {
    test('installs dartvel.theme before boot and draws the app in it', () async {
      final String app = await _applicationFor(<String, Object?>{'theme': _chopTheme});
      expect(app, contains("const core.DVThemeConfig _dvTheme = core.DVThemeConfig(seed: '#B83A12', mode: core.DVThemeMode.light, "));
      expect(app, contains("core.DVColorRole.accent: core.DVColorPair(light: '#B83A12', dark: '#FF8A5C')"));
      expect(app, contains("core.DVColorRole.background: core.DVColorPair(light: '#FAF7F2', dark: '#141210')"));
      expect(RegExp(r'static Future<void> run\(.*theme: _dvTheme\)').hasMatch(app), isTrue, reason: app);
      expect(RegExp(r'dartvelRunEmbedded\(String project\) => .*theme: _dvTheme\)').hasMatch(app), isTrue);
      expect(app, contains('return DVAppTheme(builder: (BuildContext context, ThemeData light, ThemeData dark, ThemeMode mode) => '
          'MaterialApp.router('));
      expect(app, contains('theme: light, darkTheme: dark, themeMode: mode'));
      expect(app, isNot(contains('dartvelDefaultTheme')));
    });

    test('nothing declared is Dartvel\'s own theme', () async {
      final String app = await _applicationFor(<String, Object?>{});
      expect(app, contains('const core.DVThemeConfig _dvTheme = core.DVThemeConfig.dartvel;'));
    });

    test('the source the entry declares parses back to the same theme', () {
      final DVThemeConfig config = DVThemeConfig.parse(_chopTheme).config;
      expect(dvThemeConfigSource(config), startsWith('core.DVThemeConfig('));
      expect(dvThemeConfigSource(DVThemeConfig.dartvel), 'core.DVThemeConfig.dartvel');
    });
  });

  group('the splash and the first screen', () {
    test('take the theme\'s page colours and accent where the splash names none', () {
      final DVSplash splash = DVSplash.fromConfig(<String, Object?>{'theme': _chopTheme}, root: Directory.systemTemp.path);
      expect(splash.color, '#FAF7F2');
      expect(splash.darkColor, '#141210');
      expect(splash.progressColor, '#B83A12');
      expect(splash.linkColor, '#B83A12');
      expect(splash.darkLinkColor, '#FF8A5C');
      expect(splash.problems, isEmpty);
    });

    test('what the splash names itself still wins', () {
      final DVSplash splash = DVSplash.fromConfig(<String, Object?>{
        'theme': _chopTheme,
        'splash': <String, Object?>{'color': '#FFFFFF', 'progressColor': '#000000'},
      }, root: Directory.systemTemp.path);
      expect(splash.color, '#FFFFFF');
      expect(splash.progressColor, '#000000');
    });

    test('no theme keeps today\'s defaults', () {
      final DVSplash splash = DVSplash.fromConfig(<String, Object?>{}, root: Directory.systemTemp.path);
      expect(splash.progressColor, dvProgressDefaultColor);
      expect(splash.color, dvSplashDefaultColor);
      expect(splash.themed, isFalse);
    });

    test('a bad theme entry is reported with the splash\'s problems', () {
      final DVSplash splash = DVSplash.fromConfig(<String, Object?>{
        'theme': <String, Object?>{'seed': 'brick'},
      }, root: Directory.systemTemp.path);
      expect(splash.problems.join(), contains('dartvel.theme.seed'));
    });

    test('the SSR-first head links in the theme\'s colours, dark mode its own', () {
      final DVSplash splash = DVSplash.fromConfig(<String, Object?>{
        'theme': _chopTheme,
        'web': <String, Object?>{'ssrFirst': true},
      }, root: Directory.systemTemp.path);
      final String html = dvWebSplashApply(_webIndex, splash);
      expect(html, contains('.dv-fallback a{color:#B83A12}'));
      expect(html, contains('.dv-fallback a{color:#FF8A5C}'));
      expect(html.toUpperCase(), isNot(contains('#2F6BFF')));
    });

    test('a reader with scripting off gets the theme\'s page, not white and blue', () {
      final DVSplash splash = DVSplash.fromConfig(<String, Object?>{'theme': _chopTheme}, root: Directory.systemTemp.path);
      final String html = dvWebSplashApply(_webIndex, splash);
      final String noscript = RegExp(r'<noscript><style>(.*?)</style></noscript>').firstMatch(html)!.group(1)!;
      expect(noscript, contains('html body{background:#FAF7F2}'));
      expect(noscript, contains('html .dv-fallback a{color:#B83A12}'));
      expect(noscript, contains('(prefers-color-scheme:dark){html body{background:#141210}'));
      // Without a theme the shell is what it was.
      final String bare = dvWebSplashApply(_webIndex, DVSplash.fromConfig(<String, Object?>{}, root: Directory.systemTemp.path));
      expect(bare, isNot(contains('html .dv-fallback')));
    });
  });

  group('the manifest and the browser toolbar', () {
    test('theme_color is the theme\'s accent, the background its page', () {
      final DVWebBrand brand = dvWebBrand(const <String, Object?>{'theme': _chopTheme}, 'chopdesk');
      expect(brand.themeColor, '#B83A12');
      expect(brand.backgroundColor, '#FAF7F2');
      expect(brand.darkThemeColor, '#141210');
    });

    test('pwa.themeColor still wins, and no theme writes no theme-color tag', () {
      expect(dvWebBrand(const <String, Object?>{'theme': _chopTheme, 'pwa': <String, Object?>{'themeColor': '#123456'}}, 'x').themeColor, '#123456');
      final DVWebBrand bare = dvWebBrand(const <String, Object?>{}, 'x');
      expect(bare.darkThemeColor, isNull);
      expect(dvBrandIndexHtml(_webIndex, bare), isNot(contains('theme-color')));
    });

    test('index.html gets a theme-color per appearance, once', () {
      final DVWebBrand brand = dvWebBrand(const <String, Object?>{'theme': _chopTheme}, 'chopdesk');
      final String html = dvBrandIndexHtml(_webIndex, brand);
      expect(html, contains('<meta name="theme-color" media="(prefers-color-scheme: light)" content="#B83A12">'));
      expect(html, contains('<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#141210">'));
      expect('theme-color'.allMatches(dvBrandIndexHtml(html, brand)).length, 2);
    });
  });
}
