/// Google Cloud Storage through the JSON API.
///
/// The one thing this API is unforgiving about is the object name. A name is
/// an opaque string that may contain slashes, not a path, so it has to be
/// fully percent-encoded in a URL -- slashes included. Leave them alone and
/// the request addresses a different resource, which usually exists, so the
/// call succeeds against the wrong object rather than failing.
///
/// Authentication is a bearer token: real GCS wants an OAuth2 access token,
/// and an emulator wants nothing. The adapter takes a token provider rather
/// than a token so a caller can refresh one without rebuilding the adapter.
library dartvel_core.storage.gcs;

import 'dart:convert';

import '../http/transport.dart';
import 'adapters.dart';

/// Supplies a bearer token, or null where none is needed.
typedef DVGcsTokenProvider = Future<String?> Function();

/// Google Cloud Storage and API-compatible emulators (fake-gcs-server).
class GcsFileStorageAdapter implements DVFileStorageAdapter {
  GcsFileStorageAdapter({
    required this.bucket,
    String? endpoint,
    this.project = 'dartvel',
    DVGcsTokenProvider? token,
    this.transport = dvSendHttpRequest,
  })  : endpoint = (endpoint ?? 'https://storage.googleapis.com')
            .replaceAll(RegExp(r'/+$'), ''),
        token = token ?? _noToken;

  final String bucket;
  final String endpoint;

  /// Only used when creating a bucket, which the real service requires and an
  /// emulator ignores.
  final String project;

  final DVGcsTokenProvider token;
  final DVHttpSend transport;

  static Future<String?> _noToken() async => null;

  /// Creates the bucket, ignoring the case where it already exists.
  Future<void> createBucket() async {
    final DVHttpResponse response = await _send(
      method: 'POST',
      path: '/storage/v1/b',
      query: <String, String>{'project': project},
      body: utf8.encode(jsonEncode(<String, Object?>{'name': bucket})),
      contentType: 'application/json',
    );
    if (response.statusCode == 409) return;
    _ensure(response, 'createBucket', bucket);
  }

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async {
    final DVHttpResponse response = await _send(
      method: 'POST',
      path: '/upload/storage/v1/b/$bucket/o',
      // The name travels as a query parameter on an upload, so it is encoded
      // as one rather than as a path segment.
      query: <String, String>{'uploadType': 'media', 'name': key},
      body: bytes,
      contentType: contentType ?? 'application/octet-stream',
    );
    _ensure(response, 'put', key);
  }

  @override
  Future<List<int>> get(String key) async {
    final DVHttpResponse response = await _send(
      method: 'GET',
      path: '/storage/v1/b/$bucket/o/${_encodeName(key)}',
      query: <String, String>{'alt': 'media'},
    );
    _ensure(response, 'get', key);
    return response.bodyBytes;
  }

  @override
  Future<void> delete(String key) async {
    final DVHttpResponse response = await _send(
      method: 'DELETE',
      path: '/storage/v1/b/$bucket/o/${_encodeName(key)}',
    );
    // Deleting what is not there is the caller's intent either way.
    if (response.statusCode == 404) return;
    _ensure(response, 'delete', key);
  }

  @override
  Future<bool> exists(String key) async {
    final DVHttpResponse response = await _send(
      method: 'GET',
      path: '/storage/v1/b/$bucket/o/${_encodeName(key)}',
    );
    if (response.statusCode == 404) return false;
    _ensure(response, 'exists', key);
    return true;
  }

  @override
  Future<List<String>> list({String prefix = ''}) async {
    final List<String> names = <String>[];
    String? pageToken;

    do {
      final DVHttpResponse response = await _send(
        method: 'GET',
        path: '/storage/v1/b/$bucket/o',
        query: <String, String>{
          if (prefix.isNotEmpty) 'prefix': prefix,
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      _ensure(response, 'list', prefix);

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) break;
      final Object? items = decoded['items'];
      if (items is List) {
        for (final Object? item in items) {
          if (item is Map && item['name'] is String) {
            names.add(item['name']! as String);
          }
        }
      }
      // Followed to the end: stopping at the first page silently truncates a
      // listing once a bucket grows past it, and the caller cannot tell.
      pageToken = decoded['nextPageToken'] as String?;
    } while (pageToken != null);

    return List<String>.unmodifiable(names..sort());
  }

  /// Percent-encodes an object name for use as a single path segment.
  ///
  /// A name is one opaque string, so its slashes are part of it and must be
  /// escaped. [Uri.encodeComponent] leaves a few sub-delimiters alone that GCS
  /// reads structurally, so they are escaped afterwards.
  static String _encodeName(String key) => Uri.encodeComponent(key)
      .replaceAll('!', '%21')
      .replaceAll("'", '%27')
      .replaceAll('(', '%28')
      .replaceAll(')', '%29')
      .replaceAll('*', '%2A');

  Future<DVHttpResponse> _send({
    required String method,
    required String path,
    Map<String, String> query = const <String, String>{},
    List<int>? body,
    String? contentType,
  }) async {
    final Uri url = Uri.parse(
      '$endpoint$path${query.isEmpty ? '' : '?${_query(query)}'}',
    );
    final String? bearer = await token();

    return transport(DVHttpRequest(
      url: url,
      method: method,
      headers: <String, String>{
        if (bearer != null) 'authorization': 'Bearer $bearer',
        if (contentType != null) 'content-type': contentType,
      },
      body: body ?? const <int>[],
    ));
  }

  static String _query(Map<String, String> parameters) => parameters.entries
      .map((MapEntry<String, String> e) =>
          '${Uri.encodeQueryComponent(e.key)}='
          '${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  void _ensure(DVHttpResponse response, String operation, String key) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw DVFileStorageException(
      'gcs',
      operation,
      key,
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }
}
