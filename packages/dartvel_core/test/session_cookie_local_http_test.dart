// A session cookie a browser will actually keep.
//
// The cookie is Secure and __Host- outside development, and a browser drops
// a Secure cookie that arrives over plain http. A release binary run on a
// developer's machine -- dartvel build web-server, then ./server -- is
// served over http://localhost, so signing in to Studio set a cookie the
// browser refused and every page after it was signed out, with no error
// anywhere. Whether the cookie can be Secure is a fact about the request,
// not about how the binary was built.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  const DVSessionCookie cookie = DVSessionCookie();

  test('http to a loopback host cannot carry Secure', () {
    for (final String host in <String>['localhost', '127.0.0.1', '[::1]']) {
      expect(
        DVSessionCookie.plainLocal(Uri.parse('http://$host:8093/api/x')),
        isTrue,
        reason: host,
      );
    }
  });

  test('https, or any other host, carries it', () {
    expect(
        DVSessionCookie.plainLocal(Uri.parse('https://localhost:8093/x')),
        isFalse);
    expect(DVSessionCookie.plainLocal(Uri.parse('http://shop.example/x')),
        isFalse);
  });

  test('a proxy that terminated TLS says so, and the cookie stays Secure', () {
    expect(
      DVSessionCookie.plainLocal(Uri.parse('http://localhost:8093/x'),
          forwardedProto: 'https'),
      isFalse,
    );
  });

  test('the header follows that, name and all', () {
    final String local = cookie.header('dvs_abc', development: true);
    final String served = cookie.header('dvs_abc', development: false);

    expect(local, isNot(contains('Secure')));
    expect(local, isNot(contains('__Host-')));
    expect(served, contains('Secure'));
    expect(served, contains('__Host-dv_session'));
  });
}
