// @DVPage(mfa: ...) on the device: the route gate and the challenge it
// sends a person to.
//
// The backend refuses a function whose session lacks the factor; the page is
// the half a person sees. The silent failures here:
//  * a page declaring a second factor opening for a password-only session;
//  * a page declaring a recent factor opening once the factor went stale;
//  * the challenge sending the person somewhere other than where they were
//    going -- or to another site, when `from` is a URL an attacker wrote;
//  * a page with a live session in the browser refusing because the device
//    had not asked the server which session it is on yet.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _rotated = 'dvs_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Map<String, Object?> _session(String id, {DateTime? mfaAt}) => <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': '2026-09-15T12:30:00.000Z',
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': mfaAt?.toUtc().toIso8601String(),
      'isCurrent': true,
    };

DVHttpResponse _json(int status, Object body) =>
    DVHttpResponse(statusCode: status, body: jsonEncode(body));

class _State {
  _State(String location) : uri = Uri.parse(location);

  final Uri uri;

  String get matchedLocation => uri.path;
}

void main() {
  late List<DVHttpRequest> requests;
  late DVHttpResponse Function(DVHttpRequest request) answer;

  Future<DVSessionClient> signedIn({DateTime? mfaAt, bool web = false}) async {
    requests = <DVHttpRequest>[];
    answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
          'mfaRequired': false,
          'session': _session('ses_here', mfaAt: mfaAt),
          if (!web) 'token': _token,
        });
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      tokens: DVMemorySessionTokenStore(),
      web: web,
      send: (DVHttpRequest request) async {
        requests.add(request);
        return answer(request);
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    await client.signIn(email: 'ada@example.com', password: 'correct horse');
    requests.clear();
    return client;
  }

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
    DVNavigation.detach();
  });

  group('the route gate', () {
    test('nobody signed in is sent to sign in', () async {
      expect(await DVPageMfa.check(null, _State('/billing'), DVMfa.required),
          dvSignInRoute);
    });

    test('a password-only session is sent to the challenge, with where it was '
        'going', () async {
      await signedIn();
      final String? redirect =
          await DVPageMfa.check(null, _State('/billing?tab=cards'), DVMfa.required);
      expect(redirect, isNotNull);
      final Uri target = Uri.parse(redirect!);
      expect(target.path, dvSecondFactorRoute);
      expect(target.queryParameters['from'], '/billing?tab=cards');
    });

    test('a session with the factor opens the page', () async {
      await signedIn(mfaAt: DateTime.now().subtract(const Duration(hours: 3)));
      expect(await DVPageMfa.check(null, _State('/billing'), DVMfa.required), isNull);
    });

    test('a recent-factor page refuses a factor older than its window', () async {
      await signedIn(mfaAt: DateTime.now().subtract(const Duration(minutes: 10)));
      expect(
          await DVPageMfa.check(
              null, _State('/payout'), const DVMfa.recent(Duration(minutes: 5))),
          startsWith(dvSecondFactorRoute));
      expect(
          await DVPageMfa.check(
              null, _State('/payout'), const DVMfa.recent(Duration(minutes: 15))),
          isNull);
    });

    test('in a browser that has not asked yet, the server is asked which '
        'session this is before refusing', () async {
      requests = <DVHttpRequest>[];
      answer = (DVHttpRequest request) => _json(200, <String, Object?>{
            'session': _session('ses_cookie', mfaAt: DateTime.now()),
          });
      DVSessionClient.install(DVSessionClient(
        api: (String path) => Uri.parse('https://app.example.test/api$path'),
        web: true,
        send: (DVHttpRequest request) async {
          requests.add(request);
          return answer(request);
        },
      ));
      expect(await DVPageMfa.check(null, _State('/billing'), DVMfa.required), isNull);
      expect(requests.single.url.path, '/api/auth/session');
    });
  });

  group('the challenge page', () {
    Future<GoRouter> app(WidgetTester tester, Size size) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(path: '/', builder: (_, __) => const Scaffold(body: DVText('Home'))),
          GoRoute(
            path: '/billing',
            redirect: (BuildContext context, GoRouterState state) =>
                DVPageMfa.check(context, state, DVMfa.required),
            builder: (_, __) => const Scaffold(body: DVText('Billing')),
          ),
          GoRoute(
            path: '/second-factor',
            builder: (_, GoRouterState state) => Scaffold(
              body: DV.Auth.SecondFactorPage(from: state.uri.queryParameters['from']),
            ),
          ),
        ],
      );
      DVNavigation.attach(router);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    for (final Size size in const <Size>[Size(800, 600), Size(1440, 900)]) {
      testWidgets('presents a code, keeps the rotated session and goes where '
          'the person was going (${size.width.toInt()}x${size.height.toInt()})',
          (WidgetTester tester) async {
        await tester.runAsync(() => signedIn());
        final GoRouter router = await app(tester, size);
        router.go('/billing');
        await tester.pumpAndSettle();
        expect(find.text('Billing'), findsNothing);
        expect(find.byKey(const ValueKey<String>('dv-auth-code')), findsOneWidget);
        expect(tester.takeException(), isNull);

        answer = (DVHttpRequest request) => _json(200, <String, Object?>{
              'session': _session('ses_rotated', mfaAt: DateTime.now()),
              'token': _rotated,
            });
        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-auth-code')), '123456');
        await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();

        expect(requests.single.url.path, '/api/auth/second-factor');
        expect(DV.Session.id, 'ses_rotated');
        expect(find.text('Billing'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a refused code is shown and goes nowhere',
        (WidgetTester tester) async {
      await tester.runAsync(() => signedIn());
      final GoRouter router = await app(tester, const Size(800, 600));
      router.go('/billing');
      await tester.pumpAndSettle();
      answer = (DVHttpRequest request) =>
          _json(400, <String, Object?>{'error': 'invalid_code', 'message': 'x'});
      await tester.enterText(find.byKey(const ValueKey<String>('dv-auth-code')), '000000');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('dv-auth-error')), findsOneWidget);
      expect(find.text('Billing'), findsNothing);
      expect(DV.Session.id, 'ses_here');
    });

    testWidgets('a recovery code works too', (WidgetTester tester) async {
      await tester.runAsync(() => signedIn());
      final GoRouter router = await app(tester, const Size(800, 600));
      router.go('/billing');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-use-recovery')));
      await tester.pumpAndSettle();
      answer = (DVHttpRequest request) => _json(200, <String, Object?>{
            'session': _session('ses_rotated', mfaAt: DateTime.now()),
            'token': _rotated,
          });
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-recovery-code')), 'AAAAA-BBBBB');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      final Map<String, Object?> sent =
          jsonDecode(utf8.decode(requests.single.body)) as Map<String, Object?>;
      expect(sent, <String, Object?>{'recoveryCode': 'AAAAA-BBBBB'});
      expect(find.text('Billing'), findsOneWidget);
    });

    testWidgets('a backend call refused for a second factor presents the '
        'challenge over the screen and is sent again once it is presented',
        (WidgetTester tester) async {
      await tester.runAsync(() => signedIn());
      addTearDown(() => DVStepUp.challenge = null);
      DVStepUp.challenge = null;
      DVAuth.installStepUp();
      await app(tester, const Size(800, 600));
      int calls = 0;
      late final Future<DVHttpResponse> call;
      await tester.runAsync(() async {
        call = DVStepUp.send(() async {
          calls++;
          return calls == 1
              ? _json(401, <String, Object?>{'error': 'mfa_required'})
              : _json(200, <String, Object?>{'paid': true});
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('dv-auth-code')), findsOneWidget);
      expect(calls, 1);

      answer = (DVHttpRequest request) => _json(200, <String, Object?>{
            'session': _session('ses_rotated', mfaAt: DateTime.now()),
            'token': _rotated,
          });
      await tester.enterText(find.byKey(const ValueKey<String>('dv-auth-code')), '123456');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      final DVHttpResponse answered =
          (await tester.runAsync(() => call.timeout(const Duration(seconds: 5))))!;
      expect(answered.statusCode, 200);
      expect(calls, 2);
      expect(find.byKey(const ValueKey<String>('dv-auth-code')), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final String from in <String>[
      '//evil.example/billing',
      'https://evil.example/billing',
      '/\\evil.example',
    ]) {
      testWidgets('a from that leaves the application ($from) goes home instead',
          (WidgetTester tester) async {
        await tester.runAsync(() => signedIn());
        final GoRouter router = await app(tester, const Size(800, 600));
        router.go(Uri(path: '/second-factor', queryParameters: <String, String>{
          'from': from,
        }).toString());
        await tester.pumpAndSettle();
        answer = (DVHttpRequest request) => _json(200, <String, Object?>{
              'session': _session('ses_rotated', mfaAt: DateTime.now()),
              'token': _rotated,
            });
        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-auth-code')), '123456');
        await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsOneWidget);
        expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
      });
    }
  });
}
