/// File storage adapters behind `DV.FileStorage`.
library dartvel_core.storage.adapters;


import '../http/aws_sigv4.dart';
import '../http/transport.dart';

/// Thrown when an object store rejects a request.
class DVFileStorageException implements Exception {
  final String provider;
  final String operation;
  final String key;
  final int? statusCode;
  final String? responseBody;

  const DVFileStorageException(
    this.provider,
    this.operation,
    this.key, {
    this.statusCode,
    this.responseBody,
  });

  /// True when the object simply is not there, as opposed to a real failure.
  bool get isNotFound => statusCode == 404;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    final body = responseBody == null || responseBody!.isEmpty
        ? ''
        : '\nResponse: $responseBody';
    return 'DVFileStorageException[$provider] $operation "$key"$status$body';
  }
}

abstract class DVFileStorageAdapter {
  Future<void> put(String key, List<int> bytes, {String? contentType});
  Future<List<int>> get(String key);
  Future<void> delete(String key);
  Future<bool> exists(String key);

  /// Object keys, optionally restricted to those beginning with [prefix].
  Future<List<String>> list({String prefix = ''});
}

/// Process-local storage. The default, and what `DV.FileStorage` used
/// exclusively before adapters existed.
class DVMemoryFileStorageAdapter implements DVFileStorageAdapter {
  final Map<String, List<int>> _objects = <String, List<int>>{};

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async {
    _objects[key] = List<int>.of(bytes);
  }

  @override
  Future<List<int>> get(String key) async {
    final bytes = _objects[key];
    if (bytes == null) {
      throw DVFileStorageException('memory', 'get', key, statusCode: 404);
    }
    return List<int>.of(bytes);
  }

  @override
  Future<void> delete(String key) async => _objects.remove(key);

  @override
  Future<bool> exists(String key) async => _objects.containsKey(key);

  @override
  Future<List<String>> list({String prefix = ''}) async =>
      List<String>.unmodifiable(
        _objects.keys.where((key) => key.startsWith(prefix)).toList()..sort(),
      );
}

/// S3 and S3-compatible object stores (AWS S3, Cloudflare R2, MinIO),
/// authenticated with AWS Signature Version 4.
///
/// Path-style addressing (`{endpoint}/{bucket}/{key}`) is the default because
/// R2 and MinIO require it; set [usePathStyle] to false for virtual-hosted
/// AWS buckets.
class S3FileStorageAdapter implements DVFileStorageAdapter {
  final String bucket;
  final String region;
  final DVAwsCredentials credentials;
  final Uri endpoint;
  final bool usePathStyle;
  final DVHttpSend transport;

  /// Injectable clock; SigV4 signatures are time-bound.
  final DateTime Function() now;

  S3FileStorageAdapter({
    required this.bucket,
    required this.region,
    required this.credentials,
    Uri? endpoint,
    this.usePathStyle = true,
    this.transport = dvSendHttpRequest,
    DateTime Function()? now,
  })  : endpoint = endpoint ?? Uri.https('s3.$region.amazonaws.com'),
        now = now ?? DateTime.now;

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async {
    final response = await _send(
      'PUT',
      _objectUrl(key),
      body: bytes,
      extraHeaders: <String, String>{
        'content-type': contentType ?? 'application/octet-stream',
      },
    );
    _ensure(response, 'put', key);
  }

  @override
  Future<List<int>> get(String key) async {
    final response = await _send('GET', _objectUrl(key));
    _ensure(response, 'get', key);
    return response.bodyBytes;
  }

  @override
  Future<void> delete(String key) async {
    final response = await _send('DELETE', _objectUrl(key));
    // S3 answers 204 for a delete, and reports success even when the object
    // was already gone.
    if (response.statusCode == 404) return;
    _ensure(response, 'delete', key);
  }

  @override
  Future<bool> exists(String key) async {
    final response = await _send('HEAD', _objectUrl(key));
    if (response.statusCode == 404) return false;
    _ensure(response, 'exists', key);
    return true;
  }

  @override
  Future<List<String>> list({String prefix = ''}) async {
    final url = _bucketUrl().replace(queryParameters: <String, String>{
      'list-type': '2',
      if (prefix.isNotEmpty) 'prefix': prefix,
    });
    final response = await _send('GET', url);
    _ensure(response, 'list', prefix);
    return parseListKeys(response.body);
  }

  /// Reads `<Key>` entries out of an S3 `ListBucketResult`.
  ///
  /// This reads the one element it needs rather than pulling in an XML parser.
  /// Basic entities are unescaped, since keys may legitimately contain `&`.
  static List<String> parseListKeys(String xml) => List<String>.unmodifiable(
        RegExp(r'<Key>(.*?)</Key>', dotAll: true)
            .allMatches(xml)
            .map((match) => _unescapeXml(match.group(1)!))
            .toList(),
      );

  static String _unescapeXml(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  Uri _bucketUrl() => usePathStyle
      ? endpoint.replace(path: '/$bucket')
      : endpoint.replace(host: '$bucket.${endpoint.host}', path: '/');

  Uri _objectUrl(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'A storage key cannot be empty.');
    }
    final encoded = key.split('/').map(Uri.encodeComponent).join('/');
    return usePathStyle
        ? endpoint.replace(path: '/$bucket/$encoded')
        : endpoint.replace(host: '$bucket.${endpoint.host}', path: '/$encoded');
  }

  Future<DVHttpResponse> _send(
    String method,
    Uri url, {
    List<int> body = const <int>[],
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    return transport(DVHttpRequest(
      url: url,
      method: method,
      headers: <String, String>{
        ...extraHeaders,
        ...DVAwsSigV4.signedHeaders(
          method: method,
          url: url,
          headers: extraHeaders,
          body: body,
          credentials: credentials,
          region: region,
          service: 's3',
          timestamp: now(),
        ),
      },
      body: body,
    ));
  }

  void _ensure(DVHttpResponse response, String operation, String key) {
    if (response.isSuccess) return;
    throw DVFileStorageException(
      's3',
      operation,
      key,
      statusCode: response.statusCode,
      responseBody: response.body.length > 2000
          ? '${response.body.substring(0, 2000)}…'
          : response.body,
    );
  }
}
