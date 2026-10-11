/// `push.token`, `push.unsubscribe` and `push.drainMessages` in a browser.
///
/// The browser half of Web Push: a `PushSubscription` from the service worker
/// registration `dartvel build web` generates (the worker carries the `push`
/// and `notificationclick` handlers when `dartvel.push.web` is declared), and
/// the messages that worker forwards to the page.
///
/// **Nothing here prompts.** `push.token` returns null until the person has
/// granted notifications -- asked for by `permissions.request('notifications')`
/// from a click -- and only then subscribes. A browser shows its permission
/// prompt for a request without a user gesture at most a few times before it
/// stops showing it at all, so a prompt on load spends the one chance a site
/// has.
library dartvel_flutter.platform.web.push;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_interop.dart';
import 'web_push_messages.dart';

class DVWebPushBrowser {
  const DVWebPushBrowser._();

  static const Set<String> implemented = <String>{
    'push.token',
    'push.unsubscribe',
    'push.drainMessages',
  };

  /// Whether this browser can do Web Push at all: a service worker, the Push
  /// API and the Notification API. Safari before 16.4 and an insecure origin
  /// lack one or more, and then the names stay unregistered.
  static bool get available {
    final JSObject? navigator = dvNavigator;
    return navigator != null &&
        dvJsObject(navigator, 'serviceWorker') != null &&
        dvJsObject(globalContext, 'PushManager') != null &&
        dvJsObject(globalContext, 'Notification') != null;
  }

  static final List<Map<String, Object?>> _queue = <Map<String, Object?>>[];
  static bool _listening = false;
  static int _counter = 0;

  static void register(
    void Function(String name, FutureOr<Object?> Function(Object? arguments))
        register,
  ) {
    if (!available) return;
    _listen();
    register('push.token', _token);
    register('push.unsubscribe', (Object? _) => _unsubscribe());
    register('push.drainMessages', (Object? _) => drain());
  }

  /// The messages forwarded since the last call, oldest first.
  static List<Map<String, Object?>> drain() {
    final List<Map<String, Object?>> out =
        List<Map<String, Object?>>.of(_queue);
    _queue.clear();
    return out;
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    web.window.navigator.serviceWorker.addEventListener(
      'message',
      (web.Event event) {
        final Object? data = (event as web.MessageEvent).data.dartify();
        final Map<String, Object?>? entry = dvWebPushEntryFrom(data,
            now: DateTime.now(), sequence: _counter++);
        if (entry != null) _queue.add(entry);
      }.toJS,
    );
  }

  /// The registration with an active worker. On a first visit the build's
  /// registration script has only just run, so this waits a little for the
  /// worker to activate instead of answering "none" in the first second of
  /// the app's life; null if nothing is registered, which is the truth for a
  /// site built with its service worker off.
  static Future<web.ServiceWorkerRegistration?> _registration() async {
    final web.ServiceWorkerContainer container = web.window.navigator.serviceWorker;
    final web.ServiceWorkerRegistration? existing =
        await container.getRegistration().toDart;
    if (existing != null && existing.active != null) return existing;
    try {
      return await container.ready.toDart.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return null;
    }
  }

  /// The subscription as JSON, or null while permission is not granted or
  /// there is no worker to subscribe through.
  static Future<Object?> _token(Object? arguments) async {
    if (web.Notification.permission != 'granted') return null;
    final web.ServiceWorkerRegistration? registration = await _registration();
    if (registration == null) return null;

    web.PushSubscription? subscription =
        await registration.pushManager.getSubscription().toDart;
    if (subscription == null) {
      final Object? key = arguments is Map ? arguments['vapidPublicKey'] : null;
      if (key is! String || key.isEmpty) return null;
      subscription = await registration.pushManager
          .subscribe(web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: _decodeKey(key).toJS,
          ))
          .toDart;
    }
    final JSObject json = globalContext.getProperty<JSObject>('JSON'.toJS);
    return json
        .callMethod<JSString>('stringify'.toJS, subscription)
        .toDart;
  }

  static Future<Object?> _unsubscribe() async {
    final web.ServiceWorkerRegistration? registration = await _registration();
    if (registration == null) return false;
    final web.PushSubscription? subscription =
        await registration.pushManager.getSubscription().toDart;
    if (subscription == null) return false;
    return (await subscription.unsubscribe().toDart).toDart;
  }

  /// Unpadded base64url to bytes, which is what `applicationServerKey` takes.
  static Uint8List _decodeKey(String key) =>
      base64Url.decode(key.padRight((key.length + 3) ~/ 4 * 4, '='));
}
