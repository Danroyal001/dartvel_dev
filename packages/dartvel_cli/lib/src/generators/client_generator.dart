import 'dart:io';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/helpers.dart';
import '../utils/logger.dart';
import 'route_utils.dart';

class ClientGenerator {
  static Future<void> generate({
    required String root,
    required String pagesDir,
    required String pkgName,
    required String buildId,
    required String backendHost,
    required int backendPort,
    required String devBackendHost,
    required String prodBackendHost,
    required String apiBasePath,
    required List<String> envFiles,
    required String seoSiteName,
    required String seoTitle,
    required String seoDesc,
    required String seoImage,
    required String seoTwitter,
    required String defaultTransition,
    required int durationMs,
    required String curve,
    required bool normalizeTrailing,
    required String notFoundRedirect,
    required List<String> plugins,
    required bool webPrerender,
    required bool ota,
    required YamlMap dv,
  }) async {
    // Scan pages
    final pageGlob = Glob('$pagesDir/**.dart');
    final pageFiles = <File>[];
    final fs = const LocalFileSystem();
    for (final e
        in pageGlob.listFileSystemSync(fs, root: root, followLinks: false)) {
      final path = e.path;
      final ioFile = File(path);
      if (!ioFile.existsSync()) continue;
      // Skip framework companion files from page discovery. A route page can be
      // either the legacy *.page.dart form or the spec form with @DVPage().
      final basename = p.basename(path);
      if (basename == '_layout.dart' || basename == '_guard.dart') continue;
      if (basename.endsWith('.loading.dart') ||
          basename.endsWith('.error.dart')) {
        continue;
      }
      pageFiles.add(ioFile);
    }
    pageFiles.sort((a, b) => a.path.compareTo(b.path));

    // Scan layouts: any _layout.dart under pagesDir
    final layoutGlob = Glob(p.join(pagesDir, '**/_layout.dart'));
    final layoutFiles = <File>[];
    for (final e
        in layoutGlob.listFileSystemSync(fs, root: root, followLinks: false)) {
      final ioFile = File(e.path);
      if (ioFile.existsSync()) layoutFiles.add(ioFile);
    }
    // Fallback: add root layout if present
    final rl = File(p.join(root, pagesDir, '_layout.dart'));
    if (rl.existsSync() && !layoutFiles.any((f) => p.equals(f.path, rl.path))) {
      layoutFiles.add(rl);
    }
    layoutFiles.sort((a, b) => a.path.compareTo(b.path));

    final pageImports = <String>[];
    final pageEntries = <Map<String, dynamic>>[];
    final layoutImports = <String>[];
    final layoutMapByDir = <String, Map<String, String>>{}; // dir -> {i, class}

    for (var i = 0; i < pageFiles.length; i++) {
      final abs = pageFiles[i].path;
      final rel = p.relative(abs, from: root).replaceAll('\\', '/');
      final importPath =
          rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      // Parse class name by scanning file for a page class or functional widget.
      final src = await File(abs).readAsString();
      final hasPageAnnotation = src.contains('@DVPage');
      final isLegacyPageFile = rel.endsWith('.page.dart');
      if (!hasPageAnnotation && !isLegacyPageFile) {
        continue;
      }
      final m = RegExp(
              r'(?:@DVPage\([^)]*\)\s*)?class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+(DartvelPage|DVClassWidget)')
          .firstMatch(src);
      String className;
      bool isFunctional = false;
      if (m != null) {
        className = m.group(1)!;
      } else {
        final mf = RegExp(
                r'@DVPage\([^)]*\)\s*(?:@DVFunctionalWidget\(\)\s*)?Widget\s+([A-Za-z_][A-Za-z0-9_]*)\(')
            .firstMatch(src);
        if (mf == null) {
          stderr.writeln(
              'dartvel: could not find class extending DartvelPage/DVClassWidget or @DVPage function in $rel');
          continue;
        }
        className = mf.group(1)!;
        isFunctional = true;
      }

      pageImports.add("import '$importPath' deferred as p$i;");
      String route;
      try {
        route = RouteUtils.routeFor(rel, pagesDir);
      } catch (e) {
        stderr.writeln('ERROR: Invalid route in $rel: ${e.toString()}');
        exit(1);
      }
      final dir = p.dirname(rel).replaceAll('\\', '/');

      // Detect optional .loading.dart and .error.dart siblings
      final String baseNoSuffix = rel
          .replaceFirst(RegExp(r'\.page\.dart$'), '')
          .replaceFirst(RegExp(r'\.dart$'), '');
      final loadingRel = '$baseNoSuffix.loading.dart';
      final errorRel = '$baseNoSuffix.error.dart';
      String? loadingAlias;
      String? errorAlias;
      if (!isFunctional && File(p.join(root, loadingRel)).existsSync()) {
        final importPathL =
            loadingRel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
        loadingAlias = 'pl$i';
        pageImports.add("import '$importPathL' as $loadingAlias;");
      }
      if (!isFunctional && File(p.join(root, errorRel)).existsSync()) {
        final importPathE =
            errorRel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
        errorAlias = 'pe$i';
        pageImports.add("import '$importPathE' as $errorAlias;");
      }

      pageEntries.add({
        'i': '$i',
        'class': className,
        'generatedWidget': _generatedPageWidgetName(className),
        'pageScaffold': _pageScaffoldSpec(src),
        'route': route,
        'dir': dir,
        'isFunctional': isFunctional,
        if (loadingAlias != null) 'loadingAlias': loadingAlias,
        if (errorAlias != null) 'errorAlias': errorAlias,
      });
    }

    // Import all layouts and build map by directory
    for (var j = 0; j < layoutFiles.length; j++) {
      final abs = layoutFiles[j].path;
      final rel = p.relative(abs, from: root).replaceAll('\\', '/');
      final importPath =
          rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      final src = await File(abs).readAsString();
      final m =
          RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+DartvelLayout')
              .firstMatch(src);
      if (m == null) {
        stderr.writeln(
            'dartvel: could not find a class extending DartvelLayout in $rel');
        continue;
      }
      final className = m.group(1)!;
      final alias = 'l$j';
      layoutImports.add("import '$importPath' as $alias;");
      final dir = p.dirname(rel).replaceAll('\\', '/');
      layoutMapByDir[dir] = {'i': '$j', 'class': className};
    }

    // Detect route conflicts (same computed route from multiple files)
    final routeToEntries = <String, List<Map<String, dynamic>>>{};
    for (final e in pageEntries) {
      routeToEntries
          .putIfAbsent(e['route']!, () => <Map<String, dynamic>>[])
          .add(e);
    }
    final conflicts = routeToEntries.entries.where((kv) => kv.value.length > 1);
    if (conflicts.isNotEmpty) {
      stderr.writeln('ERROR: Detected route conflicts:');
      for (final c in conflicts) {
        stderr.writeln('  Route "${c.key}" generated by:');
        for (final e in c.value) {
          // Best-effort: rebuild approximate file path from import alias index
          final idx = e['i'];
          if (idx == null) continue;
          // Search from pageImports for matching alias
          final alias = 'p$idx';
          try {
            final line =
                pageImports.firstWhere((l) => l.contains(' as $alias;'));
            final beforeAs = line.split(' as ').first;
            String path = beforeAs.trim();
            final impIdx = path.indexOf("import '");
            if (impIdx != -1) {
              var s = path.substring(impIdx + 8); // after "import '"
              final end = s.lastIndexOf("'");
              if (end != -1) s = s.substring(0, end);
              path = s;
            }
            stderr.writeln('    - ${path.trim()}');
          } catch (_) {
            stderr.writeln('    - alias $alias');
          }
        }
      }
      exit(41);
    }

    // Guards: scan for _guard.dart files and build a dir->alias map
    final guardImports = <String>[];
    final guardMapByDir = <String, String>{};
    final guardGlob = Glob(p.join(pagesDir, '**/_guard.dart'));
    for (final e
        in guardGlob.listFileSystemSync(fs, root: root, followLinks: false)) {
      final ioFile = File(e.path);
      if (!ioFile.existsSync()) continue;
      final rel = p.relative(ioFile.path, from: root).replaceAll('\\', '/');
      final importPath =
          rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      final alias = 'g${guardImports.length}';
      guardImports.add("import '$importPath' as $alias;");
      final dir = p.dirname(rel).replaceAll('\\', '/');
      guardMapByDir[dir] = alias;
    }

    // Ensure dirs
    // Ensure dirs
    Directory(p.join(root, '.dart_tool')).createSync();
    if (pageEntries.isEmpty) {
      log('dartvel: no pages found under "$pagesDir" (looking for @DVPage() pages or legacy **/*.page.dart)');
    }

    // Client runtime/helper – write only under lib/dartvel_client
    final libClientDir = Directory(p.join(root, 'lib', 'dartvel_client'))
      ..createSync(recursive: true);
    // Public generated client barrel. Apps import this single file instead of
    // reaching into generated siblings.
    final clientFile = File(p.join(libClientDir.path, 'dartvel_client.dart'));
    clientFile.writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_client;

export 'package:dartvel_core/dartvel.dart';
export 'package:dartvel_flutter/dartvel_flutter.dart';
export 'config.g.dart';
export 'dartvel_config.g.dart';
export 'dartvel_runtime.dart';
export 'env.g.dart';
export 'functions.g.dart';
export 'models.g.dart';
export 'router.g.dart';
export 'widgets.g.dart';
''');

    // Mirror config too for analyzer friendliness
    File(p.join(libClientDir.path, 'dartvel_config.g.dart'))
        .writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_client_config;
const String dvBackendBindHost = '${esc(backendHost)}';
const int    dvBackendPort      = $backendPort;
const String dvDevBackendHost   = '${esc(devBackendHost)}';
const String dvProdBackendHost  = '${esc(prodBackendHost)}';
const String dvApiBasePath      = '${esc(apiBasePath)}';
''');

    // Client runtime helper
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
          debugPrint('''\n=== DARTVEL DEV ===\nDetected Android emulator. Using 10.0.2.2 for backend.\nBase: \$url -> \$updated\n===================\n''');
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
    File(p.join(libClientDir.path, 'dartvel_runtime.dart'))
        .writeAsStringSync(runtimeDart);

    // --- Env handling: load .env files and expose PUBLIC_* keys
    final envMap = <String, String>{};
    for (final f in envFiles) {
      final m = RouteUtils.parseEnvFile(f, root);
      if (m.isNotEmpty) {
        log('dartvel: loaded env file: $f');
        envMap.addAll(m); // later files override earlier
      }
    }
    final publicEnv = <String, String>{
      for (final e in envMap.entries)
        if (e.key.startsWith('PUBLIC_')) e.key: e.value
    };

    final sbEnv = StringBuffer();
    sbEnv.writeln('// GENERATED – do not edit.');
    sbEnv.writeln('// ignore_for_file: non_constant_identifier_names');
    sbEnv.writeln('library dartvel_client_env;');
    sbEnv.writeln('');
    sbEnv.writeln('/// Environment variables provider.');
    sbEnv.writeln('class Env {');
    sbEnv.writeln('  /// Decrypts obfuscated values.');
    sbEnv.writeln(
        '  static String _d(List<int> c, int k) => String.fromCharCodes(c.map((x) => x ^ k));');
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
    File(p.join(libClientDir.path, 'env.g.dart'))
        .writeAsStringSync(sbEnv.toString());

    // Router
    final imports = ([
      "import 'package:flutter/material.dart';",
      "import 'package:go_router/go_router.dart';",
      "import 'package:dartvel_flutter/dartvel_flutter.dart';",
      ...pageImports,
      ...layoutImports,
      ...guardImports
    ]).join('\n');

    // Parse routingRedirects
    final redirects = <Map<String, String>>[];
    if (dv['routingRedirects'] is YamlList) {
      for (final r in (dv['routingRedirects'] as YamlList)) {
        if (r is YamlMap && r['from'] != null && r['to'] != null) {
          redirects
              .add({'from': r['from'].toString(), 'to': r['to'].toString()});
        }
      }
    }

    // i18n (query strategy)
    final i18n =
        dv['i18n'] is YamlMap ? dv['i18n'] as YamlMap : YamlMap.wrap({});
    final i18nParam = (i18n['param'] ?? 'lang').toString();
    final i18nDefault = (i18n['defaultLocale'] ?? '').toString();
    final i18nLocales = <String>[];
    if (i18n['locales'] is YamlList) {
      for (final v in (i18n['locales'] as YamlList)) {
        if (v != null) i18nLocales.add(v.toString());
      }
    }
    final i18nLocalesLit = i18nLocales.map((s) => "'${esc(s)}'").join(', ');

    String wrapWithLayouts(String dir, String innerExpr) {
      // Build ancestor chain from pagesDir to current dir (inclusive)
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
      // Build ancestor chain from pagesDir to dir; collect guards
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
          .map((a) =>
              '      { final r = await $a.guard(context, state); if (r != null) return r; }')
          .join('\n');
      return '\n      redirect: (context, state) async {\n$calls\n        return null;\n      },\n';
    }

    final routesSrc = pageEntries
        .map((e) => '''
    GoRoute(
      path: '${esc(e['route']!)}',
${guardRedirectFor(e['dir']!)}      pageBuilder: (context, state) {
        final params = Map<String, String>.from(state.pathParameters);
        final query  = Map<String, String>.from(state.uri.queryParameters);
        final page = const ${e['generatedWidget']}();
        final withState = DartvelRouteState(params: params, query: query, child: page);

        // i18n scope using the configured query parameter strategy.
        final i18nParam = '${esc(i18nParam)}';
        final i18nDefault = '${esc(i18nDefault)}';
        final i18nLocales = <String>[$i18nLocalesLit];
        final langRaw = query[i18nParam];
        final langTag = (i18nLocales.isEmpty && i18nDefault.isEmpty)
            ? (langRaw ?? '')
            : (DvI18n.normalize(langRaw, i18nLocales, i18nDefault.isEmpty ? (langRaw ?? '') : i18nDefault));
        final withI18n = DvI18nScope(localeTag: langTag, child: withState);

        ${e['isFunctional'] == true ? 'final loaderWrapped = withI18n;' : '''final loaderWrapped = DvDataLoader(
          load: () => page.loadData(params, query),
          child: withI18n,
${(() {
                    final la = e['loadingAlias'];
                    final ea = e['errorAlias'];
                    final lc = e['class'] != null
                        ? '${e['class']!}Loading'
                        : 'Loading';
                    final ec =
                        e['class'] != null ? '${e['class']!}Error' : 'Error';
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
          props: page.buildWebSeo(params, query),
          defaults: _defaultSeo,
          child: loaderWrapped,
        );
        final spec = ${e['isFunctional'] == true ? '_projectDefaultTransition' : '''page.transition == const PageTransitionSpec()
            ? _projectDefaultTransition
            : page.transition'''};
        final layoutWrapped = ${wrapWithLayouts(e['dir']!, 'seoWrapped')};
        final pageShellWrapped = DVPageShell(
          spec: page.pageScaffold,
          child: layoutWrapped,
        );
        return dvTransitionPage(
          key: state.pageKey,
          child: pageShellWrapped,
          spec: spec,
        );
      },
    )
  ''')
        .join(',\n');

    final generatedPageWidgets = pageEntries
        .map((e) => '''
/// Deferred generated widget wrapper for [p${e['i']}.${e['class']}].
class ${e['generatedWidget']} extends DartvelPage {
  const ${e['generatedWidget']}({super.key});

  static Future<void>? _libraryFuture;

  static Future<void> loadLibrary() {
    return _libraryFuture ??= p${e['i']}.loadLibrary();
  }

  @override
  DVPageScaffoldSpec get pageScaffold => ${e['pageScaffold']};

${e['isFunctional'] == true ? '''  @override
  Future<Object?> loadData(
    Map<String, String> params,
    Map<String, String> query,
  ) async {
    await loadLibrary();
    return null;
  }
''' : '''  @override
  Future<Object?> loadData(
    Map<String, String> params,
    Map<String, String> query,
  ) async {
    await loadLibrary();
    return p${e['i']}.${e['class']}().loadData(params, query);
  }

  @override
  PageTransitionSpec get transition => const PageTransitionSpec();
'''}
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: loadLibrary(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const DvDefaultError();
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const DvDefaultLoading();
        }
        return ${e['isFunctional'] == true ? 'p${e['i']}.${e['class']}(context)' : 'p${e['i']}.${e['class']}()'};
      },
    );
  }
}
''')
        .join('\n');

    // Global redirect builder from routingRedirects + normalization
    final sbRedirect = StringBuffer();
    sbRedirect.writeln(
        'String? _globalRedirect(BuildContext context, GoRouterState state) {');
    sbRedirect.writeln('  final path = state.uri.path;');
    if (notFoundRedirect.isNotEmpty) {
      sbRedirect.writeln(
          "  if (state.error != null) return '${esc(notFoundRedirect)}';");
    }
    if (normalizeTrailing) {
      sbRedirect.writeln("  if (path.length > 1 && path.endsWith('/')) {");
      sbRedirect.writeln(
          '    final newUri = state.uri.replace(path: path.substring(0, path.length - 1));');
      sbRedirect.writeln('    return newUri.toString();');
      sbRedirect.writeln('  }');
    }
    if (redirects.isNotEmpty) {
      for (final r in redirects) {
        final from = r['from']!;
        final to = r['to']!;
        final regex = RouteUtils.patternToRegex(from);
        sbRedirect.writeln('  { final re = RegExp(r"$regex");');
        sbRedirect.writeln('  final m = re.firstMatch(path);');
        sbRedirect.writeln('  if (m != null) {');
        final toEsc = to.replaceAll('"', '\\"');
        sbRedirect.writeln(
            '    final newPath = "$toEsc".replaceAllMapped(RegExp(r":([a-zA-Z0-9_]+)"), (mm) => m.namedGroup(mm.group(1)!) ?? "");');
        sbRedirect
            .writeln('    final newUri = state.uri.replace(path: newPath);');
        sbRedirect.writeln('    return newUri.toString();');
        sbRedirect.writeln('  } }');
      }
    }
    sbRedirect.writeln('  return null;');
    sbRedirect.writeln('}');

    final router = '''
// GENERATED – do not edit.
// ignore_for_file: unnecessary_import
$imports

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

$generatedPageWidgets

/// Creates the GoRouter instance for Dartvel routing.
GoRouter createDartvelRouter() => GoRouter(
  routes: [
$routesSrc
  ],
  redirect: _globalRedirect,
);

${(() {
      final sbRoutes = StringBuffer();
      sbRoutes.writeln(
          '/// Strongly typed route targets for type-safe navigation.');
      sbRoutes.writeln('class DVRoutes {');
      for (final e in pageEntries) {
        final routePath = e['route'] as String;
        final cleanPath = routePath.replaceAll(RegExp(r'/:[A-Za-z0-9_]+'), '');
        var name = cleanPath.replaceAll('/', '').trim();
        if (name.isEmpty) {
          name = 'index';
        }

        final paramRegex = RegExp(r':([A-Za-z0-9_]+)');
        final params =
            paramRegex.allMatches(routePath).map((m) => m.group(1)!).toList();

        if (params.isEmpty) {
          sbRoutes
              .writeln("  static const $name = DVRouteTarget('$routePath');");
        } else {
          final funcParams = params.map((p) => "required String $p").join(', ');
          var interpPath = routePath;
          for (final p in params) {
            interpPath = interpPath.replaceFirst(':$p', '\$$p');
          }
          sbRoutes.writeln(
              "  static DVRouteTarget $name({$funcParams}) => DVRouteTarget('$interpPath');");
        }
      }
      sbRoutes.writeln('}');
      return sbRoutes.toString();
    })()}
''';
    File(p.join(libClientDir.path, 'router.g.dart'))
        .writeAsStringSync('// BUILD: $buildId\n$router');

    _generateFunctionalWidgets(
      root: root,
      pkgName: pkgName,
      outputFile: File(p.join(libClientDir.path, 'widgets.g.dart')),
    );

    // Generate config.g.dart matching pubspec.yaml configuration keys
    final dbMap = dv['database'] is YamlMap
        ? dv['database'] as YamlMap
        : YamlMap.wrap({});
    final dbProvider = (dbMap['provider'] ?? 'sqlite').toString();
    final dbPath = (dbMap['path'] ?? 'dartvel.db').toString();

    final storageMap =
        dv['storage'] is YamlMap ? dv['storage'] as YamlMap : YamlMap.wrap({});
    final storageProvider = (storageMap['provider'] ?? 'local').toString();

    final authMap =
        dv['auth'] is YamlMap ? dv['auth'] as YamlMap : YamlMap.wrap({});
    final authProviders = <String>[];
    if (authMap['providers'] is YamlList) {
      for (final p in (authMap['providers'] as YamlList)) {
        if (p != null) authProviders.add("'$p'");
      }
    } else {
      authProviders.add("'email'");
    }

    final aiMap = dv['ai'] is YamlMap ? dv['ai'] as YamlMap : YamlMap.wrap({});
    final aiProvider = (aiMap['provider'] ?? 'gemini').toString();

    final mtMap = dv['multiTenancy'] is YamlMap
        ? dv['multiTenancy'] as YamlMap
        : YamlMap.wrap({});
    final mtEnabled = asBool(mtMap['enabled'], false);

    final pwaMap =
        dv['pwa'] is YamlMap ? dv['pwa'] as YamlMap : YamlMap.wrap({});
    final pwaEnabled = asBool(pwaMap['enabled'], true);

    final permissionsList = <String>[];
    if (dv['permissions'] is YamlList) {
      for (final p in (dv['permissions'] as YamlList)) {
        if (p != null) permissionsList.add("'$p'");
      }
    }

    final configContent = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// Build ID: $buildId

/// Centrally generated Dartvel configuration matching your pubspec.yaml.
class DartvelConfig {
  /// The database provider (e.g. sqlite, postgres, mysql).
  static const databaseProvider = '$dbProvider';
  
  /// The path to database file (if sqlite).
  static const databasePath = '$dbPath';
  
  /// The storage provider (e.g. local, s3, r2).
  static const storageProvider = '$storageProvider';
  
  /// The list of active authentication providers.
  static const authProviders = <String>[${authProviders.join(', ')}];
  
  /// The primary AI model provider.
  static const aiProvider = '$aiProvider';
  
  /// Whether multi-tenancy is active.
  static const multiTenancyEnabled = $mtEnabled;
  
  /// Whether PWA manifest & worker are enabled.
  static const pwaEnabled = $pwaEnabled;
  
  /// List of platform permissions requested.
  static const permissions = <String>[${permissionsList.join(', ')}];
}
''';

    File(p.join(libClientDir.path, 'config.g.dart'))
        .writeAsStringSync(configContent);

    _generateSsgBuilder(pageEntries, pageImports, root);
  }

  static void _generateSsgBuilder(
      List<Map<String, dynamic>> entries, List<String> imports, String root) {
    final sb = StringBuffer();
    sb.writeln('// GENERATED – do not edit.');
    sb.writeln('import \'dart:convert\';');
    sb.writeln('import \'dart:io\';');
    sb.writeln('import \'package:dartvel_flutter/dartvel_flutter.dart\';');

    sb.writeln(imports.join('\n'));

    sb.writeln('void main() async {');
    sb.writeln("  final outDir = Directory('build/web/_ssg');");
    sb.writeln(
        '  if (!outDir.existsSync()) outDir.createSync(recursive: true);');
    sb.writeln("  stdout.writeln('Generating SSG data...');");

    for (final e in entries) {
      final i = e['i']!;
      final className = e['class']!;
      final routePath = e['route']!;
      final prefix = 'p$i';
      final isDynamic = routePath.contains(':');

      sb.writeln('  // $routePath');
      if (e['isFunctional'] == true) {
        sb.writeln('  // Skipped functional widget page: $routePath');
        continue;
      }
      sb.writeln('  try {');
      sb.writeln('    final page = const $prefix.$className();');

      if (isDynamic) {
        sb.writeln('    final paths = await page.staticPaths;');
        sb.writeln('    for (final params in paths) {');
        sb.writeln('      final data = await page.loadData(params, {});');
        sb.writeln('      if (data != null) {');
        sb.writeln('        var key = "$routePath";');
        sb.writeln(
            '        params.forEach((k, v) => key = key.replaceAll(":\$k", v));');
        sb.writeln('        final bytes = utf8.encode(key);');
        sb.writeln('        final filename = base64Url.encode(bytes);');
        sb.writeln(
            '        File("\${outDir.path}/\$filename.json").writeAsStringSync(jsonEncode(data));');
        sb.writeln('      }');
        sb.writeln('    }');
      } else {
        sb.writeln('    final data = await page.loadData({}, {});');
        sb.writeln('    if (data != null) {');
        sb.writeln('      final key = "$routePath";');
        sb.writeln('      final bytes = utf8.encode(key);');
        sb.writeln('      final filename = base64Url.encode(bytes);');
        sb.writeln(
            '      File("\${outDir.path}/\$filename.json").writeAsStringSync(jsonEncode(data));');
        sb.writeln('    }');
      }
      sb.writeln('  } catch (e) {');
      // Keep SSG page errors non-fatal; page-specific diagnostics can be added here.
      sb.writeln('  }');
    }
    sb.writeln("  stdout.writeln('SSG generation complete.');");
    sb.writeln('}');

    final ssgFile = File(p.join(root, '.dartvel', 'ssg_builder.dart'));
    if (!ssgFile.parent.existsSync()) {
      ssgFile.parent.createSync(recursive: true);
    }
    ssgFile.writeAsStringSync(sb.toString());
  }

  static String _generatedPageWidgetName(String functionName) {
    final words = RegExp(r'[A-Za-z0-9]+')
        .allMatches(functionName)
        .map((match) => match.group(0)!)
        .where((word) => word.isNotEmpty)
        .toList();
    final pascalName =
        words.map((word) => word[0].toUpperCase() + word.substring(1)).join();
    final baseName = pascalName.isEmpty ? 'Generated' : pascalName;
    return '${baseName}GeneratedPage';
  }

  static String _pageScaffoldSpec(String source) {
    final match =
        RegExp(r'@DVPage\(([^)]*)\)', dotAll: true).firstMatch(source);
    if (match == null) {
      return _sourceBuildsScaffold(source)
          ? 'const DVPageScaffoldSpec(scaffold: false)'
          : 'const DVPageScaffoldSpec()';
    }

    final args = match.group(1) ?? '';
    final fields = <String>[];

    final title = _namedStringArg(args, 'title');
    if (title != null) fields.add('title: $title');

    final shell = _namedEnumArg(args, 'shell', 'DVPageShellMode');
    if (shell != null) fields.add('shell: $shell');

    for (final name in [
      'scaffold',
      'showAppBar',
      'safeArea',
      'centerTitle',
      'extendBody',
      'resizeToAvoidBottomInset',
    ]) {
      final value = _namedBoolArg(args, name);
      if (value != null) fields.add('$name: $value');
    }
    if (_sourceBuildsScaffold(source) &&
        _namedBoolArg(args, 'scaffold') == null) {
      fields.add('scaffold: false');
    }

    for (final name in ['backgroundColor', 'appBarBackgroundColor']) {
      final value = _namedIntArg(args, name);
      if (value != null) fields.add('$name: $value');
    }

    if (fields.isEmpty) return 'const DVPageScaffoldSpec()';
    return 'const DVPageScaffoldSpec(${fields.join(', ')})';
  }

  static bool _sourceBuildsScaffold(String source) {
    return RegExp(r'\b(?:Scaffold|CupertinoPageScaffold)\s*\(')
        .hasMatch(source);
  }

  static String? _namedStringArg(String args, String name) {
    final match = RegExp(
      '$name\\s*:\\s*((?:r)?(?:\'[^\']*\'|"[^"]*"))',
      dotAll: true,
    ).firstMatch(args);
    return match?.group(1);
  }

  static String? _namedEnumArg(String args, String name, String enumName) {
    final match = RegExp('$name\\s*:\\s*($enumName\\.[A-Za-z_][A-Za-z0-9_]*)')
        .firstMatch(args);
    return match?.group(1);
  }

  static String? _namedBoolArg(String args, String name) {
    final match = RegExp('$name\\s*:\\s*(true|false)').firstMatch(args);
    return match?.group(1);
  }

  static String? _namedIntArg(String args, String name) {
    final match =
        RegExp('$name\\s*:\\s*(0x[0-9A-Fa-f]+|[0-9]+)').firstMatch(args);
    return match?.group(1);
  }

  static void _generateFunctionalWidgets({
    required String root,
    required String pkgName,
    required File outputFile,
  }) {
    final libDir = Directory(p.join(root, 'lib'));
    final entries = <_FunctionalWidgetEntry>[];
    if (libDir.existsSync()) {
      final files = libDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) =>
              !file.path.contains('${p.separator}dartvel_client${p.separator}'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final source = file.readAsStringSync();
        if (!source.contains('@DVFunctionalWidget()')) continue;
        if (source.contains('@DVPage()')) continue;
        final rel = p.relative(file.path, from: root).replaceAll('\\', '/');
        final importPath =
            rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
        entries.addAll(_functionalWidgetsInSource(source, importPath, rel));
      }
    }

    _validateFunctionalWidgetNames(entries);

    final imports = <String>[
      "import 'dart:async';",
      "import 'package:flutter/material.dart';",
      "import 'package:dartvel_flutter/dartvel_flutter.dart';",
    ];
    final importAliases = <String, String>{};
    for (final entry in entries) {
      importAliases.putIfAbsent(
          entry.importPath, () => 'w${importAliases.length}');
    }
    for (final item in importAliases.entries) {
      imports.add("import '${item.key}' as ${item.value};");
    }
    for (int i = 0; i < entries.length; i++) {
      entries[i] =
          entries[i].copyWith(alias: importAliases[entries[i].importPath]!);
    }

    final buffer = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      ..writeln(
          '// ignore_for_file: non_constant_identifier_names, unused_import')
      ..writeln('library dartvel_client_widgets;')
      ..writeln()
      ..writeln(imports.join('\n'))
      ..writeln();

    for (final entry in entries) {
      buffer
        ..writeln('Widget ${entry.generatedName}(${entry.parameters}) {')
        ..writeln(
            '  return ${entry.alias}.${entry.sourceName}(${entry.argumentList});')
        ..writeln('}')
        ..writeln();
    }

    outputFile.writeAsStringSync(buffer.toString());
  }

  static List<_FunctionalWidgetEntry> _functionalWidgetsInSource(
    String source,
    String importPath,
    String sourcePath,
  ) {
    final entries = <_FunctionalWidgetEntry>[];
    int cursor = 0;
    while (true) {
      final annotation = source.indexOf('@DVFunctionalWidget()', cursor);
      if (annotation == -1) break;
      final widgetToken = source.indexOf('Widget', annotation);
      if (widgetToken == -1) break;
      final nameMatch = RegExp(r'Widget\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(')
          .firstMatch(source.substring(widgetToken));
      if (nameMatch == null) {
        cursor = widgetToken + 'Widget'.length;
        continue;
      }
      final sourceName = nameMatch.group(1)!;
      if (sourceName.startsWith('_')) {
        cursor = widgetToken + nameMatch.end;
        continue;
      }
      final openParen = widgetToken + nameMatch.end - 1;
      final closeParen = _matchingParen(source, openParen);
      if (closeParen == -1) {
        cursor = openParen + 1;
        continue;
      }
      final parameters = source.substring(openParen + 1, closeParen).trim();
      entries.add(_FunctionalWidgetEntry(
        importPath: importPath,
        sourcePath: sourcePath,
        alias: '',
        sourceName: sourceName,
        generatedName: _generatedWidgetName(sourceName),
        parameters: parameters,
        argumentList: _argumentList(parameters),
      ));
      cursor = closeParen + 1;
    }
    return entries;
  }

  static void _validateFunctionalWidgetNames(
    List<_FunctionalWidgetEntry> entries,
  ) {
    final byGeneratedName = <String, List<_FunctionalWidgetEntry>>{};
    for (final entry in entries) {
      byGeneratedName
          .putIfAbsent(entry.generatedName, () => <_FunctionalWidgetEntry>[])
          .add(entry);
    }

    final conflicts = byGeneratedName.entries
        .where((entry) => entry.value.length > 1)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (conflicts.isEmpty) return;

    stderr.writeln('ERROR: Duplicate generated Dartvel widget names found.');
    stderr.writeln(
        'Each @DVFunctionalWidget function must generate a unique global widget name.');
    for (final conflict in conflicts) {
      stderr.writeln('  ${conflict.key} is generated by:');
      final sources = conflict.value.toList()
        ..sort((a, b) => a.sourcePath.compareTo(b.sourcePath));
      for (final source in sources) {
        stderr.writeln('    - ${source.sourcePath}: ${source.sourceName}()');
      }
    }
    stderr.writeln(
        'Rename the annotated functions so their generated PascalCase widget names are unique.');
    exit(42);
  }

  static int _matchingParen(String source, int openParen) {
    int depth = 0;
    for (int index = openParen; index < source.length; index++) {
      final char = source[index];
      if (char == '(') depth++;
      if (char == ')') {
        depth--;
        if (depth == 0) return index;
      }
    }
    return -1;
  }

  static String _argumentList(String parameters) {
    if (parameters.trim().isEmpty) return '';
    return _splitTopLevel(parameters).map(_parameterName).join(', ');
  }

  static List<String> _splitTopLevel(String value) {
    final parts = <String>[];
    final current = StringBuffer();
    int angleDepth = 0;
    int parenDepth = 0;
    for (int index = 0; index < value.length; index++) {
      final char = value[index];
      if (char == '<') angleDepth++;
      if (char == '>') angleDepth--;
      if (char == '(') parenDepth++;
      if (char == ')') parenDepth--;
      if (char == ',' && angleDepth == 0 && parenDepth == 0) {
        parts.add(current.toString().trim());
        current.clear();
      } else {
        current.write(char);
      }
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  static String _parameterName(String parameter) {
    final cleaned = parameter
        .replaceAll('required ', '')
        .replaceAll('covariant ', '')
        .replaceAll(RegExp(r'=.*$'), '')
        .trim();
    final match = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(cleaned);
    return match?.group(1) ?? cleaned;
  }

  static String _generatedWidgetName(String functionName) {
    final stripped =
        functionName.startsWith('_') ? functionName.substring(1) : functionName;
    final words = RegExp(r'[A-Za-z0-9]+')
        .allMatches(stripped)
        .map((match) => match.group(0)!)
        .where((word) => word.isNotEmpty)
        .toList();
    return words
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join();
  }
}

class _FunctionalWidgetEntry {
  final String importPath;
  final String sourcePath;
  final String alias;
  final String sourceName;
  final String generatedName;
  final String parameters;
  final String argumentList;

  const _FunctionalWidgetEntry({
    required this.importPath,
    required this.sourcePath,
    required this.alias,
    required this.sourceName,
    required this.generatedName,
    required this.parameters,
    required this.argumentList,
  });

  _FunctionalWidgetEntry copyWith({required String alias}) {
    return _FunctionalWidgetEntry(
      importPath: importPath,
      sourcePath: sourcePath,
      alias: alias,
      sourceName: sourceName,
      generatedName: generatedName,
      parameters: parameters,
      argumentList: argumentList,
    );
  }
}
