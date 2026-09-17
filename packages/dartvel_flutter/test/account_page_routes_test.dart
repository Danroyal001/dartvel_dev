// The routes the generated router serves the prebuilt account pages at, and
// the navigation entries an application places.
//
// The generated router gives each account page a GoRoute whose redirect is
// DVAccountPages.requireSession -- dartvel_cli's account_page_routes_test pins
// that the generator writes it, and this drives the same shape through a real
// router. The silent failures:
//  * an account page reachable signed out, which renders a page that then
//    fails every call and reads as a broken server rather than a missing
//    sign-in;
//  * sign-up refused to the person who has no account yet;
//  * a browser with a live cookie sent to sign in because the device had not
//    asked the server which session it is on;
//  * an entry labelled as one page and pointing at another.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
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

class _State {
  _State(String location) : uri = Uri.parse(location);

  final Uri uri;

  String get matchedLocation => uri.path;
}

const List<DVAccountPageEntry> _entries = <DVAccountPageEntry>[
  DVAccountPageEntry(DVAccountPage.profile, DVRouteTarget('/account/profile')),
  DVAccountPageEntry(DVAccountPage.security, DVRouteTarget('/account/security')),
  DVAccountPageEntry(DVAccountPage.sessions, DVRouteTarget('/account/sessions')),
  DVAccountPageEntry(DVAccountPage.delete, DVRouteTarget('/account/delete')),
  DVAccountPageEntry(DVAccountPage.signUp, DVRouteTarget('/sign-up')),
  DVAccountPageEntry(DVAccountPage.signIn, DVRouteTarget('/login')),
];

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
  }
}

void main() {
  late List<DVHttpRequest> requests;

  DVHttpResponse route(DVHttpRequest request) {
    final String path = request.url.path.replaceFirst('/api', '');
    return switch ('${request.method} $path') {
      'POST /auth/sign-in' => _json(200, <String, Object?>{
          'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
          'mfaRequired': false,
          'session': _session('ses_here'),
          'token': _token,
        }),
      'GET /auth/session' => _json(200, <String, Object?>{'session': _session('ses_cookie')}),
      'GET /auth/factors' => _json(200, <String, Object?>{'totp': false, 'recoveryCodes': 0}),
      'GET /auth/sessions' => _json(200, <String, Object?>{
          'sessions': <Object?>[_session('ses_here')],
        }),
      'GET /auth/account' => _json(200, <String, Object?>{
          'account': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
        }),
      _ => _json(401, <String, Object?>{'error': 'unauthenticated'}),
    };
  }

  Future<void> install({bool signIn = true}) async {
    requests = <DVHttpRequest>[];
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      tokens: DVMemorySessionTokenStore(),
      web: false,
      send: (DVHttpRequest request) async {
        requests.add(request);
        return route(request);
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    if (signIn) {
      await DV.Auth.signInWithEmailAndPassword(
          email: 'ada@example.com', password: 'correct horse');
    }
  }

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
    DVNavigation.detach();
  });

  group('the session gate', () {
    test('nobody signed in is sent to sign in, carrying where they were going',
        () async {
      await install(signIn: false);
      final String? redirect = await DVAccountPages.requireSession(
          null, _State('/account/security?tab=codes'));
      expect(redirect, isNotNull);
      final Uri target = Uri.parse(redirect!);
      expect(target.path, dvSignInRoute);
      expect(target.queryParameters['from'], '/account/security?tab=codes');
    });

    test('with no session client at all, the page is still refused', () async {
      expect(await DVAccountPages.requireSession(null, _State('/account/delete')),
          startsWith(dvSignInRoute));
    });

    test('a signed-in person opens the page', () async {
      await install();
      expect(await DVAccountPages.requireSession(null, _State('/account/security')),
          isNull);
    });

    test('in a browser that has not asked yet, the server is asked before '
        'refusing', () async {
      requests = <DVHttpRequest>[];
      DVSessionClient.install(DVSessionClient(
        api: (String path) => Uri.parse('https://app.example.test/api$path'),
        web: true,
        send: (DVHttpRequest request) async {
          requests.add(request);
          return route(request);
        },
      ));
      expect(await DVAccountPages.requireSession(null, _State('/account/sessions')),
          isNull);
      expect(requests.single.url.path, '/api/auth/session');
    });
  });

  group('the navigation entries', () {
    test('each says which page it is, where it goes, and whether it needs a '
        'session', () {
      expect(<String>[for (final DVAccountPageEntry e in _entries) e.label],
          <String>['Profile', 'Security', 'Devices', 'Delete account', 'Sign up', 'Sign in']);
      expect(_entries.map((DVAccountPageEntry e) => e.requiresSession),
          <bool>[true, true, true, true, false, false]);
      expect(_entries[1].target.path, '/account/security');
    });

    test('a signed-out person is offered only what they can open', () {
      expect(DVAccountPages.visible(_entries, signedIn: false).map((e) => e.page),
          <DVAccountPage>[DVAccountPage.signUp, DVAccountPage.signIn]);
      expect(DVAccountPages.visible(_entries, signedIn: true).map((e) => e.page),
          <DVAccountPage>[
            DVAccountPage.profile,
            DVAccountPage.security,
            DVAccountPage.sessions,
            DVAccountPage.delete,
          ]);
    });
  });

  group('through a router', () {
    Future<GoRouter> app(WidgetTester tester, Size size) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget page(DVAccountPage which) => switch (which) {
            DVAccountPage.profile => DV.Auth.ProfilePage(),
            DVAccountPage.security => DV.Auth.SecurityPage(),
            DVAccountPage.sessions => DV.Auth.SessionsPage(),
            DVAccountPage.delete => DV.Auth.DeletePage(),
            DVAccountPage.signUp => DV.Auth.SignUpPage(),
            DVAccountPage.signIn => const SizedBox.shrink(),
          };
      // The shape the generator writes: sign-in carries where the gate was
      // sending the person.
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(path: '/', builder: (_, __) => const Scaffold(body: DVText('Home'))),
          for (final DVAccountPageEntry entry in _entries)
            GoRoute(
              path: entry.target.path,
              redirect: entry.requiresSession
                  ? (BuildContext context, GoRouterState state) =>
                      DVAccountPages.requireSession(context, state)
                  : null,
              pageBuilder: (_, GoRouterState state) => NoTransitionPage<void>(
                child: Scaffold(
                  body: entry.page == DVAccountPage.signIn
                      ? DV.Auth.SignInWithEmailAndPasswordPage(
                          from: state.uri.queryParameters['from'])
                      : page(entry.page),
                ),
              ),
            ),
        ],
      );
      DVNavigation.attach(router);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await settle(tester);
      return router;
    }

    for (final Size size in const <Size>[Size(800, 600), Size(1440, 900)]) {
      testWidgets('signed out, every account page but sign-up goes to sign in '
          '(${size.width.toInt()}x${size.height.toInt()})',
          (WidgetTester tester) async {
        await tester.runAsync(() => install(signIn: false));
        final GoRouter router = await app(tester, size);
        for (final DVAccountPageEntry entry in _entries) {
          router.go(entry.target.path);
          await settle(tester);
          if (entry.requiresSession) {
            expect(find.byKey(const ValueKey<String>('dv-auth-email')), findsOneWidget,
                reason: entry.label);
            expect(router.routerDelegate.currentConfiguration.uri.path, dvSignInRoute);
          } else {
            expect(router.routerDelegate.currentConfiguration.uri.path,
                entry.target.path);
          }
          expect(tester.takeException(), isNull);
        }
        expect(
            requests.where((DVHttpRequest r) => r.url.path != '/api/auth/session'),
            isEmpty,
            reason: 'no account page was built, so none called its endpoints');
      });

      testWidgets('signed in, each account page opens where its entry points '
          '(${size.width.toInt()}x${size.height.toInt()})',
          (WidgetTester tester) async {
        await tester.runAsync(() => install());
        final GoRouter router = await app(tester, size);
        router.go('/account/security');
        await settle(tester);
        expect(find.byKey(const ValueKey<String>('dv-security-totp-off')), findsOneWidget);
        expect(tester.takeException(), isNull);
        router.go('/account/sessions');
        await settle(tester);
        expect(router.routerDelegate.currentConfiguration.uri.path, '/account/sessions');
        expect(find.byKey(const ValueKey<String>('dv-auth-email')), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('signing in on the page the gate sent somebody to goes back '
          'where they were going (${size.width.toInt()}x${size.height.toInt()})',
          (WidgetTester tester) async {
        await tester.runAsync(() => install(signIn: false));
        final GoRouter router = await app(tester, size);
        router.go('/account/security');
        await settle(tester);
        expect(router.routerDelegate.currentConfiguration.uri.queryParameters['from'],
            '/account/security');
        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-auth-email')), 'ada@example.com');
        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-auth-password')), 'correct horse');
        await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
        await settle(tester);
        expect(router.routerDelegate.currentConfiguration.uri.path, '/account/security');
        expect(find.byKey(const ValueKey<String>('dv-security-totp-off')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('signing in on the page opened directly goes home',
        (WidgetTester tester) async {
      // With no from the page stayed on its form after a sign-in the server
      // accepted, so it looked as if nothing had happened.
      await tester.runAsync(() => install(signIn: false));
      final GoRouter router = await app(tester, const Size(800, 600));
      router.go('/login');
      await settle(tester);
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-email')), 'ada@example.com');
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-password')), 'correct horse');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('a from that leaves the application goes home instead',
        (WidgetTester tester) async {
      await tester.runAsync(() => install(signIn: false));
      final GoRouter router = await app(tester, const Size(800, 600));
      router.go('/login?from=https://evil.example/x');
      await settle(tester);
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-email')), 'ada@example.com');
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-password')), 'correct horse');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    });
  });

  // A page with no heading gives a screen reader nothing to name it by, and
  // `dartvel build web` refuses it: every generated account route failed the
  // build's audit when they were first served.
  group('each page names itself with one level 1 heading', () {
    final Map<String, Widget Function()> pages = <String, Widget Function()>{
      'Profile': () => DV.Auth.ProfilePage(),
      'Security': () => DV.Auth.SecurityPage(),
      'Devices': () => DV.Auth.SessionsPage(),
      'Delete your account': () => DV.Auth.DeletePage(),
      'Create an account': () => DV.Auth.SignUpPage(),
      'Sign in to your account': () => DV.Auth.SignInWithEmailAndPasswordPage(),
    };
    pages.forEach((String title, Widget Function() build) {
      testWidgets(title, (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        await tester.runAsync(() => install());
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: build())));
        await settle(tester);
        final List<SemanticsNode> headings = <SemanticsNode>[];
        void walk(SemanticsNode node) {
          if (node.headingLevel == 1) headings.add(node);
          node.visitChildren((SemanticsNode child) {
            walk(child);
            return true;
          });
        }

        SemanticsNode root = tester.getSemantics(find.byType(Scaffold));
        while (root.parent != null) {
          root = root.parent!;
        }
        walk(root);
        expect(headings.map((SemanticsNode n) => n.label), <String>[title]);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    });
  });
}
