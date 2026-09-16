import 'dart:async';
import 'dart:io';

import '../adoption/adoption_build_checks.dart';
import '../build/render_backends.dart';
import '../config/dartvel_config.dart';
import '../graph/module_mounts.dart';
import '../utils/logger.dart';
import 'account_generator.dart';
import 'analytics_generator.dart';
import 'backend_generator.dart';
import 'client_generator.dart';
import 'flag_generator.dart';
import 'job_generator.dart';
import 'model_generator.dart';
import 'platform_api_generator.dart';
import 'privacy_declarations.dart';
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
  /// What the build resolved, or null when generation was not told — in which
  /// case the project's own `dartvel.terminal` declaration stands.
  Set<DVRenderBackend>? renderBackends,
}) async {
  final root = root_ ?? Directory.current.path;
  final Set<String> done = generated ?? <String>{};
  if (!done.add(File(root).absolute.path)) return;

  // No build id. A wall-clock stamp written into every file rewrote every
  // file on every build, so a regeneration with nothing changed was
  // indistinguishable from a real change. Identical inputs produce identical
  // bytes; see Generated Code Determinism.
  final DartvelConfig config;
  try {
    config = await DartvelConfig.load(Directory(root));
  } on Object catch (error) {
    stderr.writeln(error);
    exit(2);
  }
  final pkgName = config.packageName;
  final dv = config.raw;

  // dartvel.analytics, checked before anything is written. A misspelt key
  // or a value nobody implements stops the build here rather than being
  // skipped into a running app that does something other than what the
  // pubspec says.
  final analyticsSettings = AnalyticsGenerator.read(dv);
  // DV-ANALYTICS-002 for a platform the application builds for that has no
  // way to ask about a declared category, such as iOS without the usage
  // description App Tracking Transparency needs.
  AnalyticsGenerator.checkTargets(root: root, settings: analyticsSettings);

  // dartvel.auth.pages, checked before anything is written: a misspelt page
  // or a path that is not one would otherwise be skipped into a route the
  // application believes it configured.
  AccountGenerator.readPages(dv);
  final accountDeletionGrace = AccountGenerator.readDeletionGrace(dv);

  // Every model's privacy declaration, before anything is written. A
  // sensitive field no subject path reaches (DV-PRIVACY-001) is a table an
  // erasure would leave behind while reporting success, so it stops the
  // build; personal data kept indefinitely by nobody's decision
  // (DV-PRIVACY-002) is said and allowed.
  final privacyDeclarations = DVPrivacyDeclarations.discover(root: root);
  if (privacyDeclarations.errors.isNotEmpty) {
    throw StateError(privacyDeclarations.errors.join('\n'));
  }
  for (final finding in privacyDeclarations.findings) {
    stderr.writeln(finding);
  }

  // dartvel.platformApi, before anything is written: a key nothing reads or
  // a scope naming an action no @DVPolicy defines (DV-APIKEY-001) stops the
  // build here, rather than shipping a scope every partner call is refused
  // under.
  final platformApi = PlatformApiGenerator.read(dv);
  if (platformApi != null) {
    PlatformApiGenerator.check(
      root: root,
      pkgName: pkgName,
      backendDir: config.backendDir,
      config: platformApi,
    );
  }

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

  // Adoption's build errors, before anything is written: a route both the
  // host router and a page define (DV-ADOPT-002), and a model that already
  // has a generated serializer (DV-ADOPT-003). Checked here rather than in
  // the generators because a build that is going to fail must not leave half
  // a client behind it.
  final adoption = dvAdoptionBuildCheck(
    root: root,
    pagesDir: pagesDir,
    extraRoutes: <(String, String)>[
      for (final model in publicPageModels)
        (model.route!, 'the generated page of ${model.className ?? model.functionName}'),
    ],
  );
  for (final String note in adoption.unchecked) {
    log('dartvel: $note');
  }
  if (adoption.errors.isNotEmpty) {
    throw StateError(adoption.errors.join('\n'));
  }

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
    // A module mounted as a dependency ships its generated client. Its
    // project is wherever pub resolved it, usually the pub cache, which is
    // not this build's to write into.
    if (!module.fromPackage && Directory(moduleRoot).existsSync()) {
      log('dartvel: generating mounted module ${module.id}');
      // The module is compiled into this binary, so it renders wherever the
      // parent does. Letting it default would generate a GUI main inside a
      // terminal build.
      await generate(
        root_: moduleRoot,
        generated: done,
        renderBackends: renderBackends,
      );
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
    publicPageModels: publicPageModels,
    modules: modules,
    renderBackends: renderBackends,
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

  // DV.Analytics and DV.Privacy, which the client runtime and the generated
  // server start from these files.
  AnalyticsGenerator.generate(
    root: root,
    settings: analyticsSettings,
    privacy: privacyDeclarations,
  );

  // What the generated server gives the account endpoints: the mail an
  // address change sends, under the name a person knows the application by,
  // and how long a deleted account waits before it is erased.
  AccountGenerator.generate(
    root: root,
    appName: seoSiteName.isNotEmpty ? seoSiteName : pkgName,
    deletionGrace: accountDeletionGrace,
  );

  // The scope registry, rate plans and OAuth settings, which the client and
  // the generated server both read.
  PlatformApiGenerator.generate(root: root, dv: dv);

  // Generate Models
  await ModelGenerator.generate(
    root: root,
    pkgName: pkgName,
  );

  // Generate job payloads, queue constants and handler registration.
  // @DVJob was an annotation nothing read before this pass. A handler only a
  // Flutter process can run is named here, at build time, rather than first
  // noticed as a worker that cannot run its jobs.
  final List<String> jobWarnings = await JobGenerator.generate(
    root: root,
    pkgName: pkgName,
  );
  for (final String warning in jobWarnings) {
    stderr.writeln(warning);
  }

  // Typed flag accessors from @DVFlags() declarations. A flag named by a
  // string can be misspelt and misses silently; a generated member is a
  // compile error instead. A flag past its expiry warns here, at build time.
  final List<String> flagWarnings = await FlagGenerator.generate(
    root: root,
    pkgName: pkgName,
  );
  for (final String warning in flagWarnings) {
    stderr.writeln(warning);
  }

  // Generate static paths for parameterized routes. Static generation cannot
  // enumerate a parameterized route on its own, so @DVStaticPaths() providers
  // are collected into a manifest here.
  await StaticPathsGenerator.generate(
    root: root,
    pkgName: pkgName,
  );

  // Generate Backend
  await BackendGenerator.generate(
    root: root,
    backendDir: backendDir,
    pkgName: pkgName,
    backendHost: backendHost,
    backendPort: backendPort,
    apiBasePath: apiBasePath,
  );
}
