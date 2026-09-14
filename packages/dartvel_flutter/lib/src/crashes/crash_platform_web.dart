/// Crash hooks and storage in a browser.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_core/dartvel.dart';

import '../platform/web/web_interop.dart';
import 'crash_directory.dart';
import 'crash_hook.dart';

/// Listens to the window's `error` and `unhandledrejection` events.
///
/// Both carry text rather than a Dart object, and an error that also reached
/// `PlatformDispatcher.onError` is matched by its description and stack and
/// recorded once.
void Function() dvInstallPlatformCrashHooks(DVCrashTextReceiver receive) {
  final JSObject window = globalContext;
  final JSFunction? add = dvJsMethod(window, 'addEventListener');
  final JSFunction? remove = dvJsMethod(window, 'removeEventListener');
  if (add == null || remove == null) return () {};

  final JSFunction onError = ((JSObject event) {
    final JSObject? error = dvJsObject(event, 'error');
    if (error != null) {
      receive(_describe(error), dvJsString(error, 'stack') ?? '',
          DVCrashHook.windowError);
      return;
    }
    // A cross-origin script's error reaches the page as "Script error." with
    // no object; where it came from is all there is.
    receive(
      dvJsString(event, 'message') ?? 'Script error.',
      '${dvJsString(event, 'filename') ?? ''}:'
          '${dvJsNum(event, 'lineno') ?? 0}:${dvJsNum(event, 'colno') ?? 0}',
      DVCrashHook.windowError,
    );
  }).toJS;

  final JSFunction onRejection = ((JSObject event) {
    final JSAny? reason = dvJsValue(event, 'reason');
    if (reason.isA<JSObject>()) {
      final JSObject object = reason! as JSObject;
      receive(_describe(object), dvJsString(object, 'stack') ?? '',
          DVCrashHook.unhandledRejection);
      return;
    }
    receive('Unhandled promise rejection: ${reason.dartify()}', '',
        DVCrashHook.unhandledRejection);
  }).toJS;

  add.callAsFunction(window, 'error'.toJS, onError);
  add.callAsFunction(window, 'unhandledrejection'.toJS, onRejection);
  return () {
    remove.callAsFunction(window, 'error'.toJS, onError);
    remove.callAsFunction(window, 'unhandledrejection'.toJS, onRejection);
  };
}

String _describe(JSObject error) {
  final String? message = dvJsString(error, 'message');
  final String name = dvJsString(error, 'name') ?? 'Error';
  return message == null ? name : '$name: $message';
}

/// `localStorage`, which is synchronous: the one thing a crash handler needs
/// from where it writes.
final class _LocalStorage implements DVCrashKeyValue {
  _LocalStorage(this._storage);

  final JSObject _storage;

  @override
  String? read(String key) {
    final JSAny? value = _storage.callMethod<JSAny?>('getItem'.toJS, key.toJS);
    return value.isA<JSString>() ? (value! as JSString).toDart : null;
  }

  @override
  void write(String key, String value) =>
      _storage.callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);

  @override
  void delete(String key) =>
      _storage.callMethod<JSAny?>('removeItem'.toJS, key.toJS);

  @override
  Iterable<String> get keys {
    final int length = dvJsNum(_storage, 'length')?.toInt() ?? 0;
    return <String>[
      for (int i = 0; i < length; i++)
        if (_storage.callMethod<JSAny?>('key'.toJS, i.toJS)
            case final JSAny key when key.isA<JSString>())
          (key as JSString).toDart,
    ];
  }
}

/// Kept in `localStorage` beside the records, so clearing site data resets
/// both together.
String dvInstallId(String appId) {
  JSObject? storage;
  try {
    storage = dvJsObject(globalContext, 'localStorage');
  } on Object {
    storage = null;
  }
  final JSObject? held = storage;
  if (held == null) {
    return dvInstallIdFrom(read: () => null, write: (String _) {});
  }
  final _LocalStorage local = _LocalStorage(held);
  final String key = 'dartvel.$appId.installId';
  return dvInstallIdFrom(
    read: () => local.read(key),
    write: (String id) => local.write(key, id),
  );
}

DVCrashStore? dvDefaultCrashStore(String appId) {
  // Reading localStorage throws in a sandboxed frame and where site data is
  // blocked; that is a page with nowhere to keep a report, not a crash.
  try {
    final JSObject? storage = dvJsObject(globalContext, 'localStorage');
    if (storage == null) return null;
    return DVKeyValueCrashStore(
      _LocalStorage(storage),
      prefix: 'dartvel.$appId.crash.',
    );
  } on Object {
    return null;
  }
}

bool dvHostedByTestRunner() => false;
