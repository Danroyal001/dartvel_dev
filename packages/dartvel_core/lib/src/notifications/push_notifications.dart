import 'dart:async';

/// Notification payload
class NotificationMessage {
  final String title;
  final String body;
  final Map<String, Object?>? data;
  final String? imageUrl;

  const NotificationMessage({
    required this.title,
    required this.body,
    this.data,
    this.imageUrl,
  });
}

/// Notification provider interface
abstract class NotificationProvider {
  Future<void> initialize();
  Future<String?> getToken();
  Future<void> send(String token, NotificationMessage message);
  Stream<NotificationMessage> get onMessage;
}

/// Push notification manager
class PushNotifications {
  final NotificationProvider _provider;

  PushNotifications(this._provider);

  Future<void> initialize() => _provider.initialize();
  Future<String?> getToken() => _provider.getToken();
  Stream<NotificationMessage> get onMessage => _provider.onMessage;
}
