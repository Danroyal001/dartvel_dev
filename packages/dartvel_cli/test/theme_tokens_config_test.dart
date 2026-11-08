// dartvel.theme in pubspec.yaml is the application's token set: it reaches
// the generated application entry, which installs it before the first theme
// is built, and a token missing a mode or a face that is not bundled stops
// the build with the diagnostic NEW_SPEC.md's Theme section names.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/generators/theme_tokens_source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Object? yaml(String source) => loadYaml(source);

Matcher refusedWith(String code, List<String> words) => throwsA(
      isA<DVThemeConfigException>()
          .having((DVThemeConfigException error) => error.code, 'code', code)
          .having((DVThemeConfigException error) => error.message, 'message', allOf(<Matcher>[for (final String word in words) contains(word)])),
    );

void main() {
  group('mode', modeFollowsDVTheme);
  test('no theme declared generates nothing', () {
    expect(dvThemeTokensSource(null, bundledFamilies: const <String>{}), isNull);
    expect(dvThemeTokensSource(yaml('{}'), bundledFamilies: const <String>{}), isNull);
  });

  test('colour tokens become per-mode tokens, high contrast included', () {
    final String source = dvThemeTokensSource(
      yaml('''
tokens:
  color:
    surface: { light: '#FFFFFF', dark: '#101114', highContrast: '#000000' }
    accent: { light: '#2C6BED', dark: '#5C8DFF' }
  space: { xs: 4, md: 18.5 }
  radius: { md: 8 }
'''),
      bundledFamilies: const <String>{},
    )!;
    expect(source, contains("'surface': DVColorToken('surface', light: const Color(0xFFFFFFFF), dark: const Color(0xFF101114), highContrast: const Color(0xFF000000))"));
    expect(source, contains("'accent': DVColorToken('accent', light: const Color(0xFF2C6BED), dark: const Color(0xFF5C8DFF))"));
    expect(source, contains("space: <String, double>{'xs': 4.0, 'md': 18.5}"));
    expect(source, contains("radius: <String, double>{'md': 8.0}"));
    expect(source, startsWith('DVThemeTokens.dartvel.override('));
  });

  test('a colour missing a mode is DV-THEME-001, naming the token and the mode', () {
    expect(
      () => dvThemeTokensSource(yaml("tokens: { color: { accent: { light: '#2C6BED' } } }"), bundledFamilies: const <String>{}),
      refusedWith('DV-THEME-001', <String>['color.accent', 'dark']),
    );
  });

  test('a token name the vocabulary does not have is refused, naming it', () {
    expect(
      () => dvThemeTokensSource(yaml('tokens: { space: { huge: 80 } }'), bundledFamilies: const <String>{}),
      refusedWith('DV-THEME-001', <String>['space.huge', 'xs']),
    );
  });

  test('a colour that is not a hex colour is refused, naming it', () {
    expect(
      () => dvThemeTokensSource(yaml("tokens: { color: { accent: { light: 'blue', dark: '#5C8DFF' } } }"), bundledFamilies: const <String>{}),
      refusedWith('DV-THEME-001', <String>['color.accent', 'light', 'blue']),
    );
  });

  test('the body face and its fallback chain', () {
    final String source = dvThemeTokensSource(
      yaml('fonts: { body: { family: Inter, fallback: [system-ui, sans-serif] } }'),
      bundledFamilies: const <String>{'Inter'},
    )!;
    expect(source, contains("fonts: <String, DVFontToken>{'body': DVFontToken(family: 'Inter', fallback: <String>['system-ui', 'sans-serif'])}"));
  });

  test('a face that is not bundled is DV-THEME-002', () {
    expect(
      () => dvThemeTokensSource(yaml('fonts: { body: { family: Inter } }'), bundledFamilies: const <String>{'Manrope'}),
      refusedWith('DV-THEME-002', <String>['Inter', 'flutter.fonts']),
    );
  });

  test('the generated application installs the tokens before building its theme', () async {
    final Directory root = await Directory.systemTemp.createTemp('dartvel_theme_tokens_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage() Widget _index() => DVText("Home");
''');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: themed_app
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: fonts/Inter.ttf
''');
    await ClientGenerator.generate(
      root: root.path,
      pagesDir: 'lib/pages',
      pkgName: 'themed_app',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      devBackendHost: 'http://localhost:3000',
      prodBackendHost: 'https://api.example.test',
      apiBasePath: '/api',
      envFiles: const <String>[],
      seoSiteName: 'Themed',
      seoTitle: 'Themed',
      seoDesc: 'Themed',
      seoImage: '',
      seoTwitter: '',
      defaultTransition: 'fade',
      durationMs: 200,
      curve: 'easeInOut',
      normalizeTrailing: true,
      notFoundRedirect: '',
      plugins: const <String>[],
      ota: false,
      dv: loadYaml('''
theme:
  tokens:
    color:
      accent: { light: '#2C6BED', dark: '#5C8DFF' }
  fonts:
    body: { family: Inter }
''') as YamlMap,
    );
    final String entry = File(p.join(root.path, 'lib/dartvel_client/application.g.dart')).readAsStringSync();
    final int install = entry.indexOf('runtime.DV.Theme.useTokens(DVThemeTokens.dartvel.override(');
    expect(install, isNonNegative);
    expect(install, lessThan(entry.indexOf('MaterialApp.router(')));
    expect(entry, contains("DVColorToken('accent'"));
  });
}

void modeFollowsDVTheme() {
  test('the generated application takes its mode from DV.Theme and rebuilds when it changes', () async {
    final Directory root = await Directory.systemTemp.createTemp('dartvel_theme_mode_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage() Widget _index() => DVText("Home");
''');
    await ClientGenerator.generate(
      root: root.path,
      pagesDir: 'lib/pages',
      pkgName: 'mode_app',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      devBackendHost: 'http://localhost:3000',
      prodBackendHost: 'https://api.example.test',
      apiBasePath: '/api',
      envFiles: const <String>[],
      seoSiteName: 'Mode',
      seoTitle: 'Mode',
      seoDesc: 'Mode',
      seoImage: '',
      seoTwitter: '',
      defaultTransition: 'fade',
      durationMs: 200,
      curve: 'easeInOut',
      normalizeTrailing: true,
      notFoundRedirect: '',
      plugins: const <String>[],
      ota: false,
      dv: YamlMap.wrap(<String, Object?>{}),
    );
    final String entry = File(p.join(root.path, 'lib/dartvel_client/application.g.dart')).readAsStringSync();
    expect(entry, contains('ListenableBuilder(listenable: runtime.DV.Theme'));
    expect(entry, contains('themeMode: runtime.DV.Theme.mode'));
    expect(entry, isNot(contains('themeMode: .system')));
  });
}
