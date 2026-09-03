import 'dart:async';
import 'dart:io';

import '../config/dartvel_config.dart';
import '../graph/module_mounts.dart';
import '../utils/logger.dart';
import 'backend_generator.dart';
import 'client_generator.dart';
import 'job_generator.dart';
import 'model_generator.dart';
import 'static_paths_generator.dart';

/// Generates a Dartvel project, and every module it mounts.
///
/// [root] is the project, defaulting to the working directory. A mounted
/// module is generated first: the parent imports the module's own generated
/// client, so a parent generated against an ungenerated module would import
/// a library that is not there. [generated] carries what has been done, so a
/// module mounted twice is generated once and a cycle ends rather than
/// recurring.
Future<void> generate({
  bool validateProd = false,
  String? root_,
  Set<String>? generated,
}) async {
  final root = root_ ?? Directory.current.path;
  final Set<String> done = generated ?? <String>{};
  if (!done.add(File(root).absolute.path)) return;

  // Unique build id for this generation (UTC ISO + epoch millis)
  final now = DateTime.now().toUtc();
  final buildId = '${now.toIso8601String()}#${now.millisecondsSinceEpoch}';

  log('dartvel: generator build $buildId');
  final DartvelConfig config;
  try {
    config = await DartvelConfig.load(Directory(root));
  } on Object catch (error) {
    stderr.writeln(error);
    exit(2);
  }
  final pkgName = config.packageName;
  final dv = config.raw;

  final backendHost = config.backendHost;
  final backendPort = config.backendPort;
  final apiBasePath = config.apiBasePath;

  final devBackendHost = config.devBackendHost;
  final prodBackendHost = config.prodBackendHost;

  if (validateProd && prodBackendHost.isEmpty) {
    stderr.writeln('dartvel.prodBackendHost is required for build.');
    exit(3);
  }

  final pagesDir = config.pagesDir;
  final backendDir = config.backendDir;
  final envFiles = config.envFiles;
  final seoSiteName = config.seo.siteName;
  final seoTitle = config.seo.title;
  final seoDesc = config.seo.description;
  final seoImage = config.seo.image;
  final seoTwitter = config.seo.twitterHandle;
  final defaultTransition = config.transitions.defaultTransition;
  final durationMs = config.transitions.durationMs;
  final curve = config.transitions.curve;
  final normalizeTrailing = config.normalizeTrailingSlash;
  final notFoundRedirect = config.notFoundRedirect;
  final plugins = config.plugins;
  final webPrerender = config.webPrerender;
  final ota = config.ota;

  // Generate Router (Client)
  // Discovered before the client is generated, because the router has to
  // serve the pages these describe. `generatePublicPages: true` produced a
  // list of paths and no route, so every one of them led to the application's
  // own not-found page. Discovery only reads; the manifest is still written
  // further down.
  final publicPageModels = StaticPathsGenerator.discover(
    root: root,
    pkgName: pkgName,
  ).where((p) => p.route != null && p.generatesPage).toList();

  // Modules this application mounts. Their pages become the parent's routes
  // under the mount point, so the route index, the sitemap, static
  // generation and the web server all know about them.
  final modules = dvDiscoverModuleMounts(root);
  for (final module in modules) {
    for (final problem in module.problems) {
      log('dartvel: $problem');
    }
    if (module.sourcePath.isEmpty) continue;
    // Generated before the parent, because the parent imports its client.
    final moduleRoot = File('$root/${module.sourcePath}').absolute.path;
    if (Directory(moduleRoot).existsSync()) {
      log('dartvel: generating mounted module ${module.id}');
      await generate(root_: moduleRoot, generated: done);
    }
    if (module.routes.isNotEmpty) {
      log('dartvel: mounted module ${module.id} at ${module.mount} '
          '(${module.routes.length} route(s))');
    }
  }

  await ClientGenerator.generate(
    root: root,
    pagesDir: pagesDir,
    pkgName: pkgName,
    buildId: buildId,
    publicPageModels: publicPageModels,
    modules: modules,
    backendHost: backendHost,
    backendPort: backendPort,
    devBackendHost: devBackendHost,
    prodBackendHost: prodBackendHost,
    apiBasePath: apiBasePath,
    envFiles: envFiles,
    seoSiteName: seoSiteName,
    seoTitle: seoTitle,
    seoDesc: seoDesc,
    seoImage: seoImage,
    seoTwitter: seoTwitter,
    defaultTransition: defaultTransition,
    durationMs: durationMs,
    curve: curve,
    normalizeTrailing: normalizeTrailing,
    notFoundRedirect: notFoundRedirect,
    plugins: plugins,
    webPrerender: webPrerender,
    ota: ota,
    dv: dv,
  );

  // Generate Models
  await ModelGenerator.generate(
    root: root,
    pkgName: pkgName,
    buildId: buildId,
  );

  // Generate job payloads, queue constants and handler registration.
  // @DVJob was an annotation nothing read before this pass.
  await JobGenerator.generate(
    root: root,
    pkgName: pkgName,
    buildId: buildId,
  );

  // Generate static paths for parameterized routes. Static generation cannot
  // enumerate a parameterized route on its own, so @DVStaticPaths() providers
  // are collected into a manifest here.
  await StaticPathsGenerator.generate(
    root: root,
    pkgName: pkgName,
    buildId: buildId,
  );

  // Generate Backend
  await BackendGenerator.generate(
    root: root,
    backendDir: backendDir,
    pkgName: pkgName,
    buildId: buildId,
    backendHost: backendHost,
    backendPort: backendPort,
    apiBasePath: apiBasePath,
  );
}
