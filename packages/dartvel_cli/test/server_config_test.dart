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
}
