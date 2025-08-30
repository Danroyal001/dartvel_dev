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

  final result = parser.parse(args);

  final cmd = result.command?.name ?? 'help';
  switch (cmd) {
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
    pageEntries
        .add({'i': '$i', 'class': className, 'route': route, 'dir': dir});
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

  final routesSrc = pageEntries.map((e) => '''
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
        );

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
  ''').join(',\n');

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
  File(p.join(libClientDir.path, 'router.g.dart')).writeAsStringSync(router);

  // Backend bind config
  File(p.join(backendOut.path, 'dartvel_backend.g.dart')).writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_backend_config;
const String backendHost = '${_esc(backendHost)}';
const int    backendPort = $backendPort;
const String apiBasePath = '${_esc(apiBasePath)}';
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
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'dartvel_backend.g.dart' as cfg;
${backendImports.join('\n')}

Router buildBackendRouter() {
  final router = Router();
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
          "', f" +
          i +
          ".handler);";
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
    final _paramSig =
        List.generate(_paramCount, (i) => ', String p' + i.toString()).join();
    return '''  router.${method}(cfg.apiBasePath + '${path}', (Request req${_paramSig}) async {
    dynamic body;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        final ct = req.headers['content-type'] ?? '';
        final raw = await req.readAsString();
        if (ct.contains('application/json')) {
          body = raw.isEmpty ? null : conv.jsonDecode(raw);
        } else {
          body = raw;
        }
      }
    } catch (e) { /* ignore body read errors */ }
    try {
      final result = await f${i}.${typed}(${callArgs});
      if (result is Response) return result;
      if (result is Stream<List<int>>) return Response.ok(result);
      if (result is Stream) {
        final s = (result as Stream).map((e) => e is String ? conv.utf8.encode(e) : (e as List<int>));
        return Response.ok(s);
      }
      if (result is String) return Response.ok(result, headers: {'content-type': 'text/plain; charset=utf-8'});
      return Response.ok(conv.jsonEncode(result), headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e, st) {
      // Print a visible error for non-GET methods to aid debugging
      // ignore: avoid_print
      print('[dartvel backend] ERROR in ${method.toUpperCase()} ${path}: ' + e.toString());
      // ignore: avoid_print
      print(st);
      return Response.internalServerError(body: 'Internal Server Error');
    }
  });''';
  }).join('\n')}
  return router;
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
  sbClient.writeln('library dartvel_client_functions;');
  sbClient.writeln("import 'package:dio/dio.dart';");
  sbClient.writeln("import 'dartvel_runtime.dart';");
  sbClient
      .writeln("import 'package:$pkgName/dartvel_client/dartvel_client.dart';");
  sbClient.writeln('final Dio _dvDio = Dio();');
  sbClient.writeln(
      'Future<Response<dynamic>> _dvRequest(String method, Uri uri, {dynamic data, Map<String, String>? headers}) async {');
  sbClient.writeln(
      "  final hdrs = {...DartvelClient.defaultHeaders, ...?headers};");
  sbClient.writeln(
      "  return _dvDio.requestUri(uri, data: data, options: Options(method: method.toUpperCase(), headers: hdrs));");
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
        'Map<String, dynamic>? query, dynamic body, Map<String, String>? headers }';
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
        'Future<Response<dynamic>> ' + fname + '(' + sig + ') async {');
    sbClient
        .writeln("  var routePath = '" + colon.replaceAll("'", "\\'") + "';");
    sbClient.writeln('  final Map<String, Object?> pp = ' + paramMap + ';');
    sbClient.writeln(
        "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
    sbClient.writeln('  final base = DartvelRuntime.api(routePath);');
    sbClient.writeln('  final q = <String, String>{};');
    sbClient.writeln(
        '  if (query != null) { query.forEach((k, v) { q[k] = v?.toString() ?? \"\"; }); }');
    sbClient.writeln('  final uri = base.replace(queryParameters: q);');
    sbClient.writeln("  return _dvRequest('" +
        method +
        "', uri, data: body, headers: headers);");
    sbClient.writeln('}');
    sbClient.writeln('');

    // Data-only variant
    sbClient.writeln('Future<dynamic> ' + fname + 'Data(' + sig + ') async {');
    sbClient.writeln('  final r = await ' + fname + '(' + argsNamed + ');');
    sbClient.writeln('  return r.data;');
    sbClient.writeln('}');
    sbClient.writeln('');

    // Typed variant using a mapper
    sbClient.writeln('Future<T> ' +
        fname +
        'As<T>(T Function(dynamic) fromJson, ' +
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
    if (tparams.isNotEmpty &&
        rtype.isNotEmpty &&
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
          'Map<String, dynamic>? query, dynamic body, Map<String, String>? headers }');
      final sigApi = bufSig.toString();

      // determine which typed params are path placeholders
      final colonNames = names.toSet();
      // build path pp from placeholders
      final ppPairs = tparams
          .where((p) => colonNames.contains(p))
          .map((p) => "'" + p + "': " + p)
          .join(', ');
      final ppExpr = '{ ' + ppPairs + ' }';
      // build query map merging provided query with typed params not in path
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
      sbClient.writeln(
          'Future<' + rtype + '> ' + fnameApi + '(' + sigApi + ') async {');
      sbClient
          .writeln("  var routePath = '" + colon.replaceAll("'", "\\'") + "';");
      sbClient.writeln('  final Map<String, Object?> pp = ' + ppExpr + ';');
      sbClient.writeln(
          "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
      sbClient.writeln('  final base = DartvelRuntime.api(routePath);');
      sbClient.writeln('  final qq = <String, String>{};');
      sbClient.writeln(
          "  if (query != null) { query.forEach((k, v) { qq[k] = v?.toString() ?? \"\"; }); }");
      if (qpAdd.isNotEmpty) {
        sbClient.writeln('  ' + qpAdd);
      }
      sbClient.writeln('  final uri = base.replace(queryParameters: qq);');
      sbClient.writeln("  final r = await _dvRequest('" +
          method +
          "', uri, data: body, headers: headers);");
      sbClient.writeln('  return r.data as ' + rtype + ';');
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
      'dartvel: generated lib/dartvel_client/* and .dart_tool/dartvel_backend*.g.dart');
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
  if (!devServer.existsSync()) {
    devServer.writeAsStringSync('''
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:dartvel_core/dartvel.dart';
import 'dartvel_backend.g.dart' as cfg;
import 'dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(cors())
      .addHandler(gen.buildBackendRouter());
  final server = await io.serve(handler, InternetAddress.anyIPv4, cfg.backendPort);
  stdout.writeln('dartvel backend listening on http://\${server.address.host}:\${server.port}\${cfg.apiBasePath}');
}
''');
  }

  // Start processes: backend + flutter; add in-process file watching and stdin passthrough
  Process? backP;
  Process? flutterP;

  Future<Process> _spawn(String exe, List<String> args, String tag) async {
    final p = await Process.start(exe, args, runInShell: true);
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
        final list = jsonDecode(proc.stdout as String) as List<dynamic>;
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
    backP = await _spawn(
        'dart', ['run', '.dart_tool/dartvel_dev_server.dart'], 'backend');
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
