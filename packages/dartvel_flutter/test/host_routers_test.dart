// Dartvel pages in a host that routes with Flutter's Navigator.
//
// A host on Navigator 1.0 answers onGenerateRoute; one on Navigator 2.0
// builds its own pages. Neither can take a GoRoute, so each takes a page
// that runs Dartvel's routes in a router of its own -- with Dartvel's guards,
// the host's back button reaching Dartvel's stack first, and the host's own
// routes left alone.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool signedIn = false;

List<RouteBase> dartvel() => <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const Text('dartvel home')),
      GoRoute(path: '/about', builder: (_, _) => const Text('dartvel about')),
      GoRoute(
        path: '/account',
        redirect: (_, _) => signedIn ? null : '/sign-in',
        builder: (_, _) => const Text('dartvel account'),
      ),
      GoRoute(path: '/sign-in', builder: (_, _) => const Text('dartvel sign in')),
    ];

final List<RouteBase> routes = dartvel();

Widget navigator1({String initial = '/'}) => MaterialApp(
      initialRoute: initial,
      onGenerateRoute: (RouteSettings settings) =>
          dvOnGenerateRoute(settings, routes, at: '/app') ??
          MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Text('host ${settings.name}'),
          ),
    );

void main() {
  setUp(() => signedIn = false);

  test('a host path is the host\'s, a Dartvel one under the mount is ours', () {
    expect(dvHostedLocation('/profile', routes, at: '/app'), isNull);
    expect(dvHostedLocation('/app/about?tab=2', routes, at: '/app'),
        '/about?tab=2');
    expect(dvHostedLocation('/app', routes, at: '/app'), '/');
    expect(dvHostedLocation('/app/nowhere', routes, at: '/app'), isNull);
    expect(dvHostedPath('/about', at: '/app'), '/app/about');
  });

  testWidgets('Navigator 1.0: a deep link opens the Dartvel page',
      (WidgetTester tester) async {
    await tester.pumpWidget(navigator1(initial: '/app/about'));
    await tester.pumpAndSettle();
    expect(find.text('dartvel about'), findsOneWidget);
  });

  testWidgets('Navigator 1.0: the host keeps its own routes',
      (WidgetTester tester) async {
    await tester.pumpWidget(navigator1(initial: '/profile'));
    await tester.pumpAndSettle();
    expect(find.text('host /profile'), findsOneWidget);
  });

  testWidgets('Navigator 1.0: pushed by a typed path, and back returns to the '
      'host', (WidgetTester tester) async {
    await tester.pumpWidget(navigator1(initial: '/profile'));
    await tester.pumpAndSettle();
    final NavigatorState nav = tester.state(find.byType(Navigator).first);
    nav.pushNamed(dvHostedPath('/about', at: '/app'));
    await tester.pumpAndSettle();
    expect(find.text('dartvel about'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('host /profile'), findsOneWidget);
  });

  testWidgets('back goes through Dartvel\'s own stack before the host\'s',
      (WidgetTester tester) async {
    await tester.pumpWidget(navigator1(initial: '/profile'));
    await tester.pumpAndSettle();
    final NavigatorState nav = tester.state(find.byType(Navigator).first);
    nav.pushNamed('/app');
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('dartvel home'))).push('/about');
    await tester.pumpAndSettle();
    expect(find.text('dartvel about'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('dartvel home'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('host /profile'), findsOneWidget);
  });

  testWidgets('Dartvel\'s guards run in the host', (WidgetTester tester) async {
    await tester.pumpWidget(navigator1(initial: '/app/account'));
    await tester.pumpAndSettle();
    expect(find.text('dartvel sign in'), findsOneWidget);
  });

  testWidgets('Navigator 2.0: the host puts the page in its pages',
      (WidgetTester tester) async {
    final Uri uri = Uri.parse('/app/about');
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        pages: <Page<Object?>>[
          const MaterialPage<void>(child: Text('host home')),
          ?dvPageFor(uri, routes, at: '/app'),
        ],
        onDidRemovePage: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('dartvel about'), findsOneWidget);
    expect(dvPageFor(Uri.parse('/settings'), routes, at: '/app'), isNull);
  });

  group('Navigator 1.0 with the app\'s own onGenerateRoute', () {
    // The app's handler, typed as Flutter types it. It answers /app/about
    // too, to show that Dartvel wins on its own paths.
    Route<Object?>? existing(RouteSettings settings) => switch (settings.name) {
          '/profile' || '/app/about' => MaterialPageRoute<String>(
              settings: settings,
              builder: (_) =>
                  Text('host ${settings.name} ${settings.arguments ?? ''}'.trim()),
            ),
          _ => null,
        };

    Widget app(String initial) => MaterialApp(
          initialRoute: initial,
          onGenerateRoute:
              dvRouteFactory(routes, at: '/app', existing: existing),
          onUnknownRoute: (RouteSettings settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Text('unknown'),
          ),
        );

    testWidgets('a Dartvel path is Dartvel\'s, even where the app answers it',
        (WidgetTester tester) async {
      await tester.pumpWidget(app('/app/about'));
      await tester.pumpAndSettle();
      expect(find.text('dartvel about'), findsOneWidget);
      expect(find.textContaining('host'), findsNothing);
    });

    testWidgets('every other name goes to the app\'s handler, arguments and all',
        (WidgetTester tester) async {
      await tester.pumpWidget(app('/'));
      await tester.pumpAndSettle();
      final NavigatorState nav = tester.state(find.byType(Navigator).first);
      nav.pushNamed('/profile', arguments: 42);
      await tester.pumpAndSettle();
      expect(find.text('host /profile 42'), findsOneWidget);
    });

    testWidgets('a name neither answers is unknown, as it was before',
        (WidgetTester tester) async {
      await tester.pumpWidget(app('/'));
      await tester.pumpAndSettle();
      final NavigatorState nav = tester.state(find.byType(Navigator).first);
      nav.pushNamed('/nowhere');
      await tester.pumpAndSettle();
      expect(find.text('unknown'), findsOneWidget);
    });
  });

  group('go_router with the app\'s own routes and redirect', () {
    final List<String> hostRedirected = <String>[];

    GoRouter host({String initial = '/'}) {
      hostRedirected.clear();
      final GoRouter router = dvGoRouter(
        routes,
        at: '/app',
        initialLocation: initial,
        existing: <RouteBase>[
          GoRoute(path: '/', builder: (_, _) => const Text('host home')),
          GoRoute(path: '/profile', builder: (_, _) => const Text('host profile')),
          GoRoute(path: '/login', builder: (_, _) => const Text('host login')),
          // The same path as a Dartvel page: Dartvel's wins.
          GoRoute(path: '/app/about', builder: (_, _) => const Text('host about')),
        ],
        redirect: (BuildContext context, GoRouterState state) {
          hostRedirected.add(state.uri.path);
          return state.uri.path == '/profile' ? '/login' : null;
        },
      );
      addTearDown(() {
        router.dispose();
        DVNavigation.detach();
        dvResetMount();
      });
      return router;
    }

    testWidgets('the app\'s redirect runs on its own paths',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: host(initial: '/profile')));
      await tester.pumpAndSettle();
      expect(find.text('host login'), findsOneWidget);
    });

    testWidgets('Dartvel\'s paths are Dartvel\'s: its page wins, and the '
        'app\'s redirect is not asked about them', (WidgetTester tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: host(initial: '/app/about')));
      await tester.pumpAndSettle();
      expect(find.text('dartvel about'), findsOneWidget);
      expect(hostRedirected, isNot(contains('/app/about')));
    });

    testWidgets('Dartvel\'s own guards still run under the mount',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: host(initial: '/app/account')));
      await tester.pumpAndSettle();
      expect(find.text('dartvel sign in'), findsOneWidget);
    });

    testWidgets('DV.Navigation goes through the same router',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: host()));
      await tester.pumpAndSettle();
      expect(find.text('host home'), findsOneWidget);
      DV.Navigation.navigate(const DVRouteTarget('/about'));
      await tester.pumpAndSettle();
      expect(find.text('dartvel about'), findsOneWidget);
    });
  });

  group('Navigator 2.0: the app\'s own RouterDelegate', () {
    testWidgets('one entry in its pages runs Dartvel\'s whole route table, '
        'and follows the delegate\'s location', (WidgetTester tester) async {
      final _SampleDelegate delegate = _SampleDelegate(Uri.parse('/app/about'));
      addTearDown(delegate.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerDelegate: delegate,
        routeInformationParser: const _UriParser(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('dartvel about'), findsOneWidget);

      // The app moves to another Dartvel location: the same page follows it
      // rather than staying where it was first opened.
      delegate.go(Uri.parse('/app'));
      await tester.pumpAndSettle();
      expect(find.text('dartvel home'), findsOneWidget);

      delegate.go(Uri.parse('/profile'));
      await tester.pumpAndSettle();
      expect(find.text('host /profile'), findsOneWidget);
    });

    testWidgets('navigating inside Dartvel is reported to the delegate, so '
        'its location and the address bar agree', (WidgetTester tester) async {
      final _SampleDelegate delegate = _SampleDelegate(Uri.parse('/app'));
      addTearDown(delegate.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerDelegate: delegate,
        routeInformationParser: const _UriParser(),
      ));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('dartvel home'))).go('/about');
      await tester.pumpAndSettle();
      expect(find.text('dartvel about'), findsOneWidget);
      expect(delegate.currentConfiguration, Uri.parse('/app/about'));
    });

    test('a location that is not Dartvel\'s has no Dartvel pages', () {
      expect(dvPages(Uri.parse('/profile'), routes, at: '/app'), isEmpty);
      expect(dvPages(Uri.parse('/app/about'), routes, at: '/app'), hasLength(1));
    });
  });

  group('MaterialApp.router with the app\'s own RouterConfig', () {
    GoRouter hostRouter() {
      final GoRouter router = GoRouter(routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('host home')),
        GoRoute(path: '/profile', builder: (_, _) => const Text('host profile')),
      ]);
      addTearDown(router.dispose);
      return router;
    }

    Future<void> open(WidgetTester tester, RouterConfig<Object> config,
        String location) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: config));
      await tester.pumpAndSettle();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(MethodCall(
            'pushRouteInformation', <String, Object?>{'location': location})),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a deep link to a Dartvel path opens Dartvel\'s page',
        (WidgetTester tester) async {
      final RouterConfig<Object> config =
          dvRouterConfig(routes, at: '/app', existing: hostRouter());
      await open(tester, config, '/app/about');
      expect(find.text('dartvel about'), findsOneWidget);
    });

    testWidgets('any other location is the app\'s config\'s to answer',
        (WidgetTester tester) async {
      final RouterConfig<Object> config =
          dvRouterConfig(routes, at: '/app', existing: hostRouter());
      await open(tester, config, '/profile');
      expect(find.text('host profile'), findsOneWidget);
    });

    testWidgets('back from Dartvel\'s first page returns to the app\'s',
        (WidgetTester tester) async {
      final RouterConfig<Object> config =
          dvRouterConfig(routes, at: '/app', existing: hostRouter());
      await open(tester, config, '/profile');
      await open(tester, config, '/app');
      unawaited(
          GoRouter.of(tester.element(find.text('dartvel home'))).push('/about'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('dartvel home'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('host profile'), findsOneWidget);
    });

    testWidgets('with no config of the app\'s, it is Dartvel\'s alone',
        (WidgetTester tester) async {
      await open(tester, dvRouterConfig(routes), '/about');
      expect(find.text('dartvel about'), findsOneWidget);
    });
  });
}

/// A Navigator 2.0 app as people write one: a RouterDelegate over a Uri that
/// builds its own pages, with Dartvel's added by dvPages.
class _SampleDelegate extends RouterDelegate<Uri>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Uri> {
  _SampleDelegate(this._location);

  Uri _location;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Uri get currentConfiguration => _location;

  void go(Uri location) {
    _location = location;
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(Uri configuration) async => go(configuration);

  // The sample opens where it was made, not at the platform's '/'.
  @override
  Future<void> setInitialRoutePath(Uri configuration) async {}

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        pages: <Page<Object?>>[
          MaterialPage<void>(child: Text('host $_location')),
          ...dvPages(_location, routes, at: '/app', onLocationChanged: go),
        ],
        onDidRemovePage: (_) {},
      );
}

class _UriParser extends RouteInformationParser<Uri> {
  const _UriParser();

  @override
  Future<Uri> parseRouteInformation(RouteInformation routeInformation) async =>
      routeInformation.uri;

  @override
  RouteInformation restoreRouteInformation(Uri configuration) =>
      RouteInformation(uri: configuration);
}
