// The Content-Security-Policy a Dartvel server sends with its own pages
// (queue 6d9). On a real socket, because what matters is the header the
// browser gets: a proxy-pinned list of an older build's script hashes is the
// incident this replaces.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

String hashOf(String script) =>
    "'sha256-${base64.encode(sha256.convert(utf8.encode(script)).bytes)}'";

const String policy = "default-src 'self'; script-src 'self' 'inline-scripts' 'wasm-unsafe-eval'";

void main() {
  Headers html() => Headers(<String, String>{'content-type': 'text/html; charset=utf-8'});
  Router app() => Router()
    ..get('/one', (Request req) async => Response.text('<html><head><script>splash(1)</script></head><body>one</body></html>', headers: html()))
    ..get('/two', (Request req) async => Response.text('<html><head><script>splash(2)</script></head><body>two</body></html>', headers: html()))
    ..get('/streamed', (Request req) async => Response.stream((sink) {
          sink.add(utf8.encode('<html><head><script>streamed()</script></head>'));
          sink.add(utf8.encode('<body>late</body></html>'));
          sink.close();
        }, headers: html()))
    ..get('/data', (Request req) async => Response.json(<String, Object?>{'a': 1}))
    ..get('/own', (Request req) async => Response.text('<script>x()</script>',
        headers: Headers(<String, String>{'content-type': 'text/html', 'content-security-policy': "default-src 'none'"})));

  Future<(HttpHeaders, String)> get(int port, String path) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'))).close();
      return (response.headers, await response.transform(utf8.decoder).join());
    } finally {
      client.close(force: true);
    }
  }

  test("each page's policy lists that page's own inline scripts", () async {
    final ServerHandle server = await serve(app().call, port: 0, pageContentSecurityPolicy: policy);
    addTearDown(server.stop);
    final (HttpHeaders one, String oneBody) = await get(server.port, '/one');
    final (HttpHeaders two, _) = await get(server.port, '/two');
    expect(one.value('content-security-policy'),
        "default-src 'self'; script-src 'self' ${hashOf('splash(1)')} 'wasm-unsafe-eval'");
    expect(two.value('content-security-policy'), contains(hashOf('splash(2)')),
        reason: 'a changed script is allowed by the policy sent with it');
    expect(two.value('content-security-policy'), isNot(contains(hashOf('splash(1)'))));
    expect(oneBody, contains('splash(1)'), reason: 'the body arrives whole after being read for its hashes');
  });

  test('a streamed page gets the hashes of the scripts in its first part', () async {
    final ServerHandle server = await serve(app().call, port: 0, pageContentSecurityPolicy: policy);
    addTearDown(server.stop);
    final (HttpHeaders headers, String body) = await get(server.port, '/streamed');
    expect(headers.value('content-security-policy'), contains(hashOf('streamed()')));
    expect(body, '<html><head><script>streamed()</script></head><body>late</body></html>');
  });

  test('only pages get it, and a policy a route set is kept', () async {
    final ServerHandle server = await serve(app().call, port: 0, pageContentSecurityPolicy: policy);
    addTearDown(server.stop);
    expect((await get(server.port, '/data')).$1.value('content-security-policy'), isNull);
    expect((await get(server.port, '/own')).$1.value('content-security-policy'), "default-src 'none'");
  });

  test('without a policy nothing is sent, as before', () async {
    final ServerHandle server = await serve(app().call, port: 0);
    addTearDown(server.stop);
    expect((await get(server.port, '/one')).$1.value('content-security-policy'), isNull);
  });
}
