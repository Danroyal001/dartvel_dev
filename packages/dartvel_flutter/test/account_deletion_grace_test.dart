// A deletion that waits out the project's grace period, on the device.
//
// The server answers a deletion with a window 202 and when the account will
// be erased, cancels the deletion when the person signs in within it, and
// refuses a sign-in after it with account_deleted. The silent failures here:
//  * DeletePage saying the account "has been deleted" when it is scheduled,
//    so the person never learns signing in would keep it;
//  * a sign-in that cancelled a deletion without saying so, so the person
//    believes the account is still going;
//  * a sign-in refused because the account was deleted reading as a generic
//    failure to try again.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

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

Map<String, Object?> _signedIn({bool cancelled = false}) => <String, Object?>{
      'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
      'mfaRequired': false,
      'session': _session('ses_here'),
      'token': _token,
      if (cancelled) 'deletionCancelled': true,
    };

void main() {
  late Map<String, DVHttpResponse Function(DVHttpRequest)> routes;

  Future<void> install({bool signIn = true}) async {
    routes = <String, DVHttpResponse Function(DVHttpRequest)>{
      'POST /auth/sign-in': (_) => _json(200, _signedIn()),
      'GET /auth/factors': (_) =>
          _json(200, <String, Object?>{'totp': false, 'recoveryCodes': 0}),
    };
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      tokens: DVMemorySessionTokenStore(),
      web: false,
      send: (DVHttpRequest request) async {
        final DVHttpResponse Function(DVHttpRequest)? route =
            routes['${request.method} ${request.url.path.replaceFirst('/api', '')}'];
        return route == null
            ? _json(404, <String, Object?>{'error': 'not_found'})
            : route(request);
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    if (signIn) {
      await DV.Auth.signInWithEmailAndPassword(
          email: 'ada@example.com', password: 'correct horse');
    }
  }

  Future<void> pump(WidgetTester tester, Widget page, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    await settle(tester);
  }

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  test('DV.Auth.deleteAccount answers when a scheduled deletion erases, and '
      'null for one erased at once', () async {
    await install();
    routes['POST /auth/account/delete'] = (_) => _json(202, <String, Object?>{
          'scheduled': true,
          'erasesAt': '2026-09-23T12:00:00.000Z',
        });
    expect(await DV.Auth.deleteAccount(password: 'correct horse', confirmed: true),
        DateTime.utc(2026, 9, 23, 12));
    expect(DV.Session.current, isNull);

    await install();
    routes['POST /auth/account/delete'] =
        (_) => _json(200, <String, Object?>{'deleted': true, 'erasure': null});
    expect(await DV.Auth.deleteAccount(password: 'correct horse', confirmed: true),
        isNull);
  });

  for (final Size size in const <Size>[Size(800, 600), Size(1440, 900)]) {
    testWidgets('DeletePage says when the account will be erased and that '
        'signing in keeps it (${size.width.toInt()}x${size.height.toInt()})',
        (WidgetTester tester) async {
      await tester.runAsync(() => install());
      routes['POST /auth/account/delete'] = (_) => _json(202, <String, Object?>{
            'scheduled': true,
            'erasesAt': '2026-09-23T12:00:00.000Z',
          });
      await pump(tester, DV.Auth.DeletePage(), size);
      await tester.enterText(find.byKey(_key('dv-delete-confirm-text')), 'DELETE');
      await tester.enterText(find.byKey(_key('dv-delete-password')), 'correct horse');
      await tester.ensureVisible(find.byKey(_key('dv-delete-submit')));
      await tester.tap(find.byKey(_key('dv-delete-submit')));
      await settle(tester);
      expect(find.byKey(_key('dv-delete-scheduled')), findsOneWidget);
      expect(find.textContaining('2026-09-23'), findsOneWidget);
      expect(find.textContaining('Sign in before then'), findsOneWidget);
      expect(find.text('Your account has been deleted.'), findsNothing);
      expect(DV.Session.current, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signing in within the window says the deletion was cancelled '
        '(${size.width.toInt()}x${size.height.toInt()})', (WidgetTester tester) async {
      await tester.runAsync(() => install(signIn: false));
      routes['POST /auth/sign-in'] = (_) => _json(200, _signedIn(cancelled: true));
      await pump(tester, DV.Auth.SignInWithEmailAndPasswordPage(), size);
      await tester.enterText(find.byKey(_key('dv-auth-email')), 'ada@example.com');
      await tester.enterText(find.byKey(_key('dv-auth-password')), 'correct horse');
      await tester.tap(find.byKey(_key('dv-auth-submit')));
      await settle(tester);
      expect(DV.Session.id, 'ses_here');
      expect(find.byKey(_key('dv-auth-deletion-cancelled')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an ordinary sign-in says nothing about a deletion',
      (WidgetTester tester) async {
    await tester.runAsync(() => install(signIn: false));
    await pump(tester, DV.Auth.SignInWithEmailAndPasswordPage(), const Size(800, 600));
    await tester.enterText(find.byKey(_key('dv-auth-email')), 'ada@example.com');
    await tester.enterText(find.byKey(_key('dv-auth-password')), 'correct horse');
    await tester.tap(find.byKey(_key('dv-auth-submit')));
    await settle(tester);
    expect(DV.Session.id, 'ses_here');
    expect(find.byKey(_key('dv-auth-deletion-cancelled')), findsNothing);
  });

  testWidgets('a sign-in after the window says the account was deleted',
      (WidgetTester tester) async {
    await tester.runAsync(() => install(signIn: false));
    routes['POST /auth/sign-in'] = (_) => _json(403, <String, Object?>{
          'error': 'account_deleted',
          'message': 'This account has been deleted.',
        });
    await pump(tester, DV.Auth.SignInWithEmailAndPasswordPage(), const Size(800, 600));
    await tester.enterText(find.byKey(_key('dv-auth-email')), 'ada@example.com');
    await tester.enterText(find.byKey(_key('dv-auth-password')), 'correct horse');
    await tester.tap(find.byKey(_key('dv-auth-submit')));
    await settle(tester);
    expect(DV.Session.current, isNull);
    expect(find.text('This account has been deleted.'), findsOneWidget);
  });
}
