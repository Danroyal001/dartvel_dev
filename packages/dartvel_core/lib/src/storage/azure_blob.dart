/// Azure Blob Storage, authenticated with Shared Key.
///
/// The signature is the whole adapter. Azure builds a canonical string from
/// the verb, a fixed list of standard headers, every `x-ms-` header sorted,
/// and a canonicalised resource, then HMAC-SHA256s it with the base64-decoded
/// account key. Every one of those pieces has a way to be subtly wrong that
/// produces a well-formed request Azure answers with 403, so this is written
/// against a real emulator rather than against a fake that would accept
/// anything.
library dartvel_core.storage.azure_blob;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../http/transport.dart';
import 'adapters.dart';

/// The Azure REST version this adapter speaks.
///
/// Sent on every request. Azure keys behaviour off it, so it is pinned rather
/// than tracking whatever the service currently defaults to.
const String dvAzureApiVersion = '2021-08-06';

/// Builds the string Azure signs for a Shared Key request.
///
/// [resourcePath] is the encoded path as it goes on the wire, not the decoded
/// one. Exposed for testing: the ordering rules are the part that goes wrong,
/// and a wrong one is only visible as a 403 from the far end.
String dvAzureStringToSign({
  required String method,
  required String account,
  required String resourcePath,
  required Map<String, String> queryParameters,
  required Map<String, String> headers,
  int contentLength = 0,
}) {
  String header(String name) => headers[name.toLowerCase()] ?? '';

  // Azure wants a blank here for an empty body, not a zero. Sending "0" is a
  // well-formed request that fails to authenticate.
  final String length = contentLength == 0 ? '' : '$contentLength';

  final List<String> canonicalHeaders = headers.entries
      .where((MapEntry<String, String> e) => e.key.startsWith('x-ms-'))
      .map((MapEntry<String, String> e) =>
          '${e.key.toLowerCase()}:${e.value.trim()}')
      .toList()
    ..sort();

  final List<String> canonicalQuery = queryParameters.entries
      .map((MapEntry<String, String> e) =>
          '${e.key.toLowerCase()}:${e.value}')
      .toList()
    ..sort();

  return <String>[
    method.toUpperCase(),
    header('content-encoding'),
    header('content-language'),
    length,
    header('content-md5'),
    header('content-type'),
    // The Date header is empty because x-ms-date carries it, and sending both
    // makes Azure sign one and read the other.
    '',
    header('if-modified-since'),
    header('if-match'),
    header('if-none-match'),
    header('if-unmodified-since'),
    header('range'),
    ...canonicalHeaders,
    '/$account$resourcePath',
    ...canonicalQuery,
  ].join('\n');
}

/// Azure Blob Storage and API-compatible emulators (Azurite).
class AzureBlobFileStorageAdapter implements DVFileStorageAdapter {
  AzureBlobFileStorageAdapter({
    required this.account,
    required this.accountKey,
    required this.container,
    String? endpoint,
    this.transport = dvSendHttpRequest,
  })  : endpoint = (endpoint ?? 'https://$account.blob.core.windows.net')
            .replaceAll(RegExp(r'/+$'), ''),
        _key = base64.decode(accountKey);

  final String account;
  final String accountKey;
  final String container;
  final String endpoint;
  final Uint8List _key;

  /// Injected so a test can drive the adapter without a socket. The live
  /// suite deliberately does not: a fake would accept any signature.
  final DVHttpSend transport;

  /// Whether the endpoint addresses the account through a path segment.
  ///
  /// Azurite serves every account under `/devstoreaccount1`; the real service
  /// puts the account in the hostname. The canonicalised resource has to match
  /// the path actually requested, so this decides both.
  bool get _pathStyle => !endpoint.contains('$account.blob.');

  String get _accountPrefix => _pathStyle ? '/$account' : '';

  /// Creates the container, ignoring the case where it already exists.
  Future<void> createContainer() async {
    final DVHttpResponse response = await _send(
      method: 'PUT',
      resourcePath: '/$container',
      queryParameters: <String, String>{'restype': 'container'},
    );
    if (response.statusCode == 409) return; // already there
    _ensure(response, 'createContainer', container);
  }

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async {
    final DVHttpResponse response = await _send(
      method: 'PUT',
      resourcePath: '/$container/$key',
      body: Uint8List.fromList(bytes),
      headers: <String, String>{
        'x-ms-blob-type': 'BlockBlob',
        if (contentType != null) 'content-type': contentType,
      },
    );
    _ensure(response, 'put', key);
  }

  @override
  Future<List<int>> get(String key) async {
    final DVHttpResponse response = await _send(
      method: 'GET',
      resourcePath: '/$container/$key',
    );
    _ensure(response, 'get', key);
    return response.bodyBytes;
  }

  @override
  Future<void> delete(String key) async {
    final DVHttpResponse response = await _send(
      method: 'DELETE',
      resourcePath: '/$container/$key',
    );
    // Deleting what is not there is the caller's intent either way.
    if (response.statusCode == 404) return;
    _ensure(response, 'delete', key);
  }

  @override
  Future<bool> exists(String key) async {
    final DVHttpResponse response = await _send(
      method: 'HEAD',
      resourcePath: '/$container/$key',
    );
    if (response.statusCode == 404) return false;
    _ensure(response, 'exists', key);
    return true;
  }

  @override
  Future<List<String>> list({String prefix = ''}) async {
    final DVHttpResponse response = await _send(
      method: 'GET',
      resourcePath: '/$container',
      queryParameters: <String, String>{
        'restype': 'container',
        'comp': 'list',
        if (prefix.isNotEmpty) 'prefix': prefix,
      },
    );
    _ensure(response, 'list', prefix);

    // The list response is XML. Only the blob names are wanted, and a full
    // parser for one element would be more surface than the feature.
    final Iterable<RegExpMatch> names =
        RegExp(r'<Name>(.*?)</Name>', dotAll: true).allMatches(response.body);
    return List<String>.unmodifiable(
      names.map((RegExpMatch m) => _unescapeXml(m.group(1)!)).toList()..sort(),
    );
  }

  Future<DVHttpResponse> _send({
    required String method,
    required String resourcePath,
    Map<String, String> queryParameters = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    Uint8List? body,
  }) async {
    // The signature covers the unescaped path, while the URL carries the
    // escaped one. Signing what was escaped, or sending what was signed, both
    // produce a 403 for a key that is perfectly correct.
    final String path =
        '${Uri.parse(endpoint).path}$_accountPrefix$resourcePath'
            .replaceAll(RegExp('/+'), '/');

    // Each segment is encoded explicitly rather than left to Uri, which keeps
    // '+' literal in a path where the server would read it as a space.
    final String encodedPath = path
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');

    final Uri url = Uri.parse(
      '$endpoint$encodedPath'
      '${queryParameters.isEmpty ? '' : '?${_query(queryParameters)}'}',
    );

    final Map<String, String> all = <String, String>{
      for (final MapEntry<String, String> e in headers.entries)
        e.key.toLowerCase(): e.value,
      'x-ms-date': _httpDate(DateTime.now().toUtc()),
      'x-ms-version': dvAzureApiVersion,
    };

    // The *encoded* path is what gets signed, which is what Azure documents
    // ("append the resource's encoded URI path") and what Azurite verifies.
    // Signing the decoded one works for every key made of unreserved
    // characters and fails with 403 the moment a key contains a space or a
    // plus -- a bug that would look like a credentials problem.
    final String stringToSign = dvAzureStringToSign(
      method: method,
      account: account,
      resourcePath: encodedPath,
      queryParameters: queryParameters,
      headers: all,
      contentLength: body?.length ?? 0,
    );

    final String signature = base64.encode(
      Hmac(sha256, _key).convert(utf8.encode(stringToSign)).bytes,
    );
    all['authorization'] = 'SharedKey $account:$signature';

    return transport(DVHttpRequest(
      url: url,
      method: method,
      headers: all,
      body: body ?? const <int>[],
    ));
  }

  static String _query(Map<String, String> parameters) => parameters.entries
      .map((MapEntry<String, String> e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  void _ensure(DVHttpResponse response, String operation, String key) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw DVFileStorageException(
      'azure',
      operation,
      key,
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  static String _unescapeXml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

  static const List<String> _days = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// RFC 1123, which is what Azure expects and what it signs.
  static String _httpDate(DateTime when) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${_days[when.weekday - 1]}, ${two(when.day)} '
        '${_months[when.month - 1]} ${when.year} '
        '${two(when.hour)}:${two(when.minute)}:${two(when.second)} GMT';
  }
}
