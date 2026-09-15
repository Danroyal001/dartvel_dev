// DV.Auth.OAuthConsentPage: the screen a person answers a partner's OAuth
// request on.
//
// The provider validated requests and issued codes, and no screen asked
// anybody: an application that was an OAuth provider had nothing to send a
// person to. Every failure worth a test here is a grant nobody made, or one
// made under words the person was never shown:
//  * a request approved by opening the page, before anyone pressed anything;
//  * scopes shown by their names rather than the wording their declaration
//    gave them;
//  * an approval sent without the person's own credentials or the CSRF token
//    the endpoint requires, which the server refuses and the page shows as
//    nothing happening;
//  * a refusal (not signed in) treated as success and followed somewhere.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, String> query = <String, String>{
  'response_type': 'code',
  'client_id': 'dvc_0123456789abcdef',
  'redirect_uri': 'https://partner.example/cb',
  'scope': 'orders:read',
  'state': 'xyz',
  'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
  'code_challenge_method': 'S256',
};

class FakeBackend {
  FakeBackend({this.approveStatus = 200, this.describeStatus = 200});

  final int approveStatus;
  final int describeStatus;
  final List<DVHttpRequest> requests = <DVHttpRequest>[];

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    if (request.method == 'GET' &&
        request.url.path == '/api/oauth/authorize/request') {
      return DVHttpResponse(
        statusCode: describeStatus,
        body: describeStatus == 200
            ? jsonEncode(<String, Object?>{
                'client': <String, Object?>{
                  'id': query['client_id'],
                  'name': 'Partner Web',
                },
                'scopes': <Object?>[
                  <String, Object?>{
                    'scope': 'orders:read',
                    'description': 'See your orders',
                  },
                ],
              })
            : jsonEncode(<String, Object?>{'error': 'invalid_client'}),
      );
    }
    if (request.method == 'POST' &&
        request.url.path == '/api/oauth/authorize') {
      return DVHttpResponse(
        statusCode: approveStatus,
        body: approveStatus == 200
            ? jsonEncode(<String, Object?>{
                'redirect_to': 'https://partner.example/cb?code=abc&state=xyz',
              })
            : jsonEncode(<String, Object?>{'error': 'login_required'}),
      );
    }
    return const DVHttpResponse(statusCode: 404, body: '');
  }

  List<DVHttpRequest> get posts =>
      requests.where((DVHttpRequest r) => r.method == 'POST').toList();
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

Future<List<String>> pumpConsent(
  WidgetTester tester,
  FakeBackend backend,
) async {
  final List<String> opened = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: const DVAuth().OAuthConsentPage(
          query: query,
          apiBase: Uri.parse('https://app.example/api'),
          headers: () => <String, String>{'Authorization': 'Bearer session-1'},
          send: backend.send,
          open: opened.add,
        ),
      ),
    ),
  );
  await settle(tester);
  return opened;
}

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

void main() {
  testWidgets('shows the client and each scope in its declared wording, and '
      'approves nothing on its own', (WidgetTester tester) async {
    final FakeBackend backend = FakeBackend();
    final List<String> opened = await pumpConsent(tester, backend);

    expect(find.textContaining('Partner Web'), findsWidgets);
    expect(find.text('See your orders'), findsOneWidget);
    expect(find.text('orders:read'), findsNothing);
    expect(backend.posts, isEmpty);
    expect(opened, isEmpty);
    // It asked for the request it was opened with.
    expect(backend.requests.first.url.queryParameters, query);
  });

  testWidgets('approving sends the request, the decision, the person\'s '
      'credentials and a CSRF token, then follows the redirect', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend();
    final List<String> opened = await pumpConsent(tester, backend);

    await tester.tap(byKey('dv-oauth-consent-approve'));
    await settle(tester);

    expect(backend.posts, hasLength(1));
    final DVHttpRequest post = backend.posts.single;
    expect(post.url.toString(), 'https://app.example/api/oauth/authorize');
    expect(post.headers['content-type'], 'application/x-www-form-urlencoded');
    expect(post.headers['Authorization'], 'Bearer session-1');
    expect(
      post.headers[DVCSRF.headerName],
      hasLength(greaterThanOrEqualTo(32)),
    );
    final Map<String, String> fields = Uri.splitQueryString(
      utf8.decode(post.body),
    );
    expect(fields, <String, String>{...query, 'decision': 'approve'});
    expect(opened, <String>['https://partner.example/cb?code=abc&state=xyz']);
  });

  testWidgets('denying sends deny', (WidgetTester tester) async {
    final FakeBackend backend = FakeBackend();
    await pumpConsent(tester, backend);

    await tester.tap(byKey('dv-oauth-consent-deny'));
    await settle(tester);

    final Map<String, String> fields = Uri.splitQueryString(
      utf8.decode(backend.posts.single.body),
    );
    expect(fields['decision'], 'deny');
  });

  testWidgets('an approval the server refuses is shown, and followed nowhere', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend(approveStatus: 401);
    final List<String> opened = await pumpConsent(tester, backend);

    await tester.tap(byKey('dv-oauth-consent-approve'));
    await settle(tester);

    expect(opened, isEmpty);
    expect(byKey('dv-oauth-consent-error'), findsOneWidget);
  });

  testWidgets(
    'a request the server will not describe offers nothing to approve',
    (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend(describeStatus: 400);
      await pumpConsent(tester, backend);

      expect(byKey('dv-oauth-consent-error'), findsOneWidget);
      expect(byKey('dv-oauth-consent-approve'), findsNothing);
    },
  );
}
