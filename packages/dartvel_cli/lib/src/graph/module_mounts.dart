/// Modules mounted into a parent application, at build time.
///
/// A module is a complete Dartvel application: its own pages, its own route
/// base, runnable on its own. Mounted, its routes move under the mount
/// point -- the standalone `/products/:id` becomes `/store/products/:id` --
/// and the parent's route index, sitemap, static generation and server
/// rendering all have to know about them, which is what the specification
/// means by a module contributing its routes.
///
/// Read from the declaration and from the module's own project, never from
/// anything the module hard-codes: a module that knew its mount point could
/// not be mounted twice, or anywhere else.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/page_names.dart';
import '../generators/route_utils.dart';

/// How a mounted module is built and deployed.
enum DVModuleDeployment {
  /// Compiled into the parent artifact, keeping its namespace.
  embedded,

  /// Pages in the parent; the module's backend deploys as its own service.
  splitBackend,

  /// Built and deployed independently, mounted into the parent's routes.
  federated,

  /// Models, functions and jobs but no pages.
  backendOnly,
}

/// One of a module's pages, where it answers standalone and where it
/// answers once mounted.
class DVModuleRoute {
  const DVModuleRoute({
    required this.standalone,
    required this.mounted,
    required this.import,
    required this.file,
    required this.widget,
  });

  /// The route the module serves this page at on its own.
  final String standalone;

  /// The route the parent serves it at.
  final String mounted;

  /// The page's library, as the parent imports it.
  final String import;

  /// The page file, relative to the module's project.
  final String file;

  /// The class the module's own generator made for this page, which is what
  /// the parent's router builds.
  final String widget;
}

/// A module the parent mounts.
class DVModuleMount {
  const DVModuleMount({
    required this.id,
    required this.packageName,
    required this.mount,
    required this.sourcePath,
    required this.deployment,
    required this.routes,
    this.assets = const <String, String>{},
    this.name,
    this.version,
    this.routeBase = '/',
    this.inSitemap = true,
    this.problems = const <String>[],
  });

  /// The id the parent knows it by: `DV.Modules.<id>`.
  final String id;

  /// The module project's package, which is how its pages are imported.
  final String packageName;

  /// Where the parent serves it, with no trailing slash (`/` at the root).
  final String mount;

  /// Where the module's project is, relative to the parent.
  final String sourcePath;

  final DVModuleDeployment deployment;

  /// Its pages, rebased under [mount].
  final List<DVModuleRoute> routes;

  /// What the module declares as assets, each mapped to the path the parent
  /// must ask for.
  ///
  /// Flutter serves another package's asset under `packages/<name>/`, so the
  /// path a module uses standing alone is not the path that finds it once it
  /// is mounted; a module that hard-coded either would be wrong in the other
  /// place.
  final Map<String, String> assets;

  /// The module's generated client, which is where its pages are.
  String get clientImport => 'package:$packageName/dartvel_client/dartvel_client.dart';

  final String? name;
  final String? version;

  /// The base the module serves its own pages under when it runs alone,
  /// taken off before the mount goes on: a module answering at
  /// `/shop/products` alone answers at `/store/products` mounted, not at
  /// `/store/shop/products`.
  final String routeBase;

  /// Whether the parent's sitemap lists this module's pages.
  final bool inSitemap;

  /// What is wrong with the declaration, reported rather than thrown: a
  /// build says what it could not mount and carries on with the rest.
  final List<String> problems;
}

/// The modules the project at [root] mounts.
List<DVModuleMount> dvDiscoverModuleMounts(String root) {
  final Object? section = _dartvelSection(root)['modules'];
  if (section is! Map) return const <DVModuleMount>[];

  final List<DVModuleMount> mounts = <DVModuleMount>[];
  section.forEach((Object? rawId, Object? rawBody) {
    final String id = '$rawId';
    final Map<Object?, Object?> body = rawBody is Map ? rawBody : const <Object?, Object?>{};
    final List<String> problems = <String>[];

    final String mount = _mountOf(body, problems);
    final String? sourcePath = _sourceOf(body, problems, id);
    final DVModuleDeployment deployment = _deploymentOf(body, problems, id);
    final bool inSitemap = '${body['sitemap'] ?? 'include'}' != 'exclude';

    if (sourcePath == null) {
      mounts.add(DVModuleMount(
        id: id,
        packageName: id,
        mount: mount,
        sourcePath: '',
        deployment: deployment,
        routes: const <DVModuleRoute>[],
        inSitemap: inSitemap,
        problems: problems,
      ));
      return;
    }

    final String moduleRoot = p.normalize(p.join(root, sourcePath));
    if (!Directory(moduleRoot).existsSync()) {
      problems.add('dartvel.modules.$id.source.path is "$sourcePath", and there is no project there.');
      mounts.add(DVModuleMount(
        id: id,
        packageName: id,
        mount: mount,
        sourcePath: sourcePath,
        deployment: deployment,
        routes: const <DVModuleRoute>[],
        inSitemap: inSitemap,
        problems: problems,
      ));
      return;
    }

    final Map<Object?, Object?> modulePubspec = _pubspec(moduleRoot);
    final Object? dartvel = modulePubspec['dartvel'];
    final Map<Object?, Object?> moduleSection = dartvel is Map ? dartvel : const <Object?, Object?>{};
    final Object? declared = moduleSection['module'];
    final Map<Object?, Object?> moduleDeclaration = declared is Map ? declared : const <Object?, Object?>{};
    final String packageName =
        modulePubspec['name'] is String ? modulePubspec['name']! as String : id;
    final String pagesDir =
        moduleSection['pagesDir'] is String ? moduleSection['pagesDir']! as String : 'lib/pages';
    final Object? flutterSection = modulePubspec['flutter'];
    final Object? declaredAssets =
        flutterSection is Map ? flutterSection['assets'] : null;
    final Map<String, String> assets = <String, String>{
      if (declaredAssets is List)
        for (final Object? asset in declaredAssets)
          if (asset is String && asset.isNotEmpty) asset: 'packages/$packageName/$asset',
    };

    final Object? routesSection = moduleDeclaration['routes'];
    final String routeBase = routesSection is Map && routesSection['base'] is String
        ? _normalise(routesSection['base']! as String)
        : '/';

    // A backend-only module has no pages to mount, whatever is on disk:
    // the declaration says what the parent takes from it.
    final List<DVModuleRoute> routes = deployment == DVModuleDeployment.backendOnly || problems.isNotEmpty
        ? const <DVModuleRoute>[]
        : _routesOf(
            moduleRoot: moduleRoot,
            pagesDir: pagesDir,
            packageName: packageName,
            routeBase: routeBase,
            mount: mount,
            problems: problems,
          );

    mounts.add(DVModuleMount(
      id: id,
      packageName: packageName,
      mount: mount,
      sourcePath: sourcePath,
      deployment: deployment,
      routes: routes,
      assets: assets,
      name: moduleDeclaration['name'] is String ? moduleDeclaration['name']! as String : null,
      version: moduleDeclaration['version'] == null ? null : '${moduleDeclaration['version']}',
      routeBase: routeBase,
      inSitemap: inSitemap,
      problems: problems,
    ));
  });
  mounts.sort((DVModuleMount a, DVModuleMount b) => a.id.compareTo(b.id));
  return mounts;
}

/// The module's pages, as the parent will serve them.
List<DVModuleRoute> _routesOf({
  required String moduleRoot,
  required String pagesDir,
  required String packageName,
  required String routeBase,
  required String mount,
  required List<String> problems,
}) {
  final Directory pages = Directory(p.join(moduleRoot, pagesDir));
  if (!pages.existsSync()) return const <DVModuleRoute>[];

  final List<DVModuleRoute> routes = <DVModuleRoute>[];
  final List<File> files = pages
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  for (final File file in files) {
    final String basename = p.basename(file.path);
    // The same companions page discovery skips everywhere else.
    if (basename == '_layout.dart' || basename == '_guard.dart') continue;
    if (basename.endsWith('.loading.dart') || basename.endsWith('.error.dart')) continue;

    final String rel = p.relative(file.path, from: moduleRoot).replaceAll('\\', '/');
    final String? symbol = dvPageSymbol(file.readAsStringSync());
    if (symbol == null) {
      // A file under the pages directory that declares no page. The module
      // generates nothing for it, so there is nothing for the parent to
      // serve; said rather than mounted as a route that cannot build.
      problems.add('$rel declares no page, so it is not mounted.');
      continue;
    }
    final String standalone;
    try {
      standalone = _join(routeBase, RouteUtils.routeFor(rel, pagesDir));
    } on FormatException {
      // A page the module itself could not route is the module's problem;
      // mounting does not make it the parent's.
      continue;
    }
    // The module's own base comes off before the mount goes on.
    final String withoutBase = _stripBase(standalone, routeBase);
    routes.add(DVModuleRoute(
      standalone: standalone,
      mounted: _join(mount, withoutBase),
      import: 'package:$packageName/${rel.replaceFirst(RegExp(r'^lib/'), '')}',
      file: rel,
      widget: dvGeneratedPageWidgetName(symbol),
    ));
  }
  routes.sort((DVModuleRoute a, DVModuleRoute b) => a.mounted.compareTo(b.mounted));
  return routes;
}

String _mountOf(Map<Object?, Object?> body, List<String> problems) {
  final Object? raw = body['mount'];
  final String mount = raw == null ? '/' : '$raw';
  if (!mount.startsWith('/')) {
    problems.add('A module\'s mount is a path: "$mount" does not begin with "/".');
    return '/';
  }
  return _normalise(mount);
}

String? _sourceOf(Map<Object?, Object?> body, List<String> problems, String id) {
  final Object? source = body['source'];
  final Object? path = source is Map ? source['path'] : source;
  if (path is String && path.isNotEmpty) return path;
  problems.add('dartvel.modules.$id needs a source.path pointing at the module\'s project.');
  return null;
}

DVModuleDeployment _deploymentOf(Map<Object?, Object?> body, List<String> problems, String id) {
  const Map<String, DVModuleDeployment> names = <String, DVModuleDeployment>{
    'embedded': DVModuleDeployment.embedded,
    'split-backend': DVModuleDeployment.splitBackend,
    'federated': DVModuleDeployment.federated,
    'backend-only': DVModuleDeployment.backendOnly,
  };
  final Object? raw = body['deployment'];
  if (raw == null) return DVModuleDeployment.embedded;
  final DVModuleDeployment? found = names['$raw'];
  if (found != null) return found;
  problems.add('dartvel.modules.$id.deployment is "$raw"; it is one of ${names.keys.join(', ')}.');
  return DVModuleDeployment.embedded;
}

/// A path with one leading slash and no trailing one; the root stays `/`.
String _normalise(String path) {
  final String trimmed = path.trim();
  final String withSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  final String withoutTrailing = withSlash.replaceAll(RegExp(r'/+$'), '');
  return withoutTrailing.isEmpty ? '/' : withoutTrailing;
}

/// [base] and [path] joined, without doubling the separator.
String _join(String base, String path) {
  final String left = _normalise(base);
  final String right = path == '/' ? '' : _normalise(path);
  if (left == '/') return right.isEmpty ? '/' : right;
  return right.isEmpty ? left : '$left$right';
}

/// [path] with [base] taken off the front.
String _stripBase(String path, String base) {
  final String left = _normalise(base);
  if (left == '/') return path;
  if (path == left) return '/';
  return path.startsWith('$left/') ? path.substring(left.length) : path;
}

Map<Object?, Object?> _pubspec(String root) {
  final File file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return const <Object?, Object?>{};
  try {
    final Object? doc = loadYaml(file.readAsStringSync());
    return doc is Map ? doc : const <Object?, Object?>{};
  } on Object {
    return const <Object?, Object?>{};
  }
}

Map<Object?, Object?> _dartvelSection(String root) {
  final Object? section = _pubspec(root)['dartvel'];
  return section is Map ? section : const <Object?, Object?>{};
}
