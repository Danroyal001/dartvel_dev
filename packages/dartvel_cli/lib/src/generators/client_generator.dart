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
    final pageGlob = Glob('$pagesDir/**.page.dart');
    final pageFiles = <File>[];
    final fs = const LocalFileSystem();
    for (final e
        in pageGlob.listFileSystemSync(fs, root: root, followLinks: false)) {
      final path = e.path;
      final ioFile = File(path);
      if (!ioFile.existsSync()) continue;
      // Skip layout files from page list
      if (p.basename(path) == '_layout.dart') continue;
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
      // Parse class name by scanning file for class/functional widget
      final src = await File(abs).readAsString();
      final m =
          RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+(DartvelPage|DVClassWidget)')
              .firstMatch(src);
      String className;
      bool isFunctional = false;
      if (m != null) {
        className = m.group(1)!;
      } else {
        final mf = RegExp(r'@DVFunctionalWidget\(\)\s+Widget\s+([A-Za-z_][A-Za-z0-9_]*)\(')
            .firstMatch(src);
        if (mf == null) {
          stderr.writeln(
              'dartvel: could not find class extending DartvelPage/DVClassWidget or @DVFunctionalWidget in $rel');
          continue;
        }
        className = mf.group(1)!;
        isFunctional = true;
      }

      pageImports.add("import '$importPath' as p$i;");
      String route;
      try {
        route = RouteUtils.routeFor(rel, pagesDir);
      } catch (e) {
        stderr.writeln('ERROR: Invalid route in $rel: ${e.toString()}');
        exit(1);
      }
      final dir = p.dirname(rel).replaceAll('\\', '/');

      // Detect optional .loading.dart and .error.dart siblings
      final String baseNoSuffix =
          rel.replaceFirst(RegExp(r'\.page\.dart$'), '');
      final loadingRel = '$baseNoSuffix.loading.dart';
      final errorRel = '$baseNoSuffix.error.dart';
      String? loadingAlias;
      String? errorAlias;
      if (File(p.join(root, loadingRel)).existsSync()) {
        final importPathL =
            loadingRel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
        loadingAlias = 'pl$i';
        pageImports.add("import '$importPathL' as $loadingAlias;");
      }
      if (File(p.join(root, errorRel)).existsSync()) {
        final importPathE =
            errorRel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
        errorAlias = 'pe$i';
        pageImports.add("import '$importPathE' as $errorAlias;");
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
    if (pageFiles.isEmpty) {
      log('dartvel: no pages found under "$pagesDir" (looking for **/*.page.dart)');
    }

    // Client runtime/helper – write only under lib/dartvel_client
    final libClientDir = Directory(p.join(root, 'lib', 'dartvel_client'))
      ..createSync(recursive: true);
    // Minimal client class (only if not provided by the app)
    final clientFile = File(p.join(libClientDir.path, 'dartvel_client.dart'));
    if (!clientFile.existsSync()) {
      clientFile.writeAsStringSync('''
// Simple client surface to set default headers (e.g., auth)
class DartvelClient {
  static Map<String, String> defaultHeaders = <String, String>{};
  static void setAuthToken(String token, {String scheme = 'Bearer'}) {
    defaultHeaders['Authorization'] = token.isEmpty ? '' : '\$scheme \$token';
    if (defaultHeaders['Authorization']!.isEmpty) {
      defaultHeaders.remove('Authorization');
    }
  }
}
''');
    }

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
    final i18n = dv['i18n'] is YamlMap ? dv['i18n'] as YamlMap : YamlMap.wrap({});
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
        ${e['isFunctional'] == true
            ? 'final page = p${e['i']}.${e['class']}(context);'
            : 'final page = const p${e['i']}.${e['class']}();'}
        final withState = DartvelRouteState(params: params, query: query, child: page);

        // i18n scope (query strategy only; no-op if not configured)
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
              final lc =
                  e['class'] != null ? '${e['class']!}Loading' : 'Loading';
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
  ''')
        .join(',\n');

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

/// Creates the GoRouter instance for Dartvel routing.
GoRouter createDartvelRouter() => GoRouter(
  routes: [
$routesSrc
  ],
  redirect: _globalRedirect,
);
''';
    File(p.join(libClientDir.path, 'router.g.dart'))
        .writeAsStringSync('// BUILD: $buildId\n$router');

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
    sb.writeln("  print('Generating SSG data...');");

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
      // sb.writeln("    print('Error generating SSG for $routePath: \$e');");
      sb.writeln('  }');
    }
    sb.writeln("  print('SSG generation complete.');");
    sb.writeln('}');

    final ssgFile = File(p.join(root, '.dartvel', 'ssg_builder.dart'));
    if (!ssgFile.parent.existsSync()) {
      ssgFile.parent.createSync(recursive: true);
    }
    ssgFile.writeAsStringSync(sb.toString());
  }
}
