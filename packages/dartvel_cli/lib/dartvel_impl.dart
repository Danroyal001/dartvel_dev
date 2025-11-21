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

void _log(String message) => stdout.writeln('[dartvel] ' + message);

enum _PackageManager { apt, dnf, yum, pacman, zypper, apk }

class _LinuxDependency {
  final String binary;
  final String description;
  final Map<_PackageManager, List<String>> packages;

  const _LinuxDependency(
      {required this.binary,
      required this.description,
      required this.packages});

  List<String> packagesFor(_PackageManager manager) =>
      packages[manager] ?? const <String>[];
}

const List<_LinuxDependency> _linuxDependencies = [
  _LinuxDependency(
    binary: 'ninja',
    description: 'Ninja build tool',
    packages: {
      _PackageManager.apt: ['ninja-build'],
      _PackageManager.dnf: ['ninja-build'],
      _PackageManager.yum: ['ninja-build'],
      _PackageManager.pacman: ['ninja'],
      _PackageManager.zypper: ['ninja'],
      _PackageManager.apk: ['ninja'],
    },
  ),
  _LinuxDependency(
    binary: 'cmake',
    description: 'CMake build system',
    packages: {
      _PackageManager.apt: ['cmake'],
      _PackageManager.dnf: ['cmake'],
      _PackageManager.yum: ['cmake'],
      _PackageManager.pacman: ['cmake'],
      _PackageManager.zypper: ['cmake'],
      _PackageManager.apk: ['cmake'],
    },
  ),
  _LinuxDependency(
    binary: 'pkg-config',
    description: 'pkg-config utility',
    packages: {
      _PackageManager.apt: ['pkg-config'],
      _PackageManager.dnf: ['pkgconf-pkg-config'],
      _PackageManager.yum: ['pkgconfig'],
      _PackageManager.pacman: ['pkgconf'],
      _PackageManager.zypper: ['pkg-config'],
      _PackageManager.apk: ['pkgconf'],
    },
  ),
  _LinuxDependency(
    binary: 'clang',
    description: 'Clang compiler',
    packages: {
      _PackageManager.apt: ['clang'],
      _PackageManager.dnf: ['clang'],
      _PackageManager.yum: ['clang'],
      _PackageManager.pacman: ['clang'],
      _PackageManager.zypper: ['clang'],
      _PackageManager.apk: ['clang'],
    },
  ),
  _LinuxDependency(
    binary: 'ld.lld',
    description: 'LLVM LLD linker',
    packages: {
      _PackageManager.apt: ['lld'],
      _PackageManager.dnf: ['lld'],
      _PackageManager.yum: ['lld'],
      _PackageManager.pacman: ['lld'],
      _PackageManager.zypper: ['lld'],
      _PackageManager.apk: ['lld'],
    },
  ),
];

Future<void> main(List<String> args) async {
  final mainParser = ArgParser()
    ..addCommand('routes')
    ..addCommand('build')
    ..addCommand('doctor')
    ..addCommand('watch');

  final newParser = ArgParser()
    ..addOption('template', help: 'Starter template to use', defaultsTo: 'app')
    ..addFlag('force',
        help: 'Overwrite existing directory if present', defaultsTo: false)
    ..addFlag('overwrite', help: 'Alias for --force', defaultsTo: false);
  mainParser.addCommand('new', newParser);

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

  mainParser.addCommand('dev', devParser);
  mainParser.addCommand('run', devParser);

  final previewParser = ArgParser()
    ..addOption('dir', defaultsTo: 'build/web')
    ..addOption('host', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '4321');
  mainParser.addCommand('preview', previewParser);

  final result = mainParser.parse(args);

  final cmd = result.command?.name ?? 'help';
  switch (cmd) {
    case 'routes':
      await _generate();
      stdout.writeln('Generated routes and client artifacts.');
      break;
    case 'new':
      await _new(result.command!);
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
    case '--help':
    case 'help':
    default:
      _help();
      break;
  }
}

void _help() {
  stdout.writeln('Usage:');
  stdout.writeln('  dartvel <routes|dev|build|doctor|watch|preview> ');
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
import 'dart:typed_data';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'dartvel_backend.g.dart' as cfg;
${backendImports.join('\n')}

// Multipart structures and parser (bytes): collects text fields and files
class DvMultipartFile {
  final String name;
  final String filename;
  final String contentType;
  final Uint8List bytes;
  DvMultipartFile(this.name, this.filename, this.contentType, this.bytes);
}

Map<String, dynamic> _parseMultipartForm(
    Uint8List body, String contentType) {
  final match = RegExp(r"boundary=([^;]+)").firstMatch(contentType);
  if (match == null) return <String, dynamic>{};

  final boundary = "--" + match.group(1)!;
  final boundaryBytes = Uint8List.fromList(conv.latin1.encode(boundary));

  int idxOf(Uint8List data, Uint8List pattern, int start) {
    for (var i = start; i <= data.length - pattern.length; i++) {
      var ok = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  final out = <String, dynamic>{};
  var pos = 0;
  final first = idxOf(body, boundaryBytes, pos);
  if (first == -1) return out;
  pos = first + boundaryBytes.length + 2;

  final crlf2 = Uint8List.fromList(const [13, 10, 13, 10]);

  while (pos < body.length) {
    final headerEnd = idxOf(body, crlf2, pos);
    if (headerEnd == -1) break;
    final header =
        conv.latin1.decode(body.sublist(pos, headerEnd));
    pos = headerEnd + 4;
    var next = idxOf(body, boundaryBytes, pos);
    if (next == -1) next = body.length;
    var end = next - 2;
    if (end < pos) end = pos;
    final part = Uint8List.fromList(body.sublist(pos, end));
    pos = next + boundaryBytes.length + 2;

    final cd = RegExp('content-disposition:[^\\r\\n]*',
            caseSensitive: false)
        .firstMatch(header);
    if (cd == null) continue;
    final nameMatch = RegExp('name="([^"]+)"')
        .firstMatch(cd.group(0)!);
    if (nameMatch == null) continue;
    final fieldName = nameMatch.group(1)!;
    final fileMatch =
        RegExp('filename="([^"]*)"').firstMatch(cd.group(0)!);
    var contentType = '';
    final ctMatch = RegExp('content-type:\\s*([^\\r\\n]+)',
            caseSensitive: false)
        .firstMatch(header);
    if (ctMatch != null) contentType = ctMatch.group(1)!.trim();

    if (fileMatch != null) {
      final filename = fileMatch.group(1) ?? '';
      out[fieldName] =
          DvMultipartFile(fieldName, filename, contentType, part);
    } else {
      out[fieldName] = conv.utf8.decode(part, allowMalformed: true);
    }

    if (next + boundaryBytes.length + 4 <= body.length) {
      final tail = conv.latin1.decode(body.sublist(
          next, (next + boundaryBytes.length + 4).clamp(0, body.length)));
      if (tail.startsWith(boundary + '--')) break;
    }
  }
  return out;
}

dv.Router buildBackendRouter() {
  final router = dv.Router();
  bool _hasHealth = false;
${backendEntries.map((e) {
    final path = _esc(e['path'] ?? '');
    final method = e['method']!;
    final i = e['i']!;
    final typed = e['typed'] ?? '';
    if (typed.isEmpty) {
      return "  router." +
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
    if (path == '/health' && method.toLowerCase() == 'get') {
      return "  _hasHealth = true;\n" +
          '''  router.${method}(cfg.apiBasePath + '${path}', (dv.Request req) async {
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
    return '''  router.${method}(cfg.apiBasePath + '${path}', (dv.Request req) async {
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
  if (!_hasHealth) {
    router.get(cfg.apiBasePath + '/health', (dv.Request _) async => dv.Response.text('ok'));
  }
  return router;
}

dv.Router buildBackend() => buildBackendRouter();

Future<dv.ServerHandle> startBackend({String? host, int? port, dv.TlsConfig? tls, bool h2c = false}) {
  final router = buildBackendRouter();
  final bindHost = host ?? cfg.backendHost;
  final bindPort = port ?? cfg.backendPort;
  return dv.serve(router.call, host: bindHost, port: bindPort, tls: tls, h2c: h2c);
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
      "  var send = (data == null && m != 'GET' && m != 'HEAD') ? '' : data;");
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
      sbClient.writeln(
          "  final _hdrs = <String,String>{...?(headers ?? const {})};");
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

  Future<dvs.Response> _serveStatic(dvs.Request req) async {
    final rawPath = req.url.path;
    final rel = rawPath == '/' ? 'index.html' : rawPath.substring(1);
    final resolved = p.normalize(p.join(abs, rel));
    if (!p.isWithin(abs, resolved)) {
      return dvs.Response.text('Forbidden', status: 403);
    }
    final file = File(resolved);
    if (!file.existsSync()) {
      return dvs.Response.text('Not Found', status: 404);
    }
    final bytes = await file.readAsBytes();
    final headers = dvs.Headers();
    if (resolved.endsWith('.html')) {
      headers.set('content-type', 'text/html; charset=utf-8');
    } else if (resolved.endsWith('.css')) {
      headers.set('content-type', 'text/css; charset=utf-8');
    } else if (resolved.endsWith('.js')) {
      headers.set('content-type', 'application/javascript; charset=utf-8');
    } else if (resolved.endsWith('.json')) {
      headers.set('content-type', 'application/json; charset=utf-8');
    } else if (resolved.endsWith('.png')) {
      headers.set('content-type', 'image/png');
    } else if (resolved.endsWith('.jpg') || resolved.endsWith('.jpeg')) {
      headers.set('content-type', 'image/jpeg');
    } else if (resolved.endsWith('.svg')) {
      headers.set('content-type', 'image/svg+xml');
    } else {
      headers.set('content-type', 'application/octet-stream');
    }
    return dvs.Response(200,
        headers: headers, body: Stream<List<int>>.value(bytes));
  }

  final router = dvs.Router()
    ..get('/', _serveStatic)
    ..get('/:rest(.*)', _serveStatic);

  final handle = await dvs.serve(router.call, host: host, port: port);
  stdout.writeln('[preview] Serving ' +
      abs +
      ' at http://' +
      handle.host +
      ':' +
      handle.port.toString());
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

Future<String?> _resolveExecutable(String command) async {
  try {
    final result = await Process.run('which', [command]);
    if (result.exitCode != 0) return null;
    final out = result.stdout;
    if (out is String) {
      final trimmed = out.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (out is List<int>) {
      final text = utf8.decode(out).trim();
      return text.isEmpty ? null : text;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<bool> _commandExists(String command) async =>
    (await _resolveExecutable(command)) != null;

Future<_PackageManager?> _detectPackageManager() async {
  const candidates = [
    (_PackageManager.apt, ['apt-get']),
    (_PackageManager.dnf, ['dnf']),
    (_PackageManager.yum, ['yum']),
    (_PackageManager.pacman, ['pacman']),
    (_PackageManager.zypper, ['zypper']),
    (_PackageManager.apk, ['apk']),
  ];
  for (final (manager, commands) in candidates) {
    for (final name in commands) {
      if (await _commandExists(name)) {
        return manager;
      }
    }
  }
  return null;
}

String _packageManagerLabel(_PackageManager manager) {
  switch (manager) {
    case _PackageManager.apt:
      return 'apt';
    case _PackageManager.dnf:
      return 'dnf';
    case _PackageManager.yum:
      return 'yum';
    case _PackageManager.pacman:
      return 'pacman';
    case _PackageManager.zypper:
      return 'zypper';
    case _PackageManager.apk:
      return 'apk';
  }
}

bool _isRootUser() {
  final uid = Platform.environment['EUID'] ?? Platform.environment['UID'];
  if (uid == '0') return true;
  final user = Platform.environment['USER'];
  return user == 'root';
}

bool _isLinuxDevice(String? deviceId) {
  if (deviceId == null || deviceId.isEmpty) return false;
  final id = deviceId.toLowerCase();
  return id == 'linux' || id.startsWith('linux-') || id.contains('/linux');
}

List<String>? _buildInstallCommand(
    _PackageManager manager, List<String> packages) {
  if (packages.isEmpty) return null;
  final needsSudo = !_isRootUser();
  final prefix = <String>[];
  if (needsSudo) prefix.add('sudo');
  switch (manager) {
    case _PackageManager.apt:
      return [...prefix, 'apt-get', 'install', '-y', ...packages];
    case _PackageManager.dnf:
      return [...prefix, 'dnf', 'install', '-y', ...packages];
    case _PackageManager.yum:
      return [...prefix, 'yum', 'install', '-y', ...packages];
    case _PackageManager.pacman:
      return [...prefix, 'pacman', '-Sy', '--noconfirm', ...packages];
    case _PackageManager.zypper:
      return [...prefix, 'zypper', '--non-interactive', 'install', ...packages];
    case _PackageManager.apk:
      return [...prefix, 'apk', 'add', '--no-cache', ...packages];
  }
}

Future<int> _runLoggedProcess(List<String> command,
    {String tag = 'cmd'}) async {
  _log('[$tag] executing: ' + command.join(' '));
  final process = await Process.start(command.first, command.sublist(1));
  final stdoutFuture = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) => _log('[$tag][out] ' + line));
  final stderrFuture = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) => _log('[$tag][err] ' + line));
  final code = await process.exitCode;
  await Future.wait([stdoutFuture, stderrFuture]);
  _log('[$tag] exit code ' + code.toString());
  return code;
}

Future<void> _ensureLinuxDependencies() async {
  if (!Platform.isLinux) {
    _log(
        'Skipping Linux dependency check (platform=${Platform.operatingSystem}).');
    return;
  }

  _log('Checking required Linux desktop dependencies...');
  final missing = <_LinuxDependency>[];
  for (final dep in _linuxDependencies) {
    final present = await _commandExists(dep.binary);
    if (present) {
      _log('Dependency present: ' + dep.binary);
    } else {
      _log('Dependency missing: ' + dep.binary + ' (' + dep.description + ')');
      missing.add(dep);
    }
  }

  if (missing.isEmpty) {
    _log('All required Linux dependencies are installed.');
    return;
  }

  final manager = await _detectPackageManager();
  if (manager == null) {
    _log(
        'Unable to detect supported package manager; install missing dependencies manually.');
    return;
  }

  _log('Detected package manager: ' + _packageManagerLabel(manager));
  final packages = <String>{};
  for (final dep in missing) {
    packages.addAll(dep.packagesFor(manager));
  }
  packages.removeWhere((pkg) => pkg.isEmpty);

  if (packages.isEmpty) {
    _log('No package mappings available for ' +
        _packageManagerLabel(manager) +
        '; install the missing tools manually.');
    return;
  }

  final command = _buildInstallCommand(manager, packages.toList()..sort());
  if (command == null) {
    _log(
        'Unable to construct install command; aborting automatic installation.');
    return;
  }

  _log('Attempting to install missing packages: ' + packages.join(', '));
  final code = await _runLoggedProcess(command, tag: 'deps');
  if (code == 0) {
    _log('Dependency installation completed successfully.');
  } else {
    _log('Dependency installation failed (exit code ' +
        code.toString() +
        '). Please install the packages manually.');
  }
}

Future<Map<String, String>> _flutterEnvOverrides() async {
  if (!Platform.isLinux) return const {};

  final overrides = <String, String>{};
  final snapNinja = File('/snap/flutter/current/usr/bin/ninja');
  if (!snapNinja.existsSync()) {
    final ninjaPath = await _resolveExecutable('ninja');
    if (ninjaPath != null) {
      _log(
          'Using system ninja at $ninjaPath for Flutter (snap binary missing).');
      overrides['FLUTTER_NINJA'] = ninjaPath;
      overrides['NINJA_PATH'] = ninjaPath;
      overrides['CMAKE_MAKE_PROGRAM'] = ninjaPath;
    } else {
      _log('Flutter snap ninja binary missing and no ninja found in PATH.');
    }
  }

  final lldPath =
      await _resolveExecutable('ld.lld') ?? await _resolveExecutable('lld');
  if (lldPath != null) {
    _log('Using linker at $lldPath for Flutter builds.');
    overrides['CMAKE_LINKER'] = lldPath;
    overrides['LD'] = lldPath;
    overrides['LLD_PATH'] = lldPath;
  } else {
    _log('LLD linker (ld.lld) not found; Flutter desktop builds may fail.');
  }

  return overrides;
}

Future<void> _resetFlutterLinuxBuildArtifacts(
    String projectRoot, Map<String, String> env) async {
  if (!Platform.isLinux) return;
  if (env.isEmpty) return;
  final buildDir = Directory(p.join(projectRoot, 'build', 'linux'));
  if (!buildDir.existsSync()) return;
  final targets = [
    File(p.join(buildDir.path, 'CMakeCache.txt')),
    File(p.join(buildDir.path, 'CMakeCache.txt.backup')), // just in case
    File(p.join(buildDir.path, 'build.ninja')),
    File(p.join(buildDir.path, 'x64', 'debug', 'CMakeCache.txt')),
    File(p.join(buildDir.path, 'x64', 'debug', 'build.ninja')),
    File(p.join(buildDir.path, 'x64', 'profile', 'CMakeCache.txt')),
    File(p.join(buildDir.path, 'x64', 'profile', 'build.ninja')),
    File(p.join(buildDir.path, 'x64', 'release', 'CMakeCache.txt')),
    File(p.join(buildDir.path, 'x64', 'release', 'build.ninja')),
  ];
  for (final file in targets) {
    if (file.existsSync()) {
      _log('Removing stale ${p.relative(file.path, from: projectRoot)}');
      try {
        await file.delete();
      } catch (err) {
        _log('Failed to delete ${file.path}: $err');
      }
    }
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
import 'dart:async';
import 'dartvel_backend.g.dart' as cfg;
import 'dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  // ignore: avoid_print
  print('dartvel backend build: ' + (cfg.dvGenBuildId));
  final handle = await gen.startBackend(host: '0.0.0.0', port: cfg.backendPort);
  // ignore: avoid_print
  print('dartvel backend listening on http://' + handle.host + ':' + handle.port.toString() + cfg.apiBasePath);
  await Completer<void>().future;
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

  final targetIsLinux = _isLinuxDevice(deviceOpt);
  if (targetIsLinux) {
    await _ensureLinuxDependencies();
  }

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
    Map<String, String> flutterEnv = const {};
    if (targetIsLinux) {
      flutterEnv = await _flutterEnvOverrides();
      await _resetFlutterLinuxBuildArtifacts(root, flutterEnv);
    }
    flutterP = await _spawn('flutter', flutterArgs, 'flutter',
        extraEnv: flutterEnv.isEmpty ? null : flutterEnv);
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

Future<void> _new(ArgResults cmd) async {
  final rest = cmd.rest;
  if (rest.isEmpty) {
    stderr.writeln('Usage: dartvel new <project_name> [--template app]');
    exit(2);
  }
  final projectName = rest.first;
  final targetDir = Directory(p.join(Directory.current.path, projectName));
  final force = (cmd['force'] as bool) || (cmd['overwrite'] as bool);
  if (targetDir.existsSync() && !force) {
    stderr.writeln('Directory "' +
        targetDir.path +
        '" already exists. Use --force to overwrite.');
    exit(3);
  }
  if (targetDir.existsSync() && force) {
    _log('Removing existing directory ' + targetDir.path + ' (force).');
    await targetDir.delete(recursive: true);
  }
  targetDir.createSync(recursive: true);

  String sanitize(String input) =>
      input.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
  final packageName = sanitize(projectName.toLowerCase());

  void writeFile(String relPath, String contents) {
    final file = File(p.join(targetDir.path, relPath));
    file.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  final pubspec = '''
name: $packageName
description: A new Dartvel project.
publish_to: "none"

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  dartvel_flutter:
    path: ../packages/dartvel_flutter
  dartvel_core:
    path: ../packages/dartvel_core

dev_dependencies:
  flutter_test:
    sdk: flutter
  lints: ^4.0.0

flutter:
  uses-material-design: true

dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  apiBasePath: /api
  pagesDir: lib/pages
  backendDir: lib/backend
  envFiles: [ .env, .env.local ]
''';
  writeFile('pubspec.yaml', pubspec.trim() + "\n");

  writeFile(
      'analysis_options.yaml', 'include: package:lints/recommended.yaml\n');

  final readme = '''# $projectName

Generated with `dartvel new`. Run the following to get started:

```
cd $projectName
flutter pub get
dart run dartvel_cli:dartvel dev
```

Project layout follows the recommended Dartvel structure.
''';
  writeFile('README.md', readme);

  const indexPage = '''import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Dartvel')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Hello from Dartvel starter template!'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/about'),
              child: const Text('Go to /about'),
            )
          ],
        ),
      ),
    );
  }
}
''';
  writeFile('lib/pages/index.page.dart', indexPage);

  const aboutPage = '''import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class AboutPage extends DartvelPage {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Center(
        child: Text('Edit lib/pages/about.page.dart to customise.'),
      ),
    );
  }
}
''';
  writeFile('lib/pages/about.page.dart', aboutPage);

  const layoutPage = '''import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class RootLayout extends DartvelLayout {
  const RootLayout({super.key, required super.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: child),
    );
  }
}
''';
  writeFile('lib/pages/_layout.page.dart', layoutPage);

  const helloFunction = '''import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
  final name = req.url.queryParameters['name'] ?? 'friend';
  return Res.json({'message': 'Hello, ' + name + '!'});
}
''';
  writeFile('lib/backend/functions/hello.get.dart', helloFunction);

  const echoFunction = '''import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
  final body = await req.body.jsonDecode();
  return Res.json({'echo': body});
}
''';
  writeFile('lib/backend/functions/echo.post.dart', echoFunction);

  const gitignore = '''/.dart_tool/
/build/
.env
.env.local
lib/dartvel_client/
''';
  writeFile('.gitignore', gitignore);

  File(p.join(targetDir.path, '.env'))
      .writeAsStringSync('PUBLIC_API_HOST=http://localhost:3000\n');

  stdout.writeln('Created Dartvel project in ' + targetDir.path + '.');
  stdout
      .writeln('Run `cd ' + projectName + ' && flutter pub get` to continue.');
}
