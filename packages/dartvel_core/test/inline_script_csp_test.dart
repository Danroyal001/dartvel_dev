// A page's own Content-Security-Policy, built from the inline scripts it is
// about to send (queue 6d9: a proxy pinned hashes of an earlier build's
// scripts, the new ones were refused and the app never booted).
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

String hashOf(String script) =>
    "'sha256-${base64.encode(sha256.convert(utf8.encode(script)).bytes)}'";

void main() {
  group('dvInlineScriptHashes', () {
    test('hashes the exact text of each inline script', () {
      const String page = '<html><head><script>boot(1)</script></head>'
          '<body><script type="module">import "./a.js";</script></body></html>';
      expect(dvInlineScriptHashes(page), <String>[hashOf('boot(1)'), hashOf('import "./a.js";')]);
    });

    test('leaves out scripts a browser never runs inline', () {
      const String page = '<script src="/main.dart.js"></script>'
          '<script type="application/ld+json">{"a":1}</script>'
          '<script type="application/json" id="dv-data">{}</script>'
          '<script type="text/javascript">run()</script>';
      expect(dvInlineScriptHashes(page), <String>[hashOf('run()')]);
    });

    test('a changed script gets a new hash, so a new build is never refused', () {
      final List<String> before = dvInlineScriptHashes('<script>splash(1)</script>');
      final List<String> after = dvInlineScriptHashes('<script>splash(2)</script>');
      expect(before, isNot(after));
      expect(after, <String>[hashOf('splash(2)')]);
    });

    test('the same script twice is listed once', () {
      expect(dvInlineScriptHashes('<script>x()</script><SCRIPT>x()</SCRIPT>'), <String>[hashOf('x()')]);
    });
  });

  group('dvPageContentSecurityPolicy', () {
    test("'inline-scripts' becomes the page's hashes", () {
      expect(
        dvPageContentSecurityPolicy(
          "default-src 'self'; script-src 'self' 'inline-scripts' 'wasm-unsafe-eval'",
          '<script>go()</script>',
        ),
        "default-src 'self'; script-src 'self' ${hashOf('go()')} 'wasm-unsafe-eval'",
      );
    });

    test('a page with no inline script drops the token rather than allowing anything', () {
      expect(
        dvPageContentSecurityPolicy("script-src 'self' 'inline-scripts'", '<p>plain</p>'),
        "script-src 'self'",
      );
    });

    test('a policy without the token is sent as written', () {
      expect(dvPageContentSecurityPolicy("default-src 'self'", '<script>a()</script>'), "default-src 'self'");
    });
  });
}
