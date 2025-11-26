// Push notifications abstraction
import 'dart:async';

/// Push notification message
class PushNotification {
  final String id;
  final String? title;
  final String? body;
  final Map<String, dynamic>? data;
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
  static final _messageController =
      StreamController<PushNotification>.broadcast();
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

/// Mock push provider for development
class DebugPushNotificationProvider implements PushNotificationProvider {
  final _messageController = StreamController<PushNotification>.broadcast();
  final _openedController = StreamController<PushNotification>.broadcast();

  @override
  Future<void> initialize() async {
    print('PushNotifications: initialized (debug mode)');
  }

  @override
  Future<String?> getToken() async {
    return 'debug_token_123';
  }

  @override
  Future<void> requestPermission() async {
    print('PushNotifications: permission requested');
  }

  @override
  Stream<PushNotification> get onMessage => _messageController.stream;

  @override
  Stream<PushNotification> get onMessageOpenedApp => _openedController.stream;

  @override
  Future<void> subscribeToTopic(String topic) async {
    print('PushNotifications: subscribed to $topic');
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    print('PushNotifications: unsubscribed from $topic');
  }

  // Test helper
  void simulateMessage(PushNotification notification) {
    _messageController.add(notification);
  }
}
