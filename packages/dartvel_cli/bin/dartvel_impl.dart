#!/usr/bin/env dart

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:glob/glob.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:watcher/watcher.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dvs;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addCommand('routes')
    ..addCommand('build')
    ..addCommand('doctor')
    ..addCommand('watch');

  // dev/run command with common Flutter flags passthrough
  final devParser = ArgParser(allowTrailingOptions: true)
    ..addOption('device', abbr: 'd')
    ..addFlag('release', defaultsTo: false)
    ..addFlag('profile', defaultsTo: false)
    ..addFlag('debug', defaultsTo: false)
    ..addMultiOption('dart-define')
    ..addMultiOption('dart-define-from-file')
    ..addOption('web-renderer')
    ..addFlag('verbose', abbr: 'v', defaultsTo: false);

  parser.addCommand('dev', devParser);
  parser.addCommand('run', devParser);
  final previewParser = ArgParser()
    ..addOption('dir', defaultsTo: 'build/web')
    ..addOption('host', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '4321');
  parser.addCommand('preview', previewParser);

  final result = parser.parse(args);

  final cmd = result.command?.name ?? 'help';
  switch (cmd) {
    case 'routes':
      await _generate();
      stdout.writeln('Generated routes and client artifacts.');
      break;
    case 'dev':
    case 'run':
    case 'start':
      await _dev(result.command!);
      break;
    case 'build':
      await _generate(validateProd: true);
      stdout.writeln('Generated production-ready artifacts.');
      break;
    case 'doctor':
      final code = await _doctor();
      exit(code);
    // no break
    case 'watch':
      await _watch();
      break;
    case 'preview':
      await _preview(result.command!);
      break;
    case 'help':
      _help();
      break;
    default:
      _help();
  }
}

void _help() {
  stdout.writeln('Usage:');
  stdout.writeln('  dartvel <routes|dev|build|doctor|watch> ');
}

Future<void> _generate({bool validateProd = false}) async {
  final root = Directory.current.path;
  // Unique build id for this generation (UTC ISO + epoch millis)
  final _now = DateTime.now().toUtc();
  final buildId = '${_now.toIso8601String()}#${_now.millisecondsSinceEpoch}';
  stdout.writeln('dartvel: generator build $buildId');
  final pubspecFile = File(p.join(root, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml not found in ${Directory.current.path}');
    exit(2);
  }
  final yaml = loadYaml(await pubspecFile.readAsString()) as YamlMap;
  final pkgName = (yaml['name'] ?? 'app').toString();
  final dv = (yaml['dartvel'] ?? {}) as YamlMap;

  final backendHost = (dv['backendHost'] ?? '0.0.0.0').toString();
  final backendPort = _asInt(dv['backendPort'], 3000);
  final apiBasePath = (dv['apiBasePath'] ?? '/api').toString();

  final devBackendHost =
      (dv['devBackendHost'] ?? 'http://localhost:$backendPort').toString();
  final prodBackendHost = (dv['prodBackendHost'] ?? '').toString();
  if (validateProd && prodBackendHost.isEmpty) {
    stderr.writeln('dartvel.prodBackendHost is required for build.');
    exit(3);
  }

  final pagesDir = (dv['pagesDir'] ?? 'lib/pages').toString();
  final backendDir = (dv['backendDir'] ?? 'lib/backend').toString();
  // Env files (public)
  final envFiles = <String>[];
  if (dv['envFiles'] is YamlList) {
    for (final f in (dv['envFiles'] as YamlList)) {
      if (f != null) envFiles.add(f.toString());
    }
  } else {
    envFiles.addAll(['.env', '.env.local']);
  }

  // Web defaults
  final seo = (dv['webSeoDefaults'] ?? {}) as YamlMap;
  final seoSiteName = (seo['siteName'] ?? '').toString();
  final seoTitle = (seo['defaultTitle'] ?? '').toString();
  final seoDesc = (seo['defaultDescription'] ?? '').toString();
  final seoImage = (seo['defaultImage'] ?? '').toString();
  final seoTwitter = (seo['twitterHandle'] ?? '').toString();

  final transitions =
      (dv['webTransitions'] ?? dv['transitions'] ?? {}) as YamlMap;
  final defaultTransition = (transitions['default'] ?? 'fade').toString();
  final durationMs = _asInt(transitions['durationMs'], 220);
  final curve = (transitions['curve'] ?? 'easeInOut').toString();

  // Routing options
  final normalizeTrailing = _asBool(dv['routingNormalizeTrailingSlash'], true);
  final notFoundRedirect = (dv['notFoundRedirect'] ?? '').toString();

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
    if (p.basename(path) == '_layout.page.dart') continue;
    pageFiles.add(ioFile);
  }
  pageFiles.sort((a, b) => a.path.compareTo(b.path));

  // Scan layouts: any _layout.page.dart under pagesDir
  final layoutGlob = Glob(p.join(pagesDir, '**/_layout.page.dart'));
  final layoutFiles = <File>[];
  for (final e
      in layoutGlob.listFileSystemSync(fs, root: root, followLinks: false)) {
    final ioFile = File(e.path);
    if (ioFile.existsSync()) layoutFiles.add(ioFile);
  }
  // Fallback: add root layout if present
  final rl = File(p.join(root, pagesDir, '_layout.page.dart'));
  if (rl.existsSync() && !layoutFiles.any((f) => p.equals(f.path, rl.path))) {
    layoutFiles.add(rl);
  }
  layoutFiles.sort((a, b) => a.path.compareTo(b.path));

  String _routeFor(String rel) {
    var path =
        rel.replaceFirst(RegExp('^$pagesDir/?'), '').replaceAll('\\', '/');
    path = path.replaceFirst(RegExp(r'\.page\.dart$'), '');
    // index at root → '/'
    if (path == 'index') return '/';
    // strip group folders
    path = path.replaceAllMapped(RegExp(r'\(([^)]+)\)/'), (m) => '');
    // dynamic and catch-all segments
    path = path.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) {
      final seg = m.group(1)!;
      if (seg.startsWith('...')) return '*${seg.substring(3)}';
      return ':$seg';
    });
    // support nested index: foo/index → /foo
    path = path.replaceFirst(RegExp(r'/index$'), '');
    if (path.isEmpty) return '/';
    return '/$path';
  }

  final pageImports = <String>[];
  final pageEntries = <Map<String, String>>[];
  final layoutImports = <String>[];
  final layoutMapByDir = <String, Map<String, String>>{}; // dir -> {i, class}

  for (var i = 0; i < pageFiles.length; i++) {
    final abs = pageFiles[i].path;
    final rel = p.relative(abs, from: root).replaceAll('\\', '/');
    final importPath = rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
    // Parse class name by scanning file for `class Xxx extends DartvelPage`
    final src = await File(abs).readAsString();
    final m =
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+DartvelPage')
            .firstMatch(src);
    if (m == null) {
      stderr.writeln(
          'dartvel: could not find a class extending DartvelPage in $rel');
      continue;
    }
    final className = m.group(1)!;

    pageImports.add("import '$importPath' as p$i;");
    final route = _routeFor(rel);
    final dir = p.dirname(rel).replaceAll('\\', '/');

    // Detect optional .loading.dart and .error.dart siblings
    String baseNoSuffix = rel.replaceFirst(RegExp(r'\.page\.dart$'), '');
    final loadingRel = baseNoSuffix + '.loading.dart';
    final errorRel = baseNoSuffix + '.error.dart';
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
      if (loadingAlias != null) 'loadingAlias': loadingAlias,
      if (errorAlias != null) 'errorAlias': errorAlias,
    });
  }

  // Import all layouts and build map by directory
  for (var j = 0; j < layoutFiles.length; j++) {
    final abs = layoutFiles[j].path;
    final rel = p.relative(abs, from: root).replaceAll('\\', '/');
    final importPath = rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
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
  final routeToEntries = <String, List<Map<String, String>>>{};
  for (final e in pageEntries) {
    routeToEntries
        .putIfAbsent(e['route']!, () => <Map<String, String>>[])
        .add(e);
  }
  final conflicts = routeToEntries.entries.where((kv) => kv.value.length > 1);
  if (conflicts.isNotEmpty) {
    stderr.writeln('ERROR: Detected route conflicts:');
    for (final c in conflicts) {
      stderr.writeln('  Route "' + c.key + '" generated by:');
      for (final e in c.value) {
        // Best-effort: rebuild approximate file path from import alias index
        final idx = e['i'] ?? '?';
        // Search from pageImports for matching alias
        final alias = 'p' + idx!;
        try {
          final line =
              pageImports.firstWhere((l) => l.contains(' as ' + alias + ';'));
          final beforeAs = line.split(' as ').first;
          String path = beforeAs.trim();
          final impIdx = path.indexOf("import '");
          if (impIdx != -1) {
            var s = path.substring(impIdx + 8); // after "import '"
            final end = s.lastIndexOf("'");
            if (end != -1) s = s.substring(0, end);
            path = s;
          }
          stderr.writeln('    - ' + path.trim());
        } catch (_) {
          stderr.writeln('    - alias ' + alias);
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
    final importPath = rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
    final alias = 'g' + guardImports.length.toString();
    guardImports.add("import '$importPath' as $alias;");
    final dir = p.dirname(rel).replaceAll('\\', '/');
    guardMapByDir[dir] = alias;
  }

  // Ensure dirs
  final backendOut = Directory(p.join(root, '.dart_tool'))..createSync();
  if (pageFiles.isEmpty) {
    stdout.writeln(
        'dartvel: no pages found under "$pagesDir" (looking for **/*.page.dart)');
  }

  // Client runtime/helper – write only under lib/dartvel_client
  // Client runtime/helper
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
  File(p.join(libClientDir.path, 'dartvel_config.g.dart')).writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_client_config;
const String dvBackendBindHost = '${_esc(backendHost)}';
const int    dvBackendPort      = $backendPort;
const String dvDevBackendHost   = '${_esc(devBackendHost)}';
const String dvProdBackendHost  = '${_esc(prodBackendHost)}';
const String dvApiBasePath      = '${_esc(apiBasePath)}';
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
          debugPrint('''\n=== DARTVEL DEV ===\nDetected Android emulator. Using 10.0.2.2 for backend.\nBase: ''' + url + ' -> ' + updated + '''\n===================\n''');
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
  Map<String, String> _parseEnvFile(String path) {
    final file = File(p.join(root, path));
    final out = <String, String>{};
    if (!file.existsSync()) return out;
    final lines = file.readAsLinesSync();
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var val = line.substring(eq + 1).trim();
      // strip quotes
      if ((val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))) {
        val = val.substring(1, val.length - 1);
      }
      out[key] = val;
    }
    return out;
  }

  final envMap = <String, String>{};
  for (final f in envFiles) {
    final m = _parseEnvFile(f);
    if (m.isNotEmpty) {
      stdout.writeln('dartvel: loaded env file: ' + f);
      envMap.addAll(m); // later files override earlier
    }
  }
  final publicEnv = <String, String>{
    for (final e in envMap.entries)
      if (e.key.startsWith('PUBLIC_')) e.key: e.value
  };
  String _escD(String s) => s.replaceAll('\\', r'\\').replaceAll("'", r"\'");
  final sbEnv = StringBuffer();
  sbEnv.writeln('// GENERATED – do not edit.');
  sbEnv.writeln('library dartvel_client_env;');
  sbEnv.writeln('const Map<String, String> dvPublicEnv = {');
  for (final e in publicEnv.entries) {
    sbEnv.writeln("  '" + _escD(e.key) + "': '" + _escD(e.value) + "',");
  }
  sbEnv.writeln('};');
  sbEnv.writeln('class DartvelEnv {');
  sbEnv.writeln('  static const Map<String, String> public = dvPublicEnv;');
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
        redirects.add({'from': r['from'].toString(), 'to': r['to'].toString()});
      }
    }
  }

  // i18n (query strategy)
  final i18n = (dv['i18n'] ?? {}) as YamlMap;
  final i18nParam = (i18n['param'] ?? 'lang').toString();
  final i18nDefault = (i18n['defaultLocale'] ?? '').toString();
  final i18nLocales = <String>[];
  if (i18n['locales'] is YamlList) {
    for (final v in (i18n['locales'] as YamlList)) {
      if (v != null) i18nLocales.add(v.toString());
    }
  }
  final i18nLocalesLit = i18nLocales.map((s) => "'${_esc(s)}'").join(', ');

  String _patternToRegex(String pattern) {
    final esc = pattern.replaceAllMapped(
        RegExp(r'([.+*?^${}()\[\]|\\])'), (m) => '\\${m[1]}');
    final named = esc.replaceAllMapped(
        RegExp(r':([a-zA-Z0-9_]+)'), (m) => '(?<' + m[1]! + '>[^/]+)');
    return '^' + named + r'\$';
  }

  String _wrapWithLayouts(String dir, String innerExpr) {
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
      expr = 'l' + idx + '.' + cls + '(child: ' + expr + ')';
    }
    return expr;
  }

  String _guardRedirectFor(String dir) {
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
            '      { final r = await ' +
            a +
            '.guard(context, state); if (r != null) return r; }')
        .join('\n');
    return '\n      redirect: (context, state) async {\n' +
        calls +
        '\n        return null;\n      },\n';
  }

  final routesSrc = pageEntries
      .map((e) => '''
    GoRoute(
      path: '${_esc(e['route']!)}',
${_guardRedirectFor(e['dir']!)}      pageBuilder: (context, state) {
        final page = const p${e['i']}.${e['class']}();
        final params = Map<String, String>.from(state.pathParameters);
        final query  = Map<String, String>.from(state.uri.queryParameters);
        final withState = DartvelRouteState(params: params, query: query, child: page);

        // i18n scope (query strategy only; no-op if not configured)
        final i18nParam = '${_esc(i18nParam)}';
        final i18nDefault = '${_esc(i18nDefault)}';
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
            final la = e['loadingAlias'];
            final ea = e['errorAlias'];
            final lc = e['class'] != null ? e['class']! + 'Loading' : 'Loading';
            final ec = e['class'] != null ? e['class']! + 'Error' : 'Error';
            final b = StringBuffer();
            if (la != null && (la as String).isNotEmpty) {
              b.writeln("          loading: " + la + "." + lc + "(),");
            } else {
              b.writeln("          loading: const DvDefaultLoading(),");
            }
            if (ea != null && (ea as String).isNotEmpty) {
              b.writeln("          error: " + ea + "." + ec + "(),");
            } else {
              b.writeln("          error: const DvDefaultError(),");
            }
            return b.toString();
          })()}        );

        final seoWrapped = DartvelSeo(
          props: page.buildWebSeo(params, query),
          defaults: _defaultSeo,
          child: loaderWrapped,
        );
        final spec = page.transition == const PageTransitionSpec()
            ? _projectDefaultTransition
            : page.transition;
        return dvTransitionPage(
          key: state.pageKey,
          child: ${_wrapWithLayouts(e['dir']!, 'seoWrapped')},
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
        "  if (state.error != null) return '${_esc(notFoundRedirect)}';");
  }
  if (normalizeTrailing) {
    sbRedirect.writeln("  if (path.length > 1 && path.endsWith('/')) {");
    sbRedirect.writeln(
        "    final newUri = state.uri.replace(path: path.substring(0, path.length - 1));");
    sbRedirect.writeln('    return newUri.toString();');
    sbRedirect.writeln('  }');
  }
  if (redirects.isNotEmpty) {
    for (final r in redirects) {
      final from = r['from']!;
      final to = r['to']!;
      final regex = _patternToRegex(from);
      sbRedirect.writeln('  { final re = RegExp(r"' + regex + '");');
      sbRedirect.writeln('    final m = re.firstMatch(path);');
      sbRedirect.writeln('    if (m != null) {');
      final toEsc = to.replaceAll('"', '\\"');
      sbRedirect.writeln('      final newPath = "' +
          toEsc +
          '"'
              '.replaceAllMapped(RegExp(r":([a-zA-Z0-9_]+)"), (mm) => m.namedGroup(mm.group(1)!) ?? "");');
      sbRedirect
          .writeln('      final newUri = state.uri.replace(path: newPath);');
      sbRedirect.writeln('      return newUri.toString();');
      sbRedirect.writeln('    } }');
    }
  }
  sbRedirect.writeln('  return null;');
  sbRedirect.writeln('}');

  final router = '''
// GENERATED – do not edit.
$imports

const _defaultSeo = SeoProps(
  siteName: '${_esc(seoSiteName)}',
  title: '${_esc(seoTitle)}',
  description: '${_esc(seoDesc)}',
  imageUrl: '${_esc(seoImage)}',
  twitterHandle: '${_esc(seoTwitter)}',
);

const _projectDefaultTransition = PageTransitionSpec(
  type: ${_transitionEnum(defaultTransition)},
  duration: Duration(milliseconds: $durationMs),
  curve: ${_curveExpr(curve)},
);

${sbRedirect.toString()}

GoRouter createDartvelRouter() => GoRouter(
  routes: [
$routesSrc
  ],
  redirect: _globalRedirect,
);
''';
  File(p.join(libClientDir.path, 'router.g.dart'))
      .writeAsStringSync('// BUILD: ' + buildId + '\n' + router);

  // Backend bind config
  File(p.join(backendOut.path, 'dartvel_backend.g.dart')).writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_backend_config;
const String backendHost = '${_esc(backendHost)}';
const int    backendPort = $backendPort;
const String apiBasePath = '${_esc(apiBasePath)}';
const String dvGenBuildId = '$buildId';
''');

  // Backend routes (functions)
  final fnGlob = Glob(p.join(backendDir, 'functions/**.dart'));
  final fs2 = const LocalFileSystem();
  final fnFiles = <File>[];
  for (final e
      in fnGlob.listFileSystemSync(fs2, root: root, followLinks: false)) {
    if (e is File) fnFiles.add(File(e.path));
  }

  final methodSet = {
    'get',
    'post',
    'put',
    'patch',
    'delete',
    'head',
    'options'
  };
  String routeFromRel(String rel) {
    // rel like lib/backend/functions/blog/[id].get.dart
    var path = rel
        .replaceFirst(RegExp('^$backendDir/functions/?'), '')
        .replaceAll('\\\\', '/');
    // strip group folders (parentheses)
    path = path.replaceAllMapped(RegExp(r'\(([^)]+)\)/'), (_) => '');
    // strip extension .dart and method suffix
    if (path.endsWith('.dart')) path = path.substring(0, path.length - 5);
    // split last segment by '.' to separate name and method
    final lastSlash = path.lastIndexOf('/');
    final dir = lastSlash == -1 ? '' : path.substring(0, lastSlash);
    final base = lastSlash == -1 ? path : path.substring(lastSlash + 1);
    final dot = base.lastIndexOf('.');
    final name = dot == -1 ? base : base.substring(0, dot);
    // Convert [id] -> <id>; [...slug] -> <slug|.*>
    String segConv(String s) {
      return s.replaceAllMapped(
          RegExp(r'\[(\.\.\.)?([^\]]+)\]'),
          (m) => m[1] == '...'
              ? '<' + (m[2] ?? '') + '|.*>'
              : '<' + (m[2] ?? '') + '>');
    }

    final dirConv =
        dir.split('/').where((s) => s.isNotEmpty).map(segConv).join('/');
    final nameConv = (name == 'index') ? '' : segConv(name);
    final combined = [dirConv, nameConv].where((s) => s.isNotEmpty).join('/');
    return combined.isEmpty ? '' : '/' + combined;
  }

  final backendImports = <String>[];
  final backendEntries = <Map<String, String>>[]; // {i, method, path}

  for (var i = 0; i < fnFiles.length; i++) {
    final abs = fnFiles[i].path;
    final rel = p.relative(abs, from: root).replaceAll('\\\\', '/');
    final pathRel = rel;
    // detect method from filename
    final base = p.basenameWithoutExtension(rel); // removes .dart
    final dot = base.lastIndexOf('.');
    // Allow filenames without explicit method suffix; default to POST
    var method = (dot != -1) ? base.substring(dot + 1).toLowerCase() : '';
    if (!methodSet.contains(method)) {
      method = 'post';
    }
    final importPath = rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
    backendImports.add("import '$importPath' as f$i;");
    final urlPath = routeFromRel(pathRel);
    // Detect typed function name from file (based on sanitized base name)
    final src = await File(abs).readAsString();
    // Prefer explicit handler(RequestType/Request) for compatibility
    final regHandler = RegExp(
        r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?handler\s*\(([^)]*)\)\s*(?:=>|\{)',
        multiLine: true);
    final hasHandler = regHandler.hasMatch(src);
    final baseWhole = p.basenameWithoutExtension(rel); // e.g., hello.get
    final baseNameOnly = baseWhole.contains('.')
        ? baseWhole.substring(0, baseWhole.lastIndexOf('.'))
        : baseWhole; // hello or [id] or last_read_date_[date]
    final funcCandidate = baseNameOnly.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    String typedName = '';
    String typedParams = '';
    String typedTypes = '';
    String tnamed = '0';
    String rtype = '';

    // 1) Try to find a function whose name matches the sanitized filename
    final regCandidate = RegExp(
        r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?' +
            RegExp.escape(funcCandidate) +
            r'\s*\(([^)]*)\)\s*(?:=>|\{)',
        multiLine: true);
    RegExpMatch? mm = regCandidate.firstMatch(src);
    // Try also to capture return type for typed API generation
    try {
      final _regCandidateTyped = RegExp(
          r'^\s*([A-Za-z_][\w<>, ?]*)\s+' +
              RegExp.escape(funcCandidate) +
              r'\s*\(([^)]*)\)',
          multiLine: true);
      final _mt = _regCandidateTyped.firstMatch(src);
      if (_mt != null) {
        rtype = (_mt.group(1) ?? '').trim();
      }
    } catch (_) {}

    // Utility to extract param names/types from a parameter list string
    void extractParams(String rawFull) {
      if (rawFull.contains('{')) tnamed = '1';
      var raw = rawFull.replaceAll(RegExp(r'[\{\}\[\]]'), '');
      final parts =
          raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
      final names = <String>[];
      final types = <String>[];
      for (final pstr0 in parts) {
        var pstr = pstr0.replaceAll(RegExp(r'^required\s+'), '');
        // strip default value
        final eq = pstr.indexOf('=');
        if (eq != -1) pstr = pstr.substring(0, eq).trim();
        final toks =
            pstr.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (toks.isEmpty) continue;
        final nameTok = toks.last.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
        final typeTok = (toks.length > 1
                ? toks.sublist(0, toks.length - 1).join(' ')
                : 'dynamic')
            .trim();
        if (nameTok.isEmpty) continue;
        names.add(nameTok);
        types.add(typeTok);
      }
      typedParams = names.join(',');
      typedTypes = types.join(',');
    }

    if (mm != null) {
      typedName = funcCandidate;
      extractParams(mm.group(1) ?? '');
    } else if (hasHandler) {
      // Defer to `handler(...)` style; leave untyped so router uses fN.handler
      typedName = '';
    } else {
      // 2) Fallback: detect the first top-level function declaration in the file (skip keywords)
      final regAnyFn = RegExp(
          r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(?:=>|\{)',
          multiLine: true);
      const reserved = {
        'if',
        'for',
        'while',
        'switch',
        'case',
        'default',
        'return',
        'try',
        'catch',
        'on',
        'do',
        'else'
      };
      for (final m2 in regAnyFn.allMatches(src)) {
        final name = (m2.group(1) ?? '').trim();
        if (name.isEmpty || reserved.contains(name)) continue;
        typedName = name;
        extractParams(m2.group(2) ?? '');
        break;
      }
      // Fallback return type, if not captured yet
      if (rtype.isEmpty) {
        final _regAnyTyped = RegExp(
            r'^\s*([A-Za-z_][\w<>, ?]*)?\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(?:=>|\{)',
            multiLine: true);
        final _m = _regAnyTyped.firstMatch(src);
        if (_m != null) rtype = (_m.group(1) ?? 'dynamic').trim();
      }
    }
    backendEntries.add({
      'i': '$i',
      'method': method,
      'path': urlPath,
      'typed': typedName,
      'tparams': typedParams,
      'ttypes': typedTypes,
      'tnamed': tnamed,
      'rtype': rtype
    });
  }

  final backendRoutes = '''
// GENERATED – do not edit.
import 'dart:convert' as conv;
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'dartvel_backend.g.dart' as cfg;
${backendImports.join('\n')}

// Multipart structures and parser (bytes): collects text fields and files
class DvMultipartFile { final String name; final String filename; final String contentType; final Uint8List bytes; DvMultipartFile(this.name,this.filename,this.contentType,this.bytes); }
Map<String, dynamic> _parseMultipartForm(Uint8List body, String contentType) {
  final m = RegExp(r'boundary=([^;]+)').firstMatch(contentType);
  if (m == null) return <String,dynamic>{};
  final boundary = '--' + m.group(1)!;
  final bnd = Uint8List.fromList(conv.latin1.encode(boundary));
  int idxOf(Uint8List d, Uint8List p, int s){ for(int i=s;i<=d.length-p.length;i++){ bool ok=true; for(int j=0;j<p.length;j++){ if(d[i+j]!=p[j]){ ok=false; break;} } if(ok) return i; } return -1; }
  final out = <String,dynamic>{};
  int pos = 0; final first = idxOf(body,bnd,pos); if(first==-1) return out; pos = first + bnd.length + 2;
  final crlf2 = Uint8List.fromList([13,10,13,10]);
  while(pos < body.length){ final hdrEnd = idxOf(body, crlf2, pos); if(hdrEnd==-1) break; final hdr = conv.latin1.decode(body.sublist(pos,hdrEnd)); pos = hdrEnd+4; int next = idxOf(body,bnd,pos); if(next==-1) next = body.length; int end = next-2; if(end<pos) end=pos; final part = Uint8List.fromList(body.sublist(pos,end)); pos = next + bnd.length + 2; final cd = RegExp(r'content-disposition:[^\r\n]*', caseSensitive:false).firstMatch(hdr); if(cd==null) continue; final nm = RegExp(r'name=\"([^\"]+)\"').firstMatch(cd.group(0)!); if(nm==null) continue; final name = nm.group(1)!; final fnm = RegExp(r'filename=\"([^\"]*)\"').firstMatch(cd.group(0)!); String ctype=''; final ctM = RegExp(r'content-type:\s*([^\r\n]+)', caseSensitive:false).firstMatch(hdr); if(ctM!=null) ctype = ctM.group(1)!.trim(); if(fnm!=null){ final filename = fnm.group(1) ?? ''; out[name] = DvMultipartFile(name,filename,ctype,part); } else { out[name] = conv.utf8.decode(part, allowMalformed:true); }
    if(next+ bnd.length + 4 <= body.length){ final tail = conv.latin1.decode(body.sublist(next, (next+bnd.length+4).clamp(0,body.length))); if(tail.startsWith(boundary+'--')) break; }
  }
  return out;
}

dv.DartvelShelf buildBackend() {
  final app = dv.DartvelShelf();
  app.use('log');
  app.use('cors');
  // Default health endpoint – can be overridden by adding a backend function at /health
  bool _hasHealth = false;
${backendEntries.map((e) {
    final path = _esc(e['path'] ?? '');
    final method = e['method']!;
    final i = e['i']!;
    final typed = e['typed'] ?? '';
    if (typed.isEmpty) {
      return "  app." +
          method +
          "(cfg.apiBasePath + '" +
          path +
          "', (dv.Request req) => Future.value(f" +
          i +
          ".handler(req)));";
    }
    final tparams =
        (e['tparams'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
    final ttypes = (e['ttypes'] ?? '').split(',');
    final tnamed = e['tnamed'] == '1';
    String _coerce(String name, String type) {
      final src = "(req.params['" +
          name +
          "'] ?? req.url.queryParameters['" +
          name +
          "'] ?? ((body is Map) ? (body['" +
          name +
          "']) : null))";
      final t = type.replaceAll('?', '').trim();
      if (t == 'String' || t.isEmpty || t == 'dynamic')
        return '((' + src + ')?.toString() ?? \"\")';
      if (t == 'int')
        return '((){ final v = ' +
            src +
            '; if (v is int) return v; return int.tryParse((v)?.toString() ?? \"\") ?? 0; }())';
      if (t == 'double')
        return '((){ final v = ' +
            src +
            '; if (v is double) return v; return double.tryParse((v)?.toString() ?? \"\") ?? 0.0; }())';
      if (t == 'bool')
        return '((){ final s = (' +
            src +
            ' )?.toString().toLowerCase() ?? \"\"; return s==\"true\"||s==\"1\"||s==\"yes\"; }())';
      if (t.startsWith('List<String>'))
        return '((){ final v = ' +
            src +
            '; if (v is List) return v.map((e)=>e.toString()).toList(); final s = (v)?.toString() ?? \"\"; if (s.isEmpty) return <String>[]; return s.contains(\"/\") ? s.split(\"/\") : s.split(\",\"); }())';
      if (t.endsWith('Request') || t.endsWith('RequestType')) return 'req';
      return src; // fallback
    }

    final argList = <String>[];
    for (var idx = 0; idx < tparams.length; idx++) {
      final pn = tparams[idx];
      final pt = idx < ttypes.length ? ttypes[idx] : '';
      final expr = _coerce(pn, pt);
      argList.add(tnamed ? (pn + ': ' + expr) : expr);
    }
    final callArgs = argList.join(', ');
    // Count path params like <id> and <slug|.*>
    final _paramCount = RegExp(r"<[^>]+>").allMatches(path).length;
    if (path == '/health' && method.toLowerCase() == 'get') {
      // mark that health is explicitly defined by user
      return "  _hasHealth = true;\n" +
          '''  app.${method}(cfg.apiBasePath + '${path}', (dv.Request req) async {
    Object? body;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        final ct = req.headers.get('content-type') ?? '';
        if (ct.contains('multipart/form-data')) {
          final rawb = await req.body.bytesU8();
          body = _parseMultipartForm(rawb, ct);
        } else {
          final raw = await req.body.text();
          if (ct.contains('application/json')) {
            body = raw.isEmpty ? null : conv.jsonDecode(raw);
          } else if (ct.contains('application/x-www-form-urlencoded')) {
            try { body = Uri.splitQueryString(raw); } catch (_) { body = <String,String>{}; }
          } else {
            body = raw;
          }
        }
      }
    } catch (e) { /* ignore body read errors */ }
    try {
      Object? result = await f${i}.${typed}(${callArgs});
      if (result is dv.Response) return result;
      if (result is Stream<List<int>>) return dv.Response(200, body: result);
      if (result is Stream) {
        final s = (result as Stream).map((e) => e is String ? conv.utf8.encode(e) : (e as List<int>));
        return dv.Response(200, body: s);
      }
      if (result is String) return dv.Response.text(result);
      return dv.Response(200,
          headers: dv.Headers({'content-type': 'application/json; charset=utf-8'}),
          body: Stream<List<int>>.value(conv.utf8.encode(conv.jsonEncode(result))));
    } catch (e, st) {
      // ignore: avoid_print
      print('[dartvel backend] ERROR in ${method.toUpperCase()} ${path}: ' + e.toString());
      // ignore: avoid_print
      print(st);
      return dv.Response(500, body: Stream<List<int>>.value(conv.utf8.encode('Internal Server Error')));
    }
  });''';
    }
    return '''  app.${method}(cfg.apiBasePath + '${path}', (dv.Request req) async {
    Object? body;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        final ct = req.headers.get('content-type') ?? '';
        if (ct.contains('multipart/form-data')) {
          final rawb = await req.body.bytesU8();
          body = _parseMultipartForm(rawb, ct);
        } else {
          final raw = await req.body.text();
          if (ct.contains('application/json')) {
            body = raw.isEmpty ? null : conv.jsonDecode(raw);
          } else if (ct.contains('application/x-www-form-urlencoded')) {
            try { body = Uri.splitQueryString(raw); } catch (_) { body = <String,String>{}; }
          } else {
            body = raw;
          }
        }
      }
    } catch (e) { /* ignore body read errors */ }
    try {
      Object? result = await f${i}.${typed}(${callArgs});
      if (result is dv.Response) return result;
      if (result is Stream<List<int>>) return dv.Response(200, body: result);
      if (result is Stream) {
        final s = (result as Stream).map((e) => e is String ? conv.utf8.encode(e) : (e as List<int>));
        return dv.Response(200, body: s);
      }
      if (result is String) return dv.Response.text(result);
      return dv.Response(200,
          headers: dv.Headers({'content-type': 'application/json; charset=utf-8'}),
          body: Stream<List<int>>.value(conv.utf8.encode(conv.jsonEncode(result))));
    } catch (e, st) {
      // Print a visible error for non-GET methods to aid debugging
      // ignore: avoid_print
      print('[dartvel backend] ERROR in ${method.toUpperCase()} ${path}: ' + e.toString());
      // ignore: avoid_print
      print(st);
      return dv.Response(500, body: Stream<List<int>>.value(conv.utf8.encode('Internal Server Error')));
    }
  });''';
  }).join('\n')}
  // Provide default health endpoint if not defined by user
  if (!_hasHealth) {
    app.get(cfg.apiBasePath + '/health', (dv.Request _) async => dv.Response.text('ok'));
  }
  return app;
}
''';
  File(p.join(backendOut.path, 'dartvel_backend_routes.g.dart'))
      .writeAsStringSync(backendRoutes);

  // Client function-style API (tRPC-like): generate convenient call helpers
  String toColonPath(String pth) {
    return pth
        .replaceAllMapped(
            RegExp(r'<([^>|]+)\|\.*>').pattern == ''
                ? RegExp('')
                : RegExp(r'<([^>|]+)\|\.*>'),
            (m) => ':' + m.group(1)!)
        .replaceAllMapped(RegExp(r'<([^>]+)>'), (m) => ':' + m.group(1)!);
  }

  String funcNameForFromUrl(String method, String urlPath) {
    String toUpperCamel(String s) {
      final parts =
          s.split(RegExp(r'[_]+')).where((e) => e.isNotEmpty).toList();
      if (parts.isEmpty) return '';
      return parts
          .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
          .join();
    }

    var pth = urlPath.replaceAll(RegExp(r'^/+'), '');
    pth = pth.replaceAllMapped(
        RegExp(r'<([^>|]+)\|\.*>'), (m) => 'by_' + m.group(1)!);
    pth =
        pth.replaceAllMapped(RegExp(r'<([^>]+)>'), (m) => 'by_' + m.group(1)!);
    pth = pth.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    pth = pth.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    final base = pth.isEmpty ? 'root' : pth;
    return method.toLowerCase() + toUpperCamel(base);
  }

  String paramsListFor(String colonPath) {
    final names = RegExp(r':([a-zA-Z0-9_]+)')
        .allMatches(colonPath)
        .map((m) => m.group(1)!)
        .toList();
    if (names.isEmpty) return '';
    return names.map((n) => 'required String ' + n).join(', ');
  }

  final sbClient = StringBuffer();
  sbClient.writeln('// GENERATED – do not edit.');
  sbClient.writeln('// BUILD: ' + buildId);
  sbClient.writeln('library dartvel_client_functions;');
  sbClient.writeln("import 'package:dio/dio.dart';");
  sbClient.writeln("import 'dartvel_runtime.dart';");
  sbClient
      .writeln("import 'package:$pkgName/dartvel_client/dartvel_client.dart';");
  sbClient.writeln('final Dio _dvDio = Dio();');
  sbClient.writeln(
      'Future<Response<Object?>> _dvRequest(String method, Uri uri, {Object? data, Map<String, String>? headers}) async {');
  sbClient.writeln(
      "  final hdrs = {...DartvelClient.defaultHeaders, ...?headers};");
  sbClient.writeln("  final m = method.toUpperCase();");
  sbClient.writeln(
      "  final send = (data == null && m != 'GET' && m != 'HEAD') ? '' : data;");
  sbClient.writeln(
      "  final ct = (hdrs['content-type'] ?? hdrs['Content-Type'] ?? '').toLowerCase();");
  sbClient.writeln(
      "  if (send is Map && ct.contains('application/x-www-form-urlencoded')) {\n    final q = <String,String>{};\n    (send as Map).forEach((k, v) { if (k == null) return; final kk = k.toString(); if (v == null) return; if (v is List) { q[kk] = v.map((e)=> e?.toString() ?? '').join(','); } else { q[kk] = v.toString(); } });\n    send = q.entries.map((e)=> Uri.encodeQueryComponent(e.key) + '=' + Uri.encodeQueryComponent(e.value)).join('&');\n  }");
  sbClient.writeln(
      "  return _dvDio.requestUri(uri, data: send, options: Options(method: m, headers: hdrs));");
  sbClient.writeln('}');

  for (final e in backendEntries) {
    final method = e['method']!;
    final urlPath = e['path']!;
    final colon = toColonPath(urlPath);
    final fname = funcNameForFromUrl(method, urlPath);
    final paramSig = paramsListFor(colon);
    final hasParams = paramSig.isNotEmpty;
    final sig = '{ ' +
        (hasParams ? (paramSig + ', ') : '') +
        'Map<String, dynamic>? query, Object? body, Map<String, String>? headers }';
    final names = RegExp(r':([a-zA-Z0-9_]+)')
        .allMatches(colon)
        .map((m) => m.group(1)!)
        .toList();
    final paramMap = hasParams
        ? ('{ ' + names.map((n) => "'" + n + "': " + n).join(', ') + ' }')
        : 'const <String, Object?>{}';
    final argsNamed =
        (hasParams ? (names.map((n) => n + ': ' + n).join(', ') + ', ') : '') +
            'query: query, body: body, headers: headers';

    sbClient.writeln(
        'Future<Response<Object?>> ' + fname + '(' + sig + ') async {');
    sbClient
        .writeln("  var routePath = '" + colon.replaceAll("'", "\\'") + "';");
    sbClient.writeln('  final Map<String, Object?> pp = ' + paramMap + ';');
    sbClient.writeln(
        "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
    sbClient.writeln('  final base = DartvelRuntime.api(routePath);');
    if (method == 'get' || method == 'head') {
      sbClient.writeln('  final q = <String, String>{};');
      sbClient.writeln(
          '  if (query != null) { query.forEach((k, v) { q[k] = v?.toString() ?? ""; }); }');
      sbClient.writeln('  final uri = base.replace(queryParameters: q);');
      sbClient.writeln("  return _dvRequest('" +
          method +
          "', uri, data: body, headers: headers);");
    } else {
      sbClient.writeln('  final fb = <String, dynamic>{};');
      sbClient.writeln(
          '  if (query != null) { query.forEach((k, v) { fb[k] = v; }); }');
      sbClient.writeln('  final uri = base;');
      sbClient.writeln("  final _hdrs = <String,String>{...?(headers ?? const {})};");
      if (method == 'post') {
        // Enforce multipart form-data for all generated POST endpoints
        sbClient.writeln(
            "  final _payload = (body is FormData) ? body : (body == null ? FormData.fromMap(fb) : (body is Map ? FormData.fromMap(Map<String,dynamic>.from(body as Map)) : body));");
      } else {
        // Other non-GET methods: honor provided payload, fall back to simple map
        sbClient.writeln(
            "  final _payload = (body is FormData) ? body : (body ?? fb);");
      }
      sbClient.writeln("  return _dvRequest('" +
          method +
          "', uri, data: _payload, headers: _hdrs);");
    }
    sbClient.writeln('}');
    sbClient.writeln('');

    // Data-only variant
    sbClient.writeln('Future<Object?> ' + fname + 'Data(' + sig + ') async {');
    sbClient.writeln('  final r = await ' + fname + '(' + argsNamed + ');');
    sbClient.writeln('  return r.data;');
    sbClient.writeln('}');
    sbClient.writeln('');

    // Typed variant using a mapper
    sbClient.writeln('Future<T> ' +
        fname +
        'As<T>(T Function(Object?) fromJson, ' +
        sig +
        ') async {');
    sbClient.writeln('  final r = await ' + fname + '(' + argsNamed + ');');
    sbClient.writeln('  return fromJson(r.data);');
    sbClient.writeln('}');
    sbClient.writeln('');

    // API-style typed wrapper returning backend return type, using typed function params
    final tparams =
        (e['tparams'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
    final ttypes = (e['ttypes'] ?? '').split(',');
    final rtype = (e['rtype'] ?? '').trim();
    if (rtype.isNotEmpty &&
        rtype.toLowerCase() != 'responsetype' &&
        rtype.toLowerCase() != 'response') {
      // build typed signature
      final bufSig = StringBuffer();
      bufSig.write('{ ');
      for (var i2 = 0; i2 < tparams.length; i2++) {
        final tn = tparams[i2];
        final tt = (i2 < ttypes.length && ttypes[i2].trim().isNotEmpty)
            ? ttypes[i2].trim()
            : 'String';
        bufSig.write('required ' + tt + ' ' + tn);
        if (i2 != tparams.length - 1) bufSig.write(', ');
      }
      if (tparams.isNotEmpty) bufSig.write(', ');
      bufSig.write(
          'Map<String, dynamic>? query, Object? body, Map<String, String>? headers }');
      final sigApi = bufSig.toString();

      // determine which typed params are path placeholders
      final colonNames = names.toSet();
      // build path pp from placeholders
      final ppPairs = tparams
          .where((p) => colonNames.contains(p))
          .map((p) => "'" + p + "': " + p)
          .join(', ');
      final ppExpr = (ppPairs.isEmpty)
          ? 'const <String,Object?>{}'
          : '{ ' + ppPairs + ' }';
      // build form body map merging provided query + typed params not in path (for non-GET)
      final qpLines = <String>[];
      for (var j = 0; j < tparams.length; j++) {
        final pName = tparams[j];
        if (colonNames.contains(pName)) continue;
        final pType = (j < ttypes.length ? ttypes[j] : '').trim();
        if (pType.startsWith('List<String')) {
          qpLines.add("qq['" +
              pName +
              "'] = (" +
              pName +
              ").map((e)=>e.toString()).join(',');");
        } else {
          qpLines.add("qq['" + pName + "'] = (" + pName + ").toString();");
        }
      }
      final qpAdd = qpLines.join('\n  ');

      final fnameApi = fname + 'Api';
      // Determine conversion expression for known simple return types.
      String conv(String t) {
        final tt = t.replaceAll(' ', '');
        if (tt == 'String') return 'r.data as String';
        if (tt == 'int')
          return "(r.data is int) ? (r.data as int) : (int.tryParse(r.data?.toString() ?? '') ?? 0)";
        if (tt == 'double')
          return "(r.data is double) ? (r.data as double) : (double.tryParse(r.data?.toString() ?? '') ?? 0.0)";
        if (tt == 'num')
          return "(r.data is num) ? (r.data as num) : (num.tryParse(r.data?.toString() ?? '') ?? 0)";
        if (tt == 'bool')
          return "(r.data is bool) ? (r.data as bool) : ((r.data?.toString().toLowerCase() ?? '') == 'true')";
        if (tt.startsWith('List<String')) {
          return "(r.data as List).map((e)=>e.toString()).toList() as ${t}";
        }
        if (tt.startsWith('List<int')) {
          return "(r.data as List).map((e){ if (e is int) return e; return int.tryParse(e?.toString() ?? '') ?? 0; }).toList() as ${t}";
        }
        if (tt.startsWith('List<double')) {
          return "(r.data as List).map((e){ if (e is double) return e; return double.tryParse(e?.toString() ?? '') ?? 0.0; }).toList() as ${t}";
        }
        if (tt.startsWith('List<bool')) {
          return "(r.data as List).map((e)=> (e is bool) ? e : ((e?.toString().toLowerCase() ?? '') == 'true')).toList() as ${t}";
        }
        if (tt.startsWith('Map<String,dynamic') ||
            tt.startsWith('Map<String,Object')) {
          return "Map<String, dynamic>.from(r.data as Map) as ${t}";
        }
        // Fallback: require a mapper
        return '';
      }

      final convExpr = conv(rtype);
      if (convExpr.isEmpty) {
        // Custom type – require a mapper
      final sigApiMapper = sigApi.replaceFirst(
            ' }', ", required ${rtype} Function(Object?) fromJson }");
        sbClient.writeln('Future<' +
            rtype +
            '> ' +
            fnameApi +
            '(' +
            sigApiMapper +
            ') async {');
      } else {
        sbClient.writeln(
            'Future<' + rtype + '> ' + fnameApi + '(' + sigApi + ') async {');
      }
      sbClient
          .writeln("  var routePath = '" + colon.replaceAll("'", "\\'") + "';");
      sbClient.writeln('  final Map<String, Object?> pp = ' + ppExpr + ';');
      sbClient.writeln(
          "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
      sbClient.writeln('  final base = DartvelRuntime.api(routePath);');
      // Build both query and form bodies; choose at runtime per method
      final qp = StringBuffer();
      qp.writeln('  final qq = <String, String>{};');
      qp.writeln(
          "  if (query != null) { query.forEach((k, v) { qq[k] = v?.toString() ?? ''; }); }");
      if (qpAdd.isNotEmpty) qp.writeln('  ' + qpAdd);
      sbClient.writeln(qp.toString());
      sbClient.writeln('  final fb = <String, dynamic>{};');
      for (var j = 0; j < tparams.length; j++) {
        final pName = tparams[j];
        if (!names.contains(pName)) {
          sbClient.writeln("  fb['" + pName + "'] = " + pName + ";");
        }
      }
      sbClient.writeln(
          "  if (query != null) { query.forEach((k, v) { fb[k] = v; }); }");
      sbClient.writeln("  final _M = '" + method.toUpperCase() + "';");
      sbClient.writeln(
          "  final uri = (_M == 'GET' || _M == 'HEAD') ? base.replace(queryParameters: qq) : base;");
      sbClient.writeln(
          "  final _hdrs = (_M == 'GET' || _M == 'HEAD') ? (headers ?? const {}) : (headers ?? const {});");
      if (method == 'post') {
        // Enforce multipart form-data for POST typed API methods
        sbClient.writeln(
            "  final _payload = (_M == 'GET' || _M == 'HEAD') ? body : ((body is FormData) ? body : (body == null ? FormData.fromMap(fb) : (body is Map ? FormData.fromMap(Map<String,dynamic>.from(body as Map)) : body)));");
      } else {
        sbClient.writeln(
            "  final _payload = (_M == 'GET' || _M == 'HEAD') ? body : ((body is FormData) ? body : (body ?? fb));");
      }
      sbClient.writeln("  final r = await _dvRequest('" +
          method +
          "', uri, data: _payload, headers: _hdrs);");
      if (convExpr.isEmpty) {
        sbClient.writeln('  return fromJson(r.data);');
      } else {
        sbClient.writeln('  return ' + convExpr + ';');
      }
      sbClient.writeln('}');
      sbClient.writeln('');
    }
  }

  File(p.join(libClientDir.path, 'functions.g.dart'))
      .writeAsStringSync(sbClient.toString());

  // Update .gitignore to exclude generated files (idempotent)
  final gitignore = File(p.join(root, '.gitignore'));
  final desired = <String>{
    '/lib/dartvel_client/',
    '/.dart_tool/dartvel_backend.g.dart',
    '/.dart_tool/dartvel_backend_routes.g.dart',
  };
  try {
    final lines =
        gitignore.existsSync() ? gitignore.readAsLinesSync() : <String>[];
    final set = {...lines};
    var changed = false;
    for (final l in desired) {
      if (!set.contains(l)) {
        lines.add(l);
        changed = true;
      }
    }
    if (changed) gitignore.writeAsStringSync(lines.join('\n') + '\n');
  } catch (_) {}

  stdout.writeln(
      'dartvel: generated lib/dartvel_client/* and .dart_tool/dartvel_backend*.g.dart (build ' +
          buildId +
          ')');
}

Future<int> _doctor() async {
  int warnings = 0;
  final root = Directory.current.path;
  final pubspecFile = File(p.join(root, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    stderr.writeln('doctor: pubspec.yaml not found at project root');
    return 2;
  }
  final yaml = loadYaml(await pubspecFile.readAsString()) as YamlMap;
  final deps = (yaml['dependencies'] ?? {}) as YamlMap;
  final devDeps = (yaml['dev_dependencies'] ?? {}) as YamlMap;
  final dv = (yaml['dartvel'] ?? {}) as YamlMap;

  bool _hasDep(String name) =>
      deps.containsKey(name) || devDeps.containsKey(name);

  void warn(String msg) {
    warnings++;
    stdout.writeln('WARN: ' + msg);
  }

  stdout.writeln('dartvel doctor:');

  // Check essential deps
  if (!_hasDep('go_router'))
    warn('Missing dependency: go_router (required by router)');
  if (!_hasDep('dartvel_flutter')) warn('Missing dependency: dartvel_flutter');

  // Config keys
  final pagesDir = (dv['pagesDir'] ?? 'lib/pages').toString();
  final backendDir = (dv['backendDir'] ?? 'lib/backend').toString();
  final devBackendHost = (dv['devBackendHost'] ?? '').toString();
  final prodBackendHost = (dv['prodBackendHost'] ?? '').toString();
  // Env files
  final envFiles = <String>[];
  if (dv['envFiles'] is YamlList) {
    for (final f in (dv['envFiles'] as YamlList)) {
      if (f != null) envFiles.add(f.toString());
    }
  } else {
    envFiles.addAll(['.env', '.env.local']);
  }

  // Paths
  final pagesPath = p.join(root, pagesDir);
  final backendPath = p.join(root, backendDir);
  final pagesExists = Directory(pagesPath).existsSync();
  final backendExists = Directory(backendPath).existsSync();

  stdout.writeln(
      '• pagesDir: ' + pagesDir + (pagesExists ? ' (ok)' : ' (missing)'));
  if (!pagesExists) warn('pagesDir does not exist: ' + pagesDir);
  stdout.writeln(
      '• backendDir: ' + backendDir + (backendExists ? ' (ok)' : ' (missing)'));
  if (!backendExists) warn('backendDir does not exist: ' + backendDir);

  // Pages presence
  if (pagesExists) {
    final glob = Glob(p.join(pagesDir, '**.page.dart'));
    final fs = const LocalFileSystem();
    final list = glob.listFileSystemSync(fs, root: root, followLinks: false);
    final count = list.length;
    stdout.writeln('• pages found: ' + count.toString());
    if (count == 0)
      warn('No pages found under ' + pagesDir + ' (need *.page.dart)');

    // Detect route conflicts
    String routeFor(String rel) {
      var path =
          rel.replaceFirst(RegExp('^$pagesDir/?'), '').replaceAll('\\\\', '/');
      path = path.replaceFirst(RegExp(r'\.page\.dart$'), '');
      if (path == 'index') return '/';
      path = path.replaceAllMapped(RegExp(r'\(([^)]+)\)/'), (m) => '');
      path = path.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) {
        final seg = m.group(1)!;
        if (seg.startsWith('...')) return '*' + seg.substring(3);
        return ':' + seg;
      });
      path = path.replaceFirst(RegExp(r'/index$'), '');
      if (path.isEmpty) return '/';
      return '/' + path;
    }

    final routeMap = <String, List<String>>{};
    for (final ent in list) {
      final abs = ent.path;
      final rel = p.relative(abs, from: root).replaceAll('\\\\', '/');
      if (p.basename(rel) == '_layout.page.dart') continue;
      final r = routeFor(rel);
      (routeMap[r] ??= <String>[]).add(rel);
    }
    final conflicts = routeMap.entries.where((e) => e.value.length > 1);
    if (conflicts.isNotEmpty) {
      for (final c in conflicts) {
        warn('Route conflict for "' + c.key + '" from:');
        for (final f in c.value) {
          stdout.writeln('   - ' + f);
        }
      }
    }
  }

  // Backend functions
  final fnGlob = Glob(p.join(backendDir, 'functions/**.dart'));
  final fs = const LocalFileSystem();
  final methodSet = {
    'get',
    'post',
    'put',
    'patch',
    'delete',
    'head',
    'options'
  };
  int fnCount = 0;
  for (final e
      in fnGlob.listFileSystemSync(fs, root: root, followLinks: false)) {
    final rel = p.relative(e.path, from: root).replaceAll('\\\\', '/');
    final base = p.basenameWithoutExtension(rel);
    final dot = base.lastIndexOf('.');
    final method = (dot != -1) ? base.substring(dot + 1).toLowerCase() : '';
    // Count functions even without explicit method suffix (defaults to GET)
    if (method.isEmpty || methodSet.contains(method)) fnCount++;
  }
  stdout.writeln('• backend functions: ' + fnCount.toString());
  if (fnCount == 0)
    warn('No backend functions found under ' + backendDir + '/functions');

  // prodBackendHost
  if (prodBackendHost.isEmpty) {
    warn('prodBackendHost is empty (required for build)');
  } else {
    stdout.writeln('• devBackendHost: ' + devBackendHost);
    stdout.writeln('• prodBackendHost: ' + prodBackendHost);
  }

  // Env file checks
  final foundEnv = <String>[];
  final publicKeys = <String>{};
  for (final f in envFiles) {
    final file = File(p.join(root, f));
    if (!file.existsSync()) {
      warn('Env file missing: ' + f);
      continue;
    }
    foundEnv.add(f);
    try {
      for (final line in file.readAsLinesSync()) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        final i = t.indexOf('=');
        if (i <= 0) continue;
        final key = t.substring(0, i).trim();
        if (key.startsWith('PUBLIC_')) publicKeys.add(key);
      }
    } catch (_) {}
  }
  if (foundEnv.isEmpty) {
    warn('No env files found (checked: ' + envFiles.join(', ') + ')');
  } else {
    stdout.writeln('• env files: ' + foundEnv.join(', '));
  }
  if (publicKeys.isEmpty) {
    warn('No PUBLIC_* keys found in env files (env.g.dart will be empty)');
  } else {
    stdout.writeln('• PUBLIC_* keys: ' + publicKeys.length.toString());
  }

  stdout.writeln(warnings == 0
      ? 'Doctor finished with no issues.'
      : 'Doctor finished with ' + warnings.toString() + ' warning(s).');
  return warnings == 0 ? 0 : 0; // non-fatal
}

Future<void> _watch() async {
  final root = Directory.current.path;
  final pubspecFile = File(p.join(root, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    stderr.writeln('watch: pubspec.yaml not found at project root');
    exit(2);
  }
  final yaml = loadYaml(await pubspecFile.readAsString()) as YamlMap;
  final dv = (yaml['dartvel'] ?? {}) as YamlMap;
  final pagesDir = (dv['pagesDir'] ?? 'lib/pages').toString();
  final backendDir = (dv['backendDir'] ?? 'lib/backend').toString();

  stdout.writeln('dartvel watch: watching for changes (Ctrl-C to stop) ...');
  await _generate();

  final watchers = <Stream<WatchEvent>>[
    DirectoryWatcher(p.join(root, pagesDir)).events,
    DirectoryWatcher(p.join(root, backendDir)).events,
    FileWatcher(p.join(root, 'pubspec.yaml')).events,
  ];

  Timer? debounce;
  void scheduleGen() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () async {
      stdout.writeln('[watch] change detected → regenerating...');
      await _generate();
    });
  }

  for (final s in watchers) {
    s.listen((_) => scheduleGen());
  }

  // keep running
  await Completer<void>().future;
}

int _asInt(Object? v, int dflt) {
  if (v is int) return v;
  if (v is String) {
    final n = int.tryParse(v);
    if (n != null) return n;
  }
  return dflt;
}

Future<void> _preview(ArgResults cmd) async {
  final dir = (cmd['dir'] as String?)?.trim().isNotEmpty == true
      ? (cmd['dir'] as String)
      : 'build/web';
  final host = (cmd['host'] as String?)?.trim().isNotEmpty == true
      ? (cmd['host'] as String)
      : '127.0.0.1';
  final port = _asInt(cmd['port'], 4321);

  final abs = p.normalize(p.join(Directory.current.path, dir));
  if (!Directory(abs).existsSync()) {
    stderr.writeln('[preview] Directory not found: ' + abs);
    stderr.writeln('Run a build first or pass --dir to an existing folder.');
    exit(2);
  }

  final app = dvs.DartvelShelf();
  app.use('log');
  app.static('/', dir: abs);
  await app.listen(address: host, port: port);
  stdout.writeln('[preview] Serving ' +
      abs +
      ' at http://' +
      host +
      ':' +
      port.toString());
  stdout.writeln('[preview] Press Ctrl-C to stop.');
  await Completer<void>().future;
}

String _esc(String s) => s.replaceAll(r'$', r'\\$').replaceAll("'", r"\\'");

bool _asBool(Object? v, bool dflt) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return dflt;
}

String _transitionEnum(String v) {
  switch (v) {
    case 'none':
      return 'DvTransition.none';
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
    default:
      return 'DvTransition.fade';
  }
}

String _curveExpr(String v) {
  switch (v) {
    case 'linear':
      return 'Curves.linear';
    case 'easeIn':
      return 'Curves.easeIn';
    case 'easeOut':
      return 'Curves.easeOut';
    case 'easeInOut':
      return 'Curves.easeInOut';
    case 'decelerate':
      return 'Curves.decelerate';
    default:
      return 'Curves.easeInOut';
  }
}

Future<void> _dev(ArgResults cmd) async {
  final root = Directory.current.path;
  await _generate();

  // Ensure a dev server entry under .dart_tool
  final toolDir = Directory(p.join(root, '.dart_tool'))
    ..createSync(recursive: true);
  final devServer = File(p.join(toolDir.path, 'dartvel_dev_server.dart'));
  // Always rewrite to ensure latest runtime (switch from shelf to dartvel_shelf)
  devServer.writeAsStringSync('''
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'dartvel_backend.g.dart' as cfg;
import 'dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  // ignore: avoid_print
  print('dartvel backend build: ' + (cfg.dvGenBuildId));
  final app = gen.buildBackend();
  await app.listen(address: '0.0.0.0', port: cfg.backendPort);
  // Print a friendly line (DartvelShelf does not expose the bound address here)
  // Assume localhost for convenience in logs.
  // ignore: avoid_print
  print('dartvel backend listening on http://localhost:' + cfg.backendPort.toString() + cfg.apiBasePath);
}
''');

  // Start processes: backend + flutter; add in-process file watching and stdin passthrough
  Process? backP;
  Process? flutterP;

  Future<Process> _spawn(String exe, List<String> args, String tag,
      {Map<String, String>? extraEnv}) async {
    final env = <String, String>{...Platform.environment, ...?extraEnv};
    final p = await Process.start(
      exe,
      args,
      runInShell: true,
      environment: env,
      includeParentEnvironment: true,
    );
    // Prefix logs with tag
    void _pipe(Stream<List<int>> s, IOSink out) {
      s
          .transform(SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => out.writeln('[' + tag + '] ' + line),
            onError: (e) => out.writeln('[' + tag + '][err] ' + e.toString()),
          );
    }

    _pipe(p.stdout, stdout);
    _pipe(p.stderr, stderr);
    p.exitCode.then((code) {
      stdout.writeln('[' + tag + '] exited with code ' + code.toString());
    });
    return p;
  }

  // Build flutter args
  final flutterArgs = <String>['run'];
  String? deviceOpt =
      (cmd['device'] as String?) ?? Platform.environment['DARTVEL_DEVICE'];
  if (deviceOpt == null || deviceOpt.isEmpty) {
    try {
      final proc = await Process.run('flutter', ['devices', '--machine'],
          runInShell: true);
      if ((proc.stdout as String).toString().trim().isNotEmpty) {
        final list = jsonDecode(proc.stdout as String) as List<Object?>;
        if (list.isEmpty) {
          stdout.writeln(
              '[dev] No devices found. You can pass -d chrome, -d linux, etc.');
        } else if (list.length == 1) {
          final id = (list.first as Map)['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            deviceOpt = id;
          }
        } else {
          stdout.writeln('Multiple devices detected. Select a device:');
          for (var i = 0; i < list.length; i++) {
            final m = list[i] as Map;
            final id = (m['id'] ?? '').toString();
            final name = (m['name'] ?? '').toString();
            final plat = (m['targetPlatform'] ?? '').toString();
            stdout.writeln('  [${i + 1}] $name • $id • $plat');
          }
          stdout.write('Enter number or device id (default 1): ');
          final sel = stdin.readLineSync()?.trim() ?? '';
          if (sel.isEmpty) {
            deviceOpt = (list.first as Map)['id']?.toString();
          } else {
            final n = int.tryParse(sel);
            if (n != null && n >= 1 && n <= list.length) {
              deviceOpt = (list[n - 1] as Map)['id']?.toString();
            } else {
              // assume user typed device id
              deviceOpt = sel;
            }
          }
        }
      }
    } catch (_) {}
  }
  if (deviceOpt != null && deviceOpt.isNotEmpty) {
    flutterArgs.addAll(['-d', deviceOpt]);
  }
  if (cmd['release'] == true) flutterArgs.add('--release');
  if (cmd['profile'] == true) flutterArgs.add('--profile');
  if (cmd['debug'] == true) flutterArgs.add('--debug');
  for (final dd in (cmd['dart-define'] as List<String>? ?? const [])) {
    flutterArgs.addAll(['--dart-define', dd]);
  }
  for (final ddf
      in (cmd['dart-define-from-file'] as List<String>? ?? const [])) {
    flutterArgs.addAll(['--dart-define-from-file', ddf]);
  }
  final webRenderer = cmd['web-renderer'] as String?;
  if (webRenderer != null && webRenderer.isNotEmpty) {
    flutterArgs.addAll(['--web-renderer', webRenderer]);
  }
  if (cmd['verbose'] == true) flutterArgs.add('-v');

  stdout.writeln('dartvel dev: starting backend and Flutter app...');
  try {
    // Try to locate native dartvel_shelf library and pass via env for backend
    Map<String, String>? extraEnv;
    try {
      String libName;
      if (Platform.isLinux)
        libName = 'libdartvel_shelf.so';
      else if (Platform.isMacOS)
        libName = 'libdartvel_shelf.dylib';
      else if (Platform.isWindows)
        libName = 'dartvel_shelf.dll';
      else
        libName = 'libdartvel_shelf.so';
      final candidates = <String>[
        p.join(root, libName),
        p.normalize(p.join(
            root, '../../packages/dartvel_shelf/rust/target/release', libName)),
        p.normalize(p.join(
            root, '../packages/dartvel_shelf/rust/target/release', libName)),
        p.normalize(p.join(
            root, 'packages/dartvel_shelf/rust/target/release', libName)),
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) {
          extraEnv = {'DARTVEL_SHELF_LIB': c};
          break;
        }
      }
    } catch (_) {}
    // Always add debug env that helps diagnose native crashes
    extraEnv = {
      ...?extraEnv,
      'RUST_BACKTRACE': '1',
      'MALLOC_CHECK_': '3',
    };
    backP = await _spawn(
        'dart', ['run', '.dart_tool/dartvel_dev_server.dart'], 'backend',
        extraEnv: extraEnv);
  } catch (_) {
    stdout.writeln('WARN: failed to start backend');
  }
  try {
    flutterP = await _spawn('flutter', flutterArgs, 'flutter');
  } catch (_) {
    stdout.writeln(
        'WARN: failed to start Flutter app. Ensure Flutter SDK is installed.');
  }

  // Wire stdin to Flutter for hot reload commands
  if (flutterP != null) {
    stdin.listen((data) {
      try {
        flutterP!.stdin.add(data);
      } catch (_) {}
    });
  }

  // Watch for changes and regenerate + restart backend
  try {
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    final yaml = loadYaml(await pubspecFile.readAsString()) as YamlMap;
    final dv = (yaml['dartvel'] ?? {}) as YamlMap;
    final pagesDir = (dv['pagesDir'] ?? 'lib/pages').toString();
    final backendDir = (dv['backendDir'] ?? 'lib/backend').toString();

    final streams = <Stream<WatchEvent>>[
      DirectoryWatcher(p.join(root, pagesDir)).events,
      DirectoryWatcher(p.join(root, backendDir)).events,
      FileWatcher(p.join(root, 'pubspec.yaml')).events,
    ];
    Timer? debounce;
    Future<void> restartBackend() async {
      if (debounce != null && debounce!.isActive) debounce!.cancel();
      debounce = Timer(const Duration(milliseconds: 250), () async {
        stdout.writeln(
            '[dev] change detected → regenerating and restarting backend...');
        await _generate();
        try {
          await backP?.kill(ProcessSignal.sigterm);
        } catch (_) {}
        try {
          backP = await _spawn(
              'dart', ['run', '.dart_tool/dartvel_dev_server.dart'], 'backend');
        } catch (_) {}
      });
    }

    for (final s in streams) {
      s.listen((_) => restartBackend());
    }
  } catch (e) {
    stdout.writeln('WARN: watcher failed: ' + e.toString());
  }

  // Keep running until one exits
  await Future.any([
    if (backP != null) backP!.exitCode,
    if (flutterP != null) flutterP!.exitCode,
  ].whereType<Future<int>>());
}
