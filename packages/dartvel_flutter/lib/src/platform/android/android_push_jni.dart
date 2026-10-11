/// `push.*` on Android: Firebase Cloud Messaging over the generated
/// `DartvelPush` Java class.
///
/// The class and the Firebase library behind it exist only in a project that
/// declares `dartvel.push.android.fcm`, so the names are registered only when
/// the class is found. A build without it leaves them unregistered and
/// `PushNotifications.getToken()` answers null, which is the truth.
///
/// Dart starts an operation and polls for the answer, and drains the queue of
/// messages -- the shape the billing and capture bridges use, for the reason
/// they give. Nothing is called back into Dart.
library dartvel_flutter.platform.android.push;

import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart' show dvAndroidPushBridgeClass;
import 'package:jni/jni.dart';

import 'android_capabilities.dart' show dvAndroidPushBindings;

class DVAndroidPush {
  const DVAndroidPush._();

  static const Set<String> implemented = dvAndroidPushBindings;

  /// Why the bridge is not available, or null when it is.
  static String? lastFailure;

  static JClass? _bridge;

  /// How long a Firebase operation is given. A token needs a network round
  /// trip to Google on first use.
  static const Duration _patience = Duration(seconds: 20);

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    try {
      _bridge = JClass.forName(dvAndroidPushBridgeClass);
      lastFailure = null;
    } on Object catch (error) {
      _bridge = null;
      lastFailure = 'the class $dvAndroidPushBridgeClass is not in this '
          'application ($error). `dartvel build android` writes it when '
          'pubspec.yaml declares dartvel.push.android.fcm.';
      return;
    }

    bind('push.token', (Object? _) async =>
        dvAndroidPushToken(await _operation(<String, Object?>{'op': 'token'})));
    bind('push.unsubscribe', (Object? _) async => dvAndroidPushOk(
        await _operation(<String, Object?>{'op': 'deleteToken'})));
    bind('push.subscribeToTopic', (Object? arguments) async =>
        dvAndroidPushOk(await _operation(<String, Object?>{
          'op': 'subscribe',
          'topic': _topic(arguments),
        })));
    bind('push.unsubscribeFromTopic', (Object? arguments) async =>
        dvAndroidPushOk(await _operation(<String, Object?>{
          'op': 'unsubscribe',
          'topic': _topic(arguments),
        })));
    bind('push.drainMessages', (Object? _) {
      final JClass bridge = _bridge!;
      final String drained = bridge
          .staticMethodId('drainMessages', '()Ljava/lang/String;')
          .call(bridge, JString.type, const <dynamic>[])
          .toDartString(releaseOriginal: true);
      return dvAndroidPushMessages(drained);
    });
  }

  static String _topic(Object? arguments) {
    final Object? topic = arguments is Map ? arguments['topic'] : null;
    if (topic is! String || topic.isEmpty) {
      throw ArgumentError.value(topic, 'topic', 'A push topic is a name.');
    }
    return topic;
  }

  /// Starts [request] in the bridge and waits for its JSON answer.
  static Future<String> _operation(Map<String, Object?> request) async {
    final JClass bridge = _bridge!;
    final JString argument = jsonEncode(request).toJString();
    final String id;
    try {
      id = bridge
          .staticMethodId('start', '(Ljava/lang/String;)Ljava/lang/String;')
          .call(bridge, JString.type, <dynamic>[argument])
          .toDartString(releaseOriginal: true);
    } finally {
      argument.release();
    }
    final JStaticMethodId poll = bridge.staticMethodId(
        'poll', '(Ljava/lang/String;)Ljava/lang/String;');
    final DateTime deadline = DateTime.now().add(_patience);
    Duration gap = const Duration(milliseconds: 25);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(gap);
      final JString key = id.toJString();
      final JString? answer;
      try {
        answer = poll.callNullable(bridge, JString.type, <dynamic>[key]);
      } finally {
        key.release();
      }
      if (answer != null) return answer.toDartString(releaseOriginal: true);
      if (gap < const Duration(milliseconds: 200)) gap = gap * 2;
    }
    throw StateError('Firebase did not answer within ${_patience.inSeconds}s '
        '(no network, or Google Play services is missing or out of date)');
  }
}

/// The token in the bridge's `token` answer. Throws [StateError] with the
/// reason for an error, and for an answer that holds no token: an error
/// returned as a token would be sent to the server as this device's address.
String dvAndroidPushToken(String json) {
  final Object? decoded = _decode(json);
  if (decoded is Map) {
    final Object? error = decoded['error'];
    if (error != null) throw StateError('$error');
    final Object? token = decoded['token'];
    if (token is String && token.isNotEmpty) return token;
  }
  throw StateError('the push bridge answered with no token');
}

/// Whether an operation that answers `{"ok": true}` succeeded. Throws
/// [StateError] with the reason on `{"error": ...}`.
bool dvAndroidPushOk(String json) {
  final Object? decoded = _decode(json);
  if (decoded is! Map) return false;
  final Object? error = decoded['error'];
  if (error != null) throw StateError('$error');
  return decoded['ok'] == true;
}

/// The drained messages as the list the Dart provider reads. Anything that
/// is not a JSON array is an empty list: a malformed queue must not stop the
/// application from starting.
List<Object?> dvAndroidPushMessages(String json) {
  final Object? decoded = _decode(json);
  return decoded is List ? decoded : const <Object?>[];
}

Object? _decode(String json) {
  try {
    return jsonDecode(json);
  } on FormatException {
    return null;
  }
}
