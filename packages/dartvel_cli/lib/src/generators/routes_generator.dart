import 'dart:async';
import 'dart:io';

import '../adoption/adoption_build_checks.dart';
import 'package:dartvel_core/dartvel.dart' show DVPersistedQueryMode;
import 'package:dartvel_core/framework.dart' show DVCaptureConfigError;

import '../build/graphql_options.dart';
import '../build/render_backends.dart';
import '../config/dartvel_config.dart';
import '../graph/module_mounts.dart';
import '../utils/logger.dart';
import 'account_generator.dart';
import 'analytics_generator.dart';
import 'backend_generator.dart';
import 'client_generator.dart';
import 'config_routes.dart';
import 'flag_generator.dart';
import 'http_hosts_generator.dart';
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

  // dartvel.http, checked before anything is written, through the reader the
  // running application declares its hosts with. A misspelt key would
  // otherwise be a timeout or a retry policy the pubspec states and nothing
  // applies.
  final httpHosts = HttpHostsGenerator.read(dv);
  // DV-HTTP-001 and DV-HTTP-005, which the specification makes build errors:
  // a request to a host nobody declared, and a host whose credential is
  // backend-scoped used from client code.
  HttpHostsGenerator.check(
    root: root,
    backendDir: config.backendDir,
    http: httpHosts,
  );

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

  // dartvel.api.graphql, before anything is written: a misspelt key or a
  // budget the runtime cannot use would otherwise leave /graphql answering at
  // the defaults for somebody who wrote down a limit.
  final graphqlOptions = DVGraphQLApiOptions.parse(dv);
  if (graphqlOptions?.persistedQueries == DVPersistedQueryMode.require) {
    // Said, not refused: require is the setting the section asks for, and an
    // endpoint that answers nothing fails closed.
    stderr.writeln(
      'dartvel.api.graphql.persistedQueries is require, and the build does '
      'not extract client queries into a manifest yet, so /graphql answers '
      'only documents the application loads into DVGraphQL.persistedQueries '
      'itself. Every other document is refused with DV-EDGE-002.',
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

  // The routes file, read before anything is written: a route it declares
  // that the build cannot read (DV-ROUTE-003) would otherwise run with no
  // typed target and no check against the pages.
  final DVConfigRoutes configRoutes = DVConfigRoutes.read(root: root, dv: dv);
  if (configRoutes.errors.isNotEmpty) {
    throw StateError(configRoutes.errors.join('\n'));
  }

  // The routes the application's own pages serve. Every data model has a
  // page unless it opts out, and one whose route a page file or the routes
  // file already has yields to it: the page somebody wrote is the one they
  // meant, and two routes of one shape is a page nobody can reach.
  final Set<String> takenRoutes = <String>{
    for (final (String path, String _) in dvGeneratedPageRoutes(root, pagesDir))
      path,
    for (final DVConfigRoute route in configRoutes.routes) route.path,
  };

  // Generate Router (Client)
  // Discovered before the client is generated, because the router has to
  // serve the pages these describe. Pages used to be a list of paths and no
  // route, so every one of them led to the application's own not-found
  // page. Discovery only reads; the manifest is still written further down.
  final publicPageModels = StaticPathsGenerator.discover(
    root: root,
    pkgName: pkgName,
    takenRoutes: takenRoutes,
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
      for (final DVConfigRoute route in configRoutes.routes)
        (route.path, 'the config route at ${route.source}'),
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

  // DV-ROUTE-001 and DV-ROUTE-004: config routes against everything else the
  // router serves, before a mounted module is generated.
  if (configRoutes.exists) {
    final List<String> routeErrors = dvConfigRouteConflicts(
      configRoutes,
      generated: <(String, String)>[
        for (final (String path, String source)
            in dvGeneratedPageRoutes(root, pagesDir))
          (path, 'the page $source'),
        for (final model in publicPageModels)
          (model.route!, 'the generated page of ${model.className ?? model.functionName}'),
        for (final module in modules)
          for (final route in module.routes)
            (route.mounted, 'the module ${module.id}'),
      ],
    );
    if (routeErrors.isNotEmpty) throw StateError(routeErrors.join('\n'));
  }
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
    configRoutes: configRoutes,
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

  // The hosts DV.Http sends to, which the client runtime and every server
  // role declare at startup.
  // The parent's hosts and every mounted module's, in one block: a module
  // generated from a described API carries the host its calls go to, and a
  // host nobody declared is DV-HTTP-001 on its first request.
  HttpHostsGenerator.generate(
    root: root,
    http: HttpHostsGenerator.merge(http: httpHosts, modules: modules),
  );

  // The scope registry, rate plans and OAuth settings, which the client and
  // the generated server both read.
  PlatformApiGenerator.generate(root: root, dv: dv);

  // Generate Models
  final Set<String> captured = await ModelGenerator.generate(
    root: root,
    pkgName: pkgName,
    takenRoutes: takenRoutes,
  );
  // dartvel.capture against the data models that are captured: a
  // destination naming one that is not (DV-CDC-008) would be delivered
  // nothing, which looks exactly like a quiet day.
  try {
    config.capture?.checkModels(captured);
  } on DVCaptureConfigError catch (error) {
    throw StateError('pubspec.yaml: $error');
  }

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
    takenRoutes: takenRoutes,
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
