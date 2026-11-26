/// A browser: the timers in `localStorage`, a chime from Web Audio and a
/// notification through the service worker, whose buttons snooze.
///
/// A page cannot ring once the browser is closed: nothing on the web runs a
/// timer then (Notification Triggers never shipped, and a service worker is
/// stopped within seconds of going idle). So [DVTimerReach.whileOpen], which
/// covers a background tab, a minimised window and an installed app's
/// window, and the application says so.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'timer.dart';
import 'timer_basic_delivery.dart' show dvTimerDoneBody;
import 'timer_delivery.dart';

String _key(String app) => 'dartvel.timers.$app';

DVTimerStore dvPlatformTimerStore(String app) => _LocalStorage(_key(app));

DVTimerDelivery dvPlatformTimerDelivery({required bool declared}) => _WebDelivery();

/// Another tab writing the same key fires `storage` here.
void dvTimerWatchStore(String app, void Function() changed) {
  try {
    web.window.addEventListener(
        'storage',
        ((web.StorageEvent event) {
          if (event.key == _key(app)) changed();
        }).toJS);
  } on Object {
    // No window (a worker): nothing to watch.
  }
}

final class _LocalStorage implements DVTimerStore {
  _LocalStorage(this._key);

  final String _key;
  String? _fallback;

  @override
  String? read() {
    try {
      return web.window.localStorage.getItem(_key);
    } on Object {
      return _fallback;
    }
  }

  @override
  void write(String value) {
    _fallback = value;
    try {
      web.window.localStorage.setItem(_key, value);
    } on Object {
      // Storage refused (a private window, a full quota): the timers hold
      // for this visit.
    }
  }
}

/// The query a service worker opens the app with when a notification button
/// is pressed and no window of the app is left.
const String _launchTimer = 'dartvel-timer';
const String _launchAction = 'dartvel-timer-action';

final class _WebDelivery implements DVTimerDelivery {
  _WebDelivery() {
    try {
      web.window.navigator.serviceWorker.addEventListener(
          'message', ((web.MessageEvent event) => _onMessage(event.data)).toJS);
    } on Object {
      // No service worker (an insecure origin, a private window in some
      // browsers): notifications still show, without buttons.
    }
    scheduleMicrotask(_readLaunch);
  }

  final StreamController<DVTimerAction> _actions = StreamController<DVTimerAction>.broadcast();
  web.AudioContext? _audio;
  final Map<String, web.GainNode> _sounding = <String, web.GainNode>{};

  @override
  DVTimerReach get reach => .whileOpen;

  @override
  Stream<DVTimerAction> get actions => _actions.stream;

  bool get _hasNotifications => globalContext.has('Notification');

  @override
  Future<DVTimerPermission> permission() async {
    if (!_hasNotifications) return .unsupported;
    return switch (web.Notification.permission) {
      'granted' => .granted,
      'denied' => .denied,
      _ => .notAsked,
    };
  }

  @override
  Future<DVTimerPermission> requestPermission() async {
    if (!_hasNotifications) return .unsupported;
    try {
      final String answer = (await web.Notification.requestPermission().toDart).toDart;
      return answer == 'granted' ? .granted : (answer == 'denied' ? .denied : .notAsked);
    } on Object {
      return permission();
    }
  }

  @override
  void prime() {
    try {
      final web.AudioContext audio = _audio ??= web.AudioContext();
      // Resumed from the gesture: an audio context opened later, when the
      // timer rings, would be suspended and silent.
      unawaited(audio.resume().toDart.then((_) {}, onError: (Object _) {}));
    } on Object {
      _audio = null;
    }
  }

  @override
  Future<void> schedule(DVTimer timer) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> ring(DVTimer timer) async {
    _chime(timer.id);
    _vibrate();
    await _notify(timer);
  }

  @override
  Future<void> silence(String id) async {
    final web.GainNode? gain = _sounding.remove(id);
    if (gain != null) {
      try {
        gain.disconnect();
      } on Object {
        // Already gone.
      }
    }
    try {
      final web.ServiceWorkerRegistration? registration =
          await web.window.navigator.serviceWorker.getRegistration().toDart;
      if (registration == null) return;
      final JSArray<web.Notification> shown =
          await registration.getNotifications(web.GetNotificationOptions(tag: _tag(id))).toDart;
      for (final web.Notification notification in shown.toDart) {
        notification.close();
      }
    } on Object {
      // No service worker: a page notification closes itself when clicked.
    }
  }

  static String _tag(String id) => 'dartvel-timer-$id';

  /// Three short notes every two seconds for a minute: long enough to be
  /// heard across a kitchen, short enough not to play to an empty room all
  /// evening. Scheduled up front on the audio clock, so a throttled
  /// background tab still plays it on time.
  void _chime(String id) {
    final web.AudioContext? audio = _audio;
    if (audio == null) return;
    try {
      unawaited(audio.resume().toDart.then((_) {}, onError: (Object _) {}));
      final web.GainNode gain = audio.createGain()..connect(audio.destination);
      gain.gain.value = 0.25;
      final double start = audio.currentTime + 0.05;
      for (int round = 0; round < 30; round++) {
        for (int note = 0; note < 3; note++) {
          final double at = start + round * 2 + note * 0.22;
          final web.OscillatorNode tone = audio.createOscillator()
            ..type = 'sine'
            ..connect(gain);
          tone.frequency.value = note == 2 ? 1175 : 880;
          tone.start(at);
          tone.stop(at + 0.16);
        }
      }
      _sounding.remove(id)?.disconnect();
      _sounding[id] = gain;
    } on Object {
      // Audio blocked: the notification still shows.
    }
  }

  void _vibrate() {
    try {
      web.window.navigator.vibrate(<JSNumber>[400.toJS, 200.toJS, 400.toJS, 200.toJS, 800.toJS].toJS);
    } on Object {
      // No vibration motor, or Safari.
    }
  }

  Future<void> _notify(DVTimer timer) async {
    if (await permission() != .granted) return;
    final int maxActions = _maxActions();
    final List<web.NotificationAction> buttons = <web.NotificationAction>[
      web.NotificationAction(action: 'snooze-1', title: '+1 min'),
      web.NotificationAction(action: 'snooze-5', title: '+5 min'),
      web.NotificationAction(action: 'dismiss', title: 'Dismiss'),
    ].take(maxActions).toList();
    final JSObject data = JSObject()
      ..['dartvelTimer'] = timer.id.toJS
      ..['url'] = (timer.route ?? '/').toJS;
    final web.NotificationOptions options = web.NotificationOptions(
      body: dvTimerDoneBody(timer),
      tag: _tag(timer.id),
      renotify: true,
      requireInteraction: true,
      data: data,
      actions: buttons.toJS,
    );
    try {
      final web.ServiceWorkerRegistration? registration =
          await web.window.navigator.serviceWorker.getRegistration().toDart;
      if (registration != null) {
        await registration.showNotification(timer.label, options).toDart;
        return;
      }
    } on Object {
      // Fall through to a page notification.
    }
    try {
      // A page notification cannot carry buttons; a click focuses the page
      // and stops the timer, as the worker's would.
      final web.Notification shown = web.Notification(
          timer.label, web.NotificationOptions(body: dvTimerDoneBody(timer), tag: _tag(timer.id), requireInteraction: true));
      shown.onclick = ((web.Event _) {
        web.window.focus();
        _actions.add(DVTimerAction(timer.id, .open));
        shown.close();
      }).toJS;
    } on Object {
      // Chrome on Android has no page notifications, only the worker's.
    }
  }

  static int _maxActions() {
    try {
      final JSObject notification = globalContext['Notification']! as JSObject;
      final JSAny? max = notification['maxActions'];
      return max.isA<JSNumber>() ? (max! as JSNumber).toDartInt : 2;
    } on Object {
      return 2;
    }
  }

  void _onMessage(JSAny? data) {
    if (data == null || !data.isA<JSObject>()) return;
    final JSObject message = data as JSObject;
    if (_string(message['type']) != 'dartvel-timer') return;
    final DVTimerAction? action = dvTimerActionFrom(_string(message['id']), _string(message['action']));
    if (action != null) _actions.add(action);
  }

  static String _string(JSAny? value) => value != null && value.isA<JSString>() ? (value as JSString).toDart : '';

  /// The app opened by a notification button after every window was closed:
  /// apply it, then take the query off the address so a reload does not
  /// snooze again.
  void _readLaunch() {
    try {
      final web.URL url = web.URL(web.window.location.href);
      final String? id = url.searchParams.get(_launchTimer);
      if (id == null) return;
      final DVTimerAction? action = dvTimerActionFrom(id, url.searchParams.get(_launchAction) ?? 'open');
      url.searchParams.delete(_launchTimer);
      url.searchParams.delete(_launchAction);
      web.window.history.replaceState(web.window.history.state, '', url.href);
      if (action != null) _actions.add(action);
    } on Object {
      // A malformed address: nothing to apply.
    }
  }
}
