// An absolute URL is a request to a host, and a host is declared.
//
// DV-HTTP-001 used to fire only for a name: DV.Http.host('paystak') was
// refused, while DV.Http.get('https://api.paystak.co/...') went straight out
// with no timeout of its own, no breaker and nobody's decision about it. That
// made the declaration optional in exactly the way the section says it is
// not, and made a typo in a URL the one kind of typo nothing catches.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Wire {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];
  int status = 200;

  Future<DVHttpStreamedResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return DVHttpStreamedResponse(
      statusCode: status,
      headers: const <String, String>{},
      body: const Stream<List<int>>.empty(),
    );
  }
}

Matcher _undeclared(String host) => throwsA(
      isA<DVHttpUndeclaredHostException>()
          .having((e) => e.code, 'code', 'DV-HTTP-001')
          .having((e) => e.host, 'host', host),
    );

void main() {
  const DVHttp http = DVHttp();
  late _Wire wire;

  setUp(() {
    DVHttp.reset();
    DVSecrets.reset();
    wire = _Wire();
    DVHttp.transport = wire.send;
    DVHttp.sleep = (Duration _) async {};
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  group('an absolute URL no declared host covers', () {
    test('is refused with DV-HTTP-001, and nothing is sent', () async {
      http.declare('paystack',
          const DVHttpHostConfig(baseUrl: 'https://api.paystack.co'));

      await expectLater(
        http.get('https://api.paystak.co/transaction/verify/1'),
        _undeclared('api.paystak.co'),
      );
      expect(wire.requests, isEmpty);
    });

    test('is refused with nothing declared at all', () async {
      await expectLater(
          http.post('https://example.com/hook', body: 'x'),
          _undeclared('example.com'));
      expect(wire.requests, isEmpty);
    });

    test('is refused while faked, even with a stub for its host', () async {
      // A test that passes on a call production refuses has tested a program
      // nobody runs.
      final DVHttpFake fake = http.fake(<String, DVHttpStub>{
        'api.example.com': DVHttpStub.status(200),
      });
      await expectLater(
          http.get('https://api.example.com/v1'), _undeclared('api.example.com'));
      expect(fake.calls, isEmpty);
    });

    test('is refused when only the scheme, the port or the path differs',
        () async {
      // The declaration is the base URL, not the host name: credentials
      // declared for https are not sent over plain http, nor to another port
      // or another API mounted beside the declared one.
      http.declare('partner',
          const DVHttpHostConfig(baseUrl: 'https://partner.example.com/api/v2'));

      for (final String url in <String>[
        'http://partner.example.com/api/v2/orders',
        'https://partner.example.com:8443/api/v2/orders',
        'https://partner.example.com/api/v1/orders',
        'https://partner.example.com/api/v2x/orders',
        'https://partner.example.com.evil.test/api/v2/orders',
      ]) {
        await expectLater(http.get(url), throwsA(isA<DVHttpUndeclaredHostException>()),
            reason: url);
      }
      expect(wire.requests, isEmpty);
    });
  });

  group('an absolute URL under a declared base URL', () {
    test('is sent as that host: its credential, its retries, its name',
        () async {
      DVSecrets.configure(<String, String>{'PARTNER_TOKEN': 'tok_1'});
      http.declare(
        'partner',
        const DVHttpHostConfig(
          baseUrl: 'https://partner.example.com/api/v2/',
          bearerSecret: 'PARTNER_TOKEN',
          retries: DVHttpRetryPolicy(attempts: 1),
        ),
      );
      wire.status = 503;

      final Response response =
          await http.get('https://PARTNER.example.com:443/api/v2/orders?page=2');

      expect(response.status, 503);
      expect(wire.requests, hasLength(1),
          reason: 'the host declares one attempt, and the URL is that host');
      expect(wire.requests.single.headers['authorization'], 'Bearer tok_1');
    });

    test('a stub answers it by the declared name', () async {
      http.declare('partner',
          const DVHttpHostConfig(baseUrl: 'https://partner.example.com'));
      final DVHttpFake fake = http.fake(<String, DVHttpStub>{
        'partner': DVHttpStub.status(204),
      });

      expect((await http.get('https://partner.example.com/ping')).status, 204);
      expect(fake.calls.single.host, 'partner');
    });

    test('the longest declared base URL is the one it belongs to', () async {
      DVSecrets.configure(<String, String>{'V1': 'one', 'V2': 'two'});
      http
        ..declare(
            'root',
            const DVHttpHostConfig(
                baseUrl: 'https://partner.example.com', bearerSecret: 'V1'))
        ..declare(
            'v2',
            const DVHttpHostConfig(
                baseUrl: 'https://partner.example.com/v2', bearerSecret: 'V2'));

      await http.get('https://partner.example.com/v2/orders');
      await http.get('https://partner.example.com/v3/orders');

      expect(wire.requests.map((DVHttpRequest r) => r.headers['authorization']),
          <String>['Bearer two', 'Bearer one']);
    });
  });

  group('allowUndeclaredHost', () {
    test('sends to a URL nobody could have declared, on the default policy',
        () async {
      final Response response = await http.send(
        'POST',
        'https://hooks.customer.test/in',
        body: '{}',
        allowUndeclaredHost: true,
      );
      expect(response.status, 200);
      expect(wire.requests.single.url.host, 'hooks.customer.test');
    });

    test('never lends a declared host its credential', () async {
      // The reason it cannot simply fall back to the declaration. The URL on
      // this path is somebody else's data -- a webhook subscriber's endpoint
      // -- and one pointed at the payment gateway's own API must not arrive
      // there carrying the application's secret key.
      DVSecrets.configure(<String, String>{'PAYSTACK_SECRET_KEY': 'sk_live'});
      http.declare(
        'paystack',
        const DVHttpHostConfig(
          baseUrl: 'https://api.paystack.co',
          bearerSecret: 'PAYSTACK_SECRET_KEY',
        ),
      );

      await http.send('POST', 'https://api.paystack.co/refund',
          body: '{}', allowUndeclaredHost: true);

      expect(wire.requests.single.headers.containsKey('authorization'), isFalse);
    });

    test('keeps a connection pinned to the address its caller checked',
        () async {
      await http.send('POST', 'https://hooks.customer.test/in',
          body: '{}', connectAddress: '203.0.113.7', allowUndeclaredHost: true);
      expect(wire.requests.single.connectAddress, '203.0.113.7');
    });
  });
}
