import 'dart:io';
import 'package:args/args.dart';
import 'package:glob/glob.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addCommand('routes')
    ..addCommand('dev')
    ..addCommand('build');

  final result = parser.parse(args);
  final cmd = result.command?.name ?? 'routes';
  switch (cmd) {
    case 'routes':
      await _generate();
      break;
    case 'dev':
      await _generate();
      stdout.writeln('Generated dartvel artifacts. Run your Flutter app & backend as usual.');
      break;
    case 'build':
      await _generate(validateProd: true);
      stdout.writeln('Generated production-ready artifacts.');
      break;
    default:
      stdout.writeln('Usage: dartvel [routes|dev|build]');
  }
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

  final devBackendHost = (dv['devBackendHost'] ?? 'http://localhost:$backendPort').toString();
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

  final transitions = (dv['webTransitions'] ?? dv['transitions'] ?? {}) as YamlMap;
  final defaultTransition = (transitions['default'] ?? 'fade').toString();
  final durationMs = _asInt(transitions['durationMs'], 220);
  final curve = (transitions['curve'] ?? 'easeInOut').toString();

  // Scan pages
  final pageGlob = Glob('$pagesDir/**.page.dart');
  final pageFiles = <File>[];
  final fs = const LocalFileSystem();
  for (final e in pageGlob.listFileSystemSync(fs, root: root, followLinks: false)) {
    final path = e.path;
    final ioFile = File(path);
    if (ioFile.existsSync()) pageFiles.add(ioFile);
  }
  pageFiles.sort((a, b) => a.path.compareTo(b.path));

  String _routeFor(String rel) {
    var path = rel.replaceFirst(RegExp('^$pagesDir/?'), '').replaceAll('\\', '/');
    path = path.replaceFirst(RegExp(r'\.page\.dart$'), '');
    if (path == 'index') return '/';
    path = path.replaceAllMapped(RegExp(r'\(([^)]+)\)/'), (m) => ''); // (group) folder – no URL
    path = path.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) {
      final seg = m.group(1)!;
      if (seg.startsWith('...')) return '*${seg.substring(3)}';
      return ':$seg';
    });
    return '/$path';
  }

  final pageImports = <String>[];
  final pageEntries = <Map<String, String>>[];

  for (var i = 0; i < pageFiles.length; i++) {
    final abs = pageFiles[i].path;
    final rel = p.relative(abs, from: root).replaceAll('\\', '/');
    final importPath = rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
    final base = p.basenameWithoutExtension(p.basenameWithoutExtension(rel));
    String className = base
        .replaceAll(RegExp(r'[\\[\\]\\.\\-_]'), ' ')
        .split(RegExp(r'\\s+'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join() +
        'Page';

    pageImports.add("import '$importPath' as p$i;");
    final route = _routeFor(rel);
    pageEntries.add({'i': '$i', 'class': className, 'route': route});
  }

  // Ensure dirs
  final clientDir = Directory(p.join(root, '.dart_tool', 'dartvel_client'))..createSync(recursive: true);
  final backendOut = Directory(p.join(root, '.dart_tool'))..createSync();

  // Client config
  File(p.join(clientDir.path, 'dartvel_config.g.dart')).writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_client_config;
const String dvBackendBindHost = '${_esc(backendHost)}';
const int    dvBackendPort      = $backendPort;
const String dvDevBackendHost   = '${_esc(devBackendHost)}';
const String dvProdBackendHost  = '${_esc(prodBackendHost)}';
const String dvApiBasePath      = '${_esc(apiBasePath)}';
''');

  // Client runtime helper
  File(p.join(clientDir.path, 'dartvel_runtime.dart')).writeAsStringSync('''
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'dartvel_config.g.dart' as cfg;

class DartvelRuntime {
  static const String _override = String.fromEnvironment('DARTVEL_BACKEND_URL', defaultValue: '');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    return kReleaseMode ? cfg.dvProdBackendHost : cfg.dvDevBackendHost;
  }

  static String get apiBasePath => cfg.dvApiBasePath;

  static Uri api(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final api  = apiBasePath.startsWith('/') ? apiBasePath : '/\$apiBasePath';
    final sub  = path.startsWith('/') ? path : '/\$path';
    return Uri.parse('\$base\$api\$sub');
  }
}
''');

  // Router
  final imports = ([
    "import 'package:flutter/material.dart';",
    "import 'package:go_router/go_router.dart';",
    "import 'package:dartvel_flutter/dartvel_flutter.dart';",
    ...pageImports
  ]).join('\\n');

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
    final esc = pattern.replaceAllMapped(RegExp(r'([.+*?^${}()\[\]|\\])'), (m) => '\\${m[1]}');
    final named = esc.replaceAllMapped(RegExp(r':([a-zA-Z0-9_]+)'), (m) => '(?<' + m[1]! + '>[^/]+)');
    return '^' + named + r'\$';
  }

  final routesSrc = pageEntries.map((e) => '''
    GoRoute(
      path: '${_esc(e['route']!)}',
      pageBuilder: (context, state) {
        final page = const p${e['i']}.${e['class']}();
        final params = Map<String, String>.from(state.pathParameters);
        final query  = Map<String, String>.from(state.uri.queryParameters);
        final withState = DartvelRouteState(params: params, query: query, child: page);

        // i18n scope (query strategy only; no-op if not configured)
        final _i18nParam = '${_esc(i18nParam)}';
        final _i18nDefault = '${_esc(i18nDefault)}';
        final _i18nLocales = <String>[$i18nLocalesLit];
        final langRaw = query[_i18nParam];
        final langTag = (_i18nLocales.isEmpty && _i18nDefault.isEmpty)
            ? (langRaw ?? '')
            : (DvI18n.normalize(langRaw, _i18nLocales, _i18nDefault.isEmpty ? (langRaw ?? '') : _i18nDefault));
        final withI18n = DvI18nScope(localeTag: langTag, child: withState);

        final seoWrapped = DartvelSeo(
          props: page.buildWebSeo(params, query),
          defaults: _defaultSeo,
          child: withI18n,
        );
        final spec = page.transition == const PageTransitionSpec()
            ? _projectDefaultTransition
            : page.transition;
        return dvTransitionPage(
          key: state.pageKey,
          child: seoWrapped,
          spec: spec,
        );
      },
    )
  ''').join(',\\n');

  // Global redirect builder from routingRedirects
  final sbRedirect = StringBuffer();
  sbRedirect.writeln('String? _globalRedirect(BuildContext context, GoRouterState state) {');
  sbRedirect.writeln('  final path = state.uri.path;');
  if (redirects.isNotEmpty) {
    for (final r in redirects) {
      final from = r['from']!;
      final to = r['to']!;
      final regex = _patternToRegex(from);
      sbRedirect.writeln('  { final re = RegExp(r"' + regex + '");');
      sbRedirect.writeln('    final m = re.firstMatch(path);');
      sbRedirect.writeln('    if (m != null) {');
      final toEsc = to.replaceAll('"', '\\"');
      sbRedirect.writeln('      final newPath = "' + toEsc + '"'
          '.replaceAllMapped(RegExp(r":([a-zA-Z0-9_]+)"), (mm) => m.namedGroup(mm.group(1)!) ?? "");');
      sbRedirect.writeln('      final newUri = state.uri.replace(path: newPath);');
      sbRedirect.writeln('      return newUri.toString();');
      sbRedirect.writeln('    } }');
    }
  }
  sbRedirect.writeln('  return null;');
  sbRedirect.writeln('}');

  final router = '''
// GENERATED – do not edit.
$imports

final _defaultSeo = SeoProps(
  siteName: '${_esc(seoSiteName)}',
  title: '${_esc(seoTitle)}',
  description: '${_esc(seoDesc)}',
  imageUrl: '${_esc(seoImage)}',
  twitterHandle: '${_esc(seoTwitter)}',
);

final _projectDefaultTransition = PageTransitionSpec(
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
  File(p.join(clientDir.path, 'router.g.dart')).writeAsStringSync(router);

  // Backend bind config
  File(p.join(backendOut.path, 'dartvel_backend.g.dart')).writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_backend_config;
const String backendHost = '${_esc(backendHost)}';
const int    backendPort = $backendPort;
const String apiBasePath = '${_esc(apiBasePath)}';
''');

  stdout.writeln('dartvel: generated .dart_tool/dartvel_client/* and .dart_tool/dartvel_backend.g.dart');
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
