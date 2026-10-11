/// `dartvel.push`: what a pubspec says about push notifications.
///
/// ```yaml
/// dartvel:
///   push:
///     web:
///       vapidPublicKey: BNc...   # the public half; the private key is a Secret
///     android:
///       fcm:
///         projectId: my-project
///         appId: 1:1234567890:android:abc123
///         apiKey: AIza...        # Firebase's public client key, not a secret
///         senderId: "1234567890"
/// ```
///
/// Everything here is public by design: the browser and the device need it to
/// reach the push service, and it ships in the app. The credentials that
/// *send* -- the FCM service account, the VAPID private key -- are Secrets
/// and are refused here by name, because a pubspec is committed.
library;

import 'web_push.dart';

/// The browser half of push: the key the page subscribes with.
final class DVWebPushConfig {
  const DVWebPushConfig({required this.vapidPublicKey});

  /// The application server key as unpadded base64url (65 bytes decoded).
  final String vapidPublicKey;
}

/// The Firebase app an Android build registers with, as the four values the
/// Firebase console shows (and `google-services.json` would carry).
final class DVFcmAppConfig {
  const DVFcmAppConfig({
    required this.projectId,
    required this.appId,
    required this.apiKey,
    required this.senderId,
  });

  final String projectId;
  final String appId;
  final String apiKey;
  final String senderId;
}

final class DVPushConfig {
  const DVPushConfig({this.web, this.androidFcm});

  final DVWebPushConfig? web;
  final DVFcmAppConfig? androidFcm;

  /// Whether the project asked for push on any target.
  bool get isDeclared => web != null || androidFcm != null;

  static const List<String> settings = <String>['web', 'android'];
  static const String _section = 'dartvel.push';

  factory DVPushConfig.parse(Object? section) {
    if (section == null) return const DVPushConfig();
    if (section is! Map) {
      throw ArgumentError.value(
          section, _section, 'must be a map of push settings');
    }
    for (final Object? key in section.keys) {
      if (!settings.contains('$key')) {
        throw ArgumentError.value(section[key], '$_section.$key',
            'is not a push setting; the settings are ${settings.join(', ')}');
      }
    }
    return DVPushConfig(
      web: _parseWeb(section['web']),
      androidFcm: _parseAndroid(section['android']),
    );
  }

  static DVWebPushConfig? _parseWeb(Object? web) {
    if (web == null || web == false) return null;
    const String where = '$_section.web';
    final Object? key = web is Map ? web['vapidPublicKey'] : null;
    if (web is Map) {
      for (final Object? name in web.keys) {
        if (name != 'vapidPublicKey') {
          throw ArgumentError.value(web[name], '$where.$name',
              'is not a web push setting; the one setting is vapidPublicKey');
        }
      }
    } else if (web != true) {
      throw ArgumentError.value(
          web, where, 'must be a map: web: {vapidPublicKey: <key>}');
    }
    if (key is! String || key.trim().isEmpty) {
      throw ArgumentError.value(
          key,
          '$where.vapidPublicKey',
          'is required: the browser subscribes with the public half of your '
              'VAPID key. Generate a pair with `dartvel push vapid-keys`, put '
              'the private key in the VAPID_PRIVATE_KEY secret and the public '
              'one here.');
    }
    final String trimmed = key.trim();
    final List<int> decoded;
    try {
      decoded = dvWebPushBase64Decode(trimmed);
    } on FormatException {
      throw ArgumentError.value(trimmed, '$where.vapidPublicKey',
          'is not unpadded base64url');
    }
    if (decoded.length != 65 || decoded.first != 0x04) {
      throw ArgumentError.value(
          trimmed,
          '$where.vapidPublicKey',
          'must be an uncompressed P-256 public key (65 bytes starting 0x04); '
              'this decodes to ${decoded.length}');
    }
    return DVWebPushConfig(vapidPublicKey: trimmed);
  }

  static DVFcmAppConfig? _parseAndroid(Object? android) {
    if (android == null || android == false) return null;
    const String where = '$_section.android';
    if (android is! Map) {
      throw ArgumentError.value(
          android, where, 'must be a map: android: {fcm: {...}}');
    }
    for (final Object? name in android.keys) {
      if (name != 'fcm') {
        throw ArgumentError.value(android[name], '$where.$name',
            'is not an Android push setting; the one setting is fcm');
      }
    }
    final Object? fcm = android['fcm'];
    if (fcm == null) return null;
    if (fcm is! Map) {
      throw ArgumentError.value(fcm, '$where.fcm',
          'must be a map of projectId, appId, apiKey and senderId');
    }
    const List<String> fields = <String>['projectId', 'appId', 'apiKey', 'senderId'];
    for (final Object? name in fcm.keys) {
      if (!fields.contains('$name')) {
        throw ArgumentError.value(
            fcm[name],
            '$where.fcm.$name',
            'is not an FCM app setting; they are ${fields.join(', ')}. The '
                'service account that sends is a Secret '
                '(FCM_SERVICE_ACCOUNT_JSON), never pubspec.yaml.');
      }
    }
    String field(String name) {
      final Object? value = fcm[name];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      throw ArgumentError.value(value, '$where.fcm.$name',
          'is required: the Firebase console shows it under Project settings');
    }

    return DVFcmAppConfig(
      projectId: field('projectId'),
      appId: field('appId'),
      apiKey: field('apiKey'),
      senderId: field('senderId'),
    );
  }
}
