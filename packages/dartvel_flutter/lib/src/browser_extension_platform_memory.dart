bool isChromiumExtension() => false;

bool isFirefoxExtension() => false;

Map<String, Object?> getManifest() => _unavailable();

Future<Object?> sendMessage(Object? message) => _unavailable();

Future<Map<String, Object?>> storageLocalGet([List<String>? keys]) =>
    _unavailable();

Future<void> storageLocalSet(Map<String, Object?> values) => _unavailable();

Future<void> storageLocalRemove(List<String> keys) => _unavailable();

Future<void> tabsCreate(String url, {bool active = true}) => _unavailable();

Never _unavailable() {
  throw StateError(
    'Browser extension APIs are only available inside Chromium or Firefox extension contexts.',
  );
}
