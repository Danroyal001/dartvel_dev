// One set of security headers. The `securityHeaders` middleware a route opts
// into starts from the framework default (dvDefaultSecurityHeaders) and states
// only what it adds, so the two cannot drift apart.
//
// They had: the middleware sent its own list, with an HSTS
// `includeSubDomains` the default refuses on purpose -- a framework cannot
// know what else runs under the same domain, and preloading a sibling
// subdomain into HTTPS-only can take it offline.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<Map<String, String>> middlewareHeaders() async {
  final MiddlewareContext context = MiddlewareContext();
  await Middleware.securityHeaders()(Object(), context);
  return <String, String>{
    for (final MapEntry<Object?, Object?> e
        in (context.data['securityHeaders']! as Map<Object?, Object?>).entries)
      '${e.key}'.toLowerCase(): '${e.value}',
  };
}

void main() {
  test('every default header is there, with the default value unless the '
      'middleware says it is stricter', () async {
    final Map<String, String> headers = await middlewareHeaders();
    for (final MapEntry<String, String> d in dvDefaultSecurityHeaders.entries) {
      expect(headers, contains(d.key), reason: d.key);
      if (d.key != 'x-frame-options') expect(headers[d.key], d.value, reason: d.key);
    }
  });

  test('what it adds: no framing at all, and the XSS filter off', () async {
    final Map<String, String> headers = await middlewareHeaders();
    expect(headers['x-frame-options'], 'DENY');
    expect(headers['x-xss-protection'], '0');
  });

  test('HSTS is the default one, never includeSubDomains', () async {
    final Map<String, String> headers = await middlewareHeaders();
    expect(headers['strict-transport-security'], dvDefaultStrictTransportSecurity);
    expect(headers['strict-transport-security'], isNot(contains('includeSubDomains')));
  });
}
