// The server configuration path URLs require, which nothing wrote.
//
// `dartvel build web` switches the app off Flutter's hash strategy so every
// route has a real URL -- and a real URL has to be served. The generated
// router's own comment says "it needs the server to serve index.html for
// unknown paths, which is what the .htaccess and dartvel deploy configuration
// do", and no .htaccess existed. A build uploaded to Apache answered the
// host's 404 page for anything the build had not prerendered.
import 'package:dartvel_cli/src/build/server_config.dart';
import 'package:test/test.dart';

void main() {
  group('the Apache configuration', () {
    final String config = dvApacheConfig();

    test('an existing file is served as itself', () {
      // Without this the rewrite swallows main.dart.js and every asset, and
      // the page loads index.html as its own JavaScript.
      expect(config, contains('RewriteCond %{REQUEST_FILENAME} -f'));
      expect(config, contains('RewriteCond %{REQUEST_FILENAME} -d'));
    });

    test('anything else falls back to the application', () {
      expect(config, contains('RewriteRule . /index.html [L]'));
    });

    test('it does nothing where mod_rewrite is absent', () {
      // A bare RewriteEngine on a host without the module is a 500, which is
      // a worse failure than the one being fixed.
      expect(config, contains('<IfModule mod_rewrite.c>'));
    });

    test('wasm is served as wasm', () {
      // Flutter loads CanvasKit's wasm with fetch and instantiateStreaming,
      // which refuses anything not served as application/wasm.
      expect(config, contains('application/wasm'));
    });

    test('the entry point is not cached', () {
      // index.html names the hashed bundles. A cached one keeps pointing at
      // the previous deploy's files, which is the deploy that appears to have
      // done nothing.
      expect(config, contains('index.html'));
      expect(config, contains('no-cache'));
    });
  });

  group('what may be cached forever', () {
    // Dots are escaped for the regex, so `main\.dart\.js` is what is
    // written. Matching filenames against the raw text would be matching the
    // escaping rather than the rule.
    final String config = dvApacheConfig().replaceAll(r'\.', '.');

    test('the entry bundles are not', () {
      // Flutter does not content-hash these: main.dart.js is called
      // main.dart.js in every build there has ever been. Marking them
      // immutable for a year means a returning visitor never sees a deploy
      // again -- the site is simply frozen for them, with no error and no
      // way for them to know.
      for (final String never in <String>[
        'main.dart.js',
        'flutter_bootstrap.js',
        'flutter_service_worker.js',
        'version.json',
      ]) {
        expect(config, contains(never),
            reason: '\$never has to be named somewhere that stops it being '
                'cached immutably');
      }
      expect(config, isNot(contains(r'\.(js|wasm|woff2|png|jpg|svg)\$')),
          reason: 'a blanket rule over .js catches main.dart.js');
    });

    test('what Flutter does hash still is', () {
      // canvaskit and the asset bundle carry a version in the path, so they
      // are safe to keep -- and they are the large ones.
      expect(config, contains('canvaskit'));
      expect(config, contains('assets/'));
      expect(config, contains('immutable'));
    });

    test('the service worker is never cached', () {
      // A cached service worker cannot replace itself, which is the one
      // failure with no way out from the visitor's side.
      final int swAt = config.indexOf('flutter_service_worker.js');
      expect(swAt, greaterThan(-1));
      expect(config.substring(swAt).contains('no-cache'), isTrue);
    });
  });
}
