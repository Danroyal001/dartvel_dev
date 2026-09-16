// Changing the password from DV.Auth.SecurityPage, through DV.Auth.
//
// Drives the page against a recording backend. The silent failures:
//  * a change sent without the current password;
//  * on an account with an authenticator, no way to present a code, so the
//    server's step-up refusal reads as a failure with nothing to do about it;
//  * the rotated session not adopted, so this device signs itself out on its
//    next request;
//  * a password left in a field after it was used, or a refusal that clears
//    what the person typed and says nothing;
//  * any of it overflowing at a common window size.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _rotated = 'dvs_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Map<String, Object?> _session(String id) => <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': '2026-09-15T12:30:00.000Z',
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': null,
      'isCurrent': true,
    };

DVHttpResponse _json(int status, Object body) =>
    DVHttpResponse(statusCode: status, body: jsonEncode(body));

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
  }
}

ValueKey<String> _key(String name) => ValueKey<String>(name);

void main() {
  late List<DVHttpRequest> requests;
  late Map<String, DVHttpResponse Function(DVHttpRequest)> routes;

  Map<String, Object?> bodyOf(String route) {
    final DVHttpRequest request = requests.lastWhere((DVHttpRequest r) =>
        '${r.method} ${r.url.path.replaceFirst('/api', '')}' == route);
    return jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;
  }

  int sent(String route) => requests
      .where((DVHttpRequest r) =>
          '${r.method} ${r.url.path.replaceFirst('/api', '')}' == route)
      .length;

  Future<void> install({bool totp = false}) async {
    requests = <DVHttpRequest>[];
    routes = <String, DVHttpResponse Function(DVHttpRequest)>{
      'POST /auth/sign-in': (_) => _json(200, <String, Object?>{
            'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
            'mfaRequired': false,
            'session': _session('ses_here'),
            'token': _token,
          }),
      'GET /auth/factors': (_) =>
          _json(200, <String, Object?>{'totp': totp, 'recoveryCodes': 0}),
    };
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      tokens: DVMemorySessionTokenStore(),
      web: false,
      send: (DVHttpRequest request) async {
        requests.add(request);
        final DVHttpResponse Function(DVHttpRequest)? route =
            routes['${request.method} ${request.url.path.replaceFirst('/api', '')}'];
        return route == null
            ? _json(404, <String, Object?>{'error': 'not_found'})
            : route(request);
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    await DV.Auth.signInWithEmailAndPassword(
        email: 'ada@example.com', password: 'correct horse');
    requests.clear();
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DV.Auth.SecurityPage())));
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(find.byKey(_key(key)));
    await tester.enterText(find.byKey(_key(key)), text);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_key('dv-security-password-submit')));
    await tester.tap(find.byKey(_key('dv-security-password-submit')));
    await settle(tester);
  }

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(_key(key))).controller!.text;

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  test('DV.Auth.changePassword sends both passwords, adopts the rotated '
      'session and answers how many devices were signed out', () async {
    await install();
    routes['POST /auth/account/password'] = (_) => _json(200, <String, Object?>{
          'revoked': 2,
          'session': _session('ses_rotated'),
          'token': _rotated,
        });
    final int revoked = await DV.Auth.changePassword(
        currentPassword: 'correct horse', newPassword: 'a much longer one');
    expect(revoked, 2);
    expect(bodyOf('POST /auth/account/password'), <String, Object?>{
      'currentPassword': 'correct horse',
      'newPassword': 'a much longer one',
    });
    expect(DV.Session.id, 'ses_rotated');
  });

  for (final Size size in const <Size>[Size(800, 600), Size(1440, 900)]) {
    testWidgets('changes the password, clears both fields and says the other '
        'devices were signed out (${size.width.toInt()}x${size.height.toInt()})',
        (WidgetTester tester) async {
      await tester.runAsync(() => install());
      routes['POST /auth/account/password'] = (_) => _json(200, <String, Object?>{
            'revoked': 3,
            'session': _session('ses_rotated'),
            'token': _rotated,
          });
      await pump(tester, size);
      expect(find.byKey(_key('dv-security-password-code')), findsNothing);

      await submit(tester);
      expect(sent('POST /auth/account/password'), 0);
      expect(find.byKey(_key('dv-security-password-error')), findsOneWidget);

      await type(tester, 'dv-security-password-current', 'correct horse');
      await type(tester, 'dv-security-password-new', 'a much longer one');
      await submit(tester);
      expect(bodyOf('POST /auth/account/password'), <String, Object?>{
        'currentPassword': 'correct horse',
        'newPassword': 'a much longer one',
      });
      expect(DV.Session.id, 'ses_rotated');
      expect(fieldText(tester, 'dv-security-password-current'), isEmpty);
      expect(fieldText(tester, 'dv-security-password-new'), isEmpty);
      expect(find.byKey(_key('dv-security-password-done')), findsOneWidget);
      expect(find.textContaining('3 other devices'), findsOneWidget);
      expect(find.byKey(_key('dv-security-password-error')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a wrong current password is said, and what was typed stays',
      (WidgetTester tester) async {
    await tester.runAsync(() => install());
    routes['POST /auth/account/password'] = (_) =>
        _json(400, <String, Object?>{'error': 'invalid_credentials', 'message': 'x'});
    await pump(tester, const Size(800, 600));
    await type(tester, 'dv-security-password-current', 'not it');
    await type(tester, 'dv-security-password-new', 'a much longer one');
    await submit(tester);
    expect(find.text('That password is not right.'), findsOneWidget);
    expect(fieldText(tester, 'dv-security-password-new'), 'a much longer one');
    expect(find.byKey(_key('dv-security-password-done')), findsNothing);
    expect(DV.Session.id, 'ses_here');
  });

  testWidgets('a breached new password is said as such',
      (WidgetTester tester) async {
    await tester.runAsync(() => install());
    routes['POST /auth/account/password'] = (_) => _json(400, <String, Object?>{
          'error': 'breached_password',
          'code': 'DV-EDGE-004',
          'message': 'x',
        });
    await pump(tester, const Size(800, 600));
    await type(tester, 'dv-security-password-current', 'correct horse');
    await type(tester, 'dv-security-password-new', 'password1234567890');
    await submit(tester);
    expect(find.textContaining('known data breach'), findsOneWidget);
  });

  testWidgets('with an authenticator, a code can be given, and a step-up '
      'refusal asks for one', (WidgetTester tester) async {
    await tester.runAsync(() => install(totp: true));
    routes['POST /auth/account/password'] = (DVHttpRequest request) {
      final Map<String, Object?> body =
          jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;
      if (body['code'] == null) {
        return _json(401, <String, Object?>{'error': 'mfa_required', 'maxAge': 600});
      }
      return _json(200, <String, Object?>{
        'revoked': 0,
        'session': _session('ses_rotated'),
        'token': _rotated,
      });
    };
    await pump(tester, const Size(800, 600));
    expect(find.byKey(_key('dv-security-password-code')), findsOneWidget);
    await type(tester, 'dv-security-password-current', 'correct horse');
    await type(tester, 'dv-security-password-new', 'a much longer one');
    await submit(tester);
    expect(find.textContaining('code from your authenticator app'), findsOneWidget);
    expect(DV.Session.id, 'ses_here');

    await type(tester, 'dv-security-password-code', '123456');
    await submit(tester);
    expect(bodyOf('POST /auth/account/password')['code'], '123456');
    expect(DV.Session.id, 'ses_rotated');
    expect(fieldText(tester, 'dv-security-password-code'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
