import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io';
import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart'
    show
        DVCrashConfig,
        DVCrashSinkChoice,
        DVPlatformApiConfig,
        dvMiddlewareKeysAlwaysOn,
        dvMiddlewareKeysAtRequest,
        dvMiddlewareKeysBuilt,
        dvMiddlewareKeysUnbuiltReason,
        dvMiddlewareKeysWrapping,
        dvPageMiddlewareRefusal;
import 'package:file/local.dart';
import 'client_type_imports.dart';
import 'function_body.dart';
import 'raw_path.dart';
import 'job_generator.dart';
import 'symbol_qualifier.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../build/graphql_options.dart';
import '../build/server_options.dart';
import '../updates/shorebird_config.dart';
import '../graph/module_mounts.dart';
import '../utils/helpers.dart';
import '../utils/logger.dart';
import 'openapi_generator.dart';
import 'page_policy.dart';
import 'platform_api_generator.dart';
import 'policy_classes.dart';
import 'route_utils.dart';

/// Whether a `handler(...)` parameter list is a raw handler's: one positional
/// parameter that is the request, typed as one or left untyped.
bool _takesOnlyTheRequest(String parameters) {
  final String list = RouteUtils.stripComments(parameters)
      .trim()
      .replaceAll(RegExp(r',\s*$'), '');
  if (list.isEmpty || list.contains(RegExp(r'[{\[,]'))) return false;
  final List<String> tokens =
      list.split(RegExp(r'\s+')).where((String t) => t.isNotEmpty).toList();
  if (tokens.length == 1) return true;
  final String type = tokens.sublist(0, tokens.length - 1).join(' ');
  final String bare = type.replaceAll('?', '').split('.').last;
  return bare == 'Request' || bare == 'RequestType' || bare == 'dynamic';
}

class BackendGenerator {
  /// `dartvel.crashes`, read with the parser the runtime uses, so a value the
  /// runtime could not honour fails the build here too.
  static DVCrashConfig _dvCrashConfig(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return const DVCrashConfig();
    final Object? doc = loadYaml(pubspec.readAsStringSync());
    final Object? dartvel = doc is Map ? doc['dartvel'] : null;
    try {
      return DVCrashConfig.parse(dartvel is Map ? dartvel['crashes'] : null);
    } on ArgumentError catch (error) {
      throw StateError(
        'pubspec.yaml ${error.name}: ${error.message} (got ${error.invalidValue})',
      );
    }
  }

  /// The pubspec's version, or `unversioned` -- what the generated client
  /// names the release too.
  static String _dvCrashRelease(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return 'unversioned';
    final Object? doc = loadYaml(pubspec.readAsStringSync());
    final Object? version = doc is Map ? doc['version'] : null;
    return version == null ? 'unversioned' : '$version';
  }

  /// The crash endpoint, for an application whose clients send reports to
  /// its own backend.
  ///
  /// The body limit is enforced where the body is read -- a limit checked
  /// after the read is not a limit -- and nothing a report carries is logged
  /// on any path, including a failure nobody anticipated, which answers a
  /// fixed 503. Each report is counted against the client's source as
  /// `DVClientAddress` resolves it, as well as against the install id the
  /// report names, because the install id is the client's to choose.
  static String _dvCrashRouteSource(DVCrashConfig crashes) => '''
  // Crash reports from this application's clients: dartvel.crashes.sink is
  // dartvel.
  // On the request's tenant and behind the authentication stage: a key for
  // another tenant is refused as on every route, and a valid key is refused
  // too, because an install does not report with one and the endpoint
  // declares no action a scope could cover.
  router.post(cfg.apiBasePath + core.DVCrashIngest.path, (dv.Request req) => _dvStaged(req, () async {
    if (core.DVApiPrincipal.current != null) {
      return _dvPolicyForbidden('no declared policy action');
    }
    core.DVCrashIngestResult result;
    try {
      final core.DVCrashIngest ingest = _dartvelCrashIngest ??= core.DVCrashIngest(
        repository: core.DVDatabaseCrashReportRepository.application(),
        perInstallPerHour: ${crashes.ingestPerInstallPerHour},
        perSourcePerHour: ${crashes.ingestPerSourcePerHour},
        maxBytes: ${crashes.ingestMaxBytes},
      );
      if (core.dvDeclaredTooLarge(contentLength: req.headers.get('content-length'), limit: ingest.maxBytes)) {
        result = const core.DVCrashIngestResult(core.DVCrashIngestOutcome.tooLarge);
      } else {
        final body = await core.dvReadCapped(req.body.stream, ingest.maxBytes);
        result = body == null
            ? const core.DVCrashIngestResult(core.DVCrashIngestOutcome.tooLarge)
            : await ingest.accept(body, source: core.DVClientAddress.sourceOf(req));
      }
    } on Object {
      result = const core.DVCrashIngestResult(core.DVCrashIngestOutcome.unavailable);
    }
    return dv.Response(result.status,
        headers: dv.Headers({'content-type': 'application/json; charset=utf-8'}),
        body: Stream<List<int>>.value(conv.utf8.encode(conv.jsonEncode(result.toJson()))));
    // The ingest's own limit, registered with the server: below it a report
    // is refused before it is read, and above the server's limit it is not
    // refused before the ingest can answer it.
  }), maxBodyBytes: ${crashes.ingestMaxBytes});
''';

  /// The OAuth provider's endpoints, for an application that declares
  /// `dartvel.platformApi.oauth`.
  ///
  /// Each runs on the request's tenant and none sits behind the
  /// authentication stage, because each authenticates its caller its own way.
  /// A method an endpoint does not serve is a 405 naming the ones it does --
  /// a code exchange sent as GET is refused rather than falling through to a
  /// 404 that reads as a wrong path -- and a CORS preflight is answered only
  /// where a browser-based client needs one.
  static String _dvOAuthRouteSource() => '''
  // dartvel.platformApi.oauth: this application is an OAuth 2.1 provider.
  router.get(cfg.apiBasePath + core.DVOAuthEndpoints.authorizePath, (dv.Request req) => core.dvWithRequestTenant(req, () => core.DVOAuthEndpoints.authorize(req)));
  router.post(cfg.apiBasePath + core.DVOAuthEndpoints.authorizePath, (dv.Request req) => core.dvWithRequestTenant(req, () async {
    // The consent answer is a state-changing POST from a signed-in person.
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVOAuthEndpoints.approve(req);
  }));
  router.any(cfg.apiBasePath + core.DVOAuthEndpoints.authorizePath, (dv.Request req) async => core.DVOAuthEndpoints.otherMethod(req, allow: 'GET, POST'));
  router.get(cfg.apiBasePath + core.DVOAuthEndpoints.authorizationRequestPath, (dv.Request req) => core.dvWithRequestTenant(req, () => core.DVOAuthEndpoints.authorizationRequest(req)));
  router.post(cfg.apiBasePath + core.DVOAuthEndpoints.tokenPath, (dv.Request req) => core.dvWithRequestTenant(req, () => core.DVOAuthEndpoints.token(req)));
  router.any(cfg.apiBasePath + core.DVOAuthEndpoints.tokenPath, (dv.Request req) async => core.DVOAuthEndpoints.otherMethod(req, allow: 'POST', crossOrigin: true));
  router.post(cfg.apiBasePath + core.DVOAuthEndpoints.introspectionPath, (dv.Request req) => core.dvWithRequestTenant(req, () => core.DVOAuthEndpoints.introspect(req)));
  router.any(cfg.apiBasePath + core.DVOAuthEndpoints.introspectionPath, (dv.Request req) async => core.DVOAuthEndpoints.otherMethod(req, allow: 'POST'));
  router.post(cfg.apiBasePath + core.DVOAuthEndpoints.revocationPath, (dv.Request req) => core.dvWithRequestTenant(req, () => core.DVOAuthEndpoints.revoke(req)));
  router.any(cfg.apiBasePath + core.DVOAuthEndpoints.revocationPath, (dv.Request req) async => core.DVOAuthEndpoints.otherMethod(req, allow: 'POST', crossOrigin: true));
  router.get(core.DVOAuthEndpoints.metadataPath, (dv.Request req) => core.DVOAuthEndpoints.metadata(req, apiBasePath: cfg.apiBasePath));
  router.any(core.DVOAuthEndpoints.metadataPath, (dv.Request req) async => core.DVOAuthEndpoints.otherMethod(req, allow: 'GET', crossOrigin: true));
''';

  /// The application's own sign-in endpoints, on every generated backend.
  ///
  /// Registered before any backend function, so a catch-all route cannot
  /// shadow them; a function declaring one of their exact paths stops the
  /// build instead. Each runs on the request's tenant. Sign-up, sign-in, the
  /// second factor and sign-out judge the session they are given themselves
  /// -- one waiting for its second factor is refused by the authentication
  /// stage, and it is the session those endpoints finish or end -- while the
  /// sessions endpoints run behind the stage and answer for the person it
  /// authenticated. Every POST is CSRF-checked, sign-in included: a login
  /// CSRF signs a victim's browser into the attacker's account.
  static String _dvAuthRouteSource() => '''
  // The application's own sign-in. Answers 503 naming DVAuthEndpoints.install
  // until the application installs its auth provider.
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.signUpPath, (dv.Request req) => core.dvWithRequestTenant(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.signUp(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.signInPath, (dv.Request req) => core.dvWithRequestTenant(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.signIn(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.secondFactorPath, (dv.Request req) => core.dvWithRequestTenant(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.secondFactor(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.signOutPath, (dv.Request req) => core.dvWithRequestTenant(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.signOut(req);
  }));
  router.get(cfg.apiBasePath + core.DVAuthEndpoints.sessionPath, (dv.Request req) => _dvStaged(req, () => core.DVAuthEndpoints.session(req)));
  router.get(cfg.apiBasePath + core.DVAuthEndpoints.sessionsPath, (dv.Request req) => _dvStaged(req, () => core.DVAuthEndpoints.sessions(req)));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.revokePath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.revoke(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.revokeOthersPath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.revokeOthers(req);
  }));
  // The signed-in person's second factors: behind the stage, so a session
  // still waiting for its own second factor changes none of them.
  router.get(cfg.apiBasePath + core.DVAuthEndpoints.factorsPath, (dv.Request req) => _dvStaged(req, () => core.DVAuthEndpoints.factors(req)));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.totpPath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.beginTotp(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.totpConfirmPath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.confirmTotp(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.recoveryCodesPath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.recoveryCodes(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.removeFactorPath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.removeFactor(req);
  }));
  // The signed-in person's account: an address change that waits for the new
  // address, and deletion behind the password, the second factor and explicit
  // confirmation.
  router.get(cfg.apiBasePath + core.DVAuthEndpoints.accountPath, (dv.Request req) => _dvStaged(req, () => core.DVAuthEndpoints.account(req)));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.emailChangePath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.requestEmailChange(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.emailVerifyPath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.verifyEmailChange(req);
  }));
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.deleteAccountPath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.deleteAccount(req);
  }));
  // A password change, behind the current password and a fresh second factor;
  // it rotates this session and revokes every other one.
  router.post(cfg.apiBasePath + core.DVAuthEndpoints.passwordPath, (dv.Request req) => _dvStaged(req, () async {
    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    return core.DVAuthEndpoints.changePassword(req);
  }));
''';

  /// The paths [_dvAuthRouteSource] serves, below the API base path. Kept
  /// beside it: a function declaring one would be shadowed and never run.
  static const List<String> dvReservedAuthPaths = <String>[
    '/auth/sign-up',
    '/auth/sign-in',
    '/auth/second-factor',
    '/auth/sign-out',
    '/auth/session',
    '/auth/sessions',
    '/auth/sessions/revoke',
    '/auth/sessions/revoke-others',
    '/auth/factors',
    '/auth/factors/totp',
    '/auth/factors/totp/confirm',
    '/auth/factors/recovery-codes',
    '/auth/factors/remove',
    '/auth/account',
    '/auth/account/email',
    '/auth/account/email/verify',
    '/auth/account/delete',
    '/auth/account/password',
  ];

  static Future<void> generate({
    required String root,
    required String backendDir,
    required String pkgName,
    /// Accepted and not written anywhere. A build id in generated files
    /// rewrote every file on every build.
    String? buildId,
    required String backendHost,
    required int backendPort,
    required String apiBasePath,
  }) async {
    final backendOut = Directory(p.join(root, '.dart_tool'));
    final libClientDir = Directory(p.join(root, 'lib', 'dartvel_client'));
    await _validateMiddlewareAnnotations(root);
    backendOut.createSync(recursive: true);
    libClientDir.createSync(recursive: true);
    // One library per lowered function, numbered by position: a function
    // removed since the last generation must not leave a file behind that
    // the next one could be mistaken for.
    for (final FileSystemEntity stale in backendOut.listSync()) {
      if (stale is File &&
          RegExp(r'^dartvel_backend_fn\d+\.g\.dart$')
              .hasMatch(p.basename(stale.path))) {
        stale.deleteSync();
      }
    }

    // Backend routes (functions): the application's own, and every mounted
    // module whose functions this backend is the one that answers them.
    final List<_DVBackendFunctionFile> fnFiles = <_DVBackendFunctionFile>[
      ..._functionFilesIn(
        projectRoot: root,
        backendDir: backendDir,
        packageName: pkgName,
        owner: null,
      ),
      ..._moduleFunctionFiles(root),
    ];
    _refuseShadowedRoutes(fnFiles);

    final methodSet = {
      'get',
      'post',
      'put',
      'patch',
      'delete',
      'head',
      'options'
    };

    final backendImports = <String>[];
    final backendEntries = <Map<String, String>>[]; // {i, method, path}

    for (var i = 0; i < fnFiles.length; i++) {
      final abs = fnFiles[i].file.path;
      // Relative to the project the file belongs to, which for a mounted
      // module is the module: its import and its route are its own, and
      // measuring either from the parent would name a package that does not
      // contain it and a path its client never asks for.
      final rel = fnFiles[i].relative;
      final pathRel = rel;
      // detect method from filename
      final base = p.basenameWithoutExtension(rel); // removes .dart
      final dot = base.lastIndexOf('.');
      // Allow filenames without explicit method suffix; default to POST
      var method = (dot != -1) ? base.substring(dot + 1).toLowerCase() : '';
      if (!methodSet.contains(method)) {
        method = 'post';
      }
      final importPath = rel.replaceFirst(
          RegExp(r'^lib/'), 'package:${fnFiles[i].packageName}/');
      final urlPath = RouteUtils.routeFromRel(pathRel, fnFiles[i].backendDir);
      // Detect typed function name from file (based on sanitized base name)
      final src = await File(abs).readAsString();
      final privateExpression = _privateBackendExpression(src, rel);
      final sourceSymbols = _topLevelPublicSourceSymbols(src);
      // Symbols that stayed in the source file are reached through its
      // import; the body itself moves into a generated library of its own.
      final String privateBodySource = privateExpression == null
          ? ''
          : (privateExpression.body.isBlock
              ? privateExpression.body.statements!
              : privateExpression.body.expression!);
      final qualifiedPrivateExpression = privateExpression == null
          ? ''
          : _qualifySourceSymbols(
              privateBodySource, _dvSourcePrefix, sourceSymbols);
      if (privateExpression == null) {
        backendImports.add("import '$importPath' as f$i;");
      }
      // Prefer explicit handler(RequestType/Request) for compatibility
      // The body modifier has to be allowed for. `Future<T> f() async => v;`
      // is how most of these are written, and a pattern that goes straight
      // from the parameter list to `=>` does not match it -- so the function
      // was not found, the file fell through to the handler shape, and the
      // generated router called f0.handler on a file that has no handler.
      final regHandler = RegExp(
          r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?handler\s*\(([^)]*)\)\s*'
          r'(?:async\*?|sync\*)?\s*(?:=>|\{)',
          multiLine: true);
      // Only a handler that takes the request is one: the router calls it
      // with the request. `handler()` and `handler({name, email})` were
      // taken for raw handlers too, and the routes called `f0.handler(req)`,
      // which does not compile. Those fall through to the typed search below
      // and are called with their arguments.
      final RegExpMatch? handlerMatch = regHandler.firstMatch(src);
      final hasHandler = handlerMatch != null &&
          _takesOnlyTheRequest(handlerMatch.group(1) ?? '');
      final baseWhole = p.basenameWithoutExtension(rel); // e.g., hello.get
      final baseNameOnly = baseWhole.contains('.')
          ? baseWhole.substring(0, baseWhole.lastIndexOf('.'))
          : baseWhole; // hello or [id] or last_read_date_[date]
      final funcCandidate =
          baseNameOnly.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
      String typedName = '';
      String typedParams = '';
      String typedTypes = '';
      String tnamed = '0';
      String rtype = '';
      String invocation = '';
      // Whether the function's first parameter is a DVContext.
      //
      // The public API rules say such a parameter is injected and is not a
      // client-supplied argument. The generator had never heard of the type
      // -- DVContext appeared nowhere in the CLI -- so it was decoded from
      // the request like any other parameter: the client supplied the
      // context, and context.lifecycle.request threw for want of a signal
      // nothing built.
      bool injectsContext = false;
      var parameterIndex = 0;
      void collect(String n, String t) {
        final String bare = t.trim().replaceAll('?', '');
        if (parameterIndex == 0 &&
            (bare == 'DVContext' || bare.endsWith('.DVContext'))) {
          injectsContext = true;
          parameterIndex++;
          return;
        }
        parameterIndex++;
        if (typedParams.isNotEmpty) {
          typedParams += ',';
          typedTypes += ',';
        }
        typedParams += n;
        typedTypes += t;
      }

      if (privateExpression != null) {
        typedName = privateExpression.publicName;
        rtype = privateExpression.returnType;
        invocation = 'bf$i.dvBackendFn$i';
        RouteUtils.extractParams(privateExpression.parameters, collect,
            onNamed: (v) => tnamed = v);
        final String modifier = privateExpression.body.modifier == null
            ? ''
            : ' ${privateExpression.body.modifier}';
        // In a library of its own that imports what the source file imports.
        // Lowered into the routes file, which imports nothing of the
        // application's, the first jsonEncode, relative helper or `as` prefix
        // a body used stopped the whole backend compiling. With the source's
        // own imports the parameters and the body mean what they meant where
        // they were written, DVContext included. A block keeps its braces,
        // and `async` is kept: without it the function returns a value where
        // the route awaits a Future.
        final String function = privateExpression.body.isBlock
            ? '${privateExpression.returnType} dvBackendFn$i(${privateExpression.parameters})$modifier {\n$qualifiedPrivateExpression\n}'
            : '${privateExpression.returnType} dvBackendFn$i(${privateExpression.parameters})$modifier => $qualifiedPrivateExpression;';
        File(p.join(backendOut.path, 'dartvel_backend_fn$i.g.dart'))
            .writeAsStringSync(_loweredFunctionLibrary(
          source: src,
          sourcePath: abs,
          relative: rel,
          packageName: fnFiles[i].packageName,
          sourceImport: importPath,
          qualified: qualifiedPrivateExpression != privateBodySource,
          function: function,
          outDir: backendOut.path,
        ));
        backendImports.add("import 'dartvel_backend_fn$i.g.dart' as bf$i;");
      } else {
        // 1) Try to find a function whose name matches the sanitized filename
        final regCandidate = RegExp(
            r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?' +
                RegExp.escape(funcCandidate) +
                r'\s*\(([^)]*)\)\s*(?:async\*?|sync\*)?\s*(?:=>|\{)',
            multiLine: true);
        final RegExpMatch? mm = regCandidate.firstMatch(src);
        // Try also to capture return type for typed API generation
        try {
          final regCandidateTyped = RegExp(
              r'^\s*([A-Za-z_][\w<>, ?]*)\s+' +
                  RegExp.escape(funcCandidate) +
                  r'\s*\(([^)]*)\)',
              multiLine: true);
          final mt = regCandidateTyped.firstMatch(src);
          if (mt != null) {
            rtype = (mt.group(1) ?? '').trim();
          }
        } catch (_) {}

        if (mm != null) {
          typedName = funcCandidate;
          RouteUtils.extractParams(mm.group(1) ?? '', collect,
            onNamed: (v) => tnamed = v);
        } else if (hasHandler) {
          // Defer to `handler(...)` style; leave untyped so router uses fN.handler
          typedName = '';
        } else {
          // 2) Fallback: detect the first top-level function declaration in the file (skip keywords)
          final regAnyFn = RegExp(
              r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?([A-Za-z_]\w*)\s*\(([^)]*)\)\s*'
              r'(?:async\*?|sync\*)?\s*(?:=>|\{)',
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
            RouteUtils.extractParams(m2.group(2) ?? '', collect,
            onNamed: (v) => tnamed = v);
            break;
          }
          // Fallback return type, if not captured yet
          if (rtype.isEmpty) {
            final regAnyTyped = RegExp(
                r'^\s*([A-Za-z_][\w<>, ?]*)?\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*'
                r'(?:async\*?|sync\*)?\s*(?:=>|\{)',
                multiLine: true);
            final m = regAnyTyped.firstMatch(src);
            if (m != null) rtype = (m.group(1) ?? 'dynamic').trim();
          }
        }
        if (typedName.isNotEmpty) {
          invocation = 'f$i.$typedName';
        }
      }
      if (dvReservedAuthPaths.contains(urlPath)) {
        throw StateError(
          '$rel declares ${method.toUpperCase()} '
          '$urlPath, which the generated backend serves for signing in. The '
          'function would never run. Move it, or install your provider with '
          'DVAuthEndpoints.install and use the generated endpoint.',
        );
      }
      final DVRawPath raw = dvRawPathFromSource(src, rel: rel);
      if (raw.rawPathSuffix != null &&
          dvReservedAuthPaths.contains('$urlPath${raw.rawPathSuffix}')) {
        throw StateError(
          '$rel declares ${method.toUpperCase()} '
          '$urlPath${raw.rawPathSuffix}, which the generated backend serves '
          'for signing in. The function would never run. Choose another '
          'rawPathSuffix.',
        );
      }
      backendEntries.add({
        'i': '$i',
        'method': method,
        'path': urlPath,
        // Where the function is served when that is not its generated path:
        // rawPath outside the API base path, rawPathSuffix after the
        // generated path. The generated path still names the client function.
        'rawPath': raw.rawPath ?? '',
        'rawPathSuffix': raw.rawPathSuffix ?? '',
        'typed': typedName,
        'tparams': typedParams,
        'ttypes': typedTypes,
        'tnamed': tnamed,
        'rtype': rtype,
        'src': src,
        'invocation': invocation,
        // The policy the function declares. Read here so the handler can
        // refuse before it runs: the specification asks backend functions to
        // enforce policies even if the UI guard is bypassed, and until now
        // neither side enforced anything.
        'policy': dvBackendPolicyFromSource(src) ?? '',
        // Whether that policy is a quoted Resource.action the registry
        // answers, rather than a name only the application's decide can.
        'policyAction': dvBackendPolicyIsAction(src) ? '1' : '0',
        // The second factor the function declares, as the expression the
        // gate evaluates. An mfa: this cannot read stops the build.
        'mfa': dvMfaFromSource(src, annotation: 'DVBackendFunction', rel: rel) ??
            '',
        // Where it was declared, for a refusal that has to name the file.
        'rel': rel,
        // And where that is on disk, in which package, so the client can
        // import the types the function names from the files that declare
        // them.
        'abs': abs,
        'pkg': fnFiles[i].packageName,
        // The middleware the function declares, in declaration order. Read
        // here for the same reason: @DVUseMiddleware had one reader in the
        // repository and it was a spelling check, so nineteen keys were
        // accepted and dropped.
        'middleware': dvMiddlewareKeysFromSource(src).join(' '),
        // Whether to build a DVContext and pass it first.
        'ctx': injectsContext ? '1' : '0',
      });
    }

    // Two functions served at one address. A raw path can land on another
    // function's, and one router answers with only one of them: the other is
    // a 404, or someone else's answer.
    final Map<String, String> servedAt = <String, String>{};
    for (final Map<String, String> e in backendEntries) {
      final String served = (e['rawPath'] ?? '').isNotEmpty
          ? e['rawPath']!
          : '<api>${e['path']}${e['rawPathSuffix'] ?? ''}';
      final String key = '${e['method']!.toUpperCase()} $served';
      final String? first = servedAt[key];
      if (first != null) {
        throw StateError(
          'dartvel: ${e['rel']} and $first are both served at $key. Change '
          'one rawPath or rawPathSuffix.',
        );
      }
      servedAt[key] = e['rel'] ?? '';
    }

    // @DVPolicy classes in the application and the modules it merges: which
    // ones the server can load, and whether each route's declared action is
    // answered by one of them. Refused here rather than left to the request,
    // where a route whose policy nobody wrote could only refuse everybody --
    // or, with an application decide that says yes, nobody.
    final List<_DVFoundPolicy> policies = await _discoverPolicies(
      root: root,
      pkgName: pkgName,
      backendDir: backendDir,
    );
    _refuseUnanswerableRoutePolicies(backendEntries, policies);
    final List<String> routeActions = <String>{
      for (final Map<String, String> e in backendEntries)
        if (e['policyAction'] == '1') e['policy']!,
    }.toList()
      ..sort();
    File(p.join(libClientDir.path, 'backend_policies.g.dart')).writeAsStringSync(
      _registrationsSource(
        library: 'dartvel_client_backend_policies',
        function: 'dartvelRegisterBackendPolicies',
        registration: 'registerDeclared',
        policies: <_DVFoundPolicy>[
          for (final _DVFoundPolicy found in policies)
            if (found.clientOnlyBecause == null) found,
        ],
      ),
    );
    for (final _DVFoundPolicy found in policies) {
      if (found.clientOnlyBecause == null) continue;
      stderr.writeln(
        'dartvel: @DVPolicy(${found.policy.resource}) '
        '${found.policy.className} in ${found.shownPath} is registered in the '
        'client only: that file reaches Flutter through '
        '${found.clientOnlyBecause}. The generated server cannot import it, so '
        'it answers ${found.policy.resource}\'s actions by default-deny; write '
        'the policy against dartvel_core, without the generated client, to '
        'enforce it on the server.',
      );
    }

    // OpenAPI: derived entirely from the discovered functions, per the spec's
    // "no manual openapi configs" rule. Written into the client so apps can
    // read it, and served by the generated backend at /openapi.json.
    final pubspecVersion = () {
      final pubspecFile = File(p.join(root, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) return '0.0.0';
      final parsed = loadYaml(pubspecFile.readAsStringSync());
      return parsed is YamlMap ? '${parsed['version'] ?? '0.0.0'}' : '0.0.0';
    }();
    final openApiDocument = buildOpenApiDocument(
      title: pkgName,
      version: pubspecVersion,
      apiBasePath: apiBasePath,
      operations: <OpenApiOperation>[
        for (final e in backendEntries)
          OpenApiOperation(
            method: e['method']!,
            path: (e['rawPath'] ?? '').isNotEmpty
                ? e['rawPath']!
                : '${e['path']!}${e['rawPathSuffix'] ?? ''}',
            outsideApiBase: (e['rawPath'] ?? '').isNotEmpty,
            name: e['typed'] ?? '',
            parameterNames: (e['tparams'] ?? '')
                .split(',')
                .where((String s) => s.isNotEmpty)
                .toList(),
            parameterTypes: (e['ttypes'] ?? '')
                .split(',')
                .where((String s) => s.isNotEmpty)
                .toList(),
            returnType: e['rtype'] ?? '',
          ),
      ],
    );
    final openApiJson = encodeOpenApiDocument(openApiDocument);
    // The models' tables, as the model generator wrote them down, for the
    // server to make on SQLite before it serves. Carried in the generated
    // source because a compiled server has no project beside it to read.
    final File schemaFile = File(p.join(root, '.dart_tool', 'dartvel_schema.g.json'));
    Object? schemaTables = const <Object?>[];
    if (schemaFile.existsSync()) {
      final Object? decoded = jsonDecode(schemaFile.readAsStringSync());
      if (decoded is Map && decoded['tables'] is List) {
        schemaTables = decoded['tables'];
      }
    }
    final String schemaTablesJson = jsonEncode(schemaTables);
    File(p.join(libClientDir.path, 'openapi.g.dart')).writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_client_openapi;

/// The generated OpenAPI 3.1 document for this application's backend
/// functions, as JSON. Served by the generated backend at
/// `<apiBasePath>/openapi.json`.
const String dartvelOpenApiJson = r\'\'\'
$openApiJson\'\'\';
''');

    // The Content-Security-Policy this application sends, handed to the
    // runtime where the server starts. Emitted only when the project set
    // one: a route declaring the key without it never gets this far, because
    // the middleware validator refuses that build.
    // dartvel.server: the CORS policy this application answers with and
    // whether responses are compressed. Both are decided once, where the
    // server starts, which is why declaring either as a route middleware is
    // refused -- and until now the refusal pointed at a serve call the
    // application does not write.
    // dartvel.seo.favicon: what a model page wears when neither the model
    // nor its module named one. Null emits null, which leaves the shell's.
    final String? seoFavicon = _dvSeoFavicon(root);
    final String applicationFavicon =
        seoFavicon == null ? 'null' : "'${esc(seoFavicon)}'";
    final DVServerOptions server = dvServerOptions(root);
    // dartvel.api.graphql: the budgets, introspection policy and
    // persisted-query mode /graphql answers under, installed in
    // buildBackendRouter so a mounted router gets them too. Nothing is
    // emitted when the project declares none, which leaves whatever the
    // application set on DVGraphQL in code.
    final DVGraphQLApiOptions? graphqlOptions = dvGraphQLApiOptions(root);
    // dartvel.crashes, with the runtime's own parser: whether this backend
    // serves the crash endpoint, and what it accepts there.
    final DVCrashConfig crashes = _dvCrashConfig(root);
    final bool servesCrashes = crashes.sink == DVCrashSinkChoice.dartvel;
    // The release a server's crash report names: the pubspec version, as the
    // client's does, so one release's reports from both ends group together.
    final String crashRelease = _dvCrashRelease(root);
    // dartvel.platformApi: whether every route authenticates API keys and
    // OAuth tokens, and whether this backend is an OAuth provider. Read with
    // the parser the registry is generated from.
    final DVPlatformApiConfig? platformApi = () {
      final File pubspec = File(p.join(root, 'pubspec.yaml'));
      if (!pubspec.existsSync()) return null;
      final Object? doc = loadYaml(pubspec.readAsStringSync());
      final Object? dartvel = doc is Map ? doc['dartvel'] : null;
      return dartvel is Map ? PlatformApiGenerator.read(dartvel) : null;
    }();
    final bool authenticates = platformApi != null;
    final String? corsSource = server.corsSource;
    final String corsConstant = corsSource ?? 'null';
    final String compressionLiteral = server.compression ? 'true' : 'false';
    // dartvel.tenancy: which isolation strategy, where the tenant is read
    // from, and whether a request naming none is refused. Emitted where the
    // server starts, which is the only place an application has that runs
    // before anything is served.
    final String tenancyConfiguration = _dvTenancyConfiguration(root);
    final String? csp = _dvContentSecurityPolicy(root);
    // shorebird.yaml: a base_url naming anything but Shorebird's service
    // says the patches come from this application's own server.
    final String? patchSourcePrefix = dvPatchSourcePrefix(root);
    final String patchSourceLiteral = patchSourcePrefix == null
        ? 'null'
        : "'${esc(patchSourcePrefix)}'";
    final String cspAssignment = csp == null
        ? ''
        : "\n  core.DVMiddlewareSettings.contentSecurityPolicy = "
            "'${esc(csp)}';";

    // Every mounted module's models, for Studio beside the application's:
    // embedded and backend-only modules, whose data this backend serves, and
    // only once the module's own client is generated.
    final List<(String, String)> studioModules = <(String, String)>[
      for (final (int i, DVModuleMount mount)
          in dvDiscoverModuleMounts(root).indexed)
        if (mount.mounted &&
            (mount.deployment == DVModuleDeployment.embedded ||
                mount.deployment == DVModuleDeployment.backendOnly) &&
            File(p.join(root, mount.sourcePath, 'lib', 'dartvel_client',
                    'model_pages.g.dart'))
                .existsSync())
          (mount.packageName, 'dvStudioModule$i'),
    ];
    final backendRoutes = '''
// GENERATED – do not edit.
// ignore_for_file: unused_element
import 'dart:async';
import 'dart:convert' as conv;
import 'dart:io';
import 'dart:typed_data';
import 'package:dartvel_core/dartvel.dart' as core;
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:mime/mime.dart';
import 'dartvel_backend.g.dart' as cfg;
import 'package:$pkgName/dartvel_client/model_pages.g.dart' show dartvelModelPages, dartvelStudioModels;
${studioModules.map(((String, String) m) => "import 'package:${m.$1}/dartvel_client/model_pages.g.dart' as ${m.$2} show dartvelStudioModels;\n").join()}import 'package:$pkgName/dartvel_client/modules_data.g.dart' show registerDartvelModules;
import 'package:$pkgName/dartvel_client/schedules.g.dart' show dartvelBackendCronEntries, dartvelStartBackendSchedules;
import 'package:$pkgName/dartvel_client/ai_tools.g.dart' show registerDartvelAITools;
import 'package:$pkgName/dartvel_client/analytics.g.dart' show configureDartvelAnalytics;
import 'package:$pkgName/dartvel_client/http.g.dart' show configureDartvelHttp;
import 'package:$pkgName/dartvel_client/account.g.dart' show configureDartvelBackendAccounts, dartvelStartAccountDeletionSweep;
import 'package:$pkgName/dartvel_client/privacy.g.dart' show configureDartvelBackendPrivacy;
import 'package:$pkgName/dartvel_client/jobs.g.dart' show dartvelClientOnlyJobHandlers, registerDartvelJobs;
import 'package:$pkgName/dartvel_client/backend_policies.g.dart' show dartvelRegisterBackendPolicies;
${authenticates ? "import 'package:$pkgName/dartvel_client/platform_api.g.dart' show dartvelPlatformApi;\n" : ''}${backendImports.join('\n')}

// The generated OpenAPI document, served at cfg.apiBasePath + '/openapi.json'.
const String _dvOpenApiJson = r\'\'\'
$openApiJson\'\'\';

// The generated models' tables: each statement and its columns.
const String _dvSchemaTablesJson = r\'\'\'
$schemaTablesJson\'\'\';

/// The database this process shares, made ready before anything uses it.
///
/// DV.Database is that database when the application configured none: a
/// backend function or a model with nothing configured otherwise threw on
/// its first query. On SQLite the models' tables are made, and the columns a
/// table from an earlier release is missing are added -- a web-server
/// binary's first run creates the file and everything in it. PostgreSQL and
/// MySQL are migrated with `dartvel db migrate`, where a blocking change is
/// gated rather than run by whichever instance starts first.
Future<void> _dartvelPrepareDatabase(core.DVProcessStores stores) async {
  final core.DVDatabaseAdapter? database = stores.database;
  if (database == null) return;
  if (const core.DVDatabase().configuredAdapter == null) {
    const core.DVDatabase().configure(database);
  }
  if (stores.connection?.engine != core.DVDatabaseEngine.sqlite) return;
  final List<Map<String, Object?>> tables = <Map<String, Object?>>[
    for (final Object? table in conv.jsonDecode(_dvSchemaTablesJson) as List<Object?>)
      (table! as Map<Object?, Object?>).cast<String, Object?>(),
  ];
  final core.DVGeneratedSchemaReport report = await core.dvApplyGeneratedSchema(
    database,
    tables,
    engine: core.DVDatabaseEngine.sqlite,
  );
  for (final String table in report.created) {
    stdout.writeln('dartvel: created table \$table');
  }
  for (final String column in report.added) {
    stdout.writeln('dartvel: added column \$column');
  }
  for (final String table in report.needsTenant) {
    stderr.writeln('dartvel: \$table has rows and no tenant column; run dartvel db migrate --tenant to say whose they are.');
  }
}


// Multipart structures and parser (bytes): collects text fields and files
class DvMultipartFile {
  final String name;
  final String filename;
  final String contentType;
  final Uint8List bytes;
  DvMultipartFile(this.name, this.filename, this.contentType, this.bytes);
}

Future<Map<String, Object?>> _parseMultipart(
    Stream<List<int>> stream, String contentType) async {
  final boundary = RegExp(r'boundary=([^;]+)').firstMatch(contentType)?.group(1)?.replaceAll('"', '') ?? '';
  if (boundary.isEmpty) return {};
  final transformer = MimeMultipartTransformer(boundary);
  final parts = stream.transform(transformer);
  final out = <String, Object?>{};
  await for (final part in parts) {
    final headers = part.headers;
    final cd = headers['content-disposition'] ?? '';
    final name = RegExp(r'name="([^"]+)"').firstMatch(cd)?.group(1) ?? '';
    final filename = RegExp(r'filename="([^"]*)"').firstMatch(cd)?.group(1);
    if (filename != null) {
      final bytes = await part.toList().then((chunks) => chunks.expand((x) => x).toList());
      out[name] = DvMultipartFile(name, filename, headers['content-type'] ?? '', Uint8List.fromList(bytes));
    } else if (headers['content-type'] == core.dvFlatContentType) {
      // A field packed as a binary flat buffer. Decoded as text it would reach
      // a typed parameter as the bytes that spell it, and an int parameter
      // would quietly become 0 while the request returned 200.
      final bytes = await part.toList().then((chunks) => chunks.expand((x) => x).toList());
      out[name] = core.dvFlatDecode(Uint8List.fromList(bytes));
    } else {
      final content = await conv.utf8.decodeStream(part);
      out[name] = content;
    }
  }
  return out;
}

bool _dvValidateCsrf(dv.Request req, Object? body) {
  return const core.DVCSRF().validateRequest(
    method: req.method,
    headerToken: req.headers.get(core.DVCSRF.headerName),
    bodyToken: body is Map ? body[core.DVCSRF.fieldName]?.toString() : null,
  );
}

/// Whether this request may run a function guarded by [policy].
///
/// Asks the same default-deny surface every other policy in the application
/// is answered by: can() returns false for a policy nobody registered, which
/// is the right answer to a question the application never taught it.
Future<bool> _dvAllowed(String policy, dv.Request req) =>
    core.DVBackendPolicy.allows(policy, req.url.path);

dv.Response _dvPolicyForbidden(String policy) => dv.Response(403,
    headers: dv.Headers({'content-type': 'text/plain; charset=utf-8'}),
    body: Stream<List<int>>.value(
        conv.utf8.encode('Not authorized (\$policy)')));

/// Nobody authenticated, on a route whose policy needs a caller. 401 rather
/// than the 403 a refused caller gets: signing in is the answer, and a client
/// told so can send the person to sign in instead of to a page saying they
/// may not.
dv.Response _dvUnauthenticated() => dv.Response(401,
    headers: dv.Headers({
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'no-store',
      'www-authenticate': 'Bearer',
    }),
    body: Stream<List<int>>.value(conv.utf8.encode('Unauthorized')));

/// The authentication stage.${authenticates ? r'''
/// An API key or OAuth access token on the request becomes
/// core.DVApiPrincipal.current for the rest of it, checked against the
/// tenant the request resolved to.''' : ''}
/// The application's own session -- a `Bearer dvs_` token or the session
/// cookie -- becomes core.DVSessionPrincipal.current, on the tenant it was
/// issued on and with the user read again for this request, so a route policy
/// is asked about the person signed in rather than about nobody. A request
/// carrying none of these runs unchanged. A refusal is fixed text with nothing
/// of the credential in it, and is never cached; a session that does not
/// authenticate is refused on every route, because a revoked session fails its
/// next request rather than being read as an anonymous one.
///
/// A raw path passes [cookies] false: it is called by other servers, and a
/// cookie is the credential a browser attaches to a cross-site request on its
/// own. Not reading it is what lets a raw path take a POST without a CSRF
/// token and still give a forged one no session to act as.
Future<dv.Response> _dvAuthenticated(
  dv.Request req,
  Future<dv.Response> Function() run, {
  bool cookies = true,
}) async {${authenticates ? r'''
  final core.DVApiAuthentication auth =
      await core.DVPlatformApi.authenticateRequest(req.headers.get('authorization'));
  if (auth.refused) {
    return dv.Response(auth.status!,
        headers: dv.Headers({
          'content-type': 'text/plain; charset=utf-8',
          'cache-control': 'no-store',
          if (auth.challenge != null) 'www-authenticate': auth.challenge!,
        }),
        body: Stream<List<int>>.value(conv.utf8.encode(auth.message!)));
  }
  final core.DVApiPrincipal? principal = auth.principal;
  if (principal != null) return core.DVApiPrincipal.actingAs(principal, run);''' : ''}
  final core.DVSessionAuthenticationResult session =
      await core.DVSessionAuthentication.authenticateRequest(
          authorization: req.headers.get('authorization'),
          cookie: cookies ? req.headers.get('cookie') : null);
  if (session.refused) {
    return dv.Response(session.status!,
        headers: dv.Headers({
          'content-type': 'text/plain; charset=utf-8',
          'cache-control': 'no-store',
          if (session.challenge != null) 'www-authenticate': session.challenge!,
          if (session.clearCookie != null) 'set-cookie': session.clearCookie!,
        }),
        body: Stream<List<int>>.value(conv.utf8.encode(session.message!)));
  }
  final core.DVSessionPrincipal? signedIn = session.principal;
  if (signedIn == null) return run();
  return core.DVSessionPrincipal.actingAs(signedIn, run);
}

/// The tenant scope and authentication stage for a route that is not a
/// backend function: GraphQL, the crash endpoint, OpenAPI and health.
///
/// Each was registered bare, so a key for another tenant was refused with a
/// 401 on a function's route and not looked at here -- where a GraphQL
/// mutation then ran with nothing checked. A credential is judged here exactly
/// as it is there, and refused with the same answer.
Future<dv.Response> _dvStaged(
  dv.Request req,
  Future<dv.Response> Function() run,
) =>
    core.dvWithRequestTenant(req, () => _dvAuthenticated(req, run));

/// Runs a route's declared middleware around its handler.
///
/// Both halves of this were missing. A refusal has to answer before the
/// function runs -- a rate limit that arrives after the charge went through
/// is not a rate limit -- and the headers the chain resolves have to reach a
/// response, which they never did while securityHeaders wrote them into a
/// map nothing downstream read.
Future<dv.Response> _dvGuarded(
  dv.Request req,
  List<String> keys,
  Future<dv.Response> Function() run,
) async {
  final core.DVMiddlewareResult mw = await core.dvRunMiddlewares(keys, req);
  if (!mw.allowed) {
    // The message is fixed text chosen by the runtime. Nothing from the
    // request is echoed back into it.
    return dv.Response(mw.status,
        headers: dv.Headers({'content-type': 'text/plain; charset=utf-8'}),
        body: Stream<List<int>>.value(conv.utf8.encode(mw.message)));
  }
  final dv.Response response = await run();
  mw.headers.forEach(response.headers.set);
  return response;
}

/// A body bigger than the route said it would read.
///
/// 413 with the number in it. A refusal that does not say what would have
/// been accepted leaves the caller guessing, and the limit is the contract
/// rather than a secret.
dv.Response _dvTooLarge(int limit) => dv.Response(413,
    headers: dv.Headers({'content-type': 'text/plain; charset=utf-8'}),
    body: Stream<List<int>>.value(
        conv.utf8.encode(core.dvTooLargeMessage(limit))));

${servesCrashes ? '/// The crash endpoint\'s ingest, built on the first report.\ncore.DVCrashIngest? _dartvelCrashIngest;\n\n' : ''}dv.Response _dvCsrfForbidden() => dv.Response(403,
    headers: dv.Headers({'content-type': 'text/plain; charset=utf-8'}),
    body: Stream<List<int>>.value(conv.utf8.encode('CSRF token missing')));

dv.Router buildBackendRouter() {
  // Every @DVPolicy class this server can load, from the application and the
  // modules it merges, registered before a single route exists -- so no
  // request can be answered by an empty registry, whether the router is
  // served by startBackend or mounted by somebody else's server. Then every
  // Resource.action a route declares must be registered, or nothing is
  // served: the build has already refused an action no policy class defines,
  // and what is left is a framework action the application registers itself.
  dartvelRegisterBackendPolicies();
  core.DVBackendPolicy.verifyRegistered(const <String>[${routeActions.map((String a) => "'$a'").join(', ')}]);
${graphqlOptions?.installSource ?? ''}  final router = dv.Router();
${_dvAuthRouteSource()}  bool _hasHealth = false;
${backendEntries.map((e) {
      final path = esc(e['path'] ?? '');
      // The address the route is registered at: a rawPath as written, outside
      // the API base path, or the generated path with any suffix.
      final String rawPath = e['rawPath'] ?? '';
      // Raw HTTP exposure, for callers that are not this application's
      // pages: no session cookie is read and no CSRF token is asked for.
      final bool rawExposure =
          rawPath.isNotEmpty || (e['rawPathSuffix'] ?? '').isNotEmpty;
      final String routeTarget = rawPath.isNotEmpty
          ? "'${esc(rawPath)}'"
          : "cfg.apiBasePath + '$path${esc(e['rawPathSuffix'] ?? '')}'";
      final method = e['method']!;
      final i = e['i']!;
      final typed = e['typed'] ?? '';
      final invocation = e['invocation'] ?? 'f$i.$typed';

      // The declared middleware, wrapped around the handler rather than
      // emitted inside it: a refusal has to answer before the function runs,
      // and the headers securityHeaders resolves have to reach a response
      // that exists, which they never did while the chain put them in a map
      // nothing downstream read.
      final List<String> middlewareKeys = (e['middleware'] ?? '')
          .split(' ')
          .where((String key) => key.isNotEmpty)
          .toList(growable: false);
      // Tracing wraps everything, including the chain. A request refused by
      // a rate limit is still a request, and a trace that only covers the
      // ones that got through is a latency graph with the slow half missing.
      //
      // The helper existed, was tested, and was wired to nothing -- the key
      // named it and the generator had never heard of either.
      final bool traces = middlewareKeys.contains('tracing');
      final List<String> chainKeys = middlewareKeys
          .where((String key) => key != 'tracing')
          .toList(growable: false);

      // Built rather than written out for each combination: a miscounted
      // bracket here is a generated file that does not parse, and the error
      // names a line nobody wrote.
      //
      // The innermost closure is always the handler body. Each wrapper adds
      // one `)` to the close, and the router call adds the last one. The
      // traced closure takes the request again under the same name, so the
      // body reads `req` whether it is traced or not.
      final StringBuffer open = StringBuffer('(dv.Request req) => ');
      int wrappers = 0;
      // The tenant this request named, current for everything below --
      // the chain, the policy gate and the handler.
      //
      // On every route, not only the ones that listed
      // DVMiddlewares.tenant, because a tenant-scoped model does not care
      // what the route declared. And outermost, because the chain is async
      // too: the locale middleware asks this tenant for its default
      // language.
      //
      // What this replaced was a write to a process-wide field. A server
      // has more than one request in flight and Dart hands the isolate over
      // at every await, so the next request to arrive decided what this
      // handler read from there -- and the query still returned rows, of
      // somebody else's tenant.
      //
      // Each layer is a call taking the next as a closure, outermost first,
      // and the last closure is the handler body. The authentication stage
      // sits inside tracing, so a refused credential is still a traced
      // request, and outside the declared chain, so a route's middleware
      // runs knowing who is calling.
      final List<(String, String)> layers = <(String, String)>[
        ('core.dvWithRequestTenant(req, ', '()'),
        if (traces)
          ('core.dvTraced(core.DVObservability.tracer, req, ',
              '(dv.Request req)'),
        // On every route, with or without dartvel.platformApi: the
        // application's own sessions authenticate here too.
        (rawExposure
            ? '_dvAuthenticated(req, cookies: false, '
            : '_dvAuthenticated(req, ',
            '()'),
        if (chainKeys.isNotEmpty)
          (
            '_dvGuarded(req, const <String>['
                "${chainKeys.map((String k) => "'$k'").join(', ')}"
                '], ',
            '()'
          ),
      ];
      for (int layer = 0; layer < layers.length; layer++) {
        final (String call, String parameters) = layers[layer];
        open
          ..write(call)
          ..write(parameters)
          ..write(layer == layers.length - 1 ? ' async {' : ' => ');
        wrappers++;
      }

      // Always at least the tenant scope, so there is no unwrapped form of
      // a route left to fall back to.
      final String handlerOpen = open.toString();
      final String handlerClose = '  }${')' * wrappers});';

      // The declared body limits, read once where the router is built and
      // handed to the native server as well as to the check in the handler.
      //
      // The native server reads the body before any Dart runs, so a limit
      // only the handler knows is checked after the whole body is already in
      // memory. Registered on the route, the server refuses past it without
      // buffering, and an upload route reads past the server's limit without
      // every route doing so. Read once rather than per request, so the two
      // cannot disagree: a DVBodyLimits changed after the backend starts
      // would otherwise be checked in Dart and not by the server.
      final bool limitsBody = middlewareKeys.contains('bodyLimit');
      final bool limitsUpload = middlewareKeys.contains('uploadLimit');
      final String limitDeclarations = <String>[
        if (limitsBody) '  final int _dvBodyLimit$i = core.DVBodyLimits.body;\n',
        if (limitsUpload)
          '  final int _dvUploadLimit$i = core.DVBodyLimits.upload;\n',
      ].join();
      // Both declared is the larger for the server; the check below still
      // holds a body that is not multipart to the smaller.
      final String routeLimit = limitsBody && limitsUpload
          ? '_dvUploadLimit$i > _dvBodyLimit$i ? _dvUploadLimit$i : _dvBodyLimit$i'
          : limitsUpload
              ? '_dvUploadLimit$i'
              : limitsBody
                  ? '_dvBodyLimit$i'
                  : '';
      final String routeClose = routeLimit.isEmpty
          ? handlerClose
          : '  }${')' * wrappers}, maxBodyBytes: $routeLimit);';

      final String policy = e['policy'] ?? '';
      // The declared second factor, asked before the policy: whether the
      // session proves enough is an authentication question, and a policy is
      // asked about a caller once that is settled.
      final String mfa = e['mfa'] ?? '';
      final String mfaGate = mfa.isEmpty
          ? ''
          : '\n    {'
              '\n      final _dvStepUp = core.DVAuthEndpoints.requireMfa($mfa);'
              '\n      if (_dvStepUp != null) return _dvStepUp;'
              '\n    }';
      // A route that declares no policy action is one no scope can cover, so
      // a request authenticated with an API key or OAuth token is refused
      // there rather than run with a caller nothing checked.
      final String policyGate = policy.isEmpty
          ? (authenticates
              ? '\n    if (core.DVApiPrincipal.current != null) '
                  "return _dvPolicyForbidden('no declared policy action');"
              : '')
          // A Resource.action is asked of the registry the @DVPolicy classes
          // were registered in; a reference names no action, so only the
          // application's decide can answer it.
          : e['policyAction'] == '1'
              // 401 when nobody authenticated and the policy needs a caller,
              // 403 for every other refusal.
              ? "\n    switch (await core.DVBackendPolicy.checkAction('$policy', req.url.path)) {"
                  '\n      case core.DVPolicyDecision.allowed:'
                  '\n        break;'
                  '\n      case core.DVPolicyDecision.unauthenticated:'
                  '\n        return _dvUnauthenticated();'
                  '\n      case core.DVPolicyDecision.forbidden:'
                  "\n        return _dvPolicyForbidden('$policy');"
                  '\n    }'
              : "\n    if (!await _dvAllowed('$policy', req)) "
                  "return _dvPolicyForbidden('$policy');";

      if (typed.isEmpty) {
        // A raw handler owns the request, so there is no body prelude and no
        // argument to decode. It still has to be guarded: a policy declared
        // on one of these was read, recorded and never emitted, so
        // @DVBackendFunction(policy: ...) on a raw handler was a route
        // anybody could call.
        // No shortcut for the plainest raw handler any more. It used to be
        // registered bare, which meant the one kind of route that reads the
        // request itself ran with no tenant scope around it.
        return '''$limitDeclarations  router.$method($routeTarget, $handlerOpen$mfaGate$policyGate
    return await f$i.handler(req);
$routeClose''';
      }
      final tparams =
          (e['tparams'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
      final ttypes = (e['ttypes'] ?? '').split(',');
      final tnamed = e['tnamed'] == '1';

      final argList = <String>[];
      for (var idx = 0; idx < tparams.length; idx++) {
        final pn = tparams[idx];
        final pt = idx < ttypes.length ? ttypes[idx] : '';
        final expr = RouteUtils.coerce(pn, pt);
        argList.add(tnamed ? ('$pn: $expr') : expr);
      }
      // The injected context, first and positional, ahead of whatever the
      // client supplied.
      final bool injectsContext = e['ctx'] == '1';
      final callArgs =
          (injectsContext ? <String>['_dvCtx', ...argList] : argList)
              .join(', ');
      // Built per request, because the lifecycle it carries is this
      // request's. Only where a function asked: a context nothing reads is a
      // cost on every request for the functions that did not.
      final String contextPrelude = injectsContext
          ? '\n    final _dvLifecycle = '
              'core.DVMutableLifecycleSignal<core.DVRequestLifecycle>('
              'core.DVRequestLifecycle.received);'
              '\n    final _dvCtx = core.DVContext(requestLifecycle: '
              '_dvLifecycle);'
              '\n    _dvLifecycle.set(core.DVRequestLifecycle.executing);'
              '\n    var _dvCommitted = false;'
          : '';
      // After the function returns and before the response is encoded. Not
      // completed: the body may be a stream this handler no longer owns, and
      // reporting a request complete while it is still sending would be a
      // state that lies rather than one that is missing.
      final String contextDone = injectsContext
          ? '\n      _dvLifecycle.set('
              'core.DVRequestLifecycle.preparingResponse);'
              // The hooks the function registered on its context. The context
              // is per request and not a DV.transaction, so without this
              // afterCommit and compensate filled lists nothing read. Marked
              // committed first: after-commit work that throws cannot undo a
              // function that already succeeded.
              '\n      _dvCommitted = true;'
              '\n      await core.dvCommitContext(_dvCtx);'
          : '';
      final String contextFailed = injectsContext
          ? '      _dvLifecycle.set(core.DVRequestLifecycle.failed);'
              '\n      if (!_dvCommitted) {'
              '\n        for (final _dvFailure in await core.dvCompensateContext(_dvCtx)) {'
              "\n          stderr.writeln('[dartvel backend] compensation failed: \$_dvFailure');"
              '\n        }'
              '\n      }'
          : '';
      // The declared body limit, enforced where the body is read.
      //
      // bodyLimit and uploadLimit cannot be middleware in the ordinary
      // sense: the chain runs around the handler, and by the time it has
      // anything to say the body is already in memory. A limit that arrives
      // after the read is not a limit. So the check is emitted here, and
      // only for a route that asked -- one on every route would refuse the
      // upload endpoint nobody limited.
      // Declaring both means each shape gets its own number, which is the
      // point of there being two: a JSON body of several megabytes is a
      // mistake, and an upload of several megabytes is the feature. The
      // numbers are the ones registered with the server above.
      final String limitExpr = limitsBody && limitsUpload
          ? "ct.contains('multipart/form-data') "
              '? _dvUploadLimit$i : _dvBodyLimit$i'
          : limitsUpload
              ? '_dvUploadLimit$i'
              : '_dvBodyLimit$i';
      final String readBody = limitsBody || limitsUpload
          ? '''        final _dvLimit = $limitExpr;
        if (core.dvDeclaredTooLarge(
            contentLength: req.headers.get('content-length'),
            limit: _dvLimit)) {
          return _dvTooLarge(_dvLimit);
        }
        final _dvBody = await core.dvReadCapped(req.body.stream, _dvLimit);
        if (_dvBody == null) return _dvTooLarge(_dvLimit);
        if (ct.contains('multipart/form-data')) {
          body = await _parseMultipart(Stream<List<int>>.value(_dvBody), ct);
        } else {
          final raw = conv.utf8.decode(_dvBody, allowMalformed: true);'''
          : '''        if (ct.contains('multipart/form-data')) {
          body = await _parseMultipart(req.body.stream, ct);
        } else {
          final raw = await req.body.text();''';

      final requestPrelude = '''    Object? body;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        final ct = req.headers.get('content-type') ?? '';
$readBody
          if (ct.contains('application/json')) {
            body = raw.isEmpty ? null : conv.jsonDecode(raw);
          } else if (ct.contains('application/x-www-form-urlencoded')) {
            try { body = Uri.splitQueryString(raw); } catch (_) { body = <String,String>{}; }
          } else {
            body = raw;
          }
        }
      }
    } catch (e) { /* ignore body read errors */ }${rawExposure ? '' : "\n    if (${authenticates ? 'core.DVApiPrincipal.current == null && ' : ''}!_dvValidateCsrf(req, body)) return _dvCsrfForbidden();"}''';

      // The policy gate, after the body is read so CSRF still runs first and
      // before the function is called. Emitted per route rather than wrapped
      // around the router, because a policy belongs to one function and a
      // middleware that guessed which would be the same silence again.
      if (path == '/health' && method.toLowerCase() == 'get') {
        return "  _hasHealth = true;\n"
            '''$limitDeclarations  router.$method($routeTarget, $handlerOpen
$requestPrelude$mfaGate$policyGate$contextPrelude
    try {
      Object? result = await $invocation($callArgs);$contextDone
      if (result is dv.Response) return result;
      if (result is Stream<List<int>>) return dv.Response(200, body: result);
      if (result is Stream) {
        return dv.Response(200,
            headers: dv.Headers({
              'content-type': 'text/event-stream; charset=utf-8',
              'cache-control': 'no-cache',
              'connection': 'keep-alive',
            }),
            // One JSON value per event, which is what the generated client
            // decodes. toString() sent an object as "Instance of ...", and a
            // newline split one value into two events; JSON has neither.
            body: result.map((e) => 'data: \${conv.jsonEncode(e)}\\n\\n').map(conv.utf8.encode),
            isStream: true);
      }
      if (result is String) return dv.Response.text(result);
      return dv.Response(200,
          headers: dv.Headers({'content-type': 'application/json; charset=utf-8'}),
          body: Stream<List<int>>.value(conv.utf8.encode(conv.jsonEncode(result))));
    } catch (e, st) {
$contextFailed
      // Written before anything else in the error path, and never throws.
      core.DVServerCrashes.record(e, st);
      stderr.writeln('[dartvel backend] ERROR in ${method.toUpperCase()} $path: \${e.toString()}');
      stderr.writeln(st);
      return dv.Response(500, body: Stream<List<int>>.value(conv.utf8.encode('Internal Server Error')));
    }
$routeClose''';
      }
      return '''$limitDeclarations  router.$method($routeTarget, $handlerOpen
$requestPrelude$mfaGate$policyGate$contextPrelude
    try {
      Object? result = await $invocation($callArgs);$contextDone
      if (result is dv.Response) return result;
      if (result is Stream<List<int>>) return dv.Response(200, body: result);
      if (result is Stream) {
        return dv.Response(200,
            headers: dv.Headers({
              'content-type': 'text/event-stream; charset=utf-8',
              'cache-control': 'no-cache',
              'connection': 'keep-alive',
            }),
            // One JSON value per event, which is what the generated client
            // decodes. toString() sent an object as "Instance of ...", and a
            // newline split one value into two events; JSON has neither.
            body: result.map((e) => 'data: \${conv.jsonEncode(e)}\\n\\n').map(conv.utf8.encode),
            isStream: true);
      }
      if (result is String) return dv.Response.text(result);
      return dv.Response(200,
          headers: dv.Headers({'content-type': 'application/json; charset=utf-8'}),
          body: Stream<List<int>>.value(conv.utf8.encode(conv.jsonEncode(result))));
    } catch (e, st) {
$contextFailed
      // Written before anything else in the error path, and never throws.
      core.DVServerCrashes.record(e, st);
      stderr.writeln('[dartvel backend] ERROR in ${method.toUpperCase()} $path: \${e.toString()}');
      stderr.writeln(st);
      return dv.Response(500, body: Stream<List<int>>.value(conv.utf8.encode('Internal Server Error')));
    }
$routeClose''';
    }).join('\n')}
  if (!_hasHealth) {
    // Public, because a load balancer asks it with no credential. A credential
    // that is presented is still judged, so a bad one is refused here as it is
    // everywhere else rather than read as a sign this route checks nothing.
    router.get(cfg.apiBasePath + '/health', (dv.Request req) => _dvStaged(req, () async => dv.Response.text('ok')));
  }
  // GraphQL: whatever the application registered on DVGraphQL, served on
  // the spec-shaped POST body {query, variables, operationName}, on the
  // request's tenant and behind the authentication stage. Each field declaring
  // a policy is asked it as its backend function's route asks it, so a key's
  // scopes apply to a mutation as they do to the function it resolves through.
  // The SDL document at /graphql/schema is the machine-readable schema.
  router.post(cfg.apiBasePath + '/graphql', (dv.Request req) => _dvStaged(req, () async {
    final text = await req.body.text();
    final decoded = text.isEmpty ? const <String, Object?>{} : conv.jsonDecode(text);
    // The whole body, so the persisted-query hash at
    // extensions.persistedQuery.sha256Hash reaches the manifest.
    final result = await core.DVGraphQL.executeRequest(
      decoded,
      authenticated: core.DVApiPrincipal.current != null || core.DVSessionPrincipal.current != null,
    );
    return dv.Response.json(result);
  }));
  router.get(cfg.apiBasePath + '/graphql/schema', (dv.Request req) => _dvStaged(req, () async =>
      dv.Response.text(core.DVGraphQL.toSdl())));
  // Subscriptions over Server-Sent Events. The server has no WebSocket, and
  // SSE is a standard GraphQL transport, so a subscription is reachable
  // today rather than waiting on one.
  router.post(cfg.apiBasePath + '/graphql/stream', (dv.Request req) => _dvStaged(req, () async {
    final text = await req.body.text();
    final decoded = text.isEmpty ? const <String, Object?>{} : conv.jsonDecode(text);
    // Subscribed here, inside the request's tenant and authentication, which
    // is who the subscription runs as: the stream below is written from
    // wherever the server calls it.
    final events = core.DVGraphQL.subscribeRequest(
      decoded,
      authenticated: core.DVApiPrincipal.current != null || core.DVSessionPrincipal.current != null,
    );
    return dv.Response.stream(
      (sink) {
        late StreamSubscription<Map<String, Object?>> sub;
        sub = events.listen(
          (event) => sink.add(conv.utf8.encode(
              'data: \${conv.jsonEncode(event)}\\n\\n')),
          onDone: () {
            sink.close();
          },
          onError: (Object error) {
            sink.add(conv.utf8.encode(
                'data: \${conv.jsonEncode(<String, Object?>{'errors': <Object?>[<String, Object?>{'message': '\$error'}]})}\\n\\n'));
            sink.close();
          },
        );
        // Nothing else cancels it: when the response sink closes, the
        // subscription must go with it or the producer runs forever.
        sink.done.whenComplete(sub.cancel);
      },
      headers: dv.Headers({
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache',
      }),
    );
  }));
${platformApi?.oauth != null ? _dvOAuthRouteSource() : ''}${servesCrashes ? _dvCrashRouteSource(crashes) : ''}  // The API reference is public documentation, so a partner's tooling that
  // sends its key with every request is answered; a bad credential is not.
  router.get(cfg.apiBasePath + '/openapi.json', (dv.Request req) => _dvStaged(req, () async =>
      dv.Response(200,
          headers: dv.Headers({'content-type': 'application/json'}),
          body: Stream<List<int>>.value(conv.utf8.encode(_dvOpenApiJson)))));
  return router;
}

dv.Router buildBackend() => buildBackendRouter();

/// A public model page's data on request: the row named by the route's
/// parameter, read from the application's database.
final core.DVPageDataResolver dartvelPageData = core.dvModelPageResolver(
  dartvelModelPages,
  (String sql, List<Object?> params) => const core.DVDatabase().query(sql, params),
  // The last of the specification's three fallbacks -- model, module,
  // application. The first two are already in the spec each model carries,
  // because a module's models are generated from the module's own project.
  applicationFavicon: $applicationFavicon,
);

/// The CORS policy `dartvel.server.cors` configures, or null when the
/// project named none -- which means no CORS headers rather than "allow
/// everything". A server that answers every origin is the single setting
/// most likely to be wrong, and defaulting to it would put it on every
/// application that never thought about the question.
const dv.CorsOptions? dartvelConfiguredCors = $corsConstant;

/// Whether responses are compressed, from `dartvel.server.compression`.
const bool dartvelCompression = $compressionLiteral;

/// The proxies whose forwarded client address is believed, from
/// `dartvel.server.trustedProxies`; a deployment adds more with
/// DARTVEL_TRUSTED_PROXIES. Empty trusts none, and every per-source limit
/// counts the connection's peer.
const List<String> dartvelTrustedProxies = ${server.trustedProxiesSource};

/// The header those proxies write, from `dartvel.server.forwardedHeader`.
const String? dartvelForwardedHeader = ${server.forwardedHeaderSource};

/// How many leading bits of an IPv6 client address are one source for every
/// per-source limit, from `dartvel.server.ipv6SourcePrefix`. IPv4 is counted
/// per address.
const int dartvelIpv6SourcePrefix = ${server.ipv6SourcePrefix};

/// The largest request body the server reads for a route that declares no
/// limit of its own, from `dartvel.server.maxBodyBytes`. A route declaring
/// bodyLimit or uploadLimit, and the crash endpoint, register their own.
const int dartvelMaxBodyBytes = ${server.maxBodyBytes};

/// Where this server answers the Shorebird updater, from the path of
/// shorebird.yaml's base_url, or null when the project's patches do not come
/// from its own server. `dartvel updates patch --patch-source` publishes here.
const String? dartvelPatchSourcePrefix = $patchSourceLiteral;

/// Starts the backend. With [spaRoot], the built site is served beside the
/// API and each page assembled on request from the web-server manifest and
/// the model's data. With [pageStore] -- any cache adapter, so Redis where
/// the deployment has one -- the assembled pages are kept there rather than
/// in this process, and a second instance serves what the first resolved.
///
/// [cors] and [compression] override the configuration for a caller that
/// passes them; a generated entrypoint passes neither, so what an
/// application gets is what `dartvel.server` says.
///
/// [previewMembership] answers whether a request belongs to the deployment's
/// organization, for a preview deployed with `visibility: members`. Core has
/// no request-layer user or organization to ask, so without one a members
/// preview refuses to start rather than admitting everybody.
///
/// [process] is what this process was told to be; read from DARTVEL_ROLE and
/// DARTVEL_PORT when null. Only a web process serves, and only one that
/// ticks the schedules starts them -- with [scheduleLease] claimed per
/// occurrence, [scheduleClock] as the time and [scheduleTick] as the cadence.
/// [port] wins over DARTVEL_PORT, which wins over the generated port.
///
/// [maxBodyBytes] overrides `dartvel.server.maxBodyBytes`. Each route's own
/// limit is read from `DVBodyLimits` when the router is built here, so set
/// those before calling this.
///
/// [updatesRoot] is where the Shorebird patch source keeps patches when
/// [dartvelPatchSourcePrefix] is set: DARTVEL_UPDATES_DIR when null, else
/// .dartvel/updates. It publishes only with DARTVEL_UPDATES_TOKEN set.
///
/// With [admin] and [adminRoot], the admin dashboard in [adminRoot] is served
/// at the mount: to a signed-in session when the mount requires one, and to
/// nobody else. The web-server binary passes both from what it carries.
Future<dv.ServerHandle> startBackend({String? host, int? port, dv.TlsConfig? tls, bool h2c = false, dv.CorsOptions? cors, String? spaRoot, core.DVCacheAdapter? pageStore, bool? compression, core.DVPreviewMembership? previewMembership, core.DVProcessConfiguration? process, core.DVScheduleLease? scheduleLease, DateTime Function()? scheduleClock, Duration scheduleTick = const Duration(seconds: 20), int? maxBodyBytes, core.DVDatabaseConnection? defaultDatabase, String? updatesRoot, core.DVAdminMount? admin, String? adminRoot}) async {
  // Preview Environments, before anything else runs. In a process deployed
  // as a preview this captures mail and notifications, puts every queue
  // under the preview's namespace and points DV.Database at the preview's
  // own database -- and refuses to start at all when any of that cannot be
  // established, because a preview that starts as production mails real
  // people and consumes production's jobs. In any other environment it
  // returns without touching anything. serve() installs the same preview's
  // access gate around everything it answers.
  core.DVPreviewServer.start(Platform.environment, membership: previewMembership);
  // What this process was told to be, validated: a DARTVEL_PORT that is not
  // a port refuses the start rather than binding the generated one, and a
  // worker or cron process refuses to serve the application as well.
  final core.DVProcessConfiguration processConfiguration = process ??
      core.DVProcessConfiguration.resolve(environment: Platform.environment, generatedPort: cfg.backendPort);
  if (!processConfiguration.servesHttp) {
    throw StateError('This process is DARTVEL_ROLE=\${processConfiguration.role.name}, which serves no HTTP, so startBackend will not serve the application from it. dartvelMain starts what each role runs.');
  }
  // Every @DVJob codec and every handler a server can run, and the store this
  // deployment's processes share -- the database DATABASE_URL names. Without
  // them a job a backend function dispatched went on a queue inside this
  // process, which no worker could see.
  // Crash reporting, labelled with this process's role, before anything
  // that can fail a request.
  _dartvelInstallServerCrashes(processConfiguration.role);
  // The hosts dartvel.http declares, before a backend function, a job or a
  // webhook can send: the same declaration the client runtime installs.
  configureDartvelHttp();
  registerDartvelJobs();
  // Every @DVPolicy class, before the first await below. The router registers
  // them again when it is built; nothing that runs while the database is
  // made ready -- a job, a preview check -- may meet an empty registry.
  dartvelRegisterBackendPolicies();
  // [defaultDatabase] when DATABASE_URL is not set: a web-server binary's
  // SQLite file, created here on its first run.
  final core.DVProcessStores stores = core.DVProcessStores.install(fallback: defaultDatabase);
  await _dartvelPrepareDatabase(stores);
  if (processConfiguration.roleDeclared && !const core.DVQueues().adapterConfigured) {
    stderr.writeln('dartvel: DARTVEL_ROLE=web and DATABASE_URL is not set, so a job dispatched here goes on a queue inside this process and no DARTVEL_ROLE=worker process will run it.');
  }
  // The modules this application mounts, before anything is served. The
  // registry decides where a schema-isolated module's tables are and which
  // database its models use, and a backend that registered nothing saw
  // every module as unmounted: its models resolved the plain table name in
  // a database where nothing had created it. Backend functions are where
  // model queries actually run.
  registerDartvelModules();$tenancyConfiguration$cspAssignment
  // DV.Analytics and DV.Privacy over the application's database, when this
  // process has one. Analytics first, so its adapters are in the privacy
  // walk; DV.Privacy is configured only where DARTVEL_PRIVACY_KEY is set.
  final core.DVDatabaseAdapter? dartvelDatabase = const core.DVDatabase().configuredAdapter ?? stores.database;
  if (dartvelDatabase != null) configureDartvelAnalytics(database: () => dartvelDatabase);
  configureDartvelBackendPrivacy(database: dartvelDatabase, environment: Platform.environment);
  // The walk's own tables, and its erasure and retention jobs on the queue.
  // Awaited before serving: a request for an erasure before its tables
  // exist fails. Nothing, where DV.Privacy is not configured.
  final Future<bool> dartvelPrivacyStarted = core.DVPrivacyRuntime.start();
  // The account endpoints send an address change's code through
  // DV.Notifications.mail in the generated template, and delete an account
  // through the DV.Privacy just configured -- each refused, naming what to
  // configure, where this process has no mail or no DARTVEL_PRIVACY_KEY.
  configureDartvelBackendAccounts();
  // The application's own sessions authenticate on every route. Over this
  // process's database when it has one, so a session outlives a restart and
  // is seen by every web process; in memory otherwise. An application that
  // installed its own stage first -- to resolve its user -- keeps it.
  if (core.DVSessionAuthentication.installed == null) {
    core.DVSessionAuthentication.install(
      sessions: core.DVSessions(store: dartvelDatabase == null ? core.DVMemorySessionStore() : core.DVDatabaseSessionStore(dartvelDatabase)),
      development: Platform.environment['DARTVEL_ENVIRONMENT'] == 'development',
    );
  }
  // Who may open Studio: a person granted Studio.access with `dartvel admin
  // grant`, read from this process's database, and nobody else unless the
  // application registered its own Studio.access policy, which is asked
  // instead. A signed-in customer is not an operator. With no database there
  // is nowhere a grant could be, so nobody is.
  if (dartvelDatabase != null) core.DVStudioGrants(dartvelDatabase).install();
  // Somebody to grant. Sign-up and sign-in authenticate through the provider
  // the application installed before this, and a web-server binary runs no
  // application code before this, so with nothing installed every one of
  // them answered 503 and no account could ever open Studio. Accounts go in
  // this process's database, so they outlive a restart and every web process
  // sees them. An application that installed its own provider keeps it; with
  // no database there is nowhere to keep an account, and none is installed.
  if (dartvelDatabase != null && !core.DVAuthEndpoints.installed) {
    core.DVAuthEndpoints.install(credentials: core.DVCredentialGuard(provider: core.DVDatabaseAuthProvider(dartvelDatabase)));
  }${authenticates ? '''
  // dartvel.platformApi: API keys and OAuth tokens authenticate on every
  // route, over the database this process resolves on the first request
  // that presents one -- an application may configure DV.Database after
  // the server starts.
  core.DVPlatformApi.install(dartvelPlatformApi!, database: () => const core.DVDatabase().configuredAdapter ?? stores.database);''' : ''}
  // Every @DVBackendCron schedule, registered and ticking. Nothing did this
  // before: the schedules were generated into a list and the only thing that
  // ever built a DVScheduler was the scheduler's own unit test, so a job
  // declared on a function never ran once in a served application. Returns
  // without starting a timer when there are no schedules.
  // Every @DVAITool, registered so a provider can call one. The generated
  // list carried a name, a description and a file path and nothing else,
  // which is a catalogue rather than a tool: an assistant could read that a
  // function existed and had no way to run it.
  registerDartvelAITools();
  // Only in a process that ticks them: one given no role, which is the whole
  // deployment. A declared web process is one of several, and every one of
  // them ticking would fire each schedule once per instance.
  if (processConfiguration.ticksSchedules) {
    _dartvelScheduleTimer?.cancel();
    // Claimed in the shared database when there is one: a whole deployment
    // scaled to two instances is two processes ticking.
    _dartvelScheduleTimer = dartvelStartBackendSchedules(every: scheduleTick, clock: scheduleClock, lease: scheduleLease ?? stores.scheduleLeaseFor(processConfiguration));
    // Accounts whose deletion window has closed, erased through DVQueues.
    // Ticks with no window declared too: a deletion scheduled under one the
    // project has since removed still falls due.
    _dartvelAccountSweepTimer?.cancel();
    _dartvelAccountSweepTimer = dartvelStartAccountDeletionSweep(every: scheduleTick);
    // Retention swept daily and open erasures run before their deadline,
    // each occurrence claimed like the application's schedules. Null where
    // DV.Privacy is not configured.
    _dartvelPrivacyTimer?.cancel();
    _dartvelPrivacyTimer = core.DVPrivacyRuntime.startSchedules(every: scheduleTick, clock: scheduleClock, lease: scheduleLease ?? stores.scheduleLeaseFor(processConfiguration), onFailure: core.DVServerCrashes.recordScheduled);
  } else if (dartvelBackendCronEntries.isNotEmpty) {
    stdout.writeln('dartvel: DARTVEL_ROLE=web, so this process does not tick the \${dartvelBackendCronEntries.length} backend schedule(s); the DARTVEL_ROLE=cron process runs them.');
  }
  // Who each request came from, for every per-source limit: the peer, or the
  // client a trusted proxy reports. Before the router, so no request is
  // counted by the default that trusts no proxy; a range in
  // DARTVEL_TRUSTED_PROXIES that does not parse refuses the start.
  core.DVClientAddress.install(core.DVClientAddress.fromConfiguration(trustedProxies: dartvelTrustedProxies, forwardedHeader: dartvelForwardedHeader, ipv6SourcePrefix: dartvelIpv6SourcePrefix, environment: Platform.environment));
  final router = buildBackendRouter();
  final bindHost = host ?? cfg.backendHost;
  final bindPort = port ?? processConfiguration.port;
  // A caller's argument wins over the configuration, so a test or a
  // second entrypoint can still override either; the configuration is
  // what an application gets when it says nothing here, which is what
  // every generated entrypoint does.
  await dartvelPrivacyStarted;
  // The Shorebird patch source, ahead of the application's routes, when
  // shorebird.yaml says patches come from this server. A request that is not
  // the updater's or a publish falls through to the application unread.
  final String? patchPrefix = dartvelPatchSourcePrefix;
  final core.DVShorebirdPatchSource? patchSource = patchPrefix == null
      ? null
      : core.DVShorebirdPatchSource(
          updatesRoot ?? Platform.environment['DARTVEL_UPDATES_DIR'] ?? '.dartvel\${Platform.pathSeparator}updates',
          publishToken: Platform.environment['DARTVEL_UPDATES_TOKEN'],
        );
  final Future<dv.Response> Function(dv.Request) application = patchSource == null
      ? router.call
      : (dv.Request request) async => await patchSource.respond(request, prefix: patchPrefix!) ?? await router.call(request);
  // The admin dashboard, at its mount, from files that are not under
  // [spaRoot] -- every file there is served to anybody. A caller who may not
  // see it falls through to the application, which answers the path exactly
  // as it answers any route it does not serve.
  final core.DVAdminServer? adminServer = admin == null || adminRoot == null
      ? null
      : core.DVAdminServer(mount: admin, root: adminRoot, models: ${studioModules.isEmpty ? 'dartvelStudioModels' : '<core.DVStudioModelSpec>[...dartvelStudioModels, ${studioModules.map(((String, String) m) => '...${m.$2}.dartvelStudioModels').join(', ')}]'}, database: dartvelDatabase);
  final Future<dv.Response> Function(dv.Request) withAdmin = adminServer == null
      ? application
      : (dv.Request request) async => await adminServer.respond(request) ?? await application(request);
  // The page documents Studio published, which the web app reads to let a
  // stored page take over its route without a rebuild. Public: a published
  // page is what the site shows anybody.
  final core.DVPublishedPages publishedPages = core.DVPublishedPages(database: () => const core.DVDatabase().configuredAdapter ?? dartvelDatabase);
  final Future<dv.Response> Function(dv.Request) handler = (dv.Request request) async => await publishedPages.respond(request) ?? await withAdmin(request);
  return dv.serve(handler, host: bindHost, port: bindPort, tls: tls, h2c: h2c, cors: cors ?? dartvelConfiguredCors, spaRoot: spaRoot, pageData: dartvelPageData, pageStore: pageStore, compression: compression ?? dartvelCompression, previewMembership: previewMembership, maxBodyBytes: maxBodyBytes ?? dartvelMaxBodyBytes, routeBodyLimits: <dv.DVRouteBodyLimit>[
    // A patch is larger than a request body usually is.
    if (patchPrefix != null) dv.DVRouteBodyLimit('POST', '\$patchPrefix/_dartvel/publish', $dvPatchPublishMaxBytes),
    ...router.bodyLimits,
  ]);
}

/// The schedule timer this process started, so a stopped process stops it.
Timer? _dartvelScheduleTimer;

/// The account deletion sweep this process started, likewise.
Timer? _dartvelAccountSweepTimer;

/// The retention sweep and erasure deadline schedules, likewise.
Timer? _dartvelPrivacyTimer;

/// Configures DV.Analytics and DV.Privacy in a worker or cron process over
/// the database it shares, as a web process does, and starts the privacy
/// walk: its tables, and its erasure and retention jobs.
Future<void> _dartvelStartBackendPrivacy(core.DVProcessStores stores) async {
  final core.DVDatabaseAdapter? database = const core.DVDatabase().configuredAdapter ?? stores.database;
  if (database != null) configureDartvelAnalytics(database: () => database);
  configureDartvelBackendPrivacy(database: database, environment: Platform.environment);
  await core.DVPrivacyRuntime.start();
}

bool _dartvelServerCrashesInstalled = false;

/// Installs crash reporting in this server process, as [role].
///
/// Records go in DARTVEL_CRASH_DIR, else `.dartvel/crashes` beside the
/// application, and the server's install id is kept beside them. A request
/// that answers 500, a schedule that throws and a job dead-lettered after its
/// last attempt are each recorded as unhandled. A process that cannot install
/// it says so and serves anyway: crash reporting is not a reason to be down.
void _dartvelInstallServerCrashes(core.DVProcessRole role) {
  if (_dartvelServerCrashesInstalled) return;
  _dartvelServerCrashesInstalled = true;
  try {
    final String directory = core.dvServerCrashDirectoryFor(
      appId: '$pkgName',
      environment: Platform.environment,
      currentDirectory: Directory.current.path,
      tempDirectory: Directory.systemTemp.path,
    );
    final File idFile = File('\$directory/install-id');
    String installId = idFile.existsSync() ? idFile.readAsStringSync().trim() : '';
    if (!RegExp(r'^[0-9a-f]{32}\$').hasMatch(installId)) {
      installId = core.dvAnalyticsRandomId();
      Directory(directory).createSync(recursive: true);
      idFile.writeAsStringSync(installId, flush: true);
    }
    core.DVServerCrashes.install(
      appId: '$pkgName',
      release: '${esc(crashRelease)}',
      role: role,
      store: core.DVFileCrashStore(directory),
      installId: installId,
      // dartvel.crashes, as the build checked it.
      config: core.DVCrashConfig.parse(conv.jsonDecode(r'${jsonEncode(crashes.toDeclaration())}')),
      ${servesCrashes ? '// Kept in this application\'s own table, as its clients\' reports are.\n      sink: core.DVCrashSink.repository(core.DVDatabaseCrashReportRepository.application()),' : '// No sink declared: reports are kept here and nowhere else.'}
      platform: Platform.operatingSystem,
    );
    core.DVQueues.onJobDeadLettered = core.DVServerCrashes.record;
  } on Object catch (error) {
    stderr.writeln('dartvel: crash reporting could not be installed in this process (\${error.runtimeType}); its unhandled errors are not recorded.');
  }
}

/// Runs the backend as what this process was told to be.
///
/// The one entry point every deployment starts: `.dart_tool/dartvel_server.dart`
/// calls it, and a provisioned unit or a container runs the same binary under
/// a different DARTVEL_ROLE (or `--role` in [arguments]):
///
///  * `web`, and a process given no role: serves on DARTVEL_PORT, else the
///    generated port. Given no role it is the whole deployment and ticks the
///    schedules; declared `web` it leaves them to the cron process.
///  * `worker`: works the DVQueues jobs in DARTVEL_QUEUE on the database
///    DATABASE_URL names, with every @DVJob handler a server can run, and
///    serves nothing. It refuses to start with no DATABASE_URL, where it
///    could never receive a job, and with no handler it can run. `--max-jobs`
///    returns once that many completed.
///  * `cron`: ticks the schedules, claiming each occurrence in that database
///    (or through [scheduleLease]), and serves nothing. It refuses to start
///    with no DATABASE_URL, where a second cron process would fire every
///    schedule again, unless DARTVEL_SCHEDULE_LEASE=none says it is alone.
///
/// A worker or cron process given DARTVEL_HEALTH_PORT answers GET /healthz
/// there, and nothing else.
///
/// Throws core.DVProcessConfigurationError, before anything starts, for a
/// role, port or queue it cannot honour. Returns when [until] completes.
Future<void> dartvelMain(List<String> arguments, {Future<void>? until, core.DVPreviewMembership? previewMembership, core.DVScheduleLease? scheduleLease, DateTime Function()? scheduleClock, Duration scheduleTick = const Duration(seconds: 20), String? webRoot, core.DVDatabaseConnection? defaultDatabase, String? updatesRoot, core.DVAdminMount? admin, String? adminRoot}) async {
  final core.DVProcessConfiguration process = core.DVProcessConfiguration.resolve(environment: Platform.environment, arguments: arguments, generatedPort: cfg.backendPort);
  final Future<void> stopped = until ?? Completer<void>().future;
  switch (process.role) {
    case core.DVProcessRole.web:
      final handle = await startBackend(previewMembership: previewMembership, process: process, scheduleLease: scheduleLease, scheduleClock: scheduleClock, scheduleTick: scheduleTick, spaRoot: webRoot, defaultDatabase: defaultDatabase, updatesRoot: updatesRoot, admin: admin, adminRoot: adminRoot);
      stdout.writeln('dartvel backend listening on http://\${handle.host}:\${handle.port}\${cfg.apiBasePath}');
      await stopped;
      _dartvelScheduleTimer?.cancel();
      _dartvelAccountSweepTimer?.cancel();
      _dartvelPrivacyTimer?.cancel();
      await handle.stop();
    case core.DVProcessRole.worker:
      // The same start a web process makes, less what only serving needs: a
      // preview's worker must consume the preview's queues, and a module's
      // models resolve their tables the same way in a job as in a request.
      core.DVPreviewServer.start(Platform.environment, membership: previewMembership);
      // A job that fails until it is dead-lettered is this worker's crash.
      _dartvelInstallServerCrashes(process.role);
      configureDartvelHttp();
      registerDartvelModules();$tenancyConfiguration
      registerDartvelAITools();
      // The codecs and the handlers a server can run, and the queue this
      // deployment's processes share. Neither was here, because the jobs
      // file imported dartvel_flutter, so every worker refused to start.
      registerDartvelJobs();
      // The account erasure job, for a worker given its queue.
      configureDartvelBackendAccounts();
      final core.DVProcessStores workerStores = core.DVProcessStores.install(fallback: defaultDatabase);
      await _dartvelPrepareDatabase(workerStores);
      // DV.Privacy, so an erasure or a retention sweep queued elsewhere runs
      // here -- the account erasure job included.
      await _dartvelStartBackendPrivacy(workerStores);
      if (!const core.DVQueues().adapterConfigured) {
        throw const core.DVProcessConfigurationError('DARTVEL_ROLE=worker has no queue adapter: DATABASE_URL is not set, so no queue is shared with the processes that dispatch jobs, and this worker would never receive one.');
      }
      for (final MapEntry<String, String> skipped in dartvelClientOnlyJobHandlers.entries) {
        stderr.writeln('dartvel worker: \${skipped.key} jobs cannot run in this process: \${skipped.value}.');
      }
      if (!const core.DVQueues().hasHandlers) {
        throw const core.DVProcessConfigurationError('DARTVEL_ROLE=worker and no @DVJob.handler this server can run is registered, so every job it reserved would be dead-lettered.');
      }
      final core.DVProcessHealth? workerHealth = await _dartvelServeHealth(process);
      stdout.writeln('dartvel worker working \${process.queues.join(', ')}');
      try {
        final int done = await core.DVQueueWorker(queues: process.queues).run(until: stopped, maxJobs: process.maxJobs);
        if (process.maxJobs != null) {
          stdout.writeln('Processed \$done job(s) from \${process.queues.join(', ')}.');
        }
      } finally {
        await workerHealth?.close();
      }
    case core.DVProcessRole.cron:
      core.DVPreviewServer.start(Platform.environment, membership: previewMembership);
      // A schedule that throws is this cron process's crash.
      _dartvelInstallServerCrashes(process.role);
      configureDartvelHttp();
      registerDartvelModules();$tenancyConfiguration
      registerDartvelAITools();
      // A schedule may dispatch a job, and that job has to reach the worker.
      registerDartvelJobs();
      // The account deletion sweep ticks where the schedules do.
      configureDartvelBackendAccounts();
      final core.DVProcessStores stores = core.DVProcessStores.install(fallback: defaultDatabase);
      await _dartvelPrepareDatabase(stores);
      // Each occurrence claimed in the shared database, so a second cron
      // process fires nothing twice. With none shared this throws rather than
      // start, unless DARTVEL_SCHEDULE_LEASE=none says this one is alone.
      final core.DVScheduleLease? lease = scheduleLease ?? stores.scheduleLeaseFor(process);
      if (lease == null) {
        stdout.writeln('dartvel cron: DARTVEL_SCHEDULE_LEASE=none, so no occurrence is claimed; a second cron process would fire every schedule again.');
      } else if (stores.connection?.engine == core.DVDatabaseEngine.sqlite) {
        stdout.writeln('dartvel cron: occurrences are claimed in a SQLite file, which only the processes of this host share.');
      }
      final core.DVProcessHealth? cronHealth = await _dartvelServeHealth(process);
      final Timer? timer = dartvelStartBackendSchedules(every: scheduleTick, clock: scheduleClock, lease: lease);
      final Timer? accountSweep = dartvelStartAccountDeletionSweep(every: scheduleTick);
      // Retention and erasure deadlines, claimed through the same lease.
      await _dartvelStartBackendPrivacy(stores);
      final Timer? privacySchedules = core.DVPrivacyRuntime.startSchedules(every: scheduleTick, clock: scheduleClock, lease: lease, onFailure: core.DVServerCrashes.recordScheduled);
      stdout.writeln(timer == null ? 'dartvel cron: this application declares no backend schedule' : 'dartvel cron ticking \${dartvelBackendCronEntries.length} backend schedule(s)');
      await stopped;
      timer?.cancel();
      accountSweep?.cancel();
      privacySchedules?.cancel();
      await cronHealth?.close();
  }
}

/// A worker or cron process's health endpoint, on DARTVEL_HEALTH_PORT when
/// it was given one. Off by default: a port nobody asked for is a port
/// somebody has to firewall.
Future<core.DVProcessHealth?> _dartvelServeHealth(core.DVProcessConfiguration process) async {
  final int? port = process.healthPort;
  if (port == null) return null;
  final core.DVProcessHealth health = await core.DVProcessHealth.serve(host: cfg.backendHost, port: port, role: process.role);
  stdout.writeln('dartvel \${process.role.name} health on http://\${cfg.backendHost}:\${health.port}/healthz');
  return health;
}
''';
    File(p.join(backendOut.path, 'dartvel_backend_routes.g.dart'))
        .writeAsStringSync(backendRoutes);

    // The binary a deployment runs. Every unit dartvel infra renders and the
    // image dartvel deploy writes start this one program and tell it its role
    // and port through the environment; before it there was no entry point
    // but the dev server's, which bound the generated port and nothing else.
    File(p.join(backendOut.path, 'dartvel_server.dart')).writeAsStringSync('''
// GENERATED – do not edit.
//
// The backend's entry point, compiled with
//   dart compile exe .dart_tool/dartvel_server.dart -o server
// One binary, run as the web server, a queue worker or the schedules:
// DARTVEL_ROLE (or --role) is web, worker or cron, DARTVEL_PORT is the port a
// web process binds, and DARTVEL_QUEUE the queues a worker works. DATABASE_URL
// is what the processes share: the queue, and the claim on each schedule
// occurrence. DARTVEL_HEALTH_PORT gives a worker or cron process /healthz.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' as core;

import 'dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  try {
    await gen.dartvelMain(arguments);
  } on core.DVProcessConfigurationError catch (error) {
    // EX_CONFIG: a supervisor restarting this will not fix it.
    stderr.writeln('dartvel: \$error');
    exit(78);
  }
}
''');

    // Backend bind config. `dartvel dev` prints dvGenBuildId when the backend
    // starts, to say which generated backend is the one running. That was a
    // wall-clock stamp, which changed on every build whether or not the
    // backend had; a hash of the routes the server runs changes exactly when
    // they do.
    final String backendHash =
        sha256.convert(utf8.encode(backendRoutes)).toString().substring(0, 16);
    File(p.join(backendOut.path, 'dartvel_backend.g.dart'))
        .writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_backend_config;
const String backendHost = '${esc(backendHost)}';
const int    backendPort = $backendPort;
const String apiBasePath = '${esc(apiBasePath)}';
/// A hash of the generated backend routes, not a time.
const String dvGenBuildId = '$backendHash';
''');

    // Client function-style API (tRPC-like): generate convenient call helpers
    final sbClient = StringBuffer();
    sbClient.writeln('// GENERATED – do not edit.');
    sbClient.writeln('// ignore_for_file: unused_element');
    sbClient.writeln('library dartvel_client_functions;');
    sbClient.writeln("import 'dart:convert';");
    sbClient.writeln("import 'dart:math' as math;");
    sbClient.writeln("import 'package:dartvel_core/dartvel.dart';");
    // The runtime import is decided after the body is written; see below.
    sbClient.writeln('''
/// Multipart fields for a generated POST. Modelled here rather than taken
/// from an HTTP package, so a generated client imposes no client library on
/// the application.
class DartvelFormData {
  final Map<String, String> fields;
  DartvelFormData(this.fields);

  factory DartvelFormData.fromMap(Map<Object?, Object?> map) =>
      DartvelFormData(<String, String>{
        for (final entry in map.entries)
          if (entry.key != null) '\${entry.key}': '\${entry.value ?? ''}',
      });
}
''');
    sbClient.writeln('''
/// Shared generated client state for auth and custom request headers.
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
    sbClient.writeln(
        "final String _dvCsrfToken = (() { try { return const DVCSRF().token(); } catch (_) { final random = math.Random.secure(); const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'; return String.fromCharCodes(List<int>.generate(32, (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)))); } })();");
    sbClient.writeln(
        'bool _dvRequiresCsrf(String method) => const DVCSRF().requiresValidation(method);');
    sbClient.writeln(
        'Map<String, String> _dvHeadersWithCsrf(String method, Map<String, String> headers) { if (!_dvRequiresCsrf(method)) return headers; return {...headers, DVCSRF.headerName: headers[DVCSRF.headerName] ?? _dvCsrfToken}; }');
    sbClient.writeln(
        'Object? _dvPayloadWithCsrf(String method, Object? payload) { if (!_dvRequiresCsrf(method)) return payload; if (payload is DartvelFormData) { payload.fields.putIfAbsent(DVCSRF.fieldName, () => _dvCsrfToken); return payload; } if (payload is Map<Object?, Object?>) { final copy = Map<String, Object?>.from(payload); copy.putIfAbsent(DVCSRF.fieldName, () => _dvCsrfToken); return copy; } return payload; }');
    sbClient.writeln(
        '''
/// Encodes a payload for the wire, and reports the content type it used.
///
/// The shape decides the encoding: multipart for a form, urlencoded when the
/// caller asked for it, JSON otherwise. An explicit content-type header from
/// the caller wins, because it is the caller who knows what the endpoint
/// expects.
({List<int> body, String? contentType}) _dvEncodeBody(
    Object? payload, String? declaredType) {
  if (payload == null) return (body: const <int>[], contentType: null);
  if (payload is DartvelFormData) {
    final boundary = dvGenerateMultipartBoundary();
    return (
      body: dvEncodeMultipartFields(boundary: boundary, fields: payload.fields),
      contentType: 'multipart/form-data; boundary=\$boundary',
    );
  }
  if (payload is List<int>) return (body: payload, contentType: declaredType);
  if (payload is String) {
    return (body: utf8.encode(payload), contentType: declaredType);
  }
  final type = (declaredType ?? '').toLowerCase();
  if (payload is Map && type.contains('application/x-www-form-urlencoded')) {
    final fields = <String, String>{};
    payload.forEach((Object? k, Object? v) {
      if (k == null || v == null) return;
      fields['\$k'] = v is List
          ? v.map((Object? e) => e?.toString() ?? '').join(',')
          : v.toString();
    });
    return (
      body: dvEncodeFormBody(<(String, String)>[\n        for (final e in fields.entries) (e.key, e.value),\n      ]),
      contentType: declaredType,
    );
  }
  return (
    body: utf8.encode(jsonEncode(payload)),
    contentType: declaredType ?? 'application/json; charset=utf-8',
  );
}

Map<String, String> _dvPrepareHeaders(
    String methodUpper, Map<String, String>? headers) {
  final merged = <String, String>{
    ...DartvelClient.defaultHeaders,
    ...(headers ?? const <String, String>{}),
  };
  return _dvHeadersWithCsrf(methodUpper, merged);
}

/// Sends a generated call. A function declaring `mfa:` answers a session
/// without a recent second factor with a step-up refusal; DVStepUp presents
/// the challenge the runtime installed and sends the call once more. The
/// headers are prepared per send, because a completed challenge rotates the
/// session token they carry.
Future<DVHttpResponse> _dvRequest(String method, Uri uri,
    {Object? data, Map<String, String>? headers}) {
  final methodUpper = method.toUpperCase();
  return DVStepUp.send(() {
    final hdrs = _dvPrepareHeaders(methodUpper, headers);
    final payload = _dvPayloadWithCsrf(methodUpper, data);
    final declared = hdrs['content-type'] ?? hdrs['Content-Type'];
    final encoded = _dvEncodeBody(payload, declared);
    if (encoded.contentType != null) hdrs['content-type'] = encoded.contentType!;
    return dvSendHttpRequest(DVHttpRequest(
      url: uri,
      method: methodUpper,
      headers: hdrs,
      body: encoded.body,
    ));
  });
}

Stream<T> _dvStream<T>(Uri uri, T Function(Object?) fromJson,
    {String method = "GET", Object? data, Map<String, String>? headers}) async* {
  final methodUpper = method.toUpperCase();
  final hdrs = _dvPrepareHeaders(methodUpper, headers);
  final payload = _dvPayloadWithCsrf(methodUpper, data);
  final declared = hdrs['content-type'] ?? hdrs['Content-Type'];
  final encoded = _dvEncodeBody(payload, declared);
  if (encoded.contentType != null) hdrs['content-type'] = encoded.contentType!;
  final response = await dvStreamHttpRequest(DVHttpRequest(
    url: uri,
    method: methodUpper,
    headers: hdrs,
    body: encoded.body,
  ));
  final bodyStream = response.body;
''');

    sbClient.writeln("  String buffer = '';");
    sbClient.writeln('  await for (final chunk in bodyStream) {');
    sbClient.writeln('    buffer += utf8.decode(chunk);');
    sbClient.writeln('    while (true) {');
    sbClient.writeln('      final lineEnd = buffer.indexOf("\\n");');
    sbClient.writeln('      if (lineEnd == -1) break;');
    sbClient.writeln('      final line = buffer.substring(0, lineEnd).trim();');
    sbClient.writeln('      buffer = buffer.substring(lineEnd + 1);');
    sbClient.writeln('      if (line.startsWith("data:")) {');
    sbClient.writeln('        final payload = line.substring(5).trim();');
    sbClient.writeln('        if (payload.isNotEmpty) {');
    sbClient.writeln('          try {');
    sbClient.writeln('            final json = jsonDecode(payload);');
    sbClient.writeln('            yield fromJson(json);');
    sbClient.writeln('          } catch (_) {');
    sbClient.writeln('            if ("" is T) {');
    sbClient.writeln('              yield payload as T;');
    sbClient.writeln('            }');
    sbClient.writeln('          }');
    sbClient.writeln('        }');
    sbClient.writeln('      }');
    sbClient.writeln('    }');
    sbClient.writeln('  }');
    sbClient.writeln('}');

    // Every route's own client function, so a typed wrapper cannot take a
    // name one of them already has: two declarations of one name is a
    // compile error inside a generated file, pointing at nothing.
    final Map<String, String> routeFunctionNames = <String, String>{
      for (final e in backendEntries)
        RouteUtils.funcNameForFromUrl(e['method']!, e['path']!):
            '${e['method']!.toUpperCase()} ${e['path']!}',
    };

    // The application's types the typed wrappers below name.
    final Set<String> clientTypeImports = <String>{};
    for (final e in backendEntries) {
      final method = e['method']!;
      final urlPath = e['path']!;
      final colon = RouteUtils.toColonPath(urlPath);
      final fname = RouteUtils.funcNameForFromUrl(method, urlPath);
      // Where the client sends the call: the rawPath from the host root, or
      // the generated path and its suffix under the API base path.
      final String clientRawPath = e['rawPath'] ?? '';
      final String clientPath = clientRawPath.isNotEmpty
          ? clientRawPath
          : RouteUtils.toColonPath('$urlPath${e['rawPathSuffix'] ?? ''}');
      final String runtimeUrl = clientRawPath.isNotEmpty
          ? 'DartvelRuntime.raw'
          : 'DartvelRuntime.api';
      final paramSig = RouteUtils.paramsListFor(colon);
      final hasParams = paramSig.isNotEmpty;
      final sig =
          '{ ${hasParams ? ('$paramSig, ') : ''}Map<String, Object?>? query, Object? body, Map<String, String>? headers }';
      final names = RegExp(r':([a-zA-Z0-9_]+)')
          .allMatches(colon)
          .map((m) => m.group(1)!)
          .toList();
      final paramMap = hasParams
          ? ('{ ${names.map((n) => "'$n': $n").join(', ')} }')
          : 'const <String, Object?>{}';
      final argsNamed =
          '${hasParams ? ('${names.map((n) => '$n: $n').join(', ')}, ') : ''}query: query, body: body, headers: headers';

      sbClient.writeln('Future<DVHttpResponse> $fname($sig) async {');
      sbClient
          .writeln("  String routePath = '${esc(clientPath)}';");
      sbClient.writeln('  final Map<String, Object?> pp = $paramMap;');
      sbClient.writeln(
          "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
      sbClient.writeln('  final base = $runtimeUrl(routePath);');
      if (method == 'get' || method == 'head') {
        sbClient.writeln('  final q = <String, String>{};');
        sbClient.writeln(
            '  if (query != null) { query.forEach((k, v) { q[k] = v?.toString() ?? ""; }); }');
        sbClient.writeln('  final uri = base.replace(queryParameters: q);');
        sbClient.writeln(
            "  return _dvRequest('$method', uri, data: body, headers: headers);");
      } else {
        sbClient.writeln('  final fb = <String, Object?>{};');
        sbClient.writeln(
            '  if (query != null) { query.forEach((k, v) { fb[k] = v; }); }');
        sbClient.writeln('  final uri = base;');
        sbClient.writeln(
            '  final reqHeaders = <String,String>{...(headers ?? const {})};');
        if (method == 'post') {
          // Enforce multipart form-data for all generated POST endpoints
          sbClient.writeln(
              '  final reqPayload = (body is DartvelFormData) ? body : (body == null ? DartvelFormData.fromMap(fb) : (body is Map<Object?, Object?> ? DartvelFormData.fromMap(Map<String, Object?>.from(body)) : body));');
        } else {
          // Other non-GET methods: honor provided payload, fall back to simple map
          sbClient.writeln(
              '  final reqPayload = (body is DartvelFormData) ? body : (body ?? fb);');
        }
        sbClient.writeln(
            "  return _dvRequest('$method', uri, data: reqPayload, headers: reqHeaders);");
      }
      sbClient.writeln('}');
      sbClient.writeln('');

      // Data-only variant
      sbClient.writeln('Future<Object?> ${fname}Data($sig) async {');
      sbClient.writeln('  final r = await $fname($argsNamed);');
      sbClient.writeln('  return r.data;');
      sbClient.writeln('}');
      sbClient.writeln('');

      // Typed variant using a mapper
      sbClient.writeln(
          'Future<T> ${fname}As<T>(T Function(Object?) fromJson, $sig) async {');
      sbClient.writeln('  final r = await $fname($argsNamed);');
      sbClient.writeln('  return fromJson(r.data);');
      sbClient.writeln('}');
      sbClient.writeln('');

      // API-style typed wrapper returning backend return type, using typed function params
      final tparams =
          (e['tparams'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
      final ttypes = (e['ttypes'] ?? '').split(',');
      final rtype = (e['rtype'] ?? '').trim();
      final clientReturnType = _clientReturnType(rtype);
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
          bufSig.write('required $tt $tn');
          if (i2 != tparams.length - 1) bufSig.write(', ');
        }
        if (tparams.isNotEmpty) bufSig.write(', ');
        bufSig.write(
            'Map<String, Object?>? query, Object? body, Map<String, String>? headers }');
        final sigApi = bufSig.toString();

        // Determine which typed params are dynamic path segments.
        final colonNames = names.toSet();
        // Build the path parameter map from dynamic path segments.
        final ppPairs = tparams
            .where((p) => colonNames.contains(p))
            .map((p) => "'$p': $p")
            .join(', ');
        final ppExpr =
            (ppPairs.isEmpty) ? 'const <String, Object?>{}' : '{ $ppPairs }';
        // build form body map merging provided query + typed params not in path (for non-GET)
        final qpLines = <String>[];
        for (var j = 0; j < tparams.length; j++) {
          final pName = tparams[j];
          if (colonNames.contains(pName)) continue;
          final pType = (j < ttypes.length ? ttypes[j] : '').trim();
          if (pType.startsWith('List<String')) {
            qpLines.add(
                "qq['$pName'] = ($pName).map((e)=>e.toString()).join(',');");
          } else {
            qpLines.add("qq['$pName'] = ($pName).toString();");
          }
        }
        final qpAdd = qpLines.join('\n  ');

        final String abs = e['abs'] ?? '';
        final String rel = e['rel'] ?? '';
        if (abs.isNotEmpty && rel.isNotEmpty) {
          clientTypeImports.addAll(dvClientTypeImports(
            source: e['src'] ?? '',
            sourcePath: abs,
            projectRoot: abs.substring(0, abs.length - rel.length),
            packageName: e['pkg'] ?? pkgName,
            types: <String>[
              clientReturnType,
              for (var i2 = 0; i2 < tparams.length; i2++)
                if (i2 < ttypes.length) ttypes[i2],
            ],
          ));
        }

        final hasDvBackendFn =
            (e['src'] ?? '').contains('@DVBackendFunction') ||
                (e['src'] ?? '').contains('@dvBackendFunction');
        final fnameApi = (hasDvBackendFn && e['typed']!.isNotEmpty)
            ? e['typed']!
            : '${fname}Api';
        final String? clash = routeFunctionNames[fnameApi];
        if (clash != null) {
          final String bare = fnameApi.replaceFirst(
              RegExp(r'^(get|post|put|patch|delete|head|options)'), '');
          final String suggestion = bare.isEmpty
              ? '${fnameApi}Value'
              : '${bare[0].toLowerCase()}${bare.substring(1)}';
          throw StateError(
            'The backend function _$fnameApi generates $fnameApi, which is also '
            'the client function for $clash. Rename it, for example to '
            '_$suggestion.',
          );
        }

        final isStreamType = clientReturnType.startsWith('Stream<');

        if (isStreamType) {
          String innerType = 'Object?';
          final match = RegExp(r'^Stream<(.+)>$').firstMatch(clientReturnType);
          if (match != null) {
            innerType = match.group(1)!.trim();
          }

          String convStream(String t) {
            final tt = t.replaceAll(' ', '');
            if (tt == 'String') return '(v) => v as String';
            if (tt == 'int') {
              return "(v) => (v is int) ? (v as int) : (int.tryParse(v?.toString() ?? '') ?? 0)";
            }
            if (tt == 'double') {
              return "(v) => (v is double) ? (v as double) : (double.tryParse(v?.toString() ?? '') ?? 0.0)";
            }
            if (tt == 'num') {
              return "(v) => (v is num) ? (v as num) : (num.tryParse(v?.toString() ?? '') ?? 0)";
            }
            if (tt == 'bool') {
              return "(v) => (v is bool) ? (v as bool) : ((v?.toString().toLowerCase() ?? '') == 'true')";
            }
            return '';
          }

          final convExprStream = convStream(innerType);
          if (convExprStream.isEmpty) {
            final sigApiMapper = sigApi.replaceFirst(
                ' }', ', required $innerType Function(Object?) fromJson }');
            sbClient.writeln('Stream<$innerType> $fnameApi($sigApiMapper) {');
          } else {
            sbClient.writeln('Stream<$innerType> $fnameApi($sigApi) {');
          }

          sbClient.writeln(
              "  String routePath = '${esc(clientPath)}';");
          sbClient.writeln('  final Map<String, Object?> pp = $ppExpr;');
          sbClient.writeln(
              "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
          sbClient.writeln('  final base = $runtimeUrl(routePath);');
          final qp = StringBuffer();
          qp.writeln('  final qq = <String, String>{};');
          qp.writeln(
              "  if (query != null) { query.forEach((k, v) { qq[k] = v?.toString() ?? ''; }); }");
          if (qpAdd.isNotEmpty) qp.writeln('  $qpAdd');
          sbClient.writeln(qp.toString());
          sbClient.writeln('  final fb = <String, Object?>{};');
          for (var j = 0; j < tparams.length; j++) {
            final pName = tparams[j];
            if (!names.contains(pName)) {
              sbClient.writeln("  fb['$pName'] = $pName;");
            }
          }
          sbClient.writeln(
              '  if (query != null) { query.forEach((k, v) { fb[k] = v; }); }');
          final isGetOrHead =
              method.toUpperCase() == 'GET' || method.toUpperCase() == 'HEAD';
          sbClient.writeln(
              "  final uri = ${isGetOrHead ? 'base.replace(queryParameters: qq)' : 'base'};");
          sbClient.writeln(
              '  final reqHeaders = headers ?? const <String, String>{};');
          if (isGetOrHead) {
            sbClient.writeln('  final reqPayload = body;');
          } else if (method == 'post') {
            sbClient.writeln(
                '  final reqPayload = (body is DartvelFormData) ? body : (body == null ? DartvelFormData.fromMap(fb) : (body is Map<Object?, Object?> ? DartvelFormData.fromMap(Map<String, Object?>.from(body)) : body));');
          } else {
            sbClient.writeln(
                '  final reqPayload = (body is DartvelFormData) ? body : (body ?? fb);');
          }
          if (convExprStream.isEmpty) {
            sbClient.writeln(
                "  return _dvStream<$innerType>(uri, fromJson, method: '$method', data: reqPayload, headers: reqHeaders);");
          } else {
            sbClient.writeln(
                "  return _dvStream<$innerType>(uri, $convExprStream, method: '$method', data: reqPayload, headers: reqHeaders);");
          }
          sbClient.writeln('}');
          sbClient.writeln('');
        } else {
          // Future types
          String conv(String t) {
            final tt = t.replaceAll(' ', '');
            if (tt == 'String') return 'r.data as String';
            if (tt == 'int') {
              return "(r.data is int) ? (r.data as int) : (int.tryParse(r.data?.toString() ?? '') ?? 0)";
            }
            if (tt == 'double') {
              return "(r.data is double) ? (r.data as double) : (double.tryParse(r.data?.toString() ?? '') ?? 0.0)";
            }
            if (tt == 'num') {
              return "(r.data is num) ? (r.data as num) : (num.tryParse(r.data?.toString() ?? '') ?? 0)";
            }
            if (tt == 'bool') {
              return "(r.data is bool) ? (r.data as bool) : ((r.data?.toString().toLowerCase() ?? '') == 'true')";
            }
            if (tt.startsWith('List<String')) {
              return '(r.data as List).map((e)=>e.toString()).toList() as $t';
            }
            if (tt.startsWith('List<int')) {
              return "(r.data as List).map((e){ if (e is int) return e; return int.tryParse(e?.toString() ?? '') ?? 0; }).toList() as $t";
            }
            if (tt.startsWith('List<double')) {
              return "(r.data as List).map((e){ if (e is double) return e; return double.tryParse(e?.toString() ?? '') ?? 0.0; }).toList() as $t";
            }
            if (tt.startsWith('List<bool')) {
              return "(r.data as List).map((e)=> (e is bool) ? e : ((e?.toString().toLowerCase() ?? '') == 'true')).toList() as $t";
            }
            if (tt.startsWith('List<Map<String,dynamic') ||
                tt.startsWith('List<Map<String,Object')) {
              return '(r.data as List).map((entry) => Map<String, Object?>.from(entry as Map<Object?, Object?>)).toList(growable: false)';
            }
            if (tt.startsWith('Map<String,dynamic') ||
                tt.startsWith('Map<String,Object')) {
              return 'Map<String, Object?>.from(r.data as Map<Object?, Object?>)';
            }
            // Fallback: require a mapper
            return '';
          }

          // The type the client sees, with the Future taken off.
          final convExpr = conv(clientReturnType);
          if (convExpr.isEmpty) {
            // Custom type – require a mapper
            final sigApiMapper = sigApi.replaceFirst(' }',
                ', required $clientReturnType Function(Object?) fromJson }');
            sbClient.writeln(
                'Future<$clientReturnType> $fnameApi($sigApiMapper) async {');
          } else {
            sbClient.writeln(
                'Future<$clientReturnType> $fnameApi($sigApi) async {');
          }
          sbClient.writeln(
              "  String routePath = '${esc(clientPath)}';");
          sbClient.writeln('  final Map<String, Object?> pp = $ppExpr;');
          sbClient.writeln(
              "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
          sbClient.writeln('  final base = $runtimeUrl(routePath);');
          // Build both query and form bodies; choose at runtime per method
          final qp = StringBuffer();
          qp.writeln('  final qq = <String, String>{};');
          qp.writeln(
              "  if (query != null) { query.forEach((k, v) { qq[k] = v?.toString() ?? ''; }); }");
          if (qpAdd.isNotEmpty) qp.writeln('  $qpAdd');
          sbClient.writeln(qp.toString());
          sbClient.writeln('  final fb = <String, Object?>{};');
          for (var j = 0; j < tparams.length; j++) {
            final pName = tparams[j];
            if (!names.contains(pName)) {
              sbClient.writeln("  fb['$pName'] = $pName;");
            }
          }
          sbClient.writeln(
              '  if (query != null) { query.forEach((k, v) { fb[k] = v; }); }');
          final isGetOrHead =
              method.toUpperCase() == 'GET' || method.toUpperCase() == 'HEAD';
          sbClient.writeln(
              "  final uri = ${isGetOrHead ? 'base.replace(queryParameters: qq)' : 'base'};");
          sbClient.writeln(
              '  final reqHeaders = headers ?? const <String, String>{};');
          if (isGetOrHead) {
            sbClient.writeln('  final reqPayload = body;');
          } else if (method == 'post') {
            sbClient.writeln(
                '  final reqPayload = (body is DartvelFormData) ? body : (body == null ? DartvelFormData.fromMap(fb) : (body is Map<Object?, Object?> ? DartvelFormData.fromMap(Map<String, Object?>.from(body)) : body));');
          } else {
            sbClient.writeln(
                '  final reqPayload = (body is DartvelFormData) ? body : (body ?? fb);');
          }
          sbClient.writeln(
              "  final r = await _dvRequest('$method', uri, data: reqPayload, headers: reqHeaders);");
          if (convExpr.isEmpty) {
            sbClient.writeln('  return fromJson(r.data);');
          } else {
            sbClient.writeln('  return $convExpr;');
          }
          sbClient.writeln('}');
          sbClient.writeln('');
        }
      }
    }

    // Emitted only when the body actually uses it. An unconditional import
    // warns on every project whose backend functions happen not to need the
    // runtime, and a warning in generated code is one nobody can fix.
    const String coreImport = "import 'package:dartvel_core/dartvel.dart';";
    final clientBody = sbClient.toString().replaceFirst(
        coreImport,
        coreImport +
            (clientTypeImports.toList()..sort())
                .map((String uri) => "\nimport '$uri';")
                .join());
    const runtimeSymbols = <String>['DartvelRuntime', 'dartvelBaseUrl',
        'dartvelApiBase', 'DartvelConfigRuntime'];
    final needsRuntime =
        runtimeSymbols.any((String symbol) => clientBody.contains(symbol));
    final clientSource = needsRuntime
        ? clientBody.replaceFirst("import 'dart:convert';",
            "import 'dart:convert';\nimport 'dartvel_runtime.dart';")
        : clientBody;
    File(p.join(libClientDir.path, 'functions.g.dart'))
        .writeAsStringSync(clientSource);
    File(p.join(libClientDir.path, 'schedules.g.dart'))
        .writeAsStringSync(await _generateSchedules(
      root: root,
      pkgName: pkgName,
      backendDir: backendDir,
    ));
    File(p.join(libClientDir.path, 'policies.g.dart')).writeAsStringSync(
      _registrationsSource(
        library: 'dartvel_client_policies',
        function: 'dartvelRegisterPolicies',
        // Declared, as on the server: an application's own register for the
        // same action and resource wins on both sides, whichever ran first, so
        // the client never shows an action the server refuses.
        registration: 'registerDeclared',
        policies: policies,
      ),
    );
    // The client half is a separate file because the generated backend
    // imports the one above, and a client schedule declared on a page would
    // pull Flutter into a server with no dart:ui.
    File(p.join(libClientDir.path, 'client_schedules.g.dart'))
        .writeAsStringSync(await _generateClientSchedules(
      root: root,
      pkgName: pkgName,
      backendDir: backendDir,
    ));
    File(p.join(libClientDir.path, 'ai_tools.g.dart'))
        .writeAsStringSync(await _generateAITools(
      root: root,
      pkgName: pkgName,
      backendDir: backendDir,
    ));

    // Update .gitignore to exclude generated files (idempotent)
    final gitignore = File(p.join(root, '.gitignore'));
    final desired = <String>{
      '/lib/dartvel_client/',
      '/.dartvel/',
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
      if (changed) gitignore.writeAsStringSync('${lines.join('\n')}\n');
    } catch (_) {}

    log('dartvel: generated lib/dartvel_client/* and .dart_tool/dartvel_backend*.g.dart');
  }

  /// The client half, in its own file.
  ///
  /// Separate from schedules.g.dart because the generated backend imports
  /// that one, and a client schedule declared on a page would pull Flutter
  /// into a server with no dart:ui. A show clause does not help: the whole
  /// library is still compiled.
  static Future<String> _generateClientSchedules({
    required String root,
    required String pkgName,
    required String backendDir,
  }) async {
    final entries = await _cronEntries(
      root: root,
      pkgName: pkgName,
      backendDir: backendDir,
    );
    final List<_CronEntry> clientCron = entries
        .where((entry) => entry.target == 'DVCronTarget.client')
        .toList(growable: false);
    _refusePrivateCron(clientCron, 'DVClientCron');
    final Map<String, String> aliasByImport = <String, String>{};
    for (final _CronEntry entry in clientCron) {
      aliasByImport.putIfAbsent(
        entry.importUri,
        () => 'cron${aliasByImport.length}',
      );
    }

    final sb = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      // unused_import as well: an application with no client schedule gets
      // a starter that starts nothing, so dart:async and the core barrel are
      // there for the file's shape rather than for its body.
      ..writeln(
          '// ignore_for_file: unused_element, unused_import, directives_ordering')
      ..writeln('library dartvel_client_client_schedules;')
      ..writeln()
      ..writeln("import 'dart:async';")
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      ..writeln("import 'schedules.g.dart' show dartvelClientCronEntries;");
    if (clientCron.isNotEmpty) {
      // The application lifecycle, which only this half can reach: DV lives
      // in dartvel_flutter, and importing it is exactly why the client
      // schedules are a file of their own rather than lines in the one the
      // generated server reads.
      sb.writeln("import 'package:dartvel_flutter/dartvel_flutter.dart' "
          "show DV, DVAppLifecycle, DVShowingPages;");
    }
    for (final MapEntry<String, String> import in aliasByImport.entries) {
      sb.writeln("import '${esc(import.key)}' as ${import.value};");
    }
    sb
      ..writeln()
      ..writeln('/// The function behind each client schedule.')
      ..writeln('///')
      ..writeln('/// registerAll refuses an entry with no handler rather')
      ..writeln('/// than skipping it, so a name here that does not match an')
      ..writeln('/// entry is a startup failure and not a job that quietly')
      ..writeln('/// never runs.');
    if (clientCron.isEmpty) {
      sb.writeln('const Map<String, Future<void> Function()> '
          'dartvelClientCronHandlers = '
          '<String, Future<void> Function()>{};');
    } else {
      sb.writeln('final Map<String, Future<void> Function()> '
          'dartvelClientCronHandlers = '
          '<String, Future<void> Function()>{');
      for (final _CronEntry entry in clientCron) {
        final String alias = aliasByImport[entry.importUri]!;
        sb.writeln("  '${esc(entry.name)}': () async { "
            '${entry.returnsPlainVoid ? '' : 'await '}'
            '$alias.${entry.name}(); },');
      }
      sb.writeln('};');
    }
    sb
      ..writeln()
      ..writeln('/// Registers every client schedule and starts ticking.')
      ..writeln('///')
      ..writeln('/// Starts nothing when the application declares none: a')
      ..writeln('/// timer firing in every application that has no schedule')
      ..writeln('/// is a cost nobody asked for.');
    if (clientCron.isEmpty) {
      // Nothing to start, and nothing to listen to. A lifecycle subscription
      // in every application that declares no schedule is the same cost as
      // the timer this file already refuses to start.
      sb
        ..writeln('void dartvelStartClientSchedules({')
        ..writeln('  Duration every = const Duration(seconds: 20),')
        ..writeln('  bool catchUp = false,')
        ..writeln('}) {')
        ..writeln('  // The application declares no client schedule.')
        ..writeln('}');
      return sb.toString();
    }
    sb
      ..writeln('/// Ticks only while the application is in front of')
      ..writeln('/// somebody. On a phone a tick is a wakeup as well as a')
      ..writeln('/// tick: a timer firing every twenty seconds from a')
      ..writeln('/// pocket wakes the device for a schedule that could have')
      ..writeln('/// waited, and the system suspends the timer anyway -- so')
      ..writeln('/// the periods that pass while the application is away')
      ..writeln('/// arrived whenever it happened to fire next.')
      ..writeln('///')
      ..writeln('/// Coming back ticks once straight away, because whatever')
      ..writeln('/// came due while it was away is due now rather than up to')
      ..writeln('/// `every` from now, and that wait is the whole of what')
      ..writeln('/// somebody who just opened the application is waiting on.')
      ..writeln('void dartvelStartClientSchedules({')
      ..writeln('  Duration every = const Duration(seconds: 20),')
      ..writeln('  bool catchUp = false,')
      ..writeln('}) {')
      ..writeln('  final DVScheduler scheduler = DVScheduler()')
      ..writeln('    ..registerAll(')
      ..writeln('      dartvelClientCronEntries,')
      ..writeln('      handlers: dartvelClientCronHandlers,')
      ..writeln('      catchUp: catchUp,')
      ..writeln('    );')
      ..writeln('  Timer? timer;')
      ..writeln('  StreamSubscription<DVAppLifecycle>? lifecycle;')
      ..writeln('  void tickEvery() {')
      ..writeln('    timer ??= Timer.periodic(every, (Timer _) => scheduler.tick());')
      ..writeln('  }')
      ..writeln('  void pause() {')
      ..writeln('    timer?.cancel();')
      ..writeln('    timer = null;')
      ..writeln('  }')
      // Owned by the pages on screen rather than started here. Started here,
      // nothing ever stopped it: a second router ran every schedule twice,
      // and a widget test that built the router ended with the timer still
      // running.
      ..writeln('  // Runs while a page is on screen. Registering again -- a')
      ..writeln('  // second router -- replaces this rather than adding a second')
      ..writeln('  // timer, so no schedule runs twice.')
      ..writeln("  DVShowingPages.run('dartvel.clientSchedules', start: () {")
      ..writeln('    tickEvery();')
      ..writeln('    lifecycle ??= DV.lifecycle.app.listen((DVAppLifecycle state) {')
      ..writeln('      switch (state) {')
      ..writeln('        case DVAppLifecycle.ready:')
      ..writeln('        case DVAppLifecycle.resuming:')
      ..writeln('          scheduler.tick();')
      ..writeln('          tickEvery();')
      ..writeln('        case DVAppLifecycle.backgrounded:')
      ..writeln('        case DVAppLifecycle.suspended:')
      ..writeln('        case DVAppLifecycle.shuttingDown:')
      ..writeln('        case DVAppLifecycle.stopped:')
      ..writeln('          pause();')
      ..writeln('        default:')
      ..writeln('          break;')
      ..writeln('      }')
      ..writeln('    });')
      ..writeln('  }, stop: () {')
      ..writeln('    pause();')
      ..writeln('    unawaited(lifecycle?.cancel());')
      ..writeln('    lifecycle = null;')
      ..writeln('  });')
      ..writeln('}');
    return sb.toString();
  }

  /// Every cron entry the project declares, backend and client.
  /// Every `@DVBackendCron` and `@DVClientCron` this application runs, as
  /// the schedule generators read them.
  ///
  /// Public for the documentation site, so the schedules it lists are the
  /// ones registered rather than a second reading of the source that could
  /// disagree with this one. [file] is relative to [root], including for a
  /// schedule a mounted module contributes.
  static Future<
      List<({String name, String cron, bool client, String file, bool? catchUp})>>
      cronSchedules({required String root, required String pkgName}) async {
    final String backendDir = dvProjectBackendDir(root);
    final Map<String, String> projectRoots = <String, String>{
      for (final project in _mergedProjects(root, pkgName, backendDir))
        project.packageName: project.root,
    };
    final entries =
        await _cronEntries(root: root, pkgName: pkgName, backendDir: backendDir);
    return <({String name, String cron, bool client, String file, bool? catchUp})>[
      for (final _CronEntry entry in entries)
        (
          name: entry.name,
          cron: entry.cron,
          client: entry.target == 'DVCronTarget.client',
          file: p
              .relative(
                p.join(
                  projectRoots[Uri.parse(entry.importUri).pathSegments.first] ??
                      root,
                  entry.relativePath,
                ),
                from: root,
              )
              .replaceAll(r'\', '/'),
          catchUp: entry.catchUp,
        ),
    ];
  }

  static Future<List<_CronEntry>> _cronEntries({
    required String root,
    required String pkgName,
    required String backendDir,
  }) async {
    final entries = <_CronEntry>[];
    for (final (project, file) in _mergedLibFiles(root, pkgName, backendDir)) {
      final source = await file.readAsString();
      final relativePath =
          p.relative(file.path, from: project.root).replaceAll('\\', '/');
      final importUri = relativePath.replaceFirst(
          RegExp(r'^lib/'), 'package:${project.packageName}/');
      _collectCronEntries(
        source: source,
        relativePath: relativePath,
        importUri: importUri,
        annotationName: 'DVBackendCron',
        target: 'DVCronTarget.backend',
        entries: entries,
      );
      _collectCronEntries(
        source: source,
        relativePath: relativePath,
        importUri: importUri,
        annotationName: 'DVClientCron',
        target: 'DVCronTarget.client',
        entries: entries,
      );
    }
    return entries;
  }

  /// Every `@DVPolicy(Resource)` class in the application and the modules it
  /// merges, with whether the generated server can load it.
  ///
  /// The client registers every one. The server registers those whose file
  /// does not reach Flutter: a policy written against the generated models
  /// reaches them through the `dartvel_client.dart` barrel, which exports the
  /// router and the generated widgets, and importing that into a process with
  /// no dart:ui is what once stopped the server registering policies at all.
  /// A show clause does not prevent it, because the whole library is still
  /// compiled.
  static Future<List<_DVFoundPolicy>> _discoverPolicies({
    required String root,
    required String pkgName,
    required String backendDir,
  }) async {
    final List<_DVFoundPolicy> found = <_DVFoundPolicy>[];
    for (final (project, file) in _mergedLibFiles(root, pkgName, backendDir)) {
      final String source = await file.readAsString();
      if (!source.contains('@DVPolicy(')) continue;
      final String relativePath =
          p.relative(file.path, from: project.root).replaceAll('\\', '/');
      final String importUri = relativePath.replaceFirst(
          RegExp(r'^lib/'), 'package:${project.packageName}/');
      final List<DVPolicyClass> classes =
          dvPolicyClassesIn(source, relativePath);
      if (classes.isEmpty) continue;
      final String? reached = JobGenerator.flutterReachedFrom(
        file.path,
        root: project.root,
        pkgName: project.packageName,
      );
      for (final DVPolicyClass policy in classes) {
        found.add(_DVFoundPolicy(
          importUri: importUri,
          shownPath: p.relative(file.path, from: root).replaceAll('\\', '/'),
          policy: policy,
          clientOnlyBecause: reached,
        ));
      }
    }
    return found;
  }

  /// Stops the build on a route whose `Resource.action` no policy class the
  /// server registers defines.
  ///
  /// An action on a framework resource -- a name starting `DV`, such as
  /// `DVApiKeyResource.viewAny` -- is left alone: the application answers it
  /// by registering it, which the build cannot see, and the generated server
  /// refuses to start when it has not.
  static void _refuseUnanswerableRoutePolicies(
    List<Map<String, String>> entries,
    List<_DVFoundPolicy> policies,
  ) {
    final Map<String, _DVFoundPolicy> server = <String, _DVFoundPolicy>{};
    final Map<String, _DVFoundPolicy> clientOnly = <String, _DVFoundPolicy>{};
    for (final _DVFoundPolicy found in policies) {
      for (final DVPolicyMethod method in found.policy.methods) {
        (found.clientOnlyBecause == null ? server : clientOnly).putIfAbsent(
            '${found.policy.resource}.${method.action}', () => found);
      }
    }
    for (final Map<String, String> entry in entries) {
      if (entry['policyAction'] != '1') continue;
      final String action = entry['policy']!;
      if (server.containsKey(action) || action.startsWith('DV')) continue;
      final String declared =
          "@DVBackendFunction(policy: '$action') in ${entry['rel']}";
      final _DVFoundPolicy? client = clientOnly[action];
      final int dot = action.indexOf('.');
      if (client == null) {
        throw StateError(
          '$declared names an action no @DVPolicy class defines, so the '
          'route could never be allowed by a policy -- only refused, or opened '
          'by a DVBackendPolicy.decide saying yes to a policy nobody wrote. '
          'Write ${action.substring(dot + 1)} on a '
          '@DVPolicy(${action.substring(0, dot)}) class; policy methods are '
          '${dvPolicyActions.join(', ')}.',
        );
      }
      throw StateError(
        '$declared is defined by ${client.policy.className} in '
        '${client.shownPath}, which the generated server cannot load: that '
        'file reaches Flutter through ${client.clientOnlyBecause}. The route '
        'would be refused on every request. Write the policy the server '
        'enforces against dartvel_core, without importing the generated '
        'client.',
      );
    }
  }

  /// A file registering [policies] with `DV.Auth.authorization` as the
  /// declared answers, which the application's own registration wins over.
  ///
  /// The registration tears the method off rather than wrapping it, so Dart
  /// infers the user and resource types from the policy's own signature. That
  /// is what makes the registry key the type the policy actually takes: a
  /// string this generator assembled could be assembled wrongly, and the
  /// symptom would be a policy that is registered under a name nothing asks
  /// about, which looks exactly like a policy that denies.
  static String _registrationsSource({
    required String library,
    required String function,
    required List<_DVFoundPolicy> policies,
    required String registration,
  }) {
    final Map<String, String> aliasByImport = <String, String>{};
    for (final _DVFoundPolicy found in policies) {
      aliasByImport.putIfAbsent(
        found.importUri,
        () => 'pol${aliasByImport.length}',
      );
    }

    final StringBuffer sb = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      ..writeln('// ignore_for_file: unused_import, directives_ordering')
      ..writeln('library $library;')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';");
    for (final MapEntry<String, String> import in aliasByImport.entries) {
      sb.writeln("import '${esc(import.key)}' as ${import.value};");
    }
    sb
      ..writeln()
      ..writeln('/// Puts every policy the application declares into the')
      ..writeln('/// authorization registry.')
      ..writeln('///')
      ..writeln('/// Called before anything can ask a question of it. A')
      ..writeln('/// policy nobody registered is answered false, so the cost')
      ..writeln('/// of calling this late is a check that denies for a while')
      ..writeln('/// rather than one that throws.')
      ..writeln('void $function() {');
    if (policies.isEmpty) {
      sb.writeln('  // The application declares no @DVPolicy class.');
    }
    int index = 0;
    for (final _DVFoundPolicy found in policies) {
      final DVPolicyClass policy = found.policy;
      final String alias = aliasByImport[found.importUri]!;
      final String variable = 'policy$index';
      index++;
      if (policy.methods.isEmpty) {
        // A policy class with no conventional method is not an error: it may
        // be a work in progress, and refusing the build over it would stop
        // somebody halfway through writing one.
        sb.writeln('  // ${policy.className} declares no policy action yet.');
        continue;
      }
      sb.writeln(
          '  final $alias.${policy.className} $variable = '
          '$alias.${policy.className}();');
      for (final DVPolicyMethod method in policy.methods) {
        sb.writeln("  const DVAuthAuthorization()"
            ".$registration('${esc(method.action)}', $variable.${method.action});");
      }
    }
    sb.writeln('}');
    return sb.toString();
  }

  static Future<String> _generateSchedules({
    required String root,
    required String pkgName,
    required String backendDir,
  }) async {
    final entries = <_CronEntry>[];
    for (final (project, file) in _mergedLibFiles(root, pkgName, backendDir)) {
      final source = await file.readAsString();
      final relativePath =
          p.relative(file.path, from: project.root).replaceAll('\\', '/');
      final importUri = relativePath.replaceFirst(
          RegExp(r'^lib/'), 'package:${project.packageName}/');
      _collectCronEntries(
        source: source,
        relativePath: relativePath,
        importUri: importUri,
        annotationName: 'DVBackendCron',
        target: 'DVCronTarget.backend',
        entries: entries,
      );
      _collectCronEntries(
        source: source,
        relativePath: relativePath,
        importUri: importUri,
        annotationName: 'DVClientCron',
        target: 'DVCronTarget.client',
        entries: entries,
      );
    }

    // The half that was missing. The entries below were generated correctly
    // and read by nothing: DVScheduler was instantiated in one place in the
    // repository and that place was its own unit test, so a schedule
    // travelled from the annotation into the list and stopped there while
    // the section recorded it as running.
    final List<_CronEntry> backendCron = entries
        .where((entry) => entry.target == 'DVCronTarget.backend')
        .toList(growable: false);
    _refusePrivateCron(backendCron, 'DVBackendCron');
    final Map<String, String> cronAliasByImport = <String, String>{};
    for (final _CronEntry entry in backendCron) {
      cronAliasByImport.putIfAbsent(
        entry.importUri,
        () => 'cron${cronAliasByImport.length}',
      );
    }

    final sb = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      ..writeln('// ignore_for_file: unused_element, directives_ordering')
      ..writeln('library dartvel_client_schedules;')
      ..writeln()
      ..writeln("import 'dart:async';")
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';");
    for (final MapEntry<String, String> import in cronAliasByImport.entries) {
      sb.writeln("import '${esc(import.key)}' as ${import.value};");
    }
    sb
      ..writeln()
      ..writeln('const List<DVCronEntry> dartvelCronEntries = <DVCronEntry>[');
    for (final entry in entries) {
      sb
        ..writeln('  DVCronEntry(')
        ..writeln("    name: '${esc(entry.name)}',")
        ..writeln("    cron: '${esc(entry.cron)}',")
        ..writeln('    target: ${entry.target},')
        ..writeln("    importUri: '${esc(entry.importUri)}',")
        ..writeln("    filePath: '${esc(entry.relativePath)}',");
      if (entry.catchUp != null) {
        sb.writeln('    catchUp: ${entry.catchUp},');
      }
      sb.writeln('  ),');
    }
    sb
      ..writeln('];')
      ..writeln()
      ..writeln(
          'final List<DVCronEntry> dartvelBackendCronEntries = List<DVCronEntry>.unmodifiable(')
      ..writeln(
          '  dartvelCronEntries.where((entry) => entry.target == DVCronTarget.backend),')
      ..writeln(');')
      ..writeln()
      ..writeln(
          'final List<DVCronEntry> dartvelClientCronEntries = List<DVCronEntry>.unmodifiable(')
      ..writeln(
          '  dartvelCronEntries.where((entry) => entry.target == DVCronTarget.client),')
      ..writeln(');');

    sb
      ..writeln()
      ..writeln('/// The function behind each backend schedule.')
      ..writeln('///')
      ..writeln('/// registerAll refuses an entry with no handler rather than')
      ..writeln('/// skipping it, so a name here that does not match an entry')
      ..writeln('/// is a startup failure and not a job that quietly never')
      ..writeln('/// runs.');
    if (backendCron.isEmpty) {
      sb.writeln('const Map<String, Future<void> Function()> '
          'dartvelBackendCronHandlers = '
          '<String, Future<void> Function()>{};');
    } else {
      sb.writeln('final Map<String, Future<void> Function()> '
          'dartvelBackendCronHandlers = '
          '<String, Future<void> Function()>{');
      for (final _CronEntry entry in backendCron) {
        final String alias = cronAliasByImport[entry.importUri]!;
        sb.writeln("  '${esc(entry.name)}': () async { "
            '${entry.returnsPlainVoid ? '' : 'await '}'
            '$alias.${entry.name}(); },');
      }
      sb.writeln('};');
    }
    sb
      ..writeln()
      ..writeln('/// Registers every backend schedule and starts ticking.')
      ..writeln('///')
      ..writeln('/// Returns null when the application declares no backend')
      ..writeln('/// schedule: a timer firing in every application that has')
      ..writeln('/// none is a cost nobody asked for.')
      ..writeln('///')
      ..writeln('/// The tick interval is shorter than a minute because the')
      ..writeln('/// finest cron granularity is a minute, and a tick landing')
      ..writeln('/// a little after the boundary is what keeps a minute')
      ..writeln('/// schedule from skipping one. Ticking often is safe: a')
      ..writeln('/// task is keyed to the occurrence it last ran for.')
      ..writeln('///')
      ..writeln('/// [lease] is claimed for each occurrence before it runs, so')
      ..writeln('/// several processes sharing its store run it once between')
      ..writeln('/// them. [clock] is the time the schedules are read against.')
      ..writeln('Timer? dartvelStartBackendSchedules({')
      ..writeln('  Duration every = const Duration(seconds: 20),')
      ..writeln('  bool catchUp = false,')
      ..writeln('  DateTime Function()? clock,')
      ..writeln('  DVScheduleLease? lease,')
      ..writeln('}) {');
    if (backendCron.isEmpty) {
      // No scheduler at all rather than one behind an isEmpty guard. The
      // guard made it a no-op at run time, but a module's generated files
      // are read for the capabilities it uses, and a scheduler written into
      // the file read as cron -- so mounting a module that schedules nothing
      // was refused for a grant nobody needed.
      sb
        ..writeln('  // The application declares no backend schedule.')
        ..writeln('  return null;')
        ..writeln('}');
      return sb.toString();
    }
    sb
      ..writeln('  if (dartvelBackendCronEntries.isEmpty) return null;')
      // A schedule that throws is recorded as the cron process's crash, not
      // only appended to a list nothing in a served process reads.
      ..writeln('  final DVScheduler scheduler = DVScheduler(clock: clock, lease: lease, onFailure: DVServerCrashes.recordScheduled)')
      ..writeln('    ..registerAll(')
      ..writeln('      dartvelBackendCronEntries,')
      ..writeln('      handlers: dartvelBackendCronHandlers,')
      ..writeln('      catchUp: catchUp,')
      ..writeln('    );')
      ..writeln('  return Timer.periodic(every, (Timer _) => scheduler.tick());')
      ..writeln('}');
    return sb.toString();
  }

  static Future<String> _generateAITools({
    required String root,
    required String pkgName,
    required String backendDir,
  }) async {
    final exposeBackendFunctions = _shouldExposeBackendFunctionsAsAITools(root);
    final entriesByName = <String, _AIToolEntry>{};
    for (final (project, file) in _mergedLibFiles(root, pkgName, backendDir)) {
      final source = await file.readAsString();
      final relativePath =
          p.relative(file.path, from: project.root).replaceAll('\\', '/');
      final importUri = relativePath.replaceFirst(
          RegExp(r'^lib/'), 'package:${project.packageName}/');
      _collectAIToolEntries(
        source: source,
        relativePath: relativePath,
        importUri: importUri,
        entriesByName: entriesByName,
      );
      if (exposeBackendFunctions &&
          relativePath.startsWith('${project.backendDir}/')) {
        _collectBackendFunctionAIToolEntries(
          source: source,
          relativePath: relativePath,
          importUri: importUri,
          entriesByName: entriesByName,
        );
      }
    }
    final entries = entriesByName.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    // Which entries this file can generate a handler for.
    //
    // The registration is called from the generated backend, so importing a
    // tool declared in a page would pull Flutter into a server that has no
    // dart:ui -- the whole application would stop compiling for the sake of
    // one tool the backend could never have called anyway. And a private
    // declaration has no public symbol in its file, so a handler written
    // against the catalogue's public name would not compile either.
    bool registrable(_AIToolEntry entry) =>
        !entry.declaredName.startsWith('_') &&
        entry.relativePath.startsWith('$backendDir/');

    // Aliases for the files the handlers call into. The entries used to
    // carry a name, a description and a file path and nothing else, which is
    // a catalogue rather than a set of tools: an assistant could read that a
    // function existed and had no way to run it.
    final Map<String, String> toolAliasByImport = <String, String>{};
    for (final _AIToolEntry entry in entries) {
      // Only the ones a handler will be generated for, or the import is
      // unused and the generated file carries an analyzer warning nobody
      // can act on.
      if (!registrable(entry)) continue;
      toolAliasByImport.putIfAbsent(
        entry.importUri,
        () => 'tool${toolAliasByImport.length}',
      );
    }

    final sb = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      ..writeln('// ignore_for_file: unused_element, directives_ordering')
      ..writeln('library dartvel_client_ai_tools;')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';");
    for (final MapEntry<String, String> import in toolAliasByImport.entries) {
      sb.writeln("import '${esc(import.key)}' as ${import.value};");
    }
    sb
      ..writeln()
      ..writeln('const List<DVAIToolEntry> dartvelAITools = <DVAIToolEntry>[');
    for (final entry in entries) {
      sb
        ..writeln('  DVAIToolEntry(')
        ..writeln("    name: '${esc(entry.name)}',")
        ..writeln("    description: '${esc(entry.description)}',")
        ..writeln("    importUri: '${esc(entry.importUri)}',")
        ..writeln("    filePath: '${esc(entry.relativePath)}',")
        ..writeln('  ),');
    }
    sb.writeln('];');

    // The half that was missing: something an assistant can actually call.
    //
    // A JSON Schema per tool, because every provider requires one, and a
    // handler that reads the arguments out of the input object and calls the
    // function. A value of the wrong type is refused by name rather than
    // coerced: a tool that quietly received 0 for a number it could not read
    // would run and be wrong.
    sb
      ..writeln()
      ..writeln('/// Registers every generated tool so a provider can call')
      ..writeln('/// them. Idempotent -- the registry overwrites by name.')
      ..writeln('void registerDartvelAITools() {');
    if (entries.isEmpty) {
      sb.writeln('  // This application declares no @DVAITool inputs.');
    } else {
      sb.writeln('  const registry = DVAIToolRegistry();');
    }
    for (final _AIToolEntry entry in entries) {
      // Listed, not registered, and said so where somebody reading the
      // generated file will see it rather than wondering why their tool is
      // never called.
      if (!registrable(entry)) {
        final String why = entry.declaredName.startsWith('_')
            ? 'it is declared as ${entry.declaredName}, which is private to '
                'its own file'
            : 'it is declared in ${entry.relativePath}, outside the backend '
                'this registration runs in';
        sb.writeln(
          "  // '${esc(entry.name)}' is listed and not registered: $why.",
        );
        continue;
      }
      final String alias = toolAliasByImport[entry.importUri]!;
      final String schema = entry.parameterNames.isEmpty
          ? "const <String, DVJsonValue>{}"
          // One const on the map, none inside it: a const on one value and not
          // its siblings is two lints in every application that declares a
          // tool, and generated code has to pass the analyzer its users run.
          : 'const <String, DVJsonValue>{\n'
              "        'type': DVJsonString('object'),\n"
              "        'properties': DVJsonMap(<String, DVJsonValue>{\n"
              '${[
                  for (var i = 0; i < entry.parameterNames.length; i++)
                    "          '${esc(entry.parameterNames[i])}': "
                        'DVJsonMap(<String, DVJsonValue>{'
                        "'type': DVJsonString('"
                        "${_dvJsonSchemaType(entry.parameterTypes[i])}')}),"
                ].join('\n')}\n'
              '        }),\n'
              '      }';
      final List<String> args = <String>[
        for (var i = 0; i < entry.parameterNames.length; i++)
          '${entry.named ? '${entry.parameterNames[i]}: ' : ''}'
              '_dvToolArg(args, \'${esc(entry.parameterNames[i])}\', '
              "'${esc(entry.parameterTypes[i])}') "
              'as ${entry.parameterTypes[i]}',
      ];
      sb
        ..writeln("  registry.register('${esc(entry.name)}',")
        ..writeln('      (DVJsonObject input) async {')
        ..writeln('    final args = DVJsonCodec.toJsonObject(input);');
      if (entry.returnsVoid) {
        // Awaited only when there is a Future to await. `await f()` on a
        // plain void is an error, not a no-op.
        sb
          ..writeln('    ${entry.returnsPlainVoid ? '' : 'await '}'
              '$alias.${entry.name}(${args.join(', ')});')
          ..writeln('    return const DVJsonNull();');
      } else {
        sb
          ..writeln('    final result = await $alias.${entry.name}('
              '${args.join(', ')});')
          ..writeln('    return DVJsonCodec.fromJson(result);');
      }
      sb
        ..writeln('  },')
        ..writeln("      description: '${esc(entry.description)}',")
        ..writeln('      parameters: $schema);');
    }
    sb.writeln('}');

    if (entries.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('/// One argument, refused by name rather than coerced.')
        ..writeln('///')
        ..writeln('/// A tool that quietly received 0 for a number it could')
        ..writeln('/// not read would run and be wrong, which is the failure')
        ..writeln('/// a schema exists to prevent.')
        ..writeln('Object? _dvToolArg('
            'Map<String, Object?> args, String name, String type) {')
        ..writeln('  final value = args[name];')
        ..writeln("  if (value == null && !type.endsWith('?')) {")
        ..writeln('    throw ArgumentError.value(')
        ..writeln('        name, name, '
            "'is required by this tool and was not supplied');")
        ..writeln('  }')
        ..writeln('  if (value == null) return null;')
        ..writeln("  final base = type.replaceAll('?', '');")
        ..writeln("  if (base == 'int' && value is num) return value.toInt();")
        ..writeln("  if (base == 'double' && value is num) {")
        ..writeln('    return value.toDouble();')
        ..writeln('  }')
        ..writeln("  if (base == 'String') return value.toString();")
        ..writeln('  return value;')
        ..writeln('}');
    }
    return sb.toString();
  }

  /// The JSON Schema type a Dart parameter type advertises.
  ///
  /// Anything this does not recognise is advertised as a string rather than
  /// omitted, because a provider requires a type on every property and a
  /// missing one is a tool it will not call.
  static String _dvJsonSchemaType(String type) {
    final String base = type.replaceAll('?', '').trim();
    if (base == 'int') return 'integer';
    if (base == 'double' || base == 'num') return 'number';
    if (base == 'bool') return 'boolean';
    if (base.startsWith('List')) return 'array';
    if (base.startsWith('Map')) return 'object';
    return 'string';
  }

  /// The prefix a lowered body reaches its own file's public names through.
  static const String _dvSourcePrefix = 'dvSource';

  static final RegExp _importDirective = RegExp(
    r'''^\s*import\s+(['"])([^'"]+)\1([^;]*);''',
    multiLine: true,
  );

  /// A lowered backend function, in a library whose imports are its source
  /// file's.
  ///
  /// Relative imports are rewritten for where this library is. An import
  /// that reaches Flutter is left out: a server cannot compile it, and a body
  /// that did not use it compiled before imports were carried.
  static String _loweredFunctionLibrary({
    required String source,
    required String sourcePath,
    required String relative,
    required String packageName,
    required String sourceImport,
    required bool qualified,
    required String function,
    required String outDir,
  }) {
    final String projectRoot = p.normalize(
      sourcePath.substring(0, sourcePath.length - relative.length),
    );
    final String lib = p.join(projectRoot, 'lib');
    final StringBuffer out = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      ..writeln('//')
      ..writeln("// The backend function in $relative, with that file's imports.")
      ..writeln('// ignore_for_file: unused_import, directives_ordering, '
          'duplicate_import, unnecessary_import')
      ..writeln();
    for (final RegExpMatch match in _importDirective.allMatches(source)) {
      final String uri = match.group(2)!;
      if (JobGenerator.flutterReachedThrough(uri,
              from: sourcePath, root: projectRoot, pkgName: packageName) !=
          null) {
        continue;
      }
      String target = uri;
      if (!uri.startsWith('dart:') && !uri.startsWith('package:')) {
        final String resolved =
            p.normalize(p.join(p.dirname(sourcePath), uri));
        target = p.isWithin(lib, resolved)
            ? 'package:$packageName/'
                '${p.relative(resolved, from: lib).replaceAll(r'\', '/')}'
            : p.relative(resolved, from: outDir).replaceAll(r'\', '/');
      }
      out.writeln("import '$target'${match.group(3)};");
    }
    if (qualified) {
      out.writeln("import '$sourceImport' as $_dvSourcePrefix;");
    }
    out
      ..writeln()
      ..writeln(function);
    return out.toString();
  }

  static ({
    String sourceName,
    String publicName,
    String returnType,
    String parameters,
    DVFunctionBody body,
  })? _privateBackendExpression(String source, String rel) {
    // Scanned over indices rather than lines. The old extractor matched a
    // single line, so a block body was refused and a multi-line expression
    // body was refused with it.
    final RegExp declaration = RegExp(
      r'(Future<[^>]+>|Future|Stream<[^>]+>|[A-Za-z_][A-Za-z0-9_<>, ?]*)'
      r'\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
    );

    int cursor = 0;
    while (true) {
      final int annotation = source.indexOf('@DVBackendFunction', cursor);
      if (annotation == -1) return null;

      // Step past the annotation's own argument list, then any further
      // annotations or pragmas sitting between it and the declaration. The
      // argument list is stepped over by counting parentheses: a formatter
      // wraps `@DVBackendFunction(mfa: DVMfa.recent(Duration(minutes: 15)))`
      // across lines, and reading the next line as the declaration missed
      // the function, so its route called a name that did not exist.
      int argsEnd = annotation + '@DVBackendFunction'.length;
      final int open = _firstNonSpace(source, argsEnd);
      if (open < source.length && source[open] == '(') {
        final int close = _matchingParen(source, open);
        if (close == -1) return null;
        argsEnd = close + 1;
      }
      int at = source.indexOf('\n', argsEnd);
      if (at == -1) return null;
      while (at < source.length) {
        final int lineEnd =
            source.indexOf('\n', at + 1) == -1 ? source.length : source.indexOf('\n', at + 1);
        final String line = source.substring(at, lineEnd).trim();
        if (line.isEmpty || line.startsWith('@')) {
          at = lineEnd;
          continue;
        }
        break;
      }
      if (at >= source.length) return null;

      final Match? match = declaration.matchAsPrefix(source, _firstNonSpace(source, at));
      if (match == null) {
        cursor = annotation + 1;
        continue;
      }

      final String name = match.group(2)!;
      final int openParen = match.end - 1;
      final int closeParen = _matchingParen(source, openParen);
      if (closeParen == -1) {
        cursor = annotation + 1;
        continue;
      }

      if (!name.startsWith('_')) return null;

      final DVFunctionBody? body = dvFunctionBodyAfter(source, closeParen);
      if (body == null) {
        throw StateError(
          'Dartvel private backend function input $name in $rel has no body. '
          'It is a function that returns a value, either '
          'Future<String> $name(String input) async => input or with a block.',
        );
      }

      return (
        sourceName: name,
        publicName: name.substring(1),
        returnType: match.group(1)!.trim(),
        parameters: source.substring(openParen + 1, closeParen).trim(),
        body: body,
      );
    }
  }

  static int _firstNonSpace(String source, int start) {
    int at = start;
    while (at < source.length && source[at].trim().isEmpty) {
      at += 1;
    }
    return at;
  }

  static int _matchingParen(String source, int openParen) {
    int depth = 0;
    for (int index = openParen; index < source.length; index++) {
      final String char = source[index];
      if (char == '(') depth++;
      if (char == ')') {
        depth--;
        if (depth == 0) return index;
      }
    }
    return -1;
  }

  static Set<String> _topLevelPublicSourceSymbols(String source) {
    final symbols = <String>{};
    final declarations = RegExp(
      r'^(?:final|const|var)\s+(?:(?:[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+)?([A-Za-z][A-Za-z0-9_]*)\s*=',
      multiLine: true,
    );
    for (final match in declarations.allMatches(source)) {
      symbols.add(match.group(1)!);
    }
    final functions = RegExp(
      r'^(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)+([A-Za-z][A-Za-z0-9_]*)\s*\(',
      multiLine: true,
    );
    for (final match in functions.allMatches(source)) {
      symbols.add(match.group(1)!);
    }
    return symbols;
  }

  static String _qualifySourceSymbols(
    String expression,
    String alias,
    Set<String> symbols,
  ) =>
      dvQualifySourceSymbols(expression, alias, symbols);

  static Future<void> _validateMiddlewareAnnotations(String root) async {
    // The whitelist used to be the whole story: nineteen names, checked for
    // spelling and then dropped. Every one of them changed nothing, so a
    // developer who wrote bodyLimit got a green build and no limit.
    //
    // The three sets come from the runtime, so the check and the behaviour
    // cannot drift apart -- a key the runtime learns to run stops being a
    // build error in the same commit.
    final Set<String> supported = <String>{
      ...dvMiddlewareKeysBuilt,
      ...dvMiddlewareKeysAlwaysOn,
      ...dvMiddlewareKeysAtRequest,
      ...dvMiddlewareKeysWrapping,
      ...dvMiddlewareKeysUnbuiltReason.keys,
    };
    final fs = const LocalFileSystem();
    for (final entity in Glob('lib/**.dart')
        .listFileSystemSync(fs, root: root, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.contains('/lib/dartvel_client/')) continue;
      final source = await File(entity.path).readAsString();
      final relativePath =
          p.relative(entity.path, from: root).replaceAll('\\', '/');
      final annotations = RegExp(
        r'@DVUseMiddleware\s*\(\s*(?:const\s+)?(?:<\s*DVMiddlewareKey\s*>\s*)?\[(.*?)\]\s*\)',
        dotAll: true,
      ).allMatches(source);
      // A layout is a `_layout.dart` by convention, and layout-scoped
      // middleware is in the specification and implemented nowhere -- the
      // layout generator has never read this annotation. Accepting the key
      // is the worst answer available: every page under that folder looks
      // guarded and none of them is.
      if (annotations.isNotEmpty && p.basename(path) == '_layout.dart') {
        throw StateError(
          'dartvel: @DVUseMiddleware in $relativePath is layout middleware, '
          'which nothing runs. The layout is wrapped around the pages under '
          'it and its annotations are not read. Declare the keys on each '
          '@DVPage in that folder until a layout scope exists.',
        );
      }
      for (final annotation in annotations) {
        // Which scope this declaration is in. The sets differ, and until now
        // there was one set: this loop walks every file under lib/, pages
        // included, and measured a page's keys against the ones written for
        // the HTTP chain. Nine of them were accepted on a page and ran
        // nothing.
        final bool isPage = dvMiddlewareDeclaresPage(
          source,
          annotation.start,
          annotation.end,
        );
        final body = annotation.group(1) ?? '';
        final constants = RegExp(r'DVMiddlewares\.([A-Za-z_][A-Za-z0-9_]*)')
            .allMatches(body)
            .map((match) => match.group(1)!)
            .toList();
        if (constants.isEmpty && body.trim().isNotEmpty) {
          throw StateError(
            'dartvel: unsupported middleware annotation in $relativePath. '
            'Use typed DVMiddlewares constants.',
          );
        }
        for (final name in constants) {
          if (!supported.contains(name)) {
            throw StateError(
              'dartvel: unsupported middleware "DVMiddlewares.$name" in '
              '$relativePath. Supported middleware: ${supported.join(', ')}.',
            );
          }
          if (isPage) {
            final String? refusal = dvPageMiddlewareRefusal(name);
            if (refusal != null) {
              // Refused rather than accepted and dropped. Somebody who wrote
              // bodyLimit on a page believes something is being capped, and
              // nothing is: a route activation reads no body. The message
              // carries somewhere to put it instead, because a build that
              // only says no leaves them with a green tree and no feature.
              throw StateError(
                'dartvel: DVMiddlewares.$name in $relativePath cannot be page '
                'middleware. $refusal',
              );
            }
            continue;
          }
          if (name == 'csp' && _dvContentSecurityPolicy(root) == null) {
            // A policy is a statement about one application's own scripts
            // and origins. There is no default that could be right, and
            // sending no header while the key says one is sent is the
            // silence this whole set exists to end.
            throw StateError(
              'dartvel: DVMiddlewares.csp in $relativePath needs a policy. '
              'Set dartvel.security.csp in pubspec.yaml to the '
              'Content-Security-Policy this application should send. There '
              'is no default: a policy permissive enough to suit every '
              'application would protect none of them.',
            );
          }
          final String? unbuilt = dvMiddlewareKeysUnbuiltReason[name];
          if (unbuilt != null) {
            // Refused rather than ignored. Somebody who declared bodyLimit
            // has decided large bodies are rejected, and serving them is not
            // a smaller failure for having been quiet about it.
            throw StateError(
              'dartvel: DVMiddlewares.$name in $relativePath is declared and '
              'not implemented. $unbuilt',
            );
          }
        }
      }
    }
  }

  static void _collectCronEntries({
    required String source,
    required String relativePath,
    required String importUri,
    required String annotationName,
    required String target,
    required List<_CronEntry> entries,
  }) {
    // The expression is not the whole of the annotation any more. It used to
    // be, and an argument after it did not make the schedule wrong -- it made
    // it invisible, because the pattern stopped matching and the function
    // stopped being a schedule. That is the failure worth guarding: a build
    // that says nothing and an application that quietly runs nothing.
    final pattern = RegExp(
      "@$annotationName\\(\\s*(['\"])(.*?)\\1\\s*(,[^)]*)?\\)\\s*"
      r'(?:Future<[^>]+>|Future|Stream<[^>]+>|[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+'
      r'([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      dotAll: true,
    );
    for (final match in pattern.allMatches(source)) {
      entries.add(_CronEntry(
        name: match.group(4)!,
        returnsPlainVoid:
            _dvReturnsPlainVoid(match.group(0) ?? '', match.group(4)!),
        cron: match.group(2)!,
        catchUp: _cronCatchUp(
          match.group(3),
          annotationName: annotationName,
          relativePath: relativePath,
        ),
        target: target,
        importUri: importUri,
        relativePath: relativePath,
      ));
    }
  }

  /// What the arguments after a cron expression say about catch-up.
  ///
  /// Null when nothing was said, which is not the same as false: false is a
  /// schedule refusing catch-up, and it has to outrank the blanket setting a
  /// starter is called with.
  ///
  /// A value that is not a literal stops the build. Somebody who wrote
  /// catchUp has decided something about missed periods, and a generator that
  /// silently produced a schedule ignoring it would be the quiet half of the
  /// same failure the pattern above guards against.
  static bool? _cronCatchUp(
    String? args, {
    required String annotationName,
    required String relativePath,
  }) {
    if (args == null) return null;
    if (!RegExp(r'\bcatchUp\s*:').hasMatch(args)) return null;
    final RegExpMatch? literal =
        RegExp(r'\bcatchUp\s*:\s*(true|false)\b').firstMatch(args);
    if (literal == null) {
      throw StateError(
        'The @$annotationName in $relativePath writes catchUp as something '
        'this generator cannot read. It must be written as true or false in '
        'the annotation itself, because the generated schedule carries the '
        'value rather than evaluating it.',
      );
    }
    return literal.group(1) == 'true';
  }

  static void _collectAIToolEntries({
    required String source,
    required String relativePath,
    required String importUri,
    required Map<String, _AIToolEntry> entriesByName,
  }) {
    final pattern = RegExp(
      r"""@DVAITool\s*\(\s*(?:description\s*:\s*(['"])(.*?)\1\s*)?\)\s*"""
      r'(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s*)*'
      r'(?:Future<[^>]+>|Future|Stream<[^>]+>|[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+'
      r'([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)',
      dotAll: true,
    );
    for (final match in pattern.allMatches(source)) {
      final name = match.group(3)!;
      if (name.startsWith('_')) {
        throw StateError(
          'Dartvel AI tool inputs are private in the spec, but this generator '
          'still needs public tool source while private wrappers are being '
          'implemented. Rename $name to ${name.substring(1)} for this build, '
          'and reference only generated tool APIs from '
          'dartvel_client/dartvel_client.dart.',
        );
      }
      final parameterNames = <String>[];
      final parameterTypes = <String>[];
      var named = '0';
      RouteUtils.extractParams(match.group(4) ?? '', (n, t) {
        parameterNames.add(n);
        parameterTypes.add(t);
      }, onNamed: (v) => named = v);
      entriesByName[name] = _AIToolEntry(
        name: name,
        returnsVoid: _dvReturnsNothing(match.group(0) ?? '', name),
        returnsPlainVoid: _dvReturnsPlainVoid(match.group(0) ?? '', name),
        description: match.group(2) ?? '',
        importUri: importUri,
        relativePath: relativePath,
        parameterNames: parameterNames,
        parameterTypes: parameterTypes,
        named: named == '1',
      );
    }
  }

  static void _collectBackendFunctionAIToolEntries({
    required String source,
    required String relativePath,
    required String importUri,
    required Map<String, _AIToolEntry> entriesByName,
  }) {
    final pattern = RegExp(
      r'(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s*)*'
      r'@DVBackendFunction(?:\([^)]*\))?\s*'
      r'(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s*)*'
      r'(?:Future<[^>]+>|Future|Stream<[^>]+>|[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+'
      r'([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)',
      dotAll: true,
    );
    for (final match in pattern.allMatches(source)) {
      final declaration = match.group(0) ?? '';
      final name = match.group(1)!;
      final publicName = name.startsWith('_') ? name.substring(1) : name;
      if (declaration.contains('@DVAIHidden') ||
          entriesByName.containsKey(publicName)) {
        continue;
      }
      final parameterNames = <String>[];
      final parameterTypes = <String>[];
      var named = '0';
      RouteUtils.extractParams(match.group(2) ?? '', (n, t) {
        parameterNames.add(n);
        parameterTypes.add(t);
      }, onNamed: (v) => named = v);
      entriesByName[publicName] = _AIToolEntry(
        name: publicName,
        returnsVoid: _dvReturnsNothing(declaration, name),
        returnsPlainVoid: _dvReturnsPlainVoid(declaration, name),
        description: 'Backend function $name',
        importUri: importUri,
        relativePath: relativePath,
        parameterNames: parameterNames,
        parameterTypes: parameterTypes,
        named: named == '1',
        declaredName: name,
      );
    }
  }

  static bool _shouldExposeBackendFunctionsAsAITools(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return false;
    final parsed = loadYaml(pubspec.readAsStringSync());
    if (parsed is! YamlMap) return false;
    final dartvel = parsed['dartvel'];
    if (dartvel is! YamlMap) return false;
    final ai = dartvel['ai'];
    if (ai is! YamlMap) return false;
    return ai['exposeBackendFunctionsAsTools'] == true;
  }

  static String _clientReturnType(String type) {
    final trimmed = type.trim();
    if (trimmed.isEmpty) return trimmed;
    final compact = trimmed.replaceAll(' ', '');
    if (compact == 'Map<String,dynamic>' || compact == 'Map<String,Object?>') {
      return 'Map<String, Object?>';
    }
    if (compact == 'List<Map<String,dynamic>>' ||
        compact == 'List<Map<String,Object?>>') {
      return 'List<Map<String, Object?>>';
    }
    final streamMatch = RegExp(r'^Stream<(.+)>$').firstMatch(trimmed);
    if (streamMatch != null) {
      return 'Stream<${_clientReturnType(streamMatch.group(1)!)}>';
    }
    final futureMatch = RegExp(r'^Future<(.+)>$').firstMatch(trimmed);
    if (futureMatch != null) {
      return _clientReturnType(futureMatch.group(1)!);
    }
    return trimmed;
  }
}

class _CronEntry {
  final String name;
  final String cron;
  final String target;
  final String importUri;
  final String relativePath;

  /// Whether the function returns a plain `void`.
  ///
  /// `await f()` on one of those is an error -- "this expression has type
  /// void and can't be used" -- and a @DVClientCron is usually written
  /// `void refresh() {}`, so the generated handler would not compile. A
  /// Future<void> is different: awaiting it as a statement is fine.
  final bool returnsPlainVoid;

  /// What the annotation said about catch-up, or null if it said nothing.
  final bool? catchUp;

  const _CronEntry({
    required this.name,
    required this.cron,
    required this.target,
    required this.importUri,
    required this.relativePath,
    this.returnsPlainVoid = false,
    this.catchUp,
  });
}

class _AIToolEntry {
  final String name;
  final String description;
  final String importUri;
  final String relativePath;

  /// What the tool takes, so the generated handler can call it.
  ///
  /// The entries used to carry a name, a description and a file path and
  /// nothing else, which is a catalogue rather than a tool: an assistant
  /// could read that a function existed and had no way to run it.
  final List<String> parameterNames;
  final List<String> parameterTypes;

  /// Whether the parameters are named. A tool declared with named
  /// parameters has to be called with them.
  final bool named;

  /// Whether the function returns nothing.
  ///
  /// `await f()` on a void or Future<void> function produces void, and
  /// assigning that to a variable does not compile. A generated handler that
  /// did would be a server that will not build, from a tool that sends an
  /// email and returns nothing -- an ordinary thing for a tool to be.
  final bool returnsVoid;

  /// Whether it returns a plain `void` rather than a Future of one.
  ///
  /// `await f()` on a plain void is an error. This is the difference
  /// between a handler that compiles and one that does not.
  final bool returnsPlainVoid;

  /// The name the function is actually declared under.
  ///
  /// A backend function input is private by the spec, and the catalogue
  /// lists it under the public name the generated client exposes. There is
  /// no public symbol in the source file to call, so a handler written
  /// against the public name would be generated code that does not compile.
  final String declaredName;

  const _AIToolEntry({
    required this.name,
    required this.description,
    required this.importUri,
    required this.relativePath,
    this.parameterNames = const <String>[],
    this.parameterTypes = const <String>[],
    this.named = false,
    this.returnsVoid = false,
    this.returnsPlainVoid = false,
    String? declaredName,
  }) : declaredName = declaredName ?? name;
}

/// A backend function file, with the project it belongs to.
///
/// The application's own functions and a mounted module's are generated into
/// one router, and everything about a file that the generator needs -- the
/// package that imports it, the backend directory its route is measured from
/// -- is its own project's rather than the parent's.
class _DVBackendFunctionFile {
  const _DVBackendFunctionFile({
    required this.file,
    required this.relative,
    required this.packageName,
    required this.backendDir,
    required this.owner,
  });

  final File file;

  /// The path from its own project root, with forward slashes.
  final String relative;

  final String packageName;
  final String backendDir;

  /// The module id this came from, or null for the application's own.
  final String? owner;
}

List<_DVBackendFunctionFile> _functionFilesIn({
  required String projectRoot,
  required String backendDir,
  required String packageName,
  required String? owner,
}) {
  final Directory functions = Directory(p.join(projectRoot, backendDir, 'functions'));
  if (!functions.existsSync()) return const <_DVBackendFunctionFile>[];
  final List<File> files = functions
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  return <_DVBackendFunctionFile>[
    for (final File file in files)
      _DVBackendFunctionFile(
        file: file,
        relative: p.relative(file.path, from: projectRoot).replaceAll(r'\', '/'),
        packageName: packageName,
        backendDir: backendDir,
        owner: owner,
      ),
  ];
}

/// The functions of every module this application's backend answers for.
///
/// Embedded and backend-only: both run inside the parent, so the parent is
/// what serves them. Not split-backend or federated, whose functions are
/// deployed as their own service -- building a second copy from the source
/// beside the parent would answer with something nobody deployed, and would
/// go on answering after the deployed one moved on.
List<_DVBackendFunctionFile> _moduleFunctionFiles(String root) {
  final List<_DVBackendFunctionFile> files = <_DVBackendFunctionFile>[];
  for (final DVModuleMount mount in dvDiscoverModuleMounts(root)) {
    if (!mount.mounted) continue;
    // A module that wrote exports.functions: false keeps them. The block was
    // read by nothing before, so a module that had written down exactly what
    // it shares contributed every function to the parent's router anyway.
    if (!mount.exportsFunctions) continue;
    if (mount.deployment != DVModuleDeployment.embedded &&
        mount.deployment != DVModuleDeployment.backendOnly) {
      continue;
    }
    final String projectRoot = p.join(root, mount.sourcePath);
    files.addAll(_functionFilesIn(
      projectRoot: projectRoot,
      backendDir: dvProjectBackendDir(projectRoot),
      packageName: mount.packageName,
      owner: mount.id,
    ));
  }
  return files;
}

/// Refuses two functions that would answer the same request.
///
/// A module's client asks for the module's own paths, because it was
/// generated against its own project and knows nothing about a mount, so a
/// module and the parent can both claim `/reindex`. One router can only have
/// one of them: whichever lost would be a 404, or -- worse, because nothing
/// looks wrong -- the other application's answer.
void _refuseShadowedRoutes(List<_DVBackendFunctionFile> files) {
  final Map<String, _DVBackendFunctionFile> claimed =
      <String, _DVBackendFunctionFile>{};
  for (final _DVBackendFunctionFile file in files) {
    final String base = p.basenameWithoutExtension(file.relative);
    final int dot = base.lastIndexOf('.');
    final String method = dot == -1 ? 'post' : base.substring(dot + 1).toLowerCase();
    final String path = RouteUtils.routeFromRel(file.relative, file.backendDir);
    final String key = '$method $path';
    final _DVBackendFunctionFile? first = claimed[key];
    if (first == null) {
      claimed[key] = file;
      continue;
    }
    String name(_DVBackendFunctionFile f) =>
        f.owner == null ? 'the application' : 'module ${f.owner}';
    throw StateError(
      'dartvel: ${name(first)} and ${name(file)} both answer '
      '${method.toUpperCase()} $path. A mounted module keeps its own paths, '
      'so one of them has to move: rename the function, or give the module '
      'a route base of its own.',
    );
  }
}

/// The backend directory a project declares, or the default.
String dvProjectBackendDir(String projectRoot) {
  final File pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return 'lib/backend';
  try {
    final Object? doc = loadYaml(pubspec.readAsStringSync());
    final Object? dartvel = doc is Map ? doc['dartvel'] : null;
    final Object? declared = dartvel is Map ? dartvel['backendDir'] : null;
    if (declared == null || '$declared'.trim().isEmpty) return 'lib/backend';
    return '$declared'.trim();
  } catch (_) {
    return 'lib/backend';
  }
}

/// One `@DVPolicy` class, where it is, and why only the client can load it.
class _DVFoundPolicy {
  const _DVFoundPolicy({
    required this.importUri,
    required this.shownPath,
    required this.policy,
    required this.clientOnlyBecause,
  });

  final String importUri;

  /// Relative to the application, so a module's file names the module.
  final String shownPath;

  final DVPolicyClass policy;

  /// The import through which its file reaches Flutter, or null when the
  /// generated server can load it.
  final String? clientOnlyBecause;
}

/// A project whose `lib` this application's generated schedule, AI tools and
/// backend router are built from: its own, and every module it merges.
class _DVMergedProject {
  const _DVMergedProject(this.root, this.packageName, this.backendDir);

  final String root;
  final String packageName;
  final String backendDir;
}

/// The application's own project, then every module it merges.
///
/// Embedded and backend-only run inside the parent, so what they contribute
/// is the parent's to run. A split-backend or federated module runs its own,
/// in its own deployment: running its schedule here as well would do the
/// night's work twice.
List<_DVMergedProject> _mergedProjects(
  String root,
  String pkgName,
  String backendDir,
) {
  final List<_DVMergedProject> projects = <_DVMergedProject>[
    _DVMergedProject(root, pkgName, backendDir),
  ];
  for (final DVModuleMount mount in dvDiscoverModuleMounts(root)) {
    if (!mount.mounted) continue;
    if (mount.deployment != DVModuleDeployment.embedded &&
        mount.deployment != DVModuleDeployment.backendOnly) {
      continue;
    }
    final String projectRoot = p.join(root, mount.sourcePath);
    projects.add(_DVMergedProject(
        projectRoot, mount.packageName, dvProjectBackendDir(projectRoot)));
  }
  return projects;
}

/// Every mergeable project's lib files, each with the project it came from.
List<(_DVMergedProject, File)> _mergedLibFiles(
  String root,
  String pkgName,
  String backendDir,
) =>
    <(_DVMergedProject, File)>[
      for (final project in _mergedProjects(root, pkgName, backendDir))
        for (final file in _libFilesOf(project.root)) (project, file),
    ];

/// Every mergeable project's lib files as (project-relative path, source).
///
/// The same set the policy registrations are generated from, so a check
/// against the application's policies sees exactly the policies it registers.
List<(String, String)> dvMergedLibSources(
  String root,
  String pkgName,
  String backendDir,
) =>
    <(String, String)>[
      for (final (project, file) in _mergedLibFiles(root, pkgName, backendDir))
        (
          p.relative(file.path, from: project.root).replaceAll('\\', '/'),
          file.readAsStringSync(),
        ),
    ];

/// Every Dart file under a project's `lib`, minus its own generated client.
List<File> _libFilesOf(String projectRoot) {
  const LocalFileSystem fs = LocalFileSystem();
  final List<File> files = <File>[];
  for (final entity in Glob('lib/**.dart')
      .listFileSystemSync(fs, root: projectRoot, followLinks: false)) {
    if (entity is! File) continue;
    if (entity.path.replaceAll(r'\', '/').contains('/lib/dartvel_client/')) {
      continue;
    }
    files.add(File(entity.path));
  }
  return files..sort((File a, File b) => a.path.compareTo(b.path));
}

/// Whether [declaration] declares [name] as returning nothing.
///
/// void and Future<void> both make `await f()` a void, which cannot be
/// assigned. A tool that sends an email and returns nothing is an ordinary
/// tool, and a generated handler that assigned its result would be a server
/// that does not build.
bool _dvReturnsNothing(String declaration, String name) => RegExp(
      r'(?:^|[^A-Za-z0-9_])(?:void|Future<void>|FutureOr<void>)\s+'
      '${RegExp.escape(name)}'
      r'\s*\(',
    ).hasMatch(declaration);

/// Whether [declaration] declares [name] as returning a plain `void`.
///
/// `Future<void> f(` puts a `>` between the word and the name, so this
/// matches only the bare one -- which is the case `await` cannot be used on.
bool _dvReturnsPlainVoid(String declaration, String name) => RegExp(
      r'(?:^|[^A-Za-z0-9_])void\s+'
      '${RegExp.escape(name)}'
      r'\s*\(',
    ).hasMatch(declaration);

/// Refuses a schedule on a private function.
///
/// Dropping it silently is not available: the entry list is what
/// registerAll reads, and it refuses an entry with no handler, so a
/// schedule left in the list without one is a server that will not start.
/// Filtering it out of both would be a schedule that is declared and never
/// runs, which is the failure this whole path was fixed to end.
///
/// So it is a build error, naming the file. A private function has no symbol
/// another library can call, and the generated handler lives in another
/// library.
void _refusePrivateCron(List<_CronEntry> entries, String annotation) {
  for (final _CronEntry entry in entries) {
    if (!entry.name.startsWith('_')) continue;
    throw StateError(
      'dartvel: @$annotation is declared on ${entry.name} in '
      '${entry.relativePath}, which is private to that file. The generated '
      'schedule calls it from another library and cannot see it. Make it '
      'public.',
    );
  }
}

/// `dartvel.security.csp` from pubspec.yaml, or null.
///
/// Read at generation time so a route declaring the key with nothing
/// configured fails the build, rather than starting a server that sends no
/// header while the annotation says it sends one.
String? _dvContentSecurityPolicy(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  final Object? parsed = loadYaml(pubspec.readAsStringSync());
  if (parsed is! YamlMap) return null;
  final Object? dartvel = parsed['dartvel'];
  if (dartvel is! YamlMap) return null;
  final Object? security = dartvel['security'];
  if (security is! YamlMap) return null;
  final Object? csp = security['csp'];
  if (csp is! String || csp.trim().isEmpty) return null;
  return csp.trim();
}

/// The Dart that configures tenancy at startup, from `dartvel.tenancy`.
///
/// Empty when a project declares none, so a single-tenant application gets
/// no configuration emitted at it and keeps the shared-database default it
/// already ran.
///
/// This is the only place a project can say any of it. Choosing an isolation
/// strategy meant calling DVTenants.configure from Dart that no generated
/// entrypoint runs, so schema-per-tenant and database-per-tenant -- the two
/// an application picks in order to keep tenants in separate schemas or
/// separate databases -- could not be selected, and every deployment ran the
/// shared-database default whether that is what it wanted or not.
/// DVMiddlewareSettings.requireTenant was in the same position: it gated a
/// refusal and nothing set it.
///
/// A value nobody implements fails the build. Dropping a misspelling leaves
/// the application on the default while the pubspec says otherwise, every
/// query still returns rows, and nothing about running it looks wrong.
String _dvTenancyConfiguration(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return '';
  final Object? parsed = loadYaml(pubspec.readAsStringSync());
  if (parsed is! YamlMap) return '';
  final Object? dartvel = parsed['dartvel'];
  if (dartvel is! YamlMap) return '';
  final Object? tenancy = dartvel['tenancy'];
  if (tenancy is! YamlMap) return '';

  const Map<String, String> isolations = <String, String>{
    'shared-database': 'sharedDatabase',
    'schema-per-tenant': 'schemaPerTenant',
    'database-per-tenant': 'databasePerTenant',
  };
  const Map<String, String> sources = <String, String>{
    'subdomain': 'subdomain',
    'header': 'header',
    'path-prefix': 'pathPrefix',
    'query-parameter': 'queryParameter',
  };

  String? named(String key, Map<String, String> allowed, String what) {
    final Object? value = tenancy[key];
    if (value == null) return null;
    final String written = '$value'.trim();
    final String? resolved = allowed[written];
    if (resolved == null) {
      throw StateError(
        'dartvel.tenancy.$key: "$written" is not a $what Dartvel has. '
        'Accepted: ${allowed.keys.join(', ')}.',
      );
    }
    return resolved;
  }

  final String? isolation = named('isolation', isolations, 'tenant isolation');
  final String? source = named('source', sources, 'tenant source');
  final Object? header = tenancy['header'];
  final Object? queryParameter = tenancy['queryParameter'];
  final Object? ignored = tenancy['ignoredHostLabels'];

  final List<String> arguments = <String>[
    if (isolation != null) 'isolation: core.DVTenantIsolation.$isolation',
    if (source != null) 'source: core.DVTenantSource.$source',
    // Lower-cased here because header names are case-insensitive on the wire
    // and the resolver looks the name up in a lower-cased map. Declared as
    // X-Account and matched against x-account, the lookup misses and every
    // request names no tenant.
    if (header is String && header.trim().isNotEmpty)
      "headerName: '${esc(header.trim().toLowerCase())}'",
    if (queryParameter is String && queryParameter.trim().isNotEmpty)
      "queryParameterName: '${esc(queryParameter.trim())}'",
    if (ignored is YamlList && ignored.isNotEmpty)
      'ignoredHostLabels: const <String>{'
          "${ignored.map((Object? l) => "'${esc('$l'.trim().toLowerCase())}'").join(', ')}}",
  ];

  final StringBuffer out = StringBuffer();
  if (arguments.isNotEmpty) {
    out.write('\n  const core.DVTenants().configure(${arguments.join(', ')});');
  }
  if (tenancy['require'] == true) {
    out.write('\n  core.DVMiddlewareSettings.requireTenant = true;');
  }
  return out.toString();
}

/// `dartvel.server` from pubspec.yaml.
///
/// Read at generation time and emitted into `startBackend`, because that is
/// the only serve call a Dartvel application has. The refusal for
/// `DVMiddlewares.cors` used to say "pass cors: to the serve call", which
/// was advice nobody could take: the generated entrypoint made that call and
/// read no configuration, so an application could not set a CORS policy at
/// all and could not turn compression off.
/// `dartvel.api.graphql` from the project's pubspec, or null when it
/// declares none. Throws a [FormatException] naming a key the runtime cannot
/// use.
DVGraphQLApiOptions? dvGraphQLApiOptions(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  final Object? parsed = loadYaml(pubspec.readAsStringSync());
  if (parsed is! YamlMap) return null;
  return DVGraphQLApiOptions.parse(parsed['dartvel']);
}

DVServerOptions dvServerOptions(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const DVServerOptions();
  final Object? parsed = loadYaml(pubspec.readAsStringSync());
  if (parsed is! YamlMap) return const DVServerOptions();
  return DVServerOptions.parse(parsed['dartvel']);
}


/// `dartvel.seo.favicon` from pubspec.yaml, or null.
///
/// The application-wide fallback for a model page's icon. Read here rather
/// than guessed from web/favicon.png, because a file that happens to exist is
/// not a decision somebody made -- and a page that quietly wore the wrong
/// icon would look like the feature working.
String? _dvSeoFavicon(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  final Object? parsed = loadYaml(pubspec.readAsStringSync());
  if (parsed is! YamlMap) return null;
  final Object? dartvel = parsed['dartvel'];
  if (dartvel is! YamlMap) return null;
  final Object? seo = dartvel['seo'];
  if (seo is! YamlMap) return null;
  final Object? favicon = seo['favicon'];
  if (favicon == null) return null;
  final String value = '$favicon'.trim();
  return value.isEmpty ? null : value;
}
