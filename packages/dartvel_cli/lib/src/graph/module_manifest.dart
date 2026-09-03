/// The manifest a module publishes about itself.
///
/// A federated module is deployed on its own and mounted into somebody else's
/// application, and this is what that application reads before it agrees to
/// mount it. It is generated from the module's own project because a manifest
/// written by hand goes stale the first time a page is added, and nobody
/// notices until a route 404s in production.
///
/// The routes in it are the module's own. The same module answers at
/// `/products` standalone and `/store/products` mounted, so a manifest that
/// baked in one parent's mount point would be wrong for every other parent --
/// and wrong in the way that is hardest to catch, because it works in the
/// application it was generated against.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/page_names.dart';
import '../generators/route_utils.dart';

/// The manifest for the module project at [moduleRoot].
DVModuleManifest dvModuleManifestFor(String moduleRoot) {
  final Map<Object?, Object?> pubspec = _pubspec(moduleRoot);
  final Object? dartvel = pubspec['dartvel'];
  final Map<Object?, Object?> section =
      dartvel is Map ? dartvel : const <Object?, Object?>{};
  final Object? declared = section['module'];
  final Map<Object?, Object?> module =
      declared is Map ? declared : const <Object?, Object?>{};

  final String packageName =
      pubspec['name'] is String ? pubspec['name']! as String : 'module';
  final String id = module['id'] is String ? module['id']! as String : packageName;
  final String pagesDir =
      section['pagesDir'] is String ? section['pagesDir']! as String : 'lib/pages';

  final Object? routesSection = module['routes'];
  final String routeBase = routesSection is Map && routesSection['base'] is String
      ? _normalise(routesSection['base']! as String)
      : '/';

  final Object? flutterSection = pubspec['flutter'];
  final Object? declaredAssets =
      flutterSection is Map ? flutterSection['assets'] : null;

  return DVModuleManifest(
    id: id,
    version: '${module['version'] ?? '0.0.0'}',
    routes: _routesOf(moduleRoot: moduleRoot, pagesDir: pagesDir, routeBase: routeBase),
    capabilities: <String>{
      for (final Object? c in module['capabilities'] is List
          ? module['capabilities']! as List<Object?>
          : const <Object?>[])
        '$c',
    },
    assets: <String, String>{
      if (declaredAssets is List)
        for (final Object? asset in declaredAssets)
          if (asset is String && asset.isNotEmpty)
            asset: 'packages/$packageName/$asset',
    },
    shell: '${module['shell'] ?? 'inherit'}',
    auth: '${module['auth'] ?? 'inherit'}',
    theme: '${module['theme'] ?? 'inherit'}',
    data: '${module['data'] ?? 'shared'}',
    publicFunctions: <String>[
      for (final Object? f in module['publicFunctions'] is List
          ? module['publicFunctions']! as List<Object?>
          : const <Object?>[])
        '$f',
    ],
    publicSignals: <String>[
      for (final Object? s in module['publicSignals'] is List
          ? module['publicSignals']! as List<Object?>
          : const <Object?>[])
        '$s',
    ],
    requiresParent: module['requiresParent']?.toString(),
    location: module['location']?.toString(),
  );
}

/// The routes the module serves on its own, under its own base.
List<String> _routesOf({
  required String moduleRoot,
  required String pagesDir,
  required String routeBase,
}) {
  final Directory pages = Directory(p.join(moduleRoot, pagesDir));
  if (!pages.existsSync()) return const <String>[];
  final List<String> routes = <String>[];
  final List<File> files = pages
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  for (final File file in files) {
    final String basename = p.basename(file.path);
    if (basename == '_layout.dart' || basename == '_guard.dart') continue;
    if (basename.endsWith('.loading.dart') || basename.endsWith('.error.dart')) {
      continue;
    }
    final String rel = p.relative(file.path, from: moduleRoot).replaceAll('\\', '/');
    // A file under the pages directory that declares no page generates
    // nothing, so there is no route to publish for it.
    if (dvPageSymbol(file.readAsStringSync()) == null) continue;
    try {
      routes.add(_join(routeBase, RouteUtils.routeFor(rel, pagesDir)));
    } on FormatException {
      // A page the module itself cannot route is not a route it serves.
      continue;
    }
  }
  routes.sort();
  return routes;
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

String _normalise(String path) {
  final String trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') return '/';
  final String withSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return withSlash.endsWith('/')
      ? withSlash.substring(0, withSlash.length - 1)
      : withSlash;
}

String _join(String base, String route) {
  if (base == '/') return route;
  if (route == '/') return base;
  return '$base$route';
}

/// Where a manifest was written, and whether it was signed.
class DVModuleManifestWrite {
  const DVModuleManifestWrite({
    required this.path,
    required this.signed,
    required this.manifest,
  });

  final String path;

  /// Whether a parent can trust this document.
  ///
  /// An unsigned manifest is useful for reading and for a module mounted from
  /// source, and it must never be mistakable for one a parent may act on.
  final bool signed;

  final DVModuleManifest manifest;
}

/// Writes the manifest for the module at [moduleRoot] to [out].
///
/// Signed when a [privateKey] and [keyId] are given. Without them the
/// document carries the manifest and no signature at all, rather than an
/// empty signature field -- a parent reading an empty string as a signature
/// would be one bug away from accepting it.
DVModuleManifestWrite dvWriteModuleManifest(
  String moduleRoot, {
  required String out,
  Uint8List? privateKey,
  String? keyId,
}) {
  final DVModuleManifest manifest = dvModuleManifestFor(moduleRoot);
  final bool signed = privateKey != null && keyId != null;
  final String document = signed
      ? dvSignModuleManifest(manifest, privateKey: privateKey, keyId: keyId)
      : const JsonEncoder.withIndent('  ')
          .convert(<String, Object?>{'manifest': manifest.toJson()});
  final File file = File(out);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(document);
  return DVModuleManifestWrite(
    path: file.path,
    signed: signed,
    manifest: manifest,
  );
}
