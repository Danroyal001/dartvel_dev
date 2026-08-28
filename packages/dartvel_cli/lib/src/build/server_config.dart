/// The server configuration a Dartvel web build needs to actually serve.
library dartvel_cli.build.server_config;

/// An `.htaccess` for Apache, which is what shared hosting runs.
///
/// `dartvel build web` uses path URLs rather than Flutter's hash strategy, so
/// every route is a real URL — and a real URL has to be served. Prerendering
/// writes a file per known route, but a route with a parameter has no file,
/// and neither does anything added after the last build. Without this the
/// host answers its own 404 page.
///
/// Everything here is a rule about failure:
///
///  * the rewrite is guarded by `mod_rewrite`, because a bare `RewriteEngine`
///    on a host without the module is a 500 — a worse failure than the one it
///    fixes;
///  * existing files and directories are served as themselves, or the rewrite
///    swallows `main.dart.js` and the page loads `index.html` as its own
///    JavaScript;
///  * `.wasm` is served as `application/wasm`, because
///    `instantiateStreaming` refuses anything else;
///  * `index.html` is not cached, because it names the hashed bundles and a
///    cached copy keeps pointing at the previous deploy — the deploy that
///    appears to have done nothing.
String dvApacheConfig() => '''
# Written by dartvel build web. Edits are kept: this file is only created when
# it is absent.

<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase /

  # Served as themselves. Without these the fallback below swallows every
  # asset and the page loads index.html as its own JavaScript.
  RewriteCond %{REQUEST_FILENAME} -f [OR]
  RewriteCond %{REQUEST_FILENAME} -d
  RewriteRule ^ - [L]

  # Everything else is a route. The application reads the URL and renders it.
  RewriteRule . /index.html [L]
</IfModule>

<IfModule mod_mime.c>
  # instantiateStreaming refuses a wasm module served as anything else.
  AddType application/wasm .wasm
  AddType application/javascript .js
  AddType application/json .json
</IfModule>

<IfModule mod_headers.c>
  # index.html names the hashed bundles, so a cached copy keeps pointing at
  # the previous deploy's files.
  <FilesMatch "index\\.html\$">
    Header set Cache-Control "no-cache, must-revalidate"
  </FilesMatch>

  # The bundles carry their hash in the name, so they can be kept.
  <FilesMatch "\\.(js|wasm|woff2|png|jpg|svg)\$">
    Header set Cache-Control "public, max-age=31536000, immutable"
  </FilesMatch>
</IfModule>
''';
