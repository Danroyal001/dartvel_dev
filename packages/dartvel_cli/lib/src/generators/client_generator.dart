import 'dart:convert';
import 'dart:io';

import 'function_body.dart';
import 'symbol_qualifier.dart';
import 'static_paths_generator.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../build/page_text.dart';

import '../utils/helpers.dart';
import '../utils/logger.dart';
import 'route_utils.dart';

/// Every `_layout.dart` under [pagesDir].
///
/// Extracted so discovery is testable on its own. It had no test until a
/// glob pattern was briefly turned into a literal string by an escaping slip
/// and nothing matched — the whole suite still passed, because a generator
/// that finds nothing does not fail. It emits a smaller file and the
/// application quietly loses its layouts.
List<File> discoverLayouts({required String root, required String pagesDir}) =>
    _discover(root: root, pagesDir: pagesDir, basename: '_layout.dart');

/// Every `_guard.dart` under [pagesDir]. See [discoverLayouts].
List<File> discoverGuards({required String root, required String pagesDir}) =>
    _discover(root: root, pagesDir: pagesDir, basename: '_guard.dart');

List<File> _discover({
  required String root,
  required String pagesDir,
  required String basename,
}) {
  final found = <File>[];

  // `**/` requires at least one directory, so the file directly in pagesDir
  // is not matched by it and has to be looked up by name. Layout discovery
  // already did this; guard discovery did not, so a root `_guard.dart` —
  // authorisation for the whole application — was silently ignored.
  final rootFile = File(p.join(root, pagesDir, basename));
  if (rootFile.existsSync()) found.add(rootFile);

  // Always '/': a glob separator is not a host path separator, and a
  // backslash is glob's escape character.
  for (final entity in Glob('$pagesDir/**/$basename').listFileSystemSync(
    const LocalFileSystem(),
    root: root,
    followLinks: false,
  )) {
    final file = File(entity.path);
    if (file.existsSync()) found.add(file);
  }

  // Deduplicated by absolute path, not trusted to be distinct.
  //
  // The root file is added by name above because `**/` is supposed to require
  // at least one directory. That held here and did not hold on CI, where the
  // same `_guard.dart` came back twice -- and a duplicated guard runs twice
  // while a duplicated layout wraps the page twice. Whichever way the glob
  // behaves, a file discovered once is the invariant.
  final Map<String, File> unique = <String, File>{
    for (final File file in found) p.canonicalize(file.absolute.path): file,
  };
  final List<File> result = unique.values.toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  return result;
}

class ClientGenerator {
  static Future<void> generate({
    required String root,
    required String pagesDir,
    required String pkgName,
    required String buildId,
    /// Models whose pages Dartvel generates, so the router can serve them.
    List<StaticPathsProvider> publicPageModels = const <StaticPathsProvider>[],
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
    for (final e in pageGlob.listFileSystemSync(
      fs,
      root: root,
      followLinks: false,
    )) {
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
    // pagesDir is already a posix-style path; joining with the host
    // separator would break the pattern on Windows.
    final layoutGlob = Glob('$pagesDir/**/_layout.dart');
    final layoutFiles = <File>[];
    for (final e in layoutGlob.listFileSystemSync(
      fs,
      root: root,
      followLinks: false,
    )) {
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
    final pageEntries = <_PageEntry>[];
    final layoutImports = <String>[];
    final layoutMapByDir = <String, Map<String, String>>{}; // dir -> {i, class}

    for (var i = 0; i < pageFiles.length; i++) {
      final abs = pageFiles[i].path;
      final rel = p.relative(abs, from: root).replaceAll('\\', '/');
      final importPath = rel.replaceFirst(
        RegExp(r'^lib/'),
        'package:$pkgName/',
      );
      // Parse class name by scanning file for a page class or functional widget.
      final src = await File(abs).readAsString();
      final hasPageAnnotation = src.contains('@DVPage');
      final isLegacyPageFile = rel.endsWith('.page.dart');
      if (!hasPageAnnotation && !isLegacyPageFile) {
        continue;
      }
      final m = RegExp(
        r'(?:@DVPage\([^)]*\)\s*)?(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+(DartvelPage|DVClassWidget)',
      ).firstMatch(src);
      String className;
      String publicName;
      bool isFunctional = false;
      String? pageExpressionBody;
      DVFunctionBody? pageBody;
      Set<String> pageSourceSymbols = const <String>{};
      if (m != null) {
        className = m.group(1)!;
        if (className.startsWith('_')) {
          throw StateError(
            'Dartvel private class page input $className in $rel requires '
            'generated class body lowering before it can be emitted without '
            'per-source part files. Use a private expression-bodied @DVPage '
            'function for this generator pass.',
          );
        }
        publicName = className;
      } else {
        final mf = RegExp(
          r'@DVPage\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*(?:@DVFunctionalWidget\(\)\s*)?Widget\s+([A-Za-z_][A-Za-z0-9_]*)\(',
        ).firstMatch(src);
        if (mf == null) {
          stderr.writeln(
            'dartvel: could not find class extending DartvelPage/DVClassWidget or @DVPage function in $rel',
          );
          continue;
        }
        className = mf.group(1)!;
        if (className.startsWith('_')) {
          final openParen = mf.end - 1;
          final closeParen = _matchingParen(src, openParen);
          if (closeParen == -1) {
            throw StateError(
              'Dartvel private page input $className in $rel has an invalid '
              'parameter list.',
            );
          }
          final DVFunctionBody? body = dvFunctionBodyAfter(src, closeParen);
          if (body == null) {
            throw StateError(
              'Dartvel private page input $className in $rel has no body. A '
              'page is a function that returns a widget, either '
              'Widget $className(...) => DVBox(...) or with a block.',
            );
          }
          pageBody = body;
          pageExpressionBody = body.expression;
          pageSourceSymbols = _topLevelSourceSymbols(src);
        }
        publicName =
            className.startsWith('_') ? className.substring(1) : className;
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
        final importPathL = loadingRel.replaceFirst(
          RegExp(r'^lib/'),
          'package:$pkgName/',
        );
        loadingAlias = 'pl$i';
        pageImports.add("import '$importPathL' as $loadingAlias;");
      }
      if (!isFunctional && File(p.join(root, errorRel)).existsSync()) {
        final importPathE = errorRel.replaceFirst(
          RegExp(r'^lib/'),
          'package:$pkgName/',
        );
        errorAlias = 'pe$i';
        pageImports.add("import '$importPathE' as $errorAlias;");
      }

      pageEntries.add(
        _PageEntry(
          importIndex: '$i',
          className: className,
          publicName: publicName,
          generatedWidget: _generatedPageWidgetName(className),
          pageScaffold: _pageScaffoldSpec(src),
          route: route,
          directory: dir,
          isFunctional: isFunctional,
          expressionBody: pageExpressionBody,
          body: pageBody,
          sourceSymbols: pageSourceSymbols,
          // From the source this loop already holds. Guessing a filename from
          // the route name got /docs wrong and /cloud not at all, and would
          // have been lost on the next rebuild.
          text: dvPageText(src),
          loadingAlias: loadingAlias,
          errorAlias: errorAlias,
        ),
      );
    }

    // Import all layouts and build map by directory
    for (var j = 0; j < layoutFiles.length; j++) {
      final abs = layoutFiles[j].path;
      final rel = p.relative(abs, from: root).replaceAll('\\', '/');
      final importPath = rel.replaceFirst(
        RegExp(r'^lib/'),
        'package:$pkgName/',
      );
      final src = await File(abs).readAsString();
      final m = RegExp(
        r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+DartvelLayout',
      ).firstMatch(src);
      if (m == null) {
        stderr.writeln(
          'dartvel: could not find a class extending DartvelLayout in $rel',
        );
        continue;
      }
      final className = m.group(1)!;
      final alias = 'l$j';
      layoutImports.add("import '$importPath' as $alias;");
      final dir = p.dirname(rel).replaceAll('\\', '/');
      layoutMapByDir[dir] = {'i': '$j', 'class': className};
    }

    // Detect route conflicts (same computed route from multiple files)
    final routeToEntries = <String, List<_PageEntry>>{};
    for (final e in pageEntries) {
      routeToEntries.putIfAbsent(e.route, () => <_PageEntry>[]).add(e);
    }
    final conflicts = routeToEntries.entries.where((kv) => kv.value.length > 1);
    if (conflicts.isNotEmpty) {
      stderr.writeln('ERROR: Detected route conflicts:');
      for (final c in conflicts) {
        stderr.writeln('  Route "${c.key}" generated by:');
        for (final e in c.value) {
          // Best-effort: rebuild approximate file path from import alias index
          final alias = 'p${e.importIndex}';
          // Search from pageImports for matching alias
          try {
            final line = pageImports.firstWhere(
              (l) => l.contains(' as $alias;'),
            );
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
    final guardGlob = Glob('$pagesDir/**/_guard.dart');
    for (final e in guardGlob.listFileSystemSync(
      fs,
      root: root,
      followLinks: false,
    )) {
      final ioFile = File(e.path);
      if (!ioFile.existsSync()) continue;
      final rel = p.relative(ioFile.path, from: root).replaceAll('\\', '/');
      final importPath = rel.replaceFirst(
        RegExp(r'^lib/'),
        'package:$pkgName/',
      );
      final alias = 'g${guardImports.length}';
      guardImports.add("import '$importPath' as $alias;");
      final dir = p.dirname(rel).replaceAll('\\', '/');
      guardMapByDir[dir] = alias;
    }

    // Ensure dirs
    // Ensure dirs
    Directory(p.join(root, '.dart_tool')).createSync();
    if (pageEntries.isEmpty) {
      log(
        'dartvel: no pages found under "$pagesDir" (looking for @DVPage() pages or legacy **/*.page.dart)',
      );
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
export 'ai_tools.g.dart';
export 'functions.g.dart';
export 'jobs.g.dart';
export 'models.g.dart';
export 'openapi.g.dart';
export 'router.g.dart';
export 'schedules.g.dart';
// The static-path manifest. It was generated and never exported, so the
// enumeration of a model's public pages was unreachable through the one
// import application code is told to use -- and unreachable to the build that
// has to know which pages to write.
export 'static_paths.g.dart';
export 'widgets.g.dart';
''');

    // Mirror config too for analyzer friendliness
    File(p.join(libClientDir.path, 'dartvel_config.g.dart')).writeAsStringSync(
      '''
// GENERATED – do not edit.
library dartvel_client_config;
const String dvBackendBindHost = '${esc(backendHost)}';
const int    dvBackendPort      = $backendPort;
const String dvDevBackendHost   = '${esc(devBackendHost)}';
const String dvProdBackendHost  = '${esc(prodBackendHost)}';
const String dvApiBasePath      = '${esc(apiBasePath)}';
''',
    );

    // Client runtime helper
    final runtimeDart = """
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kReleaseMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:dartvel_flutter/dartvel_flutter.dart' show DV, DVPageStore;
import 'dartvel_config.g.dart' as cfg;
import 'jobs.g.dart' show registerDartvelJobs;
import 'models.g.dart' show registerDartvelModels;

/// Wires the generated runtime into the short `DV.baseUrl` / `DV.api(...)` API.
/// Called automatically during app/router initialization.
void configureDartvelRuntime() {
  DV.registerRuntime(
    baseUrl: () => DartvelRuntime.baseUrl,
    apiBasePath: () => DartvelRuntime.apiBasePath,
    api: DartvelRuntime.api,
  );
  // A dispatched job is useless without its codec and handler, so they are
  // registered as part of configuring the runtime rather than left to the
  // application to remember.
  registerDartvelJobs();
  registerDartvelModels();
  // Reads stored Studio documents into memory so an override resolves during
  // navigation instead of flashing the compiled page first.
  unawaited(DVPageStore.prime());
}

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
    File(
      p.join(libClientDir.path, 'dartvel_runtime.dart'),
    ).writeAsStringSync(runtimeDart);

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
        if (e.key.startsWith('PUBLIC_')) e.key: e.value,
    };

    final sbEnv = StringBuffer();
    sbEnv.writeln('// GENERATED – do not edit.');
    sbEnv.writeln(
      '// ignore_for_file: non_constant_identifier_names, unused_element',
    );
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
    File(
      p.join(libClientDir.path, 'env.g.dart'),
    ).writeAsStringSync(sbEnv.toString());

    // Router
    final imports = ([
      "import 'dart:async';",
      "import 'package:flutter/material.dart';",
      "import 'package:go_router/go_router.dart';",
      "import 'package:dartvel_flutter/dartvel_flutter.dart';",
      "import 'config.g.dart';",
      "import 'dartvel_config.g.dart';",
      "import 'dartvel_runtime.dart';",
      "import 'env.g.dart';",
      "import 'functions.g.dart';",
      "import 'models.g.dart';",
      "import 'widgets.g.dart';",
      ...pageImports,
      ...layoutImports,
      ...guardImports,
    ]).join('\n');

    // Parse routingRedirects
    final redirects = <Map<String, String>>[];
    if (dv['routingRedirects'] is YamlList) {
      for (final r in (dv['routingRedirects'] as YamlList)) {
        if (r is YamlMap && r['from'] != null && r['to'] != null) {
          redirects.add({
            'from': r['from'].toString(),
            'to': r['to'].toString(),
          });
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
        final parent = p.dirname(cur).replaceAll(r'\', '/');
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
        final parent = p.dirname(cur).replaceAll(r'\', '/');
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

    // A route per model that asked Dartvel to generate its pages. Without
    // these, generatePublicPages produced a list of paths and nothing that
    // served them, so every generated page rendered the application's own
    // not-found screen.
    final modelRoutesSrc = publicPageModels
        .map(
          (m) => '''
    GoRoute(
      path: '${m.route}',
      pageBuilder: (context, state) => NoTransitionPage<void>(
        child: ${m.className}.publicPage(
          state.pathParameters['${m.param}'] ?? '',
        ),
      ),
    ),''',
        )
        .join('\n');

    // Prefixed with a separator when there are page routes before it. The
    // page entries are joined without a trailing comma, so appending a route
    // straight after the last one produces "),\n    GoRoute(" without the
    // comma -- a syntax error in generated code, which is the worst place for
    // one because nobody reads it until the compiler complains.
    final modelRoutes =
        modelRoutesSrc.isEmpty ? '' : ',\n$modelRoutesSrc';

    final routesSrc = pageEntries
        .map(
          (e) => '''
    GoRoute(
      path: '${esc(e.route)}',
${guardRedirectFor(e.directory)}      pageBuilder: (context, state) {
        final params = Map<String, String>.from(state.pathParameters);
        final query  = Map<String, String>.from(state.uri.queryParameters);
        final page = const ${e.generatedWidget}();
        // A stored Studio document overrides this compiled page: the
        // compiled one is the entrypoint the app shipped with, and the
        // editor has to be able to change it.
        final overridable = DVStudioPageRoute(
          '${esc(e.route)}',
          fallback: page,
        );
        final withState = DartvelRouteState(params: params, query: query, child: overridable);

        // i18n scope using the configured query parameter strategy.
        final i18nParam = '${esc(i18nParam)}';
        final i18nDefault = '${esc(i18nDefault)}';
        final i18nLocales = <String>[$i18nLocalesLit];
        final langRaw = query[i18nParam];
        final langTag = (i18nLocales.isEmpty && i18nDefault.isEmpty)
            ? (langRaw ?? '')
            : (DvI18n.normalize(langRaw, i18nLocales, i18nDefault.isEmpty ? (langRaw ?? '') : i18nDefault));
        final withI18n = DvI18nScope(localeTag: langTag, child: withState);

        final loaderWrapped = DvDataLoader(
          load: () => page.loadData(params, query),
          child: withI18n,
${(() {
            final la = e.loadingAlias;
            final ea = e.errorAlias;
            final lc = '${e.className}Loading';
            final ec = '${e.className}Error';
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
          })()}        );

        final seoWrapped = DartvelSeo(
          // The title the page declared, underneath whatever its own
          // buildWebSeo returns. dvStaticPage already writes that title into
          // the prerendered index.html, so a crawler saw it and a person did
          // not: Flutter boots, DartvelSeo applies SeoProps.empty, and the
          // project default overwrites the route's own title in the tab.
          //
          // Taken from the scaffold spec rather than pasted in as a literal,
          // so one declaration feeds the app bar, the static file and this.
          props: SeoProps(title: page.pageScaffold.title)
              .merge(page.buildWebSeo(params, query)),
          defaults: _defaultSeo,
          child: loaderWrapped,
        );
        final spec = ${e.isFunctional ? '_projectDefaultTransition' : '''page.transition == const PageTransitionSpec()
            ? _projectDefaultTransition
            : page.transition'''};
        final layoutWrapped = ${wrapWithLayouts(e.directory, 'seoWrapped')};
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
  ''',
        )
        .join(',\n');

    // What each route can fetch and show before you go there. DVNavLink
    // cannot know how to build a route; the router does, so it says.
    // Semantics from the start, not when Flutter guesses a screen reader is
    // present. On by default, because two things depend on it and both are
    // broken without it: the browser has no elements to focus, so the first
    // Tab is spent entering the canvas and every stop after is off by one;
    // and a screen reader only works once the tree exists, which Flutter
    // otherwise decides by detection rather than by being told.
    //
    // `dartvel: semantics: false` turns it off, for an app that has measured
    // the tree costing more than it is worth.
    final semanticsSetting = _dartvelSemantics(root);
    final semanticsEnabled = semanticsSetting is bool
        ? semanticsSetting
        : (semanticsSetting is YamlMap
            ? (semanticsSetting['enabled'] as bool? ?? true)
            : true);
    final semanticsCall = semanticsEnabled
        ? '  dvEnsureSemantics();'
        : '  // Semantics off: dartvel.semantics is false in pubspec.yaml.';

    // The text each route's page contains, taken from the source this
    // generator already has in hand. The build used to guess the file from
    // the route name and get it wrong: /docs picked up a code sample and
    // /cloud found nothing, because a route name is not a filename and a
    // rebuild would lose whatever was patched in by hand.
    final routeText = <String, List<String>>{};
    for (final e in pageEntries) {
      if (e.text.isEmpty) continue;
      routeText.putIfAbsent(e.route, () => e.text);
    }
    // Written on every generation, and generation runs as part of every
    // build, so it cannot go stale behind a rebuild.
    File(p.join(root, '.dart_tool', 'dartvel_route_text.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(routeText));

    final routeCapabilities = pageEntries
        .map((e) {
          final widgetName = _generatedPageWidgetName(e.publicName);
          return '''
  DVRoutePreloaders.register(
    '${esc(e.route)}',
    $widgetName.loadLibrary,
  );
  DVRoutePreviews.register(
    '${esc(e.route)}',
    (BuildContext context) => const $widgetName(),
  );''';
        })
        .toSet()
        .join('\n');

    final generatedPageWidgets = pageEntries.map((e) {
      final DVFunctionBody? pageBody = e.body;
      final String buildReturn;
      if (pageBody == null) {
        buildReturn =
            '  return ${e.isFunctional ? 'p${e.importIndex}.${e.publicName}(context)' : 'p${e.importIndex}.${e.publicName}()'};';
      } else if (pageBody.isBlock) {
        // The statements as written, with references to symbols that stayed
        // in the source file qualified through its deferred import -- this
        // code runs in another library, where those names do not exist.
        buildReturn = _qualifySourceSymbols(
          pageBody.statements!,
          'p${e.importIndex}',
          e.sourceSymbols,
        );
      } else {
        buildReturn = _indentGeneratedReturn(
          _qualifySourceSymbols(
            pageBody.expression!,
            'p${e.importIndex}',
            e.sourceSymbols,
          ),
        );
      }
      final sourceDoc = e.expressionBody == null
          ? '/// Deferred generated widget wrapper for [p${e.importIndex}.${e.publicName}].'
          : '/// Deferred generated widget wrapper for a private @DVPage input.';
      return '''
$sourceDoc
class ${e.generatedWidget} extends DartvelPage {
  const ${e.generatedWidget}({super.key});

  static Future<void>? _libraryFuture;

  static Future<void> loadLibrary() {
    return _libraryFuture ??= p${e.importIndex}.loadLibrary();
  }

  @override
  DVPageScaffoldSpec get pageScaffold => ${e.pageScaffold};

${e.isFunctional ? '''  @override
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
    return p${e.importIndex}.${e.publicName}().loadData(params, query);
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
${buildReturn.split('\n').map((line) => '        $line').join('\n')}
      },
    );
  }
}
''';
    }).join('\n');

    // Global redirect builder from routingRedirects + normalization
    final sbRedirect = StringBuffer();
    sbRedirect.writeln(
      'String? _globalRedirect(BuildContext context, GoRouterState state) {',
    );
    sbRedirect.writeln('  final path = state.uri.path;');
    // A browser extension opens its page as /index.html, and so does anyone
    // who lands on a static host's file directly. Without this the router
    // treats it as a route nobody declared and shows its own 404 -- which is
    // what a Dartvel extension did in Firefox, on top of a working engine.
    sbRedirect.writeln("  if (path == '/index.html') return '/';");
    sbRedirect.writeln("  if (path.endsWith('/index.html')) {");
    sbRedirect.writeln(
        "    return state.uri.replace(path: path.substring(0, "
        "path.length - 'index.html'.length - 1)).toString();");
    sbRedirect.writeln('  }');
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
          '    final newPath = "$toEsc".replaceAllMapped(RegExp(r":([a-zA-Z0-9_]+)"), (mm) => m.namedGroup(mm.group(1)!) ?? "");',
        );
        sbRedirect.writeln(
          '    final newUri = state.uri.replace(path: newPath);',
        );
        sbRedirect.writeln('    return newUri.toString();');
        sbRedirect.writeln('  } }');
      }
    }
    sbRedirect.writeln('  return null;');
    sbRedirect.writeln('}');

    final router = '''
// GENERATED – do not edit.
// ignore_for_file: unnecessary_import, unused_import
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
GoRouter createDartvelRouter() {
  configureDartvelRuntime();
  // What each route can fetch and show before you go there, so DVNavLink can
  // preload a destination on hover and preview it on a rest. The link cannot
  // know how to build a route; the router does.
$routeCapabilities
  // Path URLs on the web, not the hash Flutter defaults to.
  //
  // Without this, /docs never reaches the router: the browser asks for the
  // page, the app boots, and the router sees only "/" -- so every deep link
  // renders the home page and every URL grows a #. For a site that is fatal
  // rather than untidy, because a crawler indexes /#/docs as /, and a shared
  // link opens the wrong page.
  //
  // It needs the server to serve index.html for unknown paths, which is what
  // the .htaccess and dartvel deploy configuration do.
  dvUsePathUrlStrategy();
$semanticsCall
  final router = GoRouter(
    routes: [
$routesSrc
$modelRoutes
    ],
    redirect: _globalRedirect,
    // A route with no compiled page may still be a Studio page: builder
    // documents are data, so saving one publishes it without a rebuild.
    // Compiled routes always win — the store is only consulted here, after
    // matching has already failed.
    // A route with no compiled page at all may still be a Studio page.
    errorBuilder: (BuildContext context, GoRouterState state) =>
        DVStudioPageRoute(state.uri.path),
  );
  // DV.Navigation is used from callbacks with no BuildContext, so it needs the
  // live router rather than looking one up from the widget tree.
  DVNavigation.attach(router);

  // Anchors in the semantics tree are real anchors -- what a crawler follows
  // and what a screen reader announces -- and also what the browser navigates
  // natively, tearing the document down and rebuilding the whole application
  // to move between two routes. Intercepted so an in-app link pushes the
  // route instead. Anything that is not an in-app link is left to the
  // browser, which is the only correct default.
  dvInterceptLinkNavigation(router.go);

  // Without this DVLinkOpener has no implementation, so DVNavLink.external
  // and every middle-click silently do nothing -- which looks exactly like a
  // link that works.
  DVLinkOpener.install(dvOpenUrl);
  return router;
}

${(() {
      final sbRoutes = StringBuffer();
      sbRoutes.writeln(
          '/// Strongly typed route targets for type-safe navigation.');
      sbRoutes.writeln('class DVRoutes {');
      final claimed = <String, String>{};
      for (final e in pageEntries) {
        final routePath = e.route;
        final cleanPath = routePath.replaceAll(RegExp(r'/:[A-Za-z0-9_]+'), '');
        final name = _routeTargetName(cleanPath);

        final paramRegex = RegExp(r':([A-Za-z0-9_]+)');
        final params =
            paramRegex.allMatches(routePath).map((m) => m.group(1)!).toList();

        // Two routes reducing to one identifier emit the same member twice,
        // which fails to compile with no indication of which routes collided.
        final previous = claimed[name];
        if (previous != null && previous != routePath) {
          throw StateError(
            'Routes $previous and $routePath both generate DVRoutes.$name. '
            'Rename one of the page directories so the typed targets differ.',
          );
        }
        claimed[name] = routePath;

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
      // A manifest as well as the typed targets: DVRoutes is static consts,
      // which nothing can enumerate, so the admin's route explorer would have
      // no way to ask what routes exist.
      sbRoutes.writeln();
      sbRoutes.writeln('/// Every generated route, for tools that need to');
      sbRoutes.writeln('/// enumerate them rather than navigate to one.');
      sbRoutes.writeln(
          'const List<DVRouteInfo> dartvelRouteManifest = <DVRouteInfo>[');
      for (final e in pageEntries) {
        final params = RegExp(r':([A-Za-z0-9_]+)')
            .allMatches(e.route)
            .map((m) => "'${m.group(1)!}'")
            .join(', ');
        sbRoutes.writeln('  DVRouteInfo(');
        sbRoutes.writeln("    path: '${e.route}',");
        sbRoutes.writeln("    page: '${e.publicName}',");
        sbRoutes.writeln("    directory: '${e.directory}',");
        sbRoutes.writeln('    parameters: <String>[$params],');
        sbRoutes.writeln('  ),');
      }
      sbRoutes.writeln('];');
      return sbRoutes.toString();
    })()}
''';
    File(
      p.join(libClientDir.path, 'router.g.dart'),
    ).writeAsStringSync('// BUILD: $buildId\n$router');

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

    File(
      p.join(libClientDir.path, 'config.g.dart'),
    ).writeAsStringSync(configContent);

    _generateSsgBuilder(pageEntries, pageImports, root);
  }

  static void _generateSsgBuilder(
    List<_PageEntry> entries,
    List<String> imports,
    String root,
  ) {
    final sb = StringBuffer();
    sb.writeln('// GENERATED – do not edit.');
    sb.writeln('import \'dart:convert\';');
    sb.writeln('import \'dart:io\';');
    sb.writeln('import \'package:dartvel_flutter/dartvel_flutter.dart\';');

    sb.writeln(imports.join('\n'));

    sb.writeln('void main() async {');
    sb.writeln("  final outDir = Directory('build/web/_ssg');");
    sb.writeln(
      '  if (!outDir.existsSync()) outDir.createSync(recursive: true);',
    );
    sb.writeln("  stdout.writeln('Generating SSG data...');");

    for (final e in entries) {
      final i = e.importIndex;
      final className = e.publicName;
      final routePath = e.route;
      final prefix = 'p$i';
      final isDynamic = routePath.contains(':');

      sb.writeln('  // $routePath');
      if (e.isFunctional) {
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
        sb.writeln('        String key = "$routePath";');
        sb.writeln(
          '        params.forEach((k, v) => key = key.replaceAll(":\$k", v));',
        );
        sb.writeln('        final bytes = utf8.encode(key);');
        sb.writeln('        final filename = base64Url.encode(bytes);');
        sb.writeln(
          '        File("\${outDir.path}/\$filename.json").writeAsStringSync(jsonEncode(data));',
        );
        sb.writeln('      }');
        sb.writeln('    }');
      } else {
        sb.writeln('    final data = await page.loadData({}, {});');
        sb.writeln('    if (data != null) {');
        sb.writeln('      final key = "$routePath";');
        sb.writeln('      final bytes = utf8.encode(key);');
        sb.writeln('      final filename = base64Url.encode(bytes);');
        sb.writeln(
          '      File("\${outDir.path}/\$filename.json").writeAsStringSync(jsonEncode(data));',
        );
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


  /// The `dartvel.semantics` setting, which is either a bool or a map.
  ///
  /// Both spellings are accepted because both are the obvious thing to write:
  /// `semantics: false` and `semantics: {enabled: false}`.
  static Object? _dartvelSemantics(String root) {
    final file = File(p.join(root, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    try {
      final doc = loadYaml(file.readAsStringSync());
      final dartvel = doc is YamlMap ? doc['dartvel'] : null;
      return dartvel is YamlMap ? dartvel['semantics'] : null;
    } on Object {
      return null;
    }
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
    final match = RegExp(
      r'@DVPage\(([^)]*)\)',
      dotAll: true,
    ).firstMatch(source);
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
      'selectable',
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
    return RegExp(
      r'\b(?:Scaffold|CupertinoPageScaffold)\s*\(',
    ).hasMatch(source);
  }

  static String? _namedStringArg(String args, String name) {
    final match = RegExp(
      '$name\\s*:\\s*((?:r)?(?:\'[^\']*\'|"[^"]*"))',
      dotAll: true,
    ).firstMatch(args);
    return match?.group(1);
  }

  static String? _namedEnumArg(String args, String name, String enumName) {
    final match = RegExp(
      '$name\\s*:\\s*($enumName\\.[A-Za-z_][A-Za-z0-9_]*)',
    ).firstMatch(args);
    return match?.group(1);
  }

  static String? _namedBoolArg(String args, String name) {
    final match = RegExp('$name\\s*:\\s*(true|false)').firstMatch(args);
    return match?.group(1);
  }

  static String? _namedIntArg(String args, String name) {
    final match = RegExp(
      '$name\\s*:\\s*(0x[0-9A-Fa-f]+|[0-9]+)',
    ).firstMatch(args);
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
          .where(
            (file) => !file.path.contains(
              '${p.separator}dartvel_client${p.separator}',
            ),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final source = file.readAsStringSync();
        if (!source.contains('@DVFunctionalWidget()')) continue;
        final rel = p.relative(file.path, from: root).replaceAll('\\', '/');
        final importPath = rel.replaceFirst(
          RegExp(r'^lib/'),
          'package:$pkgName/',
        );
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
        entry.importPath,
        () => 'w${importAliases.length}',
      );
    }
    for (final item in importAliases.entries) {
      imports.add("import '${item.key}' as ${item.value};");
    }
    for (int i = 0; i < entries.length; i++) {
      entries[i] = entries[i].copyWith(
        alias: importAliases[entries[i].importPath]!,
      );
    }

    final buffer = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      ..writeln(
        '// ignore_for_file: non_constant_identifier_names, unused_import',
      )
      ..writeln('library dartvel_client_widgets;')
      ..writeln()
      ..writeln(imports.join('\n'))
      ..writeln();

    for (final entry in entries) {
      final DVFunctionBody? entryBody = entry.body;
      if (entryBody != null) {
        // Symbols that stayed behind in the source file are qualified through
        // its import: this code runs in another library, where those names do
        // not exist.
        final String rendered = entryBody.isBlock
            ? _qualifySourceSymbols(
                entryBody.statements!,
                entry.alias,
                entry.sourceSymbols,
              )
            : _indentGeneratedReturn(
                _qualifySourceSymbols(
                  entryBody.expression!,
                  entry.alias,
                  entry.sourceSymbols,
                ),
              );
        buffer
          ..writeln(
            'Widget ${entry.generatedName}(${entry.parameters})'
            '${entryBody.modifier == null ? '' : ' ${entryBody.modifier}'} {',
          )
          ..writeln(rendered)
          ..writeln('}')
          ..writeln();
      } else {
        buffer
          ..writeln('Widget ${entry.generatedName}(${entry.parameters}) {')
          ..writeln(
            '  return ${entry.alias}.${entry.sourceName}(${entry.argumentList});',
          )
          ..writeln('}')
          ..writeln();
      }
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
      final annotationStart = annotation < 240 ? 0 : annotation - 240;
      final annotationBlock = source.substring(annotationStart, widgetToken);
      if (annotationBlock.contains('@DVPage')) {
        cursor = widgetToken + 'Widget'.length;
        continue;
      }
      final nameMatch = RegExp(
        r'Widget\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      ).firstMatch(source.substring(widgetToken));
      if (nameMatch == null) {
        cursor = widgetToken + 'Widget'.length;
        continue;
      }
      final sourceName = nameMatch.group(1)!;
      if (!sourceName.startsWith('_')) {
        throw StateError(
          'Dartvel functional widget generation inputs must be private. Rename '
          '$sourceName to _$sourceName and use the generated '
          '${_generatedWidgetName('_$sourceName')} widget from '
          'dartvel_client/dartvel_client.dart. File: $sourcePath',
        );
      }
      final openParen = widgetToken + nameMatch.end - 1;
      final closeParen = _matchingParen(source, openParen);
      if (closeParen == -1) {
        cursor = openParen + 1;
        continue;
      }
      final parameters = source.substring(openParen + 1, closeParen).trim();
      final DVFunctionBody? body = dvFunctionBodyAfter(source, closeParen);
      if (body == null) {
        throw StateError(
          'Dartvel private functional widget input $sourceName in $sourcePath '
          'has no body. A functional widget is a function returning a widget, '
          'either Widget $sourceName(...) => DVText(...) or with a block.',
        );
      }
      final String? expressionBody = body.expression;
      entries.add(
        _FunctionalWidgetEntry(
          importPath: importPath,
          sourcePath: sourcePath,
          alias: '',
          sourceName: sourceName,
          generatedName: _generatedWidgetName(sourceName),
          parameters: parameters,
          argumentList: _argumentList(parameters),
          expressionBody: expressionBody,
          body: body,
          sourceSymbols: _topLevelSourceSymbols(source),
        ),
      );
      cursor = closeParen + 1;
    }
    return entries;
  }

  static Set<String> _topLevelSourceSymbols(String source) {
    final symbols = <String>{};
    final declarations = RegExp(
      r'^(?:final|const|var)\s+(?:(?:[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+)?([A-Za-z][A-Za-z0-9_]*)\s*=',
      multiLine: true,
    );
    for (final match in declarations.allMatches(source)) {
      symbols.add(match.group(1)!);
    }
    final typedVariables = RegExp(
      r'^(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)+([A-Za-z][A-Za-z0-9_]*)\s*(?:=|;)',
      multiLine: true,
    );
    for (final match in typedVariables.allMatches(source)) {
      symbols.add(match.group(1)!);
    }
    final functions = RegExp(
      r'^(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)+([A-Za-z][A-Za-z0-9_]*)\s*\(',
      multiLine: true,
    );
    for (final match in functions.allMatches(source)) {
      symbols.add(match.group(1)!);
    }
    return symbols;
  }

  static String _qualifySourceSymbols(
    String expression,
    String alias,
    Set<String> symbols,
  ) =>
      dvQualifySourceSymbols(expression, alias, symbols);

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

    final buffer = StringBuffer()
      ..writeln('Duplicate generated Dartvel widget names found.')
      ..writeln(
        'Each @DVFunctionalWidget function must generate a unique global widget name.',
      );
    for (final conflict in conflicts) {
      buffer.writeln('  ${conflict.key} is generated by:');
      final sources = conflict.value.toList()
        ..sort((a, b) => a.sourcePath.compareTo(b.sourcePath));
      for (final source in sources) {
        buffer.writeln('    - ${source.sourcePath}: ${source.sourceName}()');
      }
    }
    buffer.writeln(
      'Rename the annotated functions so their generated PascalCase widget names are unique.',
    );
    throw StateError(buffer.toString().trimRight());
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

  static String _indentGeneratedReturn(String expression) {
    final normalized = expression.trim();
    if (!normalized.contains('\n')) return '  return $normalized;';
    final lines = normalized.split('\n');
    final buffer = StringBuffer('  return ${lines.first.trimRight()}\n');
    for (int index = 1; index < lines.length; index += 1) {
      final suffix = index == lines.length - 1 ? ';' : '';
      buffer.writeln('  ${lines[index].trimRight()}$suffix');
    }
    final generated = buffer.toString();
    return generated.endsWith('\n')
        ? generated.substring(0, generated.length - 1)
        : generated;
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

/// A public Dart identifier for a route.
///
/// A leading underscore — every route under `/_dartvel_admin`, for one —
/// makes the generated member private, so the typed target exists but no
/// application code can reach it.
String _routeTargetName(String cleanPath) {
  final name = cleanPath
      .replaceAll(RegExp(r'[^A-Za-z0-9_/]'), '')
      .replaceAll('/', '')
      .replaceAll(RegExp(r'^_+'), '')
      .trim();
  if (name.isEmpty) return 'index';
  // An identifier cannot begin with a digit.
  if (RegExp(r'^[0-9]').hasMatch(name)) return 'r$name';
  return name;
}

class _PageEntry {
  final String importIndex;
  final String className;
  final String publicName;
  final String generatedWidget;
  final String pageScaffold;
  final String route;
  final String directory;
  final bool isFunctional;
  final String? expressionBody;

  /// The page's body as written, so a block can be lowered rather than
  /// refused.
  final DVFunctionBody? body;
  final Set<String> sourceSymbols;

  /// The prose on this page, for the crawler-visible body.
  final List<String> text;
  final String? loadingAlias;
  final String? errorAlias;

  const _PageEntry({
    required this.importIndex,
    required this.className,
    required this.publicName,
    required this.generatedWidget,
    required this.pageScaffold,
    required this.route,
    required this.directory,
    required this.isFunctional,
    this.expressionBody,
    this.body,
    this.sourceSymbols = const <String>{},
    this.text = const <String>[],
    this.loadingAlias,
    this.errorAlias,
  });
}

class _FunctionalWidgetEntry {
  final String importPath;
  final String sourcePath;
  final String alias;
  final String sourceName;
  final String generatedName;
  final String parameters;
  final String argumentList;
  final String? expressionBody;

  /// The scanned body, block or expression. [expressionBody] stays for the
  /// doc comment that distinguishes a private input from a public one.
  final DVFunctionBody? body;
  final Set<String> sourceSymbols;

  const _FunctionalWidgetEntry({
    required this.importPath,
    required this.sourcePath,
    required this.alias,
    required this.sourceName,
    required this.generatedName,
    required this.parameters,
    required this.argumentList,
    this.expressionBody,
    this.body,
    this.sourceSymbols = const <String>{},
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
      expressionBody: expressionBody,
      body: body,
      sourceSymbols: sourceSymbols,
    );
  }
}
