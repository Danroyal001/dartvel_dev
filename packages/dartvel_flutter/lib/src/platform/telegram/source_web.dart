import 'dart:async';
import 'dart:js_interop';

import '../web/web_interop.dart';
import 'types.dart';

DVTelegramBridge? _bridge;
DVTelegramBridge? dvTelegramBridge() {
  final telegram = dvJsObject(globalContext, 'Telegram');
  final app = telegram == null ? null : dvJsObject(telegram, 'WebApp');
  if (app == null ||
      dvJsString(app, 'platform') == 'unknown' ||
      dvJsString(app, 'platform') == null) {
    return null;
  }
  return _bridge ??= _WebTelegram(app);
}

class _WebTelegram implements DVTelegramBridge {
  _WebTelegram(this.app);
  final JSObject app;
  final Map<String, Stream<void>> _events = {};
  String? _qrText;
  @override
  Object? read(String name) =>
      name == '_qrText' ? _qrText : dvJsValue(app, name).dartify();
  (JSObject, String) _resolve(String name) {
    final parts = name.split('.');
    var owner = app;
    for (final part in parts.take(parts.length - 1)) {
      final next = dvJsObject(owner, part);
      if (next == null) {
        throw UnsupportedError(
          'Telegram does not support $name on this client',
        );
      }
      owner = next;
    }
    if (dvJsMethod(owner, parts.last) == null) {
      throw UnsupportedError('Telegram does not support $name on this client');
    }
    return (owner, parts.last);
  }

  @override
  Future<Object?> call(
    String name,
    List<Object?> arguments, {
    bool callback = false,
    bool errorFirst = false,
  }) async {
    final (owner, method) = _resolve(name);
    final args = arguments.map((v) => v.jsify()).toList();
    if (!callback) {
      await dvJsCall(owner, method, args);
      return null;
    }
    final result = Completer<Object?>();
    final JSFunction done;
    if (errorFirst) {
      done = ((JSAny? error, [JSAny? value, JSAny? extra]) {
        if (result.isCompleted) return;
        if (error != null) {
          result.completeError(
            StateError('Telegram $name: ${error.dartify()}'),
          );
        } else {
          result.complete(value.dartify());
        }
      }).toJS;
    } else {
      done = ((JSAny? value) {
        if (!result.isCompleted) result.complete(value.dartify());
      }).toJS;
    }
    args.add(done);
    await dvJsCall(owner, method, args);
    return result.future.timeout(const Duration(minutes: 2));
  }

  @override
  Stream<void> event(String name) => _events.putIfAbsent(name, () {
    late final StreamController<void> controller;
    final callback = (([JSAny? data]) {
      if (name == 'qrTextReceived') {
        final raw = data.dartify();
        _qrText = raw is Map ? raw['data'] as String? : null;
      }
      controller.add(null);
    }).toJS;
    final names = name == 'viewportChanged'
        ? [
            'viewportChanged',
            'safeAreaChanged',
            'contentSafeAreaChanged',
            'fullscreenChanged',
          ]
        : [name];
    controller = StreamController<void>.broadcast(
      sync: true,
      onListen: () {
        for (final event in names) {
          unawaited(dvJsCall(app, 'onEvent', [event.toJS, callback]));
        }
      },
      onCancel: () {
        for (final event in names) {
          unawaited(dvJsCall(app, 'offEvent', [event.toJS, callback]));
        }
      },
    );
    return controller.stream;
  });
}
