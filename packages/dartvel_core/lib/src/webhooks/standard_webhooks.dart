/// Standard Webhooks signing (https://www.standardwebhooks.com), offered
/// beside Dartvel's own scheme.
///
/// The reason to offer a second scheme at all is who verifies it. Dartvel's
/// `dartvel-webhook-signature` is verified by code the customer writes, or by
/// `DVWebhookSignature` when the customer happens to run Dartvel. A Standard
/// Webhooks signature is verified by the official `standardwebhooks` library
/// in whatever language the customer's server is written in, and by the
/// platforms that already accept it -- which is the verification code least
/// likely to skip the constant-time comparison or the age check.
///
/// The scheme, as the specification fixes it:
///
/// - the key is 24 to 64 random bytes, handed to the customer base64-encoded
///   and prefixed `whsec_`; the HMAC key is the decoded bytes, not the text;
/// - the signed content is `webhook-id.webhook-timestamp.body`, so the id a
///   consumer deduplicates on is covered by the signature, where Dartvel's
///   own scheme signs only the timestamp and the body;
/// - `webhook-signature` is a space-delimited list of `v1,<base64>` entries,
///   one per key through a rotation overlap.
///
/// No new cryptography: this is HMAC-SHA256 from `package:crypto`, as
/// `DVWebhookSignature` is.
library dartvel_core.webhooks.standard_webhooks;

import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class DVStandardWebhookSignature {
  /// The window the official libraries enforce, and the default here.
  static const Duration defaultTolerance = Duration(minutes: 5);

  static const String _prefix = 'whsec_';

  /// The HMAC key [secret] names: the base64 after an optional `whsec_`.
  ///
  /// Refuses an empty key and one that is not base64 -- by saying so, never
  /// by repeating the value, since the message may reach a log.
  static List<int> _key(String secret) {
    final String encoded =
        secret.startsWith(_prefix) ? secret.substring(_prefix.length) : secret;
    if (encoded.isEmpty) {
      throw ArgumentError('A Standard Webhooks signing key cannot be empty.');
    }
    try {
      return base64.decode(encoded);
    } on FormatException {
      throw ArgumentError(
        'A Standard Webhooks signing key must be base64, optionally prefixed '
        'whsec_. The key given is not, so nothing was signed.',
      );
    }
  }

  static String _signature(List<int> key, String id, String timestamp,
          String body) =>
      base64.encode(
          Hmac(sha256, key).convert(utf8.encode('$id.$timestamp.$body')).bytes);

  /// One `v1,<base64>` entry for [secret].
  static String sign({
    required String secret,
    required String id,
    required String timestamp,
    required String body,
  }) =>
      'v1,${_signature(_key(secret), id, timestamp, body)}';

  /// The `webhook-signature` value for [secrets], current key first.
  static String header({
    required String id,
    required String timestamp,
    required String body,
    required List<String> secrets,
  }) =>
      <String>[
        for (final String secret in secrets)
          sign(secret: secret, id: id, timestamp: timestamp, body: body),
      ].join(' ');

  /// Whether [headers] carry a valid Standard Webhooks signature of [body]
  /// under [secret].
  ///
  /// [headers] are matched without regard to case. A missing header, an
  /// unreadable timestamp or one further than [tolerance] from [now] is
  /// false, as in the official libraries; pass a null [tolerance] only where
  /// something else already bounds the age. Every `v1` entry is compared in
  /// full and in constant time, so timing says neither which entry matched
  /// nor how much of it.
  static bool verify({
    required String secret,
    required Map<String, String> headers,
    required String body,
    Duration? tolerance = defaultTolerance,
    DateTime? now,
  }) {
    final List<int> key = _key(secret);
    String? find(String name) {
      for (final MapEntry<String, String> entry in headers.entries) {
        if (entry.key.toLowerCase() == name) return entry.value;
      }
      return null;
    }

    final String? id = find('webhook-id');
    final String? timestamp = find('webhook-timestamp');
    final String? signatures = find('webhook-signature');
    if (id == null || timestamp == null || signatures == null) return false;
    final int? seconds = int.tryParse(timestamp.trim());
    if (seconds == null) return false;
    if (tolerance != null) {
      final DateTime at =
          DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      if ((now ?? DateTime.now()).difference(at).abs() > tolerance) {
        return false;
      }
    }
    final List<int> expected =
        utf8.encode(_signature(key, id, timestamp.trim(), body));
    bool matched = false;
    for (final String entry in signatures.split(' ')) {
      if (!entry.startsWith('v1,')) continue;
      if (_constantTimeEquals(utf8.encode(entry.substring(3)), expected)) {
        matched = true;
      }
    }
    return matched;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    int difference = a.length ^ b.length;
    final int length = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
