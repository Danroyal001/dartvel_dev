import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/helpers.dart';
import '../utils/logger.dart';
import 'backend_generator.dart';
import 'client_generator.dart';
import 'model_generator.dart';

Future<void> generate({bool validateProd = false}) async {
  final root = Directory.current.path;

  // Unique build id for this generation (UTC ISO + epoch millis)
  final now = DateTime.now().toUtc();
  final buildId = '${now.toIso8601String()}#${now.millisecondsSinceEpoch}';

  log('dartvel: generator build $buildId');
  final pubspecFile = File(p.join(root, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml not found in ${Directory.current.path}');
    exit(2);
  }
  final yaml = loadYaml(await pubspecFile.readAsString()) as YamlMap;
  final pkgName = (yaml['name'] ?? 'app').toString();
  final dv = yaml['dartvel'] is YamlMap ? yaml['dartvel'] as YamlMap : YamlMap.wrap({});

  final backendHost = (dv['backendHost'] ?? '0.0.0.0').toString();
  final backendPort = asInt(dv['backendPort'], 3000);
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
  final seo = dv['seo'] is YamlMap
      ? dv['seo'] as YamlMap
      : (dv['webSeoDefaults'] is YamlMap
          ? dv['webSeoDefaults'] as YamlMap
          : YamlMap.wrap({}));
  final seoSiteName = (seo['siteName'] ?? '').toString();
  final seoTitle = (seo['defaultTitle'] ?? seo['title'] ?? '').toString();
  final seoDesc =
      (seo['defaultDescription'] ?? seo['description'] ?? '').toString();
  final seoImage = (seo['defaultImage'] ?? seo['image'] ?? '').toString();
  final seoTwitter = (seo['twitterHandle'] ?? '').toString();

  final transitions = dv['webTransitions'] is YamlMap
      ? dv['webTransitions'] as YamlMap
      : (dv['transitions'] is YamlMap ? dv['transitions'] as YamlMap : YamlMap.wrap({}));
  final defaultTransition = (transitions['default'] ?? 'fade').toString();
  final durationMs = asInt(transitions['durationMs'], 220);
  final curve = (transitions['curve'] ?? 'easeInOut').toString();

  // Routing options
  final normalizeTrailing = asBool(dv['routingNormalizeTrailingSlash'], true);
  final notFoundRedirect = (dv['notFoundRedirect'] ?? '').toString();

  // New features
  final plugins = <String>[];
  if (dv['plugins'] is YamlList) {
    for (final p in (dv['plugins'] as YamlList)) {
      if (p != null) plugins.add(p.toString());
    }
  }
  final webPrerender = asBool(dv['webPrerender'], false);
  final ota = asBool(dv['ota'], false);

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
