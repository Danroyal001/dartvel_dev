bool isChromiumExtension() => false;

bool isFirefoxExtension() => false;

Map<String, Object?> getManifest() => _unavailable();

Future<Object?> sendMessage(Object? message) => _unavailable();

bool supportsFileStorage() => false;

Future<void> fileStoragePut(String key, List<int> bytes) => _unavailable();

Future<List<int>> fileStorageGet(String key) => _unavailable();

Future<void> fileStorageDelete(String key) => _unavailable();

Future<void> tabsCreate(String url, {bool active = true}) => _unavailable();

Never _unavailable() {
  throw StateError(
    'Browser extension APIs are only available inside Chromium or Firefox extension contexts.',
  );
}
