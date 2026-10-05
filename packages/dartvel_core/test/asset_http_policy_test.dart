// How long a browser and a shared cache (a CDN, a proxy) may keep what the
// server sends, by what it is. Declared under dartvel.web.server.http in
// pubspec.yaml and carried to the server in its manifest.
import 'package:dartvel_core/dartvel.dart' show DVWebServerSettings;
import 'package:dartvel_core/src/web/asset_http_policy.dart';
import 'package:test/test.dart';

void main() {
  const DVAssetHttpPolicy defaults = DVAssetHttpPolicy();

  group('by default', () {
    test('a file whose name carries its content hash is kept for a year', () {
      for (final String path in <String>[
        'assets/app.3f2a9c1b.js',
        'main-5d41402abc4b2a76.css',
        'chunk_0a1b2c3d4e5f.js',
        'img/logo.9e107d9d372bb682.png',
      ]) {
        expect(defaults.cacheControl(path), 'public, max-age=31536000, immutable', reason: path);
      }
    });

    test('a file whose name does not is revalidated every time', () {
      // Flutter's own output: the same name in every build, a new body after
      // a deploy. Kept a minute, a browser would pair a new main.dart.js with
      // the previous build's parts.
      for (final String path in <String>[
        'main.dart.js',
        'main.dart.js_105.part.js',
        'canvaskit/canvaskit.wasm',
        'flutter_bootstrap.js',
        'icons/20260930.png',
        'deadbeefcafe.txt',
        'assets/fonts/MaterialIcons-Regular.otf',
      ]) {
        expect(defaults.cacheControl(path), 'public, no-cache', reason: path);
      }
    });

    test('a document is revalidated, not stored for a set time', () {
      expect(defaults.cacheControl('index.html'), 'no-cache');
      expect(defaults.cacheControl('404.html'), 'no-cache');
      expect(defaults.documents, 'no-cache');
    });

    test('a protected file is never stored by anything', () {
      expect(defaults.cacheControl('main.dart.js', protected: true), 'private, no-store');
      expect(defaults.cacheControl('app.3f2a9c1b.js', protected: true), 'private, no-store');
    });
  });

  group('declared', () {
    test('a max age and a shared-cache max age for files that are not hashed', () {
      final DVAssetHttpPolicy policy = DVAssetHttpPolicy.parse(<String, Object?>{
        'maxAge': 60,
        'sMaxAge': 3600,
        'staleWhileRevalidate': 30,
      });
      expect(policy.cacheControl('main.dart.js'),
          'public, max-age=60, s-maxage=3600, stale-while-revalidate=30');
      // Hashed files stay immutable, and protected ones stay private.
      expect(policy.cacheControl('app.3f2a9c1b.js'), 'public, max-age=31536000, immutable');
      expect(policy.cacheControl('main.dart.js', protected: true), 'private, no-store');
    });

    test('paths that never change under their name', () {
      final DVAssetHttpPolicy policy = DVAssetHttpPolicy.parse(<String, Object?>{
        'immutable': <String>['canvaskit/**', 'fonts/*.ttf'],
      });
      expect(policy.cacheControl('canvaskit/chromium/canvaskit.wasm'), 'public, max-age=31536000, immutable');
      expect(policy.cacheControl('fonts/Manrope.ttf'), 'public, max-age=31536000, immutable');
      expect(policy.cacheControl('fonts/sub/Manrope.ttf'), 'public, no-cache');
      expect(policy.cacheControl('main.dart.js'), 'public, no-cache');
    });

    test('what a document is sent with', () {
      expect(DVAssetHttpPolicy.parse(<String, Object?>{'documents': 'public, max-age=0, s-maxage=30'})
          .cacheControl('index.html'), 'public, max-age=0, s-maxage=30');
    });

    test('a value that is not what it should be is the default, not an error', () {
      final DVAssetHttpPolicy policy = DVAssetHttpPolicy.parse(<String, Object?>{
        'maxAge': 'soon',
        'sMaxAge': -5,
        'immutable': 'canvaskit/**',
        'documents': 7,
        'memoryCacheMB': 'lots',
      });
      expect(policy.cacheControl('main.dart.js'), 'public, no-cache');
      expect(policy.cacheControl('index.html'), 'no-cache');
      expect(policy.memoryCacheBytes, defaults.memoryCacheBytes);
    });

    test('the in-memory cache and the disk cache can be sized or turned off', () {
      final DVAssetHttpPolicy policy =
          DVAssetHttpPolicy.parse(<String, Object?>{'memoryCacheMB': 4, 'diskCache': false});
      expect(policy.memoryCacheBytes, 4 * 1024 * 1024);
      expect(policy.diskCache, isFalse);
    });
  });

  test('it travels to the server in the manifest and reads back the same', () {
    final DVWebServerSettings settings = DVWebServerSettings.parse(<String, Object?>{
      'http': <String, Object?>{'maxAge': 5, 'immutable': <String>['canvaskit/**'], 'diskCache': false},
    });
    final DVWebServerSettings back = DVWebServerSettings.parse(settings.toJson());
    expect(back.http.cacheControl('main.dart.js'), 'public, max-age=5');
    expect(back.http.cacheControl('canvaskit/skwasm.wasm'), 'public, max-age=31536000, immutable');
    expect(back.http.diskCache, isFalse);
    // A manifest from before the setting reads as the defaults.
    expect(DVWebServerSettings.parse(<String, Object?>{}).http.cacheControl('main.dart.js'),
        'public, no-cache');
    expect(DVWebServerSettings.parse(const <String, Object?>{}).toJson().containsKey('http'), isFalse,
        reason: 'the defaults are not written, so an older server reads the manifest as it did');
  });
}
