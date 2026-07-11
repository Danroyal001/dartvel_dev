import 'dart:async';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'utils/route_utils.dart';

class RouterBuilder implements Builder {
  final BuilderOptions options;

  RouterBuilder(this.options);

  @override
  Map<String, List<String>> get buildExtensions => {
        'pubspec.yaml': [
          'lib/dartvel_client/router.g.dart',
          'lib/dartvel_client/env.g.dart',
          'lib/dartvel_client/dartvel_config.g.dart',
          'lib/dartvel_client/dartvel_runtime.dart',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    // 1. Read pubspec.yaml to get config
    final pubspecId = AssetId(buildStep.inputId.package, 'pubspec.yaml');
    if (!await buildStep.canRead(pubspecId)) {
      log.warning('Could not find pubspec.yaml');
      return;
    }
    final pubspecContent = await buildStep.readAsString(pubspecId);
    final pubspec = loadYaml(pubspecContent);
    final dv = pubspec['dartvel'] as YamlMap?;
    if (dv == null) {
      log.warning('No dartvel section in pubspec.yaml');
      return;
    }

    final pkgName = pubspec['name'] as String;
    final pagesDir = (dv['pagesDir'] ?? 'lib/pages').toString();
    final backendHost = (dv['backendHost'] ?? '0.0.0.0').toString();
    final backendPort = (dv['backendPort'] as int?) ?? 3000;
    final devBackendHost =
        (dv['devBackendHost'] ?? 'http://localhost:3000').toString();
    final prodBackendHost = (dv['prodBackendHost'] ?? '').toString();
    final apiBasePath = (dv['apiBasePath'] ?? '/api').toString();
    final envFiles =
        (dv['envFiles'] as YamlList?)?.map((e) => e.toString()).toList() ??
            ['.env', '.env.local'];
    final seo = dv['seo'] is YamlMap
        ? dv['seo'] as YamlMap
        : (dv['webSeoDefaults'] is YamlMap
            ? dv['webSeoDefaults'] as YamlMap
            : YamlMap.wrap({}));
    final seoSiteName = (seo['siteName'] ?? pkgName).toString();
    final seoTitle =
        (seo['defaultTitle'] ?? seo['title'] ?? 'Dartvel App').toString();
    final seoDesc =
        (seo['defaultDescription'] ?? seo['description'] ?? '').toString();
    final seoImage = (seo['defaultImage'] ?? seo['image'] ?? '').toString();
    final seoTwitter = (seo['twitterHandle'] ?? '').toString();
    final defaultTransition =
        (dv['transitions']?['default'] ?? 'fade').toString();
    final durationMs = (dv['transitions']?['durationMs'] as int?) ?? 200;
    final curve = (dv['transitions']?['curve'] ?? 'easeInOut').toString();
    final normalizeTrailing =
        (dv['routingNormalizeTrailingSlash'] as bool?) ?? true;
    final notFoundRedirect = (dv['routingRedirects'] is YamlMap
            ? (dv['routingRedirects']['notFound'] ?? '').toString()
            : '')
        .toString();

    // 2. Scan pages
    final pageGlob = Glob('$pagesDir/**.dart');
    final pageAssets = await buildStep.findAssets(pageGlob).toList();
    // Sort by path for determinism
    pageAssets.sort((a, b) => a.path.compareTo(b.path));

    // 3. Scan layouts
    final layoutGlob = Glob('$pagesDir/**/_layout.dart');
    final layoutAssets = await buildStep.findAssets(layoutGlob).toList();
    // Add root layout if not covered by glob (glob should cover it if pagesDir is lib/pages)
    // But check just in case
    final rootLayoutId = AssetId(
      buildStep.inputId.package,
      p.join(pagesDir, '_layout.dart'),
    );
    if (!layoutAssets.contains(rootLayoutId) &&
        await buildStep.canRead(rootLayoutId)) {
      layoutAssets.add(rootLayoutId);
    }
    layoutAssets.sort((a, b) => a.path.compareTo(b.path));

    // 4. Scan guards
    final guardGlob = Glob('$pagesDir/**/_guard.dart');
    final guardAssets = await buildStep.findAssets(guardGlob).toList();
    guardAssets.sort((a, b) => a.path.compareTo(b.path));

    // 5. Process Pages
    final pageImports = <String>[];
    final pageEntries = <Map<String, dynamic>>[];
    final layoutImports = <String>[];
    final layoutMapByDir = <String, Map<String, String>>{};
    final guardImports = <String>[];
    final guardMapByDir = <String, String>{};

    for (var i = 0; i < pageAssets.length; i++) {
      final asset = pageAssets[i];
      final path = asset.path;
      final basename = p.basename(path);
      if (basename == '_layout.dart' || basename == '_guard.dart') continue;
      if (basename.endsWith('.loading.dart') ||
          basename.endsWith('.error.dart')) {
        continue;
      }
      final importPath = path.replaceFirst(
        RegExp(r'^lib/'),
        'package:$pkgName/',
      );
      final src = await buildStep.readAsString(asset);
      final hasPageAnnotation = src.contains('@DVPage');
      final isLegacyPageFile = path.endsWith('.page.dart');
      if (!hasPageAnnotation && !isLegacyPageFile) {
        continue;
      }
      final m = RegExp(
        r'(?:@DVPage\([^)]*\)\s*)?class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+(DartvelPage|DVClassWidget)',
      ).firstMatch(src);
      String className;
      bool isFunctional = false;
      if (m != null) {
        className = m.group(1)!;
      } else {
        final mf = RegExp(r'@DVFunctionalWidget\(\)\s+Widget\s+([A-Za-z_][A-Za-z0-9_]*)\(')
            .firstMatch(src);
        if (mf == null) {
          log.warning(
            'dartvel: could not find class extending DartvelPage/DVClassWidget or @DVFunctionalWidget in $path',
          );
          continue;
        }
        className = mf.group(1)!;
        isFunctional = true;
      }
      pageImports.add("import '$importPath' as p$i;");

      String route;
      try {
        route = RouteUtils.routeFor(path, pagesDir);
      } catch (e) {
        log.severe('Invalid route in $path: $e');
        continue;
      }
      final dir = p.dirname(path).replaceAll('\\', '/');

      // Check for loading/error siblings
      final baseNoSuffix = path
          .replaceFirst(RegExp(r'\.page\.dart$'), '')
          .replaceFirst(RegExp(r'\.dart$'), '');
      final loadingAsset = AssetId(asset.package, '$baseNoSuffix.loading.dart');
      final errorAsset = AssetId(asset.package, '$baseNoSuffix.error.dart');

      String? loadingAlias;
      String? errorAlias;

      if (await buildStep.canRead(loadingAsset)) {
        final imp = loadingAsset.path.replaceFirst(
          RegExp(r'^lib/'),
          'package:$pkgName/',
        );
        loadingAlias = 'pl$i';
        pageImports.add("import '$imp' as $loadingAlias;");
      }
      if (await buildStep.canRead(errorAsset)) {
        final imp = errorAsset.path.replaceFirst(
          RegExp(r'^lib/'),
          'package:$pkgName/',
        );
        errorAlias = 'pe$i';
        pageImports.add("import '$imp' as $errorAlias;");
      }

      pageEntries.add({
        'i': '$i',
        'class': className,
        'route': route,
        'dir': dir,
        'isFunctional': isFunctional,
        if (loadingAlias != null) 'loadingAlias': loadingAlias,
        if (errorAlias != null) 'errorAlias': errorAlias,
      });
    }

    // 6. Process Layouts
    for (var j = 0; j < layoutAssets.length; j++) {
      final asset = layoutAssets[j];
      final path = asset.path;
      final importPath = path.replaceFirst(
        RegExp(r'^lib/'),
        'package:$pkgName/',
      );
      final src = await buildStep.readAsString(asset);
      final m = RegExp(
        r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+DartvelLayout',
      ).firstMatch(src);
      if (m == null) continue;
      final className = m.group(1)!;
      final alias = 'l$j';
      layoutImports.add("import '$importPath' as $alias;");
      final dir = p.dirname(path).replaceAll('\\', '/');
      layoutMapByDir[dir] = {'i': '$j', 'class': className};
    }

    // 7. Process Guards
    for (var k = 0; k < guardAssets.length; k++) {
      final asset = guardAssets[k];
      final path = asset.path;
      final importPath = path.replaceFirst(
        RegExp(r'^lib/'),
        'package:$pkgName/',
      );
      final alias = 'g$k';
      guardImports.add("import '$importPath' as $alias;");
      final dir = p.dirname(path).replaceAll('\\', '/');
      guardMapByDir[dir] = alias;
    }

    // 8. Generate Code
    // ... (Logic from ClientGenerator) ...
    // Since we are in a Builder, we write to AssetIds.

    // Helper functions for code generation
    String esc(String s) => s.replaceAll("'", "\\'");
    String transitionEnum(String t) {
      switch (t) {
        case 'fade':
          return 'DvTransition.fade';
        case 'slideLeft':
          return 'DvTransition.slideLeft';
        case 'slideUp':
          return 'DvTransition.slideUp';
        case 'scale':
          return 'DvTransition.scale';
        case 'sharedAxis':
          return 'DvTransition.sharedAxis';
        case 'none':
          return 'DvTransition.none';
        default:
          return 'DvTransition.fade';
      }
    }

    String curveExpr(String c) {
      // simplified mapping
      if (c == 'linear') return 'Curves.linear';
      if (c == 'easeIn') return 'Curves.easeIn';
      if (c == 'easeOut') return 'Curves.easeOut';
      return 'Curves.easeInOut';
    }

    String wrapWithLayouts(String dir, String innerExpr) {
      final parts = <String>[];
      var cur = dir;
      while (true) {
        parts.add(cur);
        if (cur == pagesDir) break;
        final parent = p.dirname(cur).replaceAll('\\\\', '/');
        if (parent == cur) break;
        cur = parent;
      }
      final chain = parts.reversed
          .where((d) => layoutMapByDir.containsKey(d))
          .map((d) => layoutMapByDir[d]!)
          .toList();
      var expr = innerExpr;
      for (final m in chain) {
        final idx = m['i']!;
        final cls = m['class']!;
        expr = 'l$idx.$cls(child: $expr)';
      }
      return expr;
    }

    String guardRedirectFor(String dir) {
      final parts = <String>[];
      var cur = dir;
      while (true) {
        parts.add(cur);
        if (cur == pagesDir) break;
        final parent = p.dirname(cur).replaceAll('\\\\', '/');
        if (parent == cur) break;
        cur = parent;
      }
      final chain = parts.reversed
          .where((d) => guardMapByDir.containsKey(d))
          .map((d) => guardMapByDir[d]!)
          .toList();
      if (chain.isEmpty) return '';
      final calls = chain
          .map(
            (a) =>
                '      { final r = await $a.guard(context, state); if (r != null) return r; }',
          )
          .join('\n');
      return '\n      redirect: (context, state) async {\n$calls\n        return null;\n      },\n';
    }

    // i18n
    final i18n = (dv['i18n'] as Map?) ?? {};
    final defaultLocale = i18n['defaultLocale'] as String? ?? 'en';
    final locales = <String>{defaultLocale};
    final i18nParam = (i18n['param'] ?? 'lang').toString();
    final i18nDefault = (i18n['defaultLocale'] ?? '').toString();
    final i18nLocales = <String>[];
    if (i18n['locales'] is List) {
      for (final v in (i18n['locales'] as List)) {
        if (v != null) i18nLocales.add(v.toString());
      }
    }
    final i18nLocalesLit = i18nLocales.map((s) => "'${esc(s)}'").join(', ');

    final routesSrc = pageEntries
        .map(
          (e) => '''
    GoRoute(
      path: '${esc(e['route']!)}',
${guardRedirectFor(e['dir']!)}      pageBuilder: (context, state) {
        final params = Map<String, String>.from(state.pathParameters);
        final query  = Map<String, String>.from(state.uri.queryParameters);
        ${e['isFunctional'] == true
            ? 'final page = p${e['i']}.${e['class']}(context);'
            : 'final page = const p${e['i']}.${e['class']}();'}
        final withState = DartvelRouteState(params: params, query: query, child: page);

        final i18nParam = '${esc(i18nParam)}';
        final i18nDefault = '${esc(i18nDefault)}';
        final i18nLocales = <String>[$i18nLocalesLit];
        final langRaw = query[i18nParam];
        final langTag = (i18nLocales.isEmpty && i18nDefault.isEmpty)
            ? (langRaw ?? '')
            : (DvI18n.normalize(langRaw, i18nLocales, i18nDefault.isEmpty ? (langRaw ?? '') : i18nDefault));
        final withI18n = DvI18nScope(localeTag: langTag, child: withState);

        ${e['isFunctional'] == true
            ? 'final loaderWrapped = withI18n;'
            : '''final loaderWrapped = DvDataLoader(
          load: () => page.loadData(params, query),
          child: withI18n,
${(() {
            final la = e['loadingAlias'];
            final ea = e['errorAlias'];
            final lc = e['class'] != null ? '${e['class']!}Loading' : 'Loading';
            final ec = e['class'] != null ? '${e['class']!}Error' : 'Error';
            final b = StringBuffer();
            if (la != null && la.isNotEmpty) {
              b.writeln("          loading: $la.$lc(),");
            } else {
              b.writeln("          loading: const DvDefaultLoading(),");
            }
            if (ea != null && ea.isNotEmpty) {
              b.writeln("          error: $ea.$ec(),");
            } else {
              b.writeln("          error: const DvDefaultError(),");
            }
            return b.toString();
          })()}        );'''}

        final seoWrapped = DartvelSeo(
          props: ${e['isFunctional'] == true ? 'SeoProps.empty' : 'page.buildWebSeo(params, query)'},
          defaults: _defaultSeo,
          child: loaderWrapped,
        );
        final spec = ${e['isFunctional'] == true
            ? '_projectDefaultTransition'
            : '''page.transition == const PageTransitionSpec()
            ? _projectDefaultTransition
            : page.transition'''};
        return dvTransitionPage(
          key: state.pageKey,
          child: ${wrapWithLayouts(e['dir']!, 'seoWrapped')},
          spec: spec,
        );
      },
    )
  ''',
        )
        .join(',\n');

    // Global redirect
    final sbRedirect = StringBuffer();
    sbRedirect.writeln(
      'String? _globalRedirect(BuildContext context, GoRouterState state) {',
    );
    sbRedirect.writeln('  final path = state.uri.path;');
    if (notFoundRedirect.isNotEmpty) {
      sbRedirect.writeln(
        "  if (state.error != null) return '${esc(notFoundRedirect)}';",
      );
    }
    if (normalizeTrailing) {
      sbRedirect.writeln("  if (path.length > 1 && path.endsWith('/')) {");
      sbRedirect.writeln(
        '    final newUri = state.uri.replace(path: path.substring(0, path.length - 1));',
      );
      sbRedirect.writeln('    return newUri.toString();');
      sbRedirect.writeln('  }');
    }
    // (Skipping complex regex redirects for brevity/safety in builder for now, or add if needed)
    sbRedirect.writeln('  return null;');
    sbRedirect.writeln('}');

    final routerContent = '''
// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
${pageImports.join('\n')}
${layoutImports.join('\n')}
${guardImports.join('\n')}

const _defaultSeo = SeoProps(
  siteName: '${esc(seoSiteName)}',
  title: '${esc(seoTitle)}',
  description: '${esc(seoDesc)}',
  imageUrl: '${esc(seoImage)}',
  twitterHandle: '${esc(seoTwitter)}',
);

const _projectDefaultTransition = PageTransitionSpec(
  type: ${transitionEnum(defaultTransition)},
  duration: Duration(milliseconds: $durationMs),
  curve: ${curveExpr(curve)},
);

${sbRedirect.toString()}

/// Creates the GoRouter instance for Dartvel routing.
GoRouter createDartvelRouter() => GoRouter(
  routes: [
$routesSrc
  ],
  redirect: _globalRedirect,
);
''';

    // Write router.g.dart
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/dartvel_client/router.g.dart'),
      routerContent,
    );

    // Write env.g.dart
    final envMap = <String, String>{};
    // Note: In build_runner, we can't easily read arbitrary files outside the package structure
    // unless they are assets. .env files are usually at root.
    // We can try to read them if they are in the package.
    for (final f in envFiles) {
      final envId = AssetId(buildStep.inputId.package, f);
      if (await buildStep.canRead(envId)) {
        final content = await buildStep.readAsString(envId);
        // Parse manually since RouteUtils.parseEnvFile uses File
        final lines = content.split('\n');
        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final eq = line.indexOf('=');
          if (eq <= 0) continue;
          final key = line.substring(0, eq).trim();
          var val = line.substring(eq + 1).trim();
          if ((val.startsWith('"') && val.endsWith('"')) ||
              (val.startsWith("'") && val.endsWith("'"))) {
            val = val.substring(1, val.length - 1);
          }
          envMap[key] = val;
        }
      }
    }
    final publicEnv = <String, String>{
      for (final e in envMap.entries)
        if (e.key.startsWith('PUBLIC_')) e.key: e.value,
    };

    final sbEnv = StringBuffer();
    sbEnv.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    sbEnv.writeln('library dartvel_client_env;');
    sbEnv.writeln('');
    sbEnv.writeln('/// Environment variables provider.');
    sbEnv.writeln('class Env {');
    sbEnv.writeln('  /// Decrypts obfuscated values.');
    sbEnv.writeln(
      '  static String _d(List<int> c, int k) => String.fromCharCodes(c.map((x) => x ^ k));',
    );
    for (final e in publicEnv.entries) {
      final obf = RouteUtils.obfuscate(e.value);
      final parts = obf.split(', ');
      final key = parts.last;
      final list = parts.sublist(0, parts.length - 1).join(', ');
      sbEnv.writeln('  // ignore: non_constant_identifier_names');
      sbEnv.writeln('  /// Value of ${e.key} environment variable.');
      sbEnv.writeln('  static String get ${e.key} => _d($list, $key);');
    }
    sbEnv.writeln('}');
    sbEnv.writeln('');
    sbEnv.writeln('/// Legacy map support for environment variables.');
    sbEnv.writeln('final Map<String, String> dvPublicEnv = {');
    for (final e in publicEnv.entries) {
      sbEnv.writeln("  '${e.key}': Env.${e.key},");
    }
    sbEnv.writeln('};');
    sbEnv.writeln('/// Public environment variable manager.');
    sbEnv.writeln('class DartvelEnv {');
    sbEnv.writeln('  /// Map of all public environment variables.');
    sbEnv.writeln('  static final Map<String, String> public = dvPublicEnv;');
    sbEnv.writeln('  /// Gets a public environment variable by key.');
    sbEnv.writeln('  static String? get(String key) => dvPublicEnv[key];');
    sbEnv.writeln('}');
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/dartvel_client/env.g.dart'),
      sbEnv.toString(),
    );

    // Write dartvel_config.g.dart
    final configContent = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
library dartvel_client_config;
const String dvBackendBindHost = '${esc(backendHost)}';
const int    dvBackendPort      = $backendPort;
const String dvDevBackendHost   = '${esc(devBackendHost)}';
const String dvProdBackendHost  = '${esc(prodBackendHost)}';
const String dvApiBasePath      = '${esc(apiBasePath)}';
''';
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        'lib/dartvel_client/dartvel_config.g.dart',
      ),
      configContent,
    );

    // Write dartvel_runtime.dart (static helper)
    final runtimeDart = """
import 'package:flutter/foundation.dart' show kReleaseMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'dartvel_config.g.dart' as cfg;

class DartvelRuntime {
  static const String _override = String.fromEnvironment('DARTVEL_BACKEND_URL', defaultValue: '');
  static bool _emulatorNoteShown = false;

  static String _adjustDevHost(String url) {
    if (kIsWeb) return url;
    try {
      final u = Uri.parse(url);
      final host = (u.host).toLowerCase();
      final isLocal = host == 'localhost' || host == '127.0.0.1';
      final onAndroid = defaultTargetPlatform == TargetPlatform.android;
      if (onAndroid && isLocal) {
        final updated = u.replace(host: '10.0.2.2').toString();
        if (!_emulatorNoteShown) {
          _emulatorNoteShown = true;
          debugPrint('''\\n=== DARTVEL DEV ===\\nDetected Android emulator. Using 10.0.2.2 for backend.\\nBase: \$url -> \$updated\\n===================\\n''');
        }
        return updated;
      }
    } catch (_) {}
    return url;
  }

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    final url = kReleaseMode ? cfg.dvProdBackendHost : cfg.dvDevBackendHost;
    return _adjustDevHost(url);
  }

  static String get apiBasePath => cfg.dvApiBasePath;

  static Uri api(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final api  = apiBasePath.startsWith('/') ? apiBasePath : '/\$apiBasePath';
    final sub  = path.startsWith('/') ? path : '/\$path';
    return Uri.parse('\$base\$api\$sub');
  }
}
""";
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        'lib/dartvel_client/dartvel_runtime.dart',
      ),
      runtimeDart,
    );
  }
}

Builder routerBuilder(BuilderOptions options) => RouterBuilder(options);
