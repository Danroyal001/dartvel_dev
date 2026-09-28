// GENERATED – do not edit.
// ignore_for_file: unused_element
library dartvel_client_functions;
import 'dart:convert';
import 'dartvel_runtime.dart';
import 'dart:math' as math;
import 'package:dartvel_core/dartvel.dart';
/// Multipart fields for a generated POST. Modelled here rather than taken
/// from an HTTP package, so a generated client imposes no client library on
/// the application.
class DartvelFormData {
  final Map<String, String> fields;
  DartvelFormData(this.fields);

  factory DartvelFormData.fromMap(Map<Object?, Object?> map) =>
      DartvelFormData(<String, String>{
        for (final entry in map.entries)
          if (entry.key != null) '${entry.key}': '${entry.value ?? ''}',
      });
}

/// Shared generated client state for auth and custom request headers.
class DartvelClient {
  static Map<String, String> defaultHeaders = <String, String>{};

  static void setAuthToken(String token, {String scheme = 'Bearer'}) {
    defaultHeaders['Authorization'] = token.isEmpty ? '' : '$scheme $token';
    if (defaultHeaders['Authorization']!.isEmpty) {
      defaultHeaders.remove('Authorization');
    }
  }
}

final String _dvCsrfToken = (() { try { return const DVCSRF().token(); } catch (_) { final random = math.Random.secure(); const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'; return String.fromCharCodes(List<int>.generate(32, (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)))); } })();
bool _dvRequiresCsrf(String method) => const DVCSRF().requiresValidation(method);
Map<String, String> _dvHeadersWithCsrf(String method, Map<String, String> headers) { if (!_dvRequiresCsrf(method)) return headers; return {...headers, DVCSRF.headerName: headers[DVCSRF.headerName] ?? _dvCsrfToken}; }
Object? _dvPayloadWithCsrf(String method, Object? payload) { if (!_dvRequiresCsrf(method)) return payload; if (payload is DartvelFormData) { payload.fields.putIfAbsent(DVCSRF.fieldName, () => _dvCsrfToken); return payload; } if (payload is Map<Object?, Object?>) { final copy = Map<String, Object?>.from(payload); copy.putIfAbsent(DVCSRF.fieldName, () => _dvCsrfToken); return copy; } return payload; }
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
      contentType: 'multipart/form-data; boundary=$boundary',
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
      fields['$k'] = v is List
          ? v.map((Object? e) => e?.toString() ?? '').join(',')
          : v.toString();
    });
    return (
      body: dvEncodeFormBody(<(String, String)>[
        for (final e in fields.entries) (e.key, e.value),
      ]),
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

/// Sends a module call carried to the backend: installed as
/// DVModuleRpc.transport, so it goes through the same request path as a
/// backend function -- session, CSRF token and step-up included.
Future<Object?> dvModuleRpcSend(String path, Map<String, Object?> arguments) async {
  final r = await _dvRequest('post', DartvelRuntime.api(path),
      data: arguments, headers: <String, String>{'content-type': 'application/json'});
  final Object? data = r.data;
  return data is Map ? data['result'] : null;
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

  String buffer = '';
  await for (final chunk in bodyStream) {
    buffer += utf8.decode(chunk);
    while (true) {
      final lineEnd = buffer.indexOf("\n");
      if (lineEnd == -1) break;
      final line = buffer.substring(0, lineEnd).trim();
      buffer = buffer.substring(lineEnd + 1);
      if (line.startsWith("data:")) {
        final payload = line.substring(5).trim();
        if (payload.isNotEmpty) {
          try {
            final json = jsonDecode(payload);
            yield fromJson(json);
          } catch (_) {
            if ("" is T) {
              yield payload as T;
            }
          }
        }
      }
    }
  }
}
