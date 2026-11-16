// "Is this request signed in?" is asked one way. DVSessionAuthentication
// .ofRequest(request) reads the authorization header, the cookie, whether the
// request is plain local, and the host the session is scoped to -- the call
// that was assembled by hand in Studio's API, the data-model API, the admin
// dashboard, the generated backend and the preview, and had started to read
// the host differently in one of them.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/http.dart';
import 'package:test/test.dart';

Request request({String? authorization, String? cookie}) => Request(
      method: 'GET',
      url: Uri.parse('https://shop.example/api/admin'),
      headers: Headers(<String, String>{
        'host': 'shop.example',
        if (authorization != null) 'authorization': authorization,
        if (cookie != null) 'cookie': cookie,
      }),
      bodyStream: const Stream<List<int>>.empty(),
    );

Future<DVSessionAuthenticationResult> byHand(Request r) =>
    DVSessionAuthentication.authenticateRequest(
      plainLocal: DVSessionCookie.plainLocal(r.url,
          forwardedProto: r.headers.get('x-forwarded-proto'), host: r.headers.get('host')),
      authorization: r.headers.get('authorization'),
      cookie: r.headers.get('cookie'),
      host: DVSessionScope.requestHost(r),
    );

void main() {
  setUp(DVSessionAuthentication.uninstall);

  test('it answers as the hand-built call does, credential or none', () async {
    for (final Request r in <Request>[
      request(),
      request(authorization: 'Bearer abc.def'),
      request(cookie: '__Host-dv_session=abc'),
    ]) {
      final DVSessionAuthenticationResult one = await DVSessionAuthentication.ofRequest(r);
      final DVSessionAuthenticationResult two = await byHand(r);
      expect(one.refused, two.refused);
      expect(one.status, two.status);
      expect(one.principal?.userId, two.principal?.userId);
    }
  });

  test('cookies: false reads the header only', () async {
    final DVSessionAuthenticationResult cookieOnly = await DVSessionAuthentication.ofRequest(
        request(cookie: '__Host-dv_session=abc'),
        cookies: false);
    expect(cookieOnly.refused, isFalse, reason: 'with the cookie ignored nothing was presented');
  });

  test('nothing assembles the call by hand any more', () {
    final Directory packages = Directory('..');
    final List<String> offenders = <String>[
      for (final String rel in <String>[
        'dartvel_core/lib/src/admin/studio_api.dart',
        'dartvel_core/lib/src/admin/model_data_api.dart',
        'dartvel_core/lib/src/admin/admin_server.dart',
        'dartvel_cli/lib/src/generators/backend_generator.dart',
        'dartvel_cli/lib/src/build/web_server.dart',
      ])
        if (File('${packages.path}/$rel').readAsStringSync().contains('DVSessionAuthentication.authenticateRequest('))
          rel,
    ];
    expect(offenders, isEmpty);
  });
}
