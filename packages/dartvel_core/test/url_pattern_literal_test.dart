// A route pattern with no parameter in it is compared with the path rather
// than run as a regular expression. It must still match exactly what the
// regular expression did: that one path, its characters taken literally.
import 'package:dartvel_core/http.dart';
import 'package:test/test.dart';

bool _matches(String pattern, String path) =>
    URLPattern(pattern).exec(Uri.parse('http://localhost$path')) != null;

void main() {
  test('a literal pattern matches its own path and nothing else', () {
    expect(_matches('/plaintext', '/plaintext'), isTrue);
    expect(_matches('/plaintext', '/plaintext/'), isFalse);
    expect(_matches('/plaintext', '/plaintextx'), isFalse);
    expect(_matches('/plaintext', '/x/plaintext'), isFalse);
    expect(_matches('/', '/'), isTrue);
    expect(_matches('/', '/a'), isFalse);
  });

  test('characters a regular expression gives meaning are literal', () {
    expect(_matches('/a.b', '/a.b'), isTrue);
    expect(_matches('/a.b', '/axb'), isFalse);
    expect(_matches('/files/*', '/files/*'), isTrue);
    expect(_matches('/files/*', '/files/anything'), isFalse);
    expect(_matches('/(x)', '/(x)'), isTrue);
  });

  test('a literal match has no parameters; a named one still does', () {
    expect(URLPattern('/json').exec(Uri.parse('http://h/json'))!.pathname,
        isEmpty);
    expect(
        URLPattern('/echo/:n').exec(Uri.parse('http://h/echo/7'))!.pathname,
        <String, String>{'n': '7'});
    expect(
        URLPattern('/echo/<n>').exec(Uri.parse('http://h/echo/7'))!.pathname,
        <String, String>{'n': '7'});
  });
}
