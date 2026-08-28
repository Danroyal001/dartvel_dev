// Push notifications abstraction
import 'dart:async';
import 'dart:developer' as developer;

/// Push notification message
class PushNotification {
  final String id;
  final String? title;
  final String? body;
  final Map<String, Object?>? data;
  final DateTime receivedAt;

  PushNotification({
    required this.id,
    this.title,
    this.body,
    this.data,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();
}

/// Push notification provider
abstract class PushNotificationProvider {
  Future<void> initialize();
  Future<String?> getToken();
  Future<void> requestPermission();
  Stream<PushNotification> get onMessage;
  Stream<PushNotification> get onMessageOpenedApp;
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);
}

/// Push notifications manager
class PushNotifications {
  static PushNotificationProvider? _provider;
  // Not closed, deliberately. These are process-lifetime broadcast channels
  // on a static holder: nothing owns them, so nothing is in a position to
  // close them, and closing one would end delivery for every listener in the
  // application rather than release anything.
  // ignore: close_sinks
  static final _messageController =
      StreamController<PushNotification>.broadcast();
  // ignore: close_sinks
  static final _openedController =
      StreamController<PushNotification>.broadcast();

  static void setProvider(PushNotificationProvider provider) {
    _provider = provider;

    // Forward events
    provider.onMessage.listen(_messageController.add);
    provider.onMessageOpenedApp.listen(_openedController.add);
  }

  static Future<void> initialize() async {
    if (_provider == null) {
      throw StateError('PushNotificationProvider not set');
    }
    await _provider!.initialize();
  }

  static Future<String?> getToken() async {
    if (_provider == null) return null;
    return _provider!.getToken();
  }

  static Future<void> requestPermission() async {
    if (_provider == null) return;
    await _provider!.requestPermission();
  }

  static Stream<PushNotification> get onMessage => _messageController.stream;

  static Stream<PushNotification> get onMessageOpenedApp =>
      _openedController.stream;

  static Future<void> subscribeToTopic(String topic) async {
    if (_provider == null) return;
    await _provider!.subscribeToTopic(topic);
  }

  static Future<void> unsubscribeFromTopic(String topic) async {
    if (_provider == null) return;
    await _provider!.unsubscribeFromTopic(topic);
  }
}

/// In-memory push provider for local development and tests.
class LocalPushNotificationProvider implements PushNotificationProvider {
  // Same lifetime as the provider, which lives as long as the application
  // that registered it.
  // ignore: close_sinks
  final _messageController = StreamController<PushNotification>.broadcast();
  // ignore: close_sinks
  final _openedController = StreamController<PushNotification>.broadcast();

  @override
  Future<void> initialize() async {
    developer.log('PushNotifications: initialized (debug mode)',
        name: 'dartvel');
  }

  @override
  Future<String?> getToken() async {
    return 'local-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Future<void> requestPermission() async {
    developer.log('PushNotifications: permission requested', name: 'dartvel');
  }

  @override
  Stream<PushNotification> get onMessage => _messageController.stream;

  @override
  Stream<PushNotification> get onMessageOpenedApp => _openedController.stream;

  @override
  Future<void> subscribeToTopic(String topic) async {
    developer.log('PushNotifications: subscribed to $topic', name: 'dartvel');
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    developer.log('PushNotifications: unsubscribed from $topic',
        name: 'dartvel');
  }

  // Test helper
  void simulateMessage(PushNotification notification) {
    _messageController.add(notification);
  }
}

@Deprecated('Use LocalPushNotificationProvider instead.')
typedef DebugPushNotificationProvider = LocalPushNotificationProvider;
