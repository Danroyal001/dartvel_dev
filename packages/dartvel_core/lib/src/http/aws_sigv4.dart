/// AWS Signature Version 4 request signing.
library dartvel_core.http.aws_sigv4;

import 'dart:convert';

import 'package:crypto/crypto.dart';

class DVAwsCredentials {
  final String accessKeyId;
  final String secretAccessKey;

  /// Present for temporary credentials (STS / instance roles).
  final String? sessionToken;

  const DVAwsCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
  });
}

/// Signs requests with AWS Signature Version 4.
///
/// Returns the headers to add rather than mutating a request, so callers stay
/// in control of how the request is assembled.
class DVAwsSigV4 {
  static const String _algorithm = 'AWS4-HMAC-SHA256';

  const DVAwsSigV4._();

  /// Signs a request and returns the headers to send with it, including
  /// `authorization`, `x-amz-date` and `x-amz-content-sha256`.
  ///
  /// [headers] must contain everything that will actually be sent apart from
  /// the returned ones; every entry is signed, so adding a header afterwards
  /// invalidates the signature.
  static Map<String, String> signedHeaders({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required List<int> body,
    required DVAwsCredentials credentials,
    required String region,
    required String service,
    required DateTime timestamp,
  }) {
    final utc = timestamp.toUtc();
    final amzDate = _amzDate(utc);
    final dateStamp = amzDate.substring(0, 8);
    final payloadHash = sha256.convert(body).toString();

    final canonicalHeaders = <String, String>{
      for (final entry in headers.entries)
        entry.key.toLowerCase().trim(): _collapse(entry.value),
      'host': url.host + (url.hasPort ? ':${url.port}' : ''),
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      if (credentials.sessionToken case final token?)
        'x-amz-security-token': token,
    };

    final sortedNames = canonicalHeaders.keys.toList()..sort();
    final signedHeaderList = sortedNames.join(';');

    final canonicalRequest = <String>[
      method.toUpperCase(),
      _canonicalPath(url),
      _canonicalQuery(url),
      '${sortedNames.map((name) => '$name:${canonicalHeaders[name]}').join('\n')}\n',
      signedHeaderList,
      payloadHash,
    ].join('\n');

    final scope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = <String>[
      _algorithm,
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signature = _hex(
      _hmac(_signingKey(credentials.secretAccessKey, dateStamp, region, service),
          utf8.encode(stringToSign)),
    );

    return <String, String>{
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      if (credentials.sessionToken case final token?)
        'x-amz-security-token': token,
      'authorization': '$_algorithm '
          'Credential=${credentials.accessKeyId}/$scope, '
          'SignedHeaders=$signedHeaderList, '
          'Signature=$signature',
    };
  }

  static List<int> _signingKey(
    String secret,
    String dateStamp,
    String region,
    String service,
  ) {
    var key = _hmac(utf8.encode('AWS4$secret'), utf8.encode(dateStamp));
    key = _hmac(key, utf8.encode(region));
    key = _hmac(key, utf8.encode(service));
    return _hmac(key, utf8.encode('aws4_request'));
  }

  static List<int> _hmac(List<int> key, List<int> data) =>
      Hmac(sha256, key).convert(data).bytes;

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  /// `yyyyMMddTHHmmssZ`.
  static String _amzDate(DateTime utc) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
        '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}'
        '${two(utc.second)}Z';
  }

  /// Header values are trimmed and internal runs of whitespace collapsed.
  static String _collapse(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _canonicalPath(Uri url) =>
      url.path.isEmpty ? '/' : Uri.encodeFull(url.path);

  /// Query parameters sorted by name, then value, each percent-encoded.
  static String _canonicalQuery(Uri url) {
    if (url.queryParameters.isEmpty) return '';
    final pairs = <(String, String)>[
      for (final entry in url.queryParametersAll.entries)
        for (final value in entry.value)
          (_encode(entry.key), _encode(value)),
    ]..sort((left, right) {
        final byName = left.$1.compareTo(right.$1);
        return byName != 0 ? byName : left.$2.compareTo(right.$2);
      });
    return pairs.map((pair) => '${pair.$1}=${pair.$2}').join('&');
  }

  static String _encode(String value) =>
      Uri.encodeComponent(value).replaceAll('%7E', '~');
}
