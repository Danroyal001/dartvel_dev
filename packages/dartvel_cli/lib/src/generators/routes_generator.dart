import 'dart:async';
import 'dart:io';

import '../config/dartvel_config.dart';
import '../utils/logger.dart';
import 'backend_generator.dart';
import 'client_generator.dart';
import 'job_generator.dart';
import 'model_generator.dart';
import 'static_paths_generator.dart';

Future<void> generate({bool validateProd = false}) async {
  final root = Directory.current.path;

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
  await ClientGenerator.generate(
    root: root,
    pagesDir: pagesDir,
    pkgName: pkgName,
    buildId: buildId,
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
