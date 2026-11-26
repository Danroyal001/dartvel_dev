/// The delivery every platform without a better one gets: the platform's
/// plain local notification when a timer rings, while the app runs.
library dartvel_flutter.timers.timer_basic_delivery;

import 'dart:async';

import '../../dartvel_flutter.dart' show DVNativeBridge;
import 'timer.dart';
import 'timer_delivery.dart';

/// Rings through `notifications.sendLocal` (the freedesktop service on
/// Linux, the system's notification on macOS, Windows and iOS) and asks for
/// permission through `permissions.request`. Nothing is scheduled with the
/// operating system, so it rings only while the app runs.
final class DVBasicTimerDelivery implements DVTimerDelivery {
  DVBasicTimerDelivery();

  final StreamController<DVTimerAction> _actions = StreamController<DVTimerAction>.broadcast();

  @override
  DVTimerReach get reach => .whileOpen;

  @override
  Stream<DVTimerAction> get actions => _actions.stream;

  @override
  Future<DVTimerPermission> permission() async {
    if (!DVNativeBridge.isRegistered('notifications.sendLocal')) return .unsupported;
    if (!DVNativeBridge.isRegistered('permissions.isGranted')) return .granted;
    try {
      final bool? granted = await DVNativeBridge.invoke<bool>(
          'permissions.isGranted', <String, Object?>{'permission': 'notifications'});
      return granted == true ? .granted : .notAsked;
    } on Object {
      return .notAsked;
    }
  }

  @override
  Future<DVTimerPermission> requestPermission() async {
    if (!DVNativeBridge.isRegistered('permissions.request')) return permission();
    try {
      final bool? granted = await DVNativeBridge.invoke<bool>(
          'permissions.request', <String, Object?>{'permission': 'notifications'});
      return granted == true ? .granted : .denied;
    } on Object {
      return .denied;
    }
  }

  @override
  void prime() {}

  @override
  Future<void> schedule(DVTimer timer) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> ring(DVTimer timer) async {
    if (!DVNativeBridge.isRegistered('notifications.sendLocal')) return;
    try {
      await DVNativeBridge.invoke<Object?>(
          'notifications.sendLocal', <String, Object?>{'title': timer.label, 'body': dvTimerDoneBody(timer)});
    } on Object {
      // Notifications switched off: the app's own ringing view still shows it.
    }
  }

  @override
  Future<void> silence(String id) async {}
}

/// The notification's text under the label.
String dvTimerDoneBody(DVTimer timer) => 'Your ${dvTimerLength(timer.duration)} timer is done.';
