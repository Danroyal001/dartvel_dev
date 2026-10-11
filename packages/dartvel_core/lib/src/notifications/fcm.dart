// Firebase Cloud Messaging, HTTP v1: the server credentials half.
//
// FCM v1 does not take an API key. It takes a short-lived OAuth2 access token,
// minted by signing a JWT with a service account's RSA private key and
// exchanging it at Google's token endpoint (the "jwt-bearer" grant, RFC 7523).
// Both steps are here so an application gives Dartvel one secret -- the
// service-account key file -- instead of wiring a credentials layer of its own.
//
// The private key is the most valuable thing this file touches. It is read
// through DVSecrets (so any log line quoting it is redacted), held in a
// private field, and absent from every toString, exception and message.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../http/transport.dart';
import '../secrets/secrets.dart';
import '../updates/patch_signing.dart';
import 'push_exception.dart';

/// The OAuth scope FCM HTTP v1 requires.
const String dvFirebaseMessagingScope =
    'https://www.googleapis.com/auth/firebase.messaging';

/// The Secrets key the service-account file is read from: the JSON as
/// downloaded from the Firebase console, or that JSON base64-encoded (what a
/// single-line environment variable usually needs).
const String dvFcmServiceAccountSecret = 'FCM_SERVICE_ACCOUNT_JSON';

/// A Google service account, as the key file describes it.
class DVGoogleServiceAccount {
  /// The Google Cloud project the account belongs to.
  final String projectId;

  /// The account's email, which is the JWT issuer.
  final String clientEmail;

  /// Where assertions are exchanged for access tokens. Always https.
  final Uri tokenUri;

  /// Identifies which of the account's keys signed, so Google can look it up.
  final String? privateKeyId;

  final String _privateKeyPem;

  DVGoogleServiceAccount._({
    required this.projectId,
    required this.clientEmail,
    required this.tokenUri,
    required this.privateKeyId,
    required String privateKeyPem,
  }) : _privateKeyPem = privateKeyPem;

  /// Reads the key file. Throws [ArgumentError] naming what is wrong, never
  /// quoting the key.
  factory DVGoogleServiceAccount.fromJson(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw ArgumentError.value(
        '<redacted>',
        'serviceAccount',
        'The FCM service account is not JSON. Paste the key file from the '
            'Firebase console (Project settings, Service accounts) or its '
            'base64.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw ArgumentError.value('<redacted>', 'serviceAccount',
          'A service account key file is a JSON object.');
    }
    final Map<String, Object?> file = decoded;
    if (file['type'] != 'service_account') {
      throw ArgumentError.value('<redacted>', 'serviceAccount',
          'Not a service account key file (type is not "service_account"). '
              'FCM HTTP v1 needs a service account, not an API key or a user '
              'credential.');
    }
    String require(String field) {
      final Object? value = file[field];
      if (value is String && value.trim().isNotEmpty) return value;
      throw ArgumentError.value('<redacted>', 'serviceAccount',
          'The service account key file has no "$field".');
    }

    final Uri tokenUri = Uri.parse(
        (file['token_uri'] as String?) ?? 'https://oauth2.googleapis.com/token');
    if (tokenUri.scheme != 'https') {
      throw ArgumentError.value('<redacted>', 'serviceAccount',
          'token_uri must be https: the signed assertion is sent there.');
    }
    return DVGoogleServiceAccount._(
      projectId: require('project_id'),
      clientEmail: require('client_email'),
      tokenUri: tokenUri,
      privateKeyId: file['private_key_id'] as String?,
      privateKeyPem: require('private_key'),
    );
  }

  /// Reads the account from [dvFcmServiceAccountSecret].
  ///
  /// Throws [DVSecretNotFoundException] when the secret is not set.
  factory DVGoogleServiceAccount.fromSecrets(
      [DVSecrets secrets = const DVSecrets()]) {
    final String raw = secrets.get(dvFcmServiceAccountSecret).trim();
    if (raw.startsWith('{')) return DVGoogleServiceAccount.fromJson(raw);
    final String decoded;
    try {
      decoded = utf8.decode(base64.decode(raw));
    } on FormatException {
      throw ArgumentError.value('<redacted>', dvFcmServiceAccountSecret,
          'Neither JSON nor base64 of JSON.');
    }
    return DVGoogleServiceAccount.fromJson(decoded);
  }

  /// A signed JWT asking for [scope], valid for [lifetime] (Google allows at
  /// most one hour).
  String signAssertion({
    required String scope,
    DateTime? now,
    Duration lifetime = const Duration(hours: 1),
  }) {
    if (lifetime > const Duration(hours: 1) || lifetime <= Duration.zero) {
      throw ArgumentError.value(lifetime, 'lifetime',
          'Google accepts an assertion that lives up to one hour.');
    }
    final int issuedAt =
        (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    final String signingInput = '${_segment(<String, Object?>{
      'alg': 'RS256',
      'typ': 'JWT',
      if (privateKeyId != null) 'kid': privateKeyId,
    })}.${_segment(<String, Object?>{
      'iss': clientEmail,
      'scope': scope,
      'aud': tokenUri.toString(),
      'iat': issuedAt,
      'exp': issuedAt + lifetime.inSeconds,
    })}';

    final RSAPrivateKey key;
    try {
      key = DVPatchSigning.privateKey(_privateKeyPem);
    } on Object {
      // Not the underlying message: a parser error can quote the input.
      throw ArgumentError.value('<redacted>', 'private_key',
          'The service account private key could not be read as PEM.');
    }
    final RSASigner signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    final RSASignature signature =
        signer.generateSignature(Uint8List.fromList(utf8.encode(signingInput)));
    return '$signingInput.${_base64Url(signature.bytes)}';
  }

  static String _segment(Map<String, Object?> json) =>
      _base64Url(utf8.encode(jsonEncode(json)));

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  @override
  String toString() => 'DVGoogleServiceAccount($clientEmail, $projectId)';
}

/// Access tokens for one service account and scope: minted on demand, kept
/// until shortly before they expire, and never requested twice at once.
class DVGoogleAccessTokens {
  DVGoogleAccessTokens({
    required this.account,
    this.scope = dvFirebaseMessagingScope,
    this.transport = dvSendHttpRequest,
    DateTime Function()? clock,
    this.refreshMargin = const Duration(minutes: 1),
  }) : _clock = clock ?? DateTime.now;

  final DVGoogleServiceAccount account;
  final String scope;
  final DVHttpSend transport;
  final Duration refreshMargin;
  final DateTime Function() _clock;

  String? _token;
  DateTime? _expiresAt;
  Future<String>? _inFlight;

  /// The current token, exchanging for a new one when there is none or it is
  /// about to lapse. Usable directly as a `DVAccessTokenSupplier`.
  Future<String> call() {
    final String? token = _token;
    final DateTime? expiresAt = _expiresAt;
    if (token != null &&
        expiresAt != null &&
        _clock().isBefore(expiresAt.subtract(refreshMargin))) {
      return Future<String>.value(token);
    }
    return _inFlight ??= _exchange().whenComplete(() => _inFlight = null);
  }

  /// Forgets the cached token, e.g. after the API answered 401.
  void invalidate() {
    _token = null;
    _expiresAt = null;
  }

  Future<String> _exchange() async {
    final DateTime requestedAt = _clock();
    final String assertion =
        account.signAssertion(scope: scope, now: requestedAt);
    final DVHttpResponse response = await transport(DVHttpRequest(
      url: account.tokenUri,
      headers: const <String, String>{
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: dvEncodeFormBody(<(String, String)>[
        ('grant_type', 'urn:ietf:params:oauth:grant-type:jwt-bearer'),
        ('assertion', assertion),
      ]),
    ));

    Map<String, Object?>? json;
    try {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) json = decoded;
    } on FormatException {
      // Falls through to the status-based failure below.
    }

    final Object? accessToken = json?['access_token'];
    if (response.isSuccess && accessToken is String && accessToken.isNotEmpty) {
      final Object? lifetime = json!['expires_in'];
      _token = accessToken;
      _expiresAt = requestedAt.add(Duration(seconds: lifetime is int ? lifetime : 3600));
      return accessToken;
    }

    // The error text comes from Google's answer, which does not echo the
    // assertion; the request body is deliberately never part of this.
    final Object? code = json?['error'];
    final Object? description = json?['error_description'];
    throw DVPushProviderException(
      'googleOAuth',
      description is String
          ? 'Google refused the service account: $description'
          : 'Google refused the service account token exchange.',
      statusCode: response.statusCode,
      errorCode: code is String ? code : null,
    );
  }
}

/// How urgently Android should deliver a message.
enum FirebaseAndroidPriority {
  /// Wakes the device. Required for a data message that must arrive at once.
  high,

  /// Batched with other work to save battery.
  normal,
}

/// Delivery options for FCM messages that the portable
/// `DVNotificationMessage` has no field for.
class FirebasePushOptions {
  const FirebasePushOptions({
    this.androidPriority,
    this.timeToLive,
    this.collapseKey,
    this.androidChannelId,
    this.dryRun = false,
  });

  final FirebaseAndroidPriority? androidPriority;

  /// How long FCM holds the message for an offline device.
  final Duration? timeToLive;

  /// Messages sharing a key replace each other while queued.
  final String? collapseKey;

  /// The Android notification channel the notification is posted on.
  final String? androidChannelId;

  /// FCM validates the request and delivers nothing (`validate_only`).
  final bool dryRun;

  bool get hasAndroidOptions =>
      androidPriority != null ||
      timeToLive != null ||
      collapseKey != null ||
      androidChannelId != null;
}

/// What FCM's v1 error codes mean, in words an operator can act on.
String dvFcmFailureReason(String? errorCode, int status) =>
    switch (errorCode) {
      'UNREGISTERED' => 'The registration token is no longer valid: the app '
          'was uninstalled or the token expired. Stop sending to it.',
      'INVALID_ARGUMENT' => 'FCM rejected the request as malformed. Check the '
          'token or topic, the payload size (4KB) and the data keys.',
      'SENDER_ID_MISMATCH' => 'The token belongs to a different Firebase '
          'project than the one this service account sends for.',
      'QUOTA_EXCEEDED' => 'FCM quota exceeded for this project, device or '
          'topic. Retry with backoff.',
      'UNAVAILABLE' => 'FCM is temporarily unavailable. Retry with backoff.',
      'INTERNAL' => 'FCM had an internal error. Retry with backoff.',
      'THIRD_PARTY_AUTH_ERROR' => 'The iOS (APNs) credentials registered '
          'with Firebase were rejected.',
      _ => switch (status) {
          401 => 'FCM rejected the access token. It may have expired or the '
              'service account may lack the Firebase Cloud Messaging API role.',
          403 => 'The service account may not send for this project.',
          404 => 'The registration token is no longer valid.',
          _ => 'The push service rejected the notification.',
        },
    };

/// Pulls FCM's `FcmError.errorCode` (or, failing that, the canonical status)
/// out of an error body. Null when the body says neither.
String? dvFcmErrorCode(String body) {
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) return null;
    final Object? error = decoded['error'];
    if (error is! Map<String, Object?>) return null;
    final Object? details = error['details'];
    if (details is List) {
      for (final Object? detail in details) {
        if (detail is Map<String, Object?> && detail['errorCode'] is String) {
          return detail['errorCode']! as String;
        }
      }
    }
    final Object? status = error['status'];
    return status is String ? status : null;
  } on FormatException {
    return null;
  }
}
