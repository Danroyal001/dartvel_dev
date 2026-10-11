/// `PushNotifications` on a device: one provider over the `push.*` bindings.
///
/// Android registers them over JNI (the `DartvelPush` class `dartvel build
/// android` writes, which holds the FCM token and the messages the Firebase
/// service received) and the browser registers them over the service worker
/// `dartvel build web` generates (a Web Push subscription and the pushes the
/// worker forwarded). The provider does not know which it is talking to, which
/// is the point: an application writes
///
/// ```dart
/// final String? token = await PushNotifications.getToken();
/// ```
///
/// once, and it is an FCM registration token on a phone and a subscription on
/// the web -- exactly the two things `DVNotificationRoutes.pushTokens` and
/// `.webPushSubscriptions` take on the server.
///
/// Two rules shape it. **Permission is a user action**: [initialize] asks for
/// nothing, [requestPermission] is what a button calls. A prompt at first paint
/// is how a site loses the permission for good, because a browser stops
/// showing it after a few dismissals. And **a missing binding degrades**: a
/// platform with no push (or a build that did not declare `dartvel.push`)
/// answers null and does nothing, instead of throwing at startup.
///
/// Messages are polled from the platform's queue rather than delivered by a
/// callback, for the reason the billing and capture bridges are: a callback
/// into Dart from whichever thread Android or the worker picks is the part of
/// JNI and JS interop hardest to get right and hardest to see going wrong.
library dartvel_flutter.push.device_push;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';

import '../../dartvel_flutter.dart' show DVNativeBridge;

class DVDevicePushProvider implements PushNotificationProvider {
  /// [vapidPublicKey] is the application server key a browser subscribes with
  /// (`dartvel.push.web.vapidPublicKey`); Android ignores it.
  ///
  /// [pollInterval] is how often the platform's queue is drained while
  /// something listens for messages; [Duration.zero] disables the timer and
  /// leaves [poll] to the caller, which is how the tests drive it.
  DVDevicePushProvider({
    this.vapidPublicKey,
    this.pollInterval = const Duration(seconds: 1),
  });

  final String? vapidPublicKey;
  final Duration pollInterval;

  // Closed by dispose().
  // ignore: close_sinks
  final StreamController<PushNotification> _messages =
      StreamController<PushNotification>.broadcast();
  // ignore: close_sinks
  final StreamController<PushNotification> _opened =
      StreamController<PushNotification>.broadcast();

  Timer? _timer;

  /// Whether the platform's queue is being drained on a timer.
  bool get isPolling => _timer != null;

  /// Ids already delivered, bounded: a platform queue that hands a message
  /// over twice must not show it twice.
  final List<String> _seen = <String>[];
  static const int _remembered = 256;

  @override
  Future<void> initialize() async {
    // Deliberately asks for nothing. See the library comment.
    // Only where the platform has a queue to drain: on a target with no push
    // (or under `flutter test`) a timer would tick for nothing, and a pending
    // timer is a failure in a widget test.
    if (pollInterval > Duration.zero &&
        DVNativeBridge.isRegistered('push.drainMessages')) {
      _timer ??= Timer.periodic(pollInterval, (_) => unawaited(poll()));
    }
    // Whatever arrived before the first listener existed (a message that
    // launched the process) is collected now.
    await poll();
  }

  @override
  Future<String?> getToken() async {
    final String? token = await DVNativeBridge.invoke<String>(
      'push.token',
      <String, Object?>{
        if (vapidPublicKey != null) 'vapidPublicKey': vapidPublicKey,
      },
    );
    return token == null || token.isEmpty ? null : token;
  }

  @override
  Future<void> requestPermission() async {
    await DVNativeBridge.invoke<bool>(
      'permissions.request',
      <String, Object?>{'permission': 'notifications'},
    );
  }

  @override
  Stream<PushNotification> get onMessage => _messages.stream;

  @override
  Stream<PushNotification> get onMessageOpenedApp => _opened.stream;

  @override
  Future<void> subscribeToTopic(String topic) async {
    if (!DVNativeBridge.isRegistered('push.subscribeToTopic')) {
      throw _noTopics;
    }
    await DVNativeBridge.invoke<bool>(
        'push.subscribeToTopic', <String, Object?>{'topic': topic});
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    if (!DVNativeBridge.isRegistered('push.unsubscribeFromTopic')) {
      throw _noTopics;
    }
    await DVNativeBridge.invoke<bool>(
        'push.unsubscribeFromTopic', <String, Object?>{'topic': topic});
  }

  static final UnsupportedError _noTopics = UnsupportedError(
    'This platform has no push topics (Web Push does not; FCM on Android '
    'does). Keep topic membership on the server and send to the '
    'subscriptions it lists.',
  );

  /// Drops this device's registration: the FCM token is deleted, or the
  /// browser subscription is unsubscribed. True when something was removed.
  Future<bool> unsubscribe() async =>
      await DVNativeBridge.invoke<bool>('push.unsubscribe') ?? false;

  /// Collects what the platform received since the last call and delivers it.
  Future<void> poll() async {
    final List<Object?>? batch =
        await DVNativeBridge.invoke<List<Object?>>('push.drainMessages');
    if (batch == null) return;
    for (final Object? entry in batch) {
      final PushNotification? message = _parse(entry);
      if (message == null || _alreadyDelivered(message.id)) continue;
      final bool tapped = entry is Map && entry['opened'] == true;
      (tapped ? _opened : _messages).add(message);
    }
  }

  bool _alreadyDelivered(String id) {
    if (_seen.contains(id)) return true;
    _seen.add(id);
    if (_seen.length > _remembered) _seen.removeAt(0);
    return false;
  }

  static PushNotification? _parse(Object? entry) {
    if (entry is! Map) return null;
    final Object? id = entry['id'];
    if (id is! String || id.isEmpty) return null;
    final Object? received = entry['receivedAt'];
    final Object? data = entry['data'];
    return PushNotification(
      id: id,
      title: entry['title'] as String?,
      body: entry['body'] as String?,
      data: data is Map
          ? <String, Object?>{
              for (final MapEntry<Object?, Object?> e in data.entries)
                '${e.key}': e.value,
            }
          : null,
      receivedAt: received is int
          ? DateTime.fromMillisecondsSinceEpoch(received)
          : null,
    );
  }

  /// Stops polling and closes the streams.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _messages.close();
    await _opened.close();
  }
}
