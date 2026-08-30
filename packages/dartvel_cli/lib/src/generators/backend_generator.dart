import 'dart:io';
import 'package:file/local.dart';
import 'symbol_qualifier.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/helpers.dart';
import '../utils/logger.dart';
import 'openapi_generator.dart';
import 'route_utils.dart';

class BackendGenerator {
  static Future<void> generate({
    required String root,
    required String backendDir,
    required String pkgName,
    required String buildId,
    required String backendHost,
    required int backendPort,
    required String apiBasePath,
  }) async {
    final backendOut = Directory(p.join(root, '.dart_tool'));
    final libClientDir = Directory(p.join(root, 'lib', 'dartvel_client'));
    await _validateMiddlewareAnnotations(root);
    backendOut.createSync(recursive: true);
    libClientDir.createSync(recursive: true);

    // Backend bind config
    File(p.join(backendOut.path, 'dartvel_backend.g.dart'))
        .writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_backend_config;
const String backendHost = '${esc(backendHost)}';
const int    backendPort = $backendPort;
const String apiBasePath = '${esc(apiBasePath)}';
const String dvGenBuildId = '$buildId';
''');

    // Backend routes (functions)
    final functionsDir = Directory(p.join(root, backendDir, 'functions'));
    final fnFiles = functionsDir.existsSync()
        ? functionsDir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
        : <File>[]
      ..sort((a, b) => a.path.compareTo(b.path));

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
      final abs = fnFiles[i].path;
      final rel = p.relative(abs, from: root).replaceAll(r'\', '/');
      final pathRel = rel;
      // detect method from filename
      final base = p.basenameWithoutExtension(rel); // removes .dart
      final dot = base.lastIndexOf('.');
      // Allow filenames without explicit method suffix; default to POST
      var method = (dot != -1) ? base.substring(dot + 1).toLowerCase() : '';
      if (!methodSet.contains(method)) {
        method = 'post';
      }
      final importPath =
          rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      final urlPath = RouteUtils.routeFromRel(pathRel, backendDir);
      // Detect typed function name from file (based on sanitized base name)
      final src = await File(abs).readAsString();
      final privateExpression = _privateBackendExpression(src, rel);
      final sourceSymbols = _topLevelPublicSourceSymbols(src);
      final qualifiedPrivateExpression = privateExpression == null
          ? ''
          : _qualifySourceSymbols(
              privateExpression.expression,
              'f$i',
              sourceSymbols,
            );
      if (privateExpression == null ||
          qualifiedPrivateExpression != privateExpression.expression) {
        backendImports.add("import '$importPath' as f$i;");
      }
      // Prefer explicit handler(RequestType/Request) for compatibility
      final regHandler = RegExp(
          r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?handler\s*\(([^)]*)\)\s*(?:=>|\{)',
          multiLine: true);
      final hasHandler = regHandler.hasMatch(src);
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
      String helper = '';

      if (privateExpression != null) {
        typedName = privateExpression.publicName;
        rtype = privateExpression.returnType;
        invocation = '_dvBackendFn$i';
        RouteUtils.extractParams(privateExpression.parameters, (n, t) {
          if (typedParams.isNotEmpty) {
            typedParams += ',';
            typedTypes += ',';
          }
          typedParams += n;
          typedTypes += t;
        }, onNamed: (v) => tnamed = v);
        helper =
            '${privateExpression.returnType} _dvBackendFn$i(${privateExpression.parameters}) => $qualifiedPrivateExpression;';
      } else {
        // 1) Try to find a function whose name matches the sanitized filename
        final regCandidate = RegExp(
            r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?' +
                RegExp.escape(funcCandidate) +
                r'\s*\(([^)]*)\)\s*(?:=>|\{)',
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
          RouteUtils.extractParams(mm.group(1) ?? '', (n, t) {
            if (typedParams.isNotEmpty) {
              typedParams += ',';
              typedTypes += ',';
            }
            typedParams += n;
            typedTypes += t;
          }, onNamed: (v) => tnamed = v);
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
            RouteUtils.extractParams(m2.group(2) ?? '', (n, t) {
              if (typedParams.isNotEmpty) {
                typedParams += ',';
                typedTypes += ',';
              }
              typedParams += n;
              typedTypes += t;
            }, onNamed: (v) => tnamed = v);
            break;
          }
          // Fallback return type, if not captured yet
          if (rtype.isEmpty) {
            final regAnyTyped = RegExp(
                r'^\s*([A-Za-z_][\w<>, ?]*)?\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(?:=>|\{)',
                multiLine: true);
            final m = regAnyTyped.firstMatch(src);
            if (m != null) rtype = (m.group(1) ?? 'dynamic').trim();
          }
        }
        if (typedName.isNotEmpty) {
          invocation = 'f$i.$typedName';
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
        'rtype': rtype,
        'src': src,
        'invocation': invocation,
        'helper': helper,
      });
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
            path: e['path']!,
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
    File(p.join(libClientDir.path, 'openapi.g.dart')).writeAsStringSync('''
// GENERATED – do not edit.
library dartvel_client_openapi;

/// The generated OpenAPI 3.1 document for this application's backend
/// functions, as JSON. Served by the generated backend at
/// `<apiBasePath>/openapi.json`.
const String dartvelOpenApiJson = r\'\'\'
$openApiJson\'\'\';
''');

    final backendRoutes = '''
// GENERATED – do not edit.
import 'dart:async';
import 'dart:convert' as conv;
import 'dart:io';
import 'dart:typed_data';
import 'package:dartvel_core/dartvel.dart' as core;
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:mime/mime.dart';
import 'dartvel_backend.g.dart' as cfg;
${backendImports.join('\n')}

// The generated OpenAPI document, served at cfg.apiBasePath + '/openapi.json'.
const String _dvOpenApiJson = r\'\'\'
$openApiJson\'\'\';

${backendEntries.map((e) => e['helper'] ?? '').where((helper) => helper.isNotEmpty).join('\n')}

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

dv.Response _dvCsrfForbidden() => dv.Response(403,
    headers: dv.Headers({'content-type': 'text/plain; charset=utf-8'}),
    body: Stream<List<int>>.value(conv.utf8.encode('CSRF token missing')));

dv.Router buildBackendRouter() {
  final router = dv.Router();
  bool _hasHealth = false;
${backendEntries.map((e) {
      final path = esc(e['path'] ?? '');
      final method = e['method']!;
      final i = e['i']!;
      final typed = e['typed'] ?? '';
      final invocation = e['invocation'] ?? 'f$i.$typed';
      if (typed.isEmpty) {
        return "  router.$method(cfg.apiBasePath + '$path', (dv.Request req) => Future.value(f$i.handler(req)));";
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
      final callArgs = argList.join(', ');
      final requestPrelude = '''    Object? body;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        final ct = req.headers.get('content-type') ?? '';
        if (ct.contains('multipart/form-data')) {
          body = await _parseMultipart(req.body.stream, ct);
        } else {
          final raw = await req.body.text();
          if (ct.contains('application/json')) {
            body = raw.isEmpty ? null : conv.jsonDecode(raw);
          } else if (ct.contains('application/x-www-form-urlencoded')) {
            try { body = Uri.splitQueryString(raw); } catch (_) { body = <String,String>{}; }
          } else {
            body = raw;
          }
        }
      }
    } catch (e) { /* ignore body read errors */ }
    if (!_dvValidateCsrf(req, body)) return _dvCsrfForbidden();''';

      if (path == '/health' && method.toLowerCase() == 'get') {
        return "  _hasHealth = true;\n"
            '''  router.$method(cfg.apiBasePath + '$path', (dv.Request req) async {
$requestPrelude
    try {
      Object? result = await $invocation($callArgs);
      if (result is dv.Response) return result;
      if (result is Stream<List<int>>) return dv.Response(200, body: result);
      if (result is Stream) {
        return dv.Response(200,
            headers: dv.Headers({
              'content-type': 'text/event-stream; charset=utf-8',
              'cache-control': 'no-cache',
              'connection': 'keep-alive',
            }),
            body: result.map((e) => 'data: \${e.toString().replaceAll('\\n', '\\ndata: ')}\\n\\n').map(conv.utf8.encode),
            isStream: true);
      }
      if (result is String) return dv.Response.text(result);
      return dv.Response(200,
          headers: dv.Headers({'content-type': 'application/json; charset=utf-8'}),
          body: Stream<List<int>>.value(conv.utf8.encode(conv.jsonEncode(result))));
    } catch (e, st) {
      stderr.writeln('[dartvel backend] ERROR in ${method.toUpperCase()} $path: \${e.toString()}');
      stderr.writeln(st);
      return dv.Response(500, body: Stream<List<int>>.value(conv.utf8.encode('Internal Server Error')));
    }
  });''';
      }
      return '''  router.$method(cfg.apiBasePath + '$path', (dv.Request req) async {
$requestPrelude
    try {
      Object? result = await $invocation($callArgs);
      if (result is dv.Response) return result;
      if (result is Stream<List<int>>) return dv.Response(200, body: result);
      if (result is Stream) {
        return dv.Response(200,
            headers: dv.Headers({
              'content-type': 'text/event-stream; charset=utf-8',
              'cache-control': 'no-cache',
              'connection': 'keep-alive',
            }),
            body: result.map((e) => 'data: \${e.toString().replaceAll('\\n', '\\ndata: ')}\\n\\n').map(conv.utf8.encode),
            isStream: true);
      }
      if (result is String) return dv.Response.text(result);
      return dv.Response(200,
          headers: dv.Headers({'content-type': 'application/json; charset=utf-8'}),
          body: Stream<List<int>>.value(conv.utf8.encode(conv.jsonEncode(result))));
    } catch (e, st) {
      stderr.writeln('[dartvel backend] ERROR in ${method.toUpperCase()} $path: \${e.toString()}');
      stderr.writeln(st);
      return dv.Response(500, body: Stream<List<int>>.value(conv.utf8.encode('Internal Server Error')));
    }
  });''';
    }).join('\n')}
  if (!_hasHealth) {
    router.get(cfg.apiBasePath + '/health', (dv.Request _) async => dv.Response.text('ok'));
  }
  // GraphQL: whatever the application registered on DVGraphQL, served on
  // the spec-shaped POST body {query, variables, operationName}. The SDL
  // document at /graphql/schema is the machine-readable schema.
  router.post(cfg.apiBasePath + '/graphql', (dv.Request req) async {
    final text = await req.body.text();
    final decoded = text.isEmpty ? const <String, Object?>{} : conv.jsonDecode(text);
    final map = decoded is Map ? decoded : const <String, Object?>{};
    final result = await core.DVGraphQL.execute(
      '\${map['query'] ?? ''}',
      variables: (map['variables'] as Map?)?.cast<String, Object?>(),
      operationName: map['operationName'] as String?,
    );
    return dv.Response.json(result);
  });
  router.get(cfg.apiBasePath + '/graphql/schema', (dv.Request _) async =>
      dv.Response.text(core.DVGraphQL.toSdl()));
  // Subscriptions over Server-Sent Events. The server has no WebSocket, and
  // SSE is a standard GraphQL transport, so a subscription is reachable
  // today rather than waiting on one.
  router.post(cfg.apiBasePath + '/graphql/stream', (dv.Request req) async {
    final text = await req.body.text();
    final decoded = text.isEmpty ? const <String, Object?>{} : conv.jsonDecode(text);
    final map = decoded is Map ? decoded : const <String, Object?>{};
    return dv.Response.stream(
      (sink) {
        final events = core.DVGraphQL.subscribe(
          '\${map['query'] ?? ''}',
          variables: (map['variables'] as Map?)?.cast<String, Object?>(),
          operationName: map['operationName'] as String?,
        );
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
  });
  router.get(cfg.apiBasePath + '/openapi.json', (dv.Request _) async =>
      dv.Response(200,
          headers: dv.Headers({'content-type': 'application/json'}),
          body: Stream<List<int>>.value(conv.utf8.encode(_dvOpenApiJson))));
  return router;
}

dv.Router buildBackend() => buildBackendRouter();

Future<dv.ServerHandle> startBackend({String? host, int? port, dv.TlsConfig? tls, bool h2c = false, dv.CorsOptions? cors}) {
  final router = buildBackendRouter();
  final bindHost = host ?? cfg.backendHost;
  final bindPort = port ?? cfg.backendPort;
  return dv.serve(router.call, host: bindHost, port: bindPort, tls: tls, h2c: h2c, cors: cors);
}
''';
    File(p.join(backendOut.path, 'dartvel_backend_routes.g.dart'))
        .writeAsStringSync(backendRoutes);

    // Client function-style API (tRPC-like): generate convenient call helpers
    final sbClient = StringBuffer();
    sbClient.writeln('// GENERATED – do not edit.');
    sbClient.writeln('// BUILD: $buildId');
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

Future<DVHttpResponse> _dvRequest(String method, Uri uri,
    {Object? data, Map<String, String>? headers}) async {
  final methodUpper = method.toUpperCase();
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

    for (final e in backendEntries) {
      final method = e['method']!;
      final urlPath = e['path']!;
      final colon = RouteUtils.toColonPath(urlPath);
      final fname = RouteUtils.funcNameForFromUrl(method, urlPath);
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
          .writeln("  String routePath = '${esc(colon)}';");
      sbClient.writeln('  final Map<String, Object?> pp = $paramMap;');
      sbClient.writeln(
          "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
      sbClient.writeln('  final base = DartvelRuntime.api(routePath);');
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

        final hasDvBackendFn =
            (e['src'] ?? '').contains('@DVBackendFunction') ||
                (e['src'] ?? '').contains('@dvBackendFunction');
        final fnameApi = (hasDvBackendFn && e['typed']!.isNotEmpty)
            ? e['typed']!
            : '${fname}Api';

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
              "  String routePath = '${esc(colon)}';");
          sbClient.writeln('  final Map<String, Object?> pp = $ppExpr;');
          sbClient.writeln(
              "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
          sbClient.writeln('  final base = DartvelRuntime.api(routePath);');
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

          final convExpr = conv(rtype);
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
              "  String routePath = '${esc(colon)}';");
          sbClient.writeln('  final Map<String, Object?> pp = $ppExpr;');
          sbClient.writeln(
              "  pp.forEach((k, v) { final rep = (v is List) ? v.map((e)=>e.toString()).join('/') : ((v?.toString()) ?? ''); routePath = routePath.replaceAll(':\$k', Uri.encodeComponent(rep)); });");
          sbClient.writeln('  final base = DartvelRuntime.api(routePath);');
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
    final clientBody = sbClient.toString();
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

    log('dartvel: generated lib/dartvel_client/* and .dart_tool/dartvel_backend*.g.dart (build $buildId)');
  }

  static Future<String> _generateSchedules({
    required String root,
    required String pkgName,
  }) async {
    final fs = const LocalFileSystem();
    final files = <File>[];
    for (final entity in Glob('lib/**.dart')
        .listFileSystemSync(fs, root: root, followLinks: false)) {
      if (entity is! File) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.contains('/lib/dartvel_client/')) continue;
      files.add(File(entity.path));
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final entries = <_CronEntry>[];
    for (final file in files) {
      final source = await file.readAsString();
      final relativePath =
          p.relative(file.path, from: root).replaceAll('\\', '/');
      final importUri =
          relativePath.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
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

    final sb = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      ..writeln('library dartvel_client_schedules;')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      ..writeln()
      ..writeln('const List<DVCronEntry> dartvelCronEntries = <DVCronEntry>[');
    for (final entry in entries) {
      sb
        ..writeln('  DVCronEntry(')
        ..writeln("    name: '${esc(entry.name)}',")
        ..writeln("    cron: '${esc(entry.cron)}',")
        ..writeln('    target: ${entry.target},')
        ..writeln("    importUri: '${esc(entry.importUri)}',")
        ..writeln("    filePath: '${esc(entry.relativePath)}',")
        ..writeln('  ),');
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
    return sb.toString();
  }

  static Future<String> _generateAITools({
    required String root,
    required String pkgName,
    required String backendDir,
  }) async {
    final fs = const LocalFileSystem();
    final files = <File>[];
    for (final entity in Glob('lib/**.dart')
        .listFileSystemSync(fs, root: root, followLinks: false)) {
      if (entity is! File) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.contains('/lib/dartvel_client/')) continue;
      files.add(File(entity.path));
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final exposeBackendFunctions = _shouldExposeBackendFunctionsAsAITools(root);
    final entriesByName = <String, _AIToolEntry>{};
    for (final file in files) {
      final source = await file.readAsString();
      final relativePath =
          p.relative(file.path, from: root).replaceAll('\\', '/');
      final importUri =
          relativePath.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      _collectAIToolEntries(
        source: source,
        relativePath: relativePath,
        importUri: importUri,
        entriesByName: entriesByName,
      );
      if (exposeBackendFunctions && relativePath.startsWith('$backendDir/')) {
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

    final sb = StringBuffer()
      ..writeln('// GENERATED – do not edit.')
      ..writeln('library dartvel_client_ai_tools;')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
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
    return sb.toString();
  }

  static ({
    String sourceName,
    String publicName,
    String returnType,
    String parameters,
    String expression,
  })? _privateBackendExpression(String source, String rel) {
    final lines = source.split('\n');
    for (var index = 0; index < lines.length; index += 1) {
      if (!lines[index].contains('@DVBackendFunction')) continue;
      for (var probe = index + 1;
          probe < lines.length && probe <= index + 6;
          probe += 1) {
        final line = lines[probe].trim();
        if (line.isEmpty || line.startsWith('@')) continue;
        final match = RegExp(
          r'^((?:Future<[^>]+>|Future|Stream<[^>]+>|[A-Za-z_][A-Za-z0-9_<>, ?]*))\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:async\s*)?=>\s*(.*);\s*$',
        ).firstMatch(line);
        if (match == null) continue;
        final returnType = match.group(1)!.trim();
        final name = match.group(2)!;
        final parameters = match.group(3)!.trim();
        final expression = match.group(4)!.trim();
        if (!name.startsWith('_')) return null;
        return (
          sourceName: name,
          publicName: name.substring(1),
          returnType: returnType,
          parameters: parameters,
          expression: expression,
        );
      }
    }

    for (var index = 0; index < lines.length; index += 1) {
      if (!lines[index].contains('@DVBackendFunction')) continue;
      for (var probe = index + 1;
          probe < lines.length && probe <= index + 6;
          probe += 1) {
        final line = lines[probe].trim();
        if (line.isEmpty || line.startsWith('@')) continue;
        final match = RegExp(
          r'^(?:Future<[^>]+>|Future|Stream<[^>]+>|[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
        ).firstMatch(line);
        if (match == null) continue;
        final name = match.group(1)!;
        if (name.startsWith('_')) {
          throw StateError(
            'Dartvel private backend function input $name in $rel must use an '
            'expression body for this generator pass, for example '
            'Future<String> $name(String input) async => input. '
            'Block-bodied private backend functions require generated body '
            'lowering before they can be emitted without per-source part files.',
          );
        }
        break;
      }
    }
    return null;
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
    const supported = <String>{
      'auth',
      'policy',
      'tenant',
      'cors',
      'csrf',
      'rateLimit',
      'rateLimitCheckout',
      'requestLogging',
      'tracing',
      'securityHeaders',
      'csp',
      'bodyLimit',
      'uploadLimit',
      'compression',
      'locale',
      'idempotency',
      'cacheTags',
      'featureFlags',
      'maintenance',
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
        r'@DVUseMiddleware\s*\(\s*\[(.*?)\]\s*\)',
        dotAll: true,
      ).allMatches(source);
      for (final annotation in annotations) {
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
    final pattern = RegExp(
      "@$annotationName\\(\\s*(['\"])(.*?)\\1\\s*\\)\\s*"
      r'(?:Future<[^>]+>|Future|Stream<[^>]+>|[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+'
      r'([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      dotAll: true,
    );
    for (final match in pattern.allMatches(source)) {
      entries.add(_CronEntry(
        name: match.group(3)!,
        cron: match.group(2)!,
        target: target,
        importUri: importUri,
        relativePath: relativePath,
      ));
    }
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
      r'([A-Za-z_][A-Za-z0-9_]*)\s*\(',
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
      entriesByName[name] = _AIToolEntry(
        name: name,
        description: match.group(2) ?? '',
        importUri: importUri,
        relativePath: relativePath,
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
      r'([A-Za-z_][A-Za-z0-9_]*)\s*\(',
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
      entriesByName[publicName] = _AIToolEntry(
        name: publicName,
        description: 'Backend function $name',
        importUri: importUri,
        relativePath: relativePath,
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

  const _CronEntry({
    required this.name,
    required this.cron,
    required this.target,
    required this.importUri,
    required this.relativePath,
  });
}

class _AIToolEntry {
  final String name;
  final String description;
  final String importUri;
  final String relativePath;

  const _AIToolEntry({
    required this.name,
    required this.description,
    required this.importUri,
    required this.relativePath,
  });
}
