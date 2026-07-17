import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? _apiRoot() {
  final browser = globalContext.getProperty<JSObject?>('browser'.toJS);
  if (_hasRuntime(browser)) return browser;
  final chrome = globalContext.getProperty<JSObject?>('chrome'.toJS);
  if (_hasRuntime(chrome)) return chrome;
  return null;
}

JSObject? _runtime(JSObject? root) =>
    root?.getProperty<JSObject?>('runtime'.toJS);

JSObject? _storageLocal(JSObject root) {
  final storage = root.getProperty<JSObject?>('storage'.toJS);
  return storage?.getProperty<JSObject?>('local'.toJS);
}

bool _hasRuntime(JSObject? root) {
  final runtime = _runtime(root);
  return runtime != null && (runtime.has('id') || runtime.has('getManifest'));
}

bool isChromiumExtension() {
  final chrome = globalContext.getProperty<JSObject?>('chrome'.toJS);
  return _hasRuntime(chrome);
}

bool isFirefoxExtension() {
  final browser = globalContext.getProperty<JSObject?>('browser'.toJS);
  return _hasRuntime(browser) && !isChromiumExtension();
}

Map<String, Object?> getManifest() {
  final runtime = _requiredRuntime();
  final value = runtime.callMethod<JSAny?>('getManifest'.toJS);
  return _objectMap(value);
}

Future<Object?> sendMessage(Object? message) async {
  final runtime = _requiredRuntime();
  final value = runtime.callMethodVarArgs<JSAny?>(
    'sendMessage'.toJS,
    [message.jsify()],
  );
  return _awaitValue(value);
}

Future<Map<String, Object?>> storageLocalGet([List<String>? keys]) async {
  final local = _requiredStorageLocal();
  final args = <JSAny?>[if (keys != null) keys.jsify()];
  final value = local.callMethodVarArgs<JSAny?>('get'.toJS, args);
  return _objectMap(await _awaitValue(value));
}

Future<void> storageLocalSet(Map<String, Object?> values) async {
  final local = _requiredStorageLocal();
  final value = local.callMethodVarArgs<JSAny?>('set'.toJS, [values.jsify()]);
  await _awaitValue(value);
}

Future<void> storageLocalRemove(List<String> keys) async {
  final local = _requiredStorageLocal();
  final value = local.callMethodVarArgs<JSAny?>('remove'.toJS, [keys.jsify()]);
  await _awaitValue(value);
}

Future<void> tabsCreate(String url, {bool active = true}) async {
  final root = _requiredApiRoot();
  final tabs = root.getProperty<JSObject?>('tabs'.toJS);
  if (tabs == null || !tabs.has('create')) {
    throw StateError('Browser extension tabs.create API is not available.');
  }
  final value = tabs.callMethodVarArgs<JSAny?>(
    'create'.toJS,
    [
      <String, Object?>{
        'url': url,
        'active': active,
      }.jsify(),
    ],
  );
  await _awaitValue(value);
}

JSObject _requiredApiRoot() {
  final root = _apiRoot();
  if (root == null) {
    throw StateError(
      'Browser extension APIs are only available inside Chromium or Firefox extension contexts.',
    );
  }
  return root;
}

JSObject _requiredRuntime() {
  final runtime = _runtime(_requiredApiRoot());
  if (runtime == null) {
    throw StateError('Browser extension runtime API is not available.');
  }
  return runtime;
}

JSObject _requiredStorageLocal() {
  final local = _storageLocal(_requiredApiRoot());
  if (local == null) {
    throw StateError('Browser extension storage.local API is not available.');
  }
  return local;
}

FutureOr<Object?> _awaitValue(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) return null;
  try {
    return (value as JSPromise<JSAny?>).toDart.then((resolved) {
      if (resolved == null || resolved.isUndefinedOrNull) return null;
      return resolved.dartify();
    });
  } catch (_) {
    return value.dartify();
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  if (value is JSAny) {
    final dartValue = value.dartify();
    if (dartValue is Map) return Map<String, Object?>.from(dartValue);
  }
  return const <String, Object?>{};
}
