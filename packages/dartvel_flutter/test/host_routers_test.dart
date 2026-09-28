// Dartvel pages in a host that routes with Flutter's Navigator.
//
// A host on Navigator 1.0 answers onGenerateRoute; one on Navigator 2.0
// builds its own pages. Neither can take a GoRoute, so each takes a page
// that runs Dartvel's routes in a router of its own -- with Dartvel's guards,
// the host's back button reaching Dartvel's stack first, and the host's own
// routes left alone.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
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
}
