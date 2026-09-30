// Studio is routes of the application, not an application of its own.
//
// dvStudioRoutes is what the generated router mounts at the Studio mount:
// <mount>, guarded by the Studio grant on the client as the server guards it
// before anything is rendered, and <mount>/login, Studio's sign-in, for
// anybody. Studio's screens are a deferred library loaded only once the
// guard has let the caller through, so a caller with no grant never has a
// Studio section built -- or its code fetched.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/find/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Server {
  _Server({required this.granted});

  bool granted;
  final List<String> calls = <String>[];

  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    switch ('$method $path') {
      case 'GET api/access':
        return DVStudioReply(200, <String, Object?>{'granted': granted});
      case 'GET api/me':
        return const DVStudioReply(200, <String, Object?>{
          'userId': 'u-ops',
          'email': 'ops@example.com',
        });
      case 'POST api/auth/sign-out':
        granted = false;
        return const DVStudioReply(204, null);
      case 'POST api/auth/sign-in':
        // The operator's account, which holds the grant.
        granted = true;
        return const DVStudioReply(200, <String, Object?>{
          'mfaRequired': false,
        });
      case 'GET api/models':
        return const DVStudioReply(200, <String, Object?>{
          'models': <Object?>[],
          'studioModels': <Object?>[],
        });
      case 'GET api/site':
        return const DVStudioReply(200, <String, Object?>{
          'pages': <Object?>[],
        });
      case 'GET api/pages':
        return const DVStudioReply(200, <String, Object?>{
          'pages': <Object?>[],
        });
    }
    return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
  }
}

Future<GoRouter> _open(
  WidgetTester tester,
  _Server server,
  String location, {
  List<String>? opened,
  List<String> signInReturns = const <String>[],
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GoRouter router = GoRouter(
    initialLocation: location,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const Text('the shop')),
      ...dvStudioRoutes(
        mount: '/__studio',
        title: 'Studio · shop',
        transport: server.call,
        open: (String path) => opened?.add(path),
        signInReturns: signInReturns,
        location: (GoRouterState state) =>
            Uri.parse('https://shop.example${state.uri}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

bool _dataRequested(_Server server) => server.calls.any(
  (String call) =>
      call != 'GET api/access' && !call.startsWith('POST api/auth/'),
);

void main() {
  setUpAll(dvStudioLoadLibrariesForTest);

  testWidgets('a caller with no grant is sent to the sign-in and never has a '
      'Studio section built', (WidgetTester tester) async {
    final _Server server = _Server(granted: false);
    final GoRouter router = await _open(tester, server, '/__studio');

    expect(router.state.uri.path, '/__studio/login');
    expect(router.state.uri.queryParameters['from'], '/__studio');
    expect(find.byType(DVStudioSignInScreen), findsOneWidget);
    expect(find.byType(DVStudioScreen), findsNothing);
    expect(find.text('Site map'), findsNothing);
    expect(find.text('Team'), findsNothing);
    // Asked whether it may, and nothing else: no records, pages or graph.
    expect(_dataRequested(server), isFalse, reason: '${server.calls}');
  });

  testWidgets('a granted caller gets Studio at the mount', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(granted: true);
    final GoRouter router = await _open(tester, server, '/__studio');

    expect(router.state.uri.path, '/__studio');
    expect(find.byType(DVStudioScreen), findsOneWidget);
    expect(find.byType(DVStudioSignInScreen), findsNothing);
  });

  testWidgets('Studio is on the shared page shell: the browser''s find '
      'reaches it and its text can be selected', (
    WidgetTester tester,
  ) async {
    // Studio built its route straight to DVStudioHost, with no DVPageShell
    // above it. Everything the shell carries -- the find registration the
    // browser matches against, the selection area, keyboard scrolling, the
    // D-pad -- was therefore missing on exactly the screen a person spends
    // their day in, and Ctrl+F over Studio found nothing. A Studio screen is
    // a page; it goes through the page.
    final _Server server = _Server(granted: true);
    await _open(tester, server, '/__studio');

    expect(find.byType(DVStudioScreen), findsOneWidget);
    final Finder shell = find.byType(DVPageShell);
    expect(shell, findsOneWidget,
        reason: 'Studio must be drawn through DVPageShell, not beside it');
    // The shell must be above Studio's frame, not inside it, or the
    // registrar the selection needs is Studio's own.
    expect(
      find.descendant(of: shell, matching: find.byType(DVStudioScreen)),
      findsOneWidget,
    );
    // Registered, and findable: the block the browser matches is written
    // from the page, and a Studio page that is not findable would opt out
    // of the one thing every page gets by default.
    final DVPageScaffoldSpec spec =
        tester.widget<DVPageShell>(shell).spec;
    expect(spec.findable, isTrue);
    expect(spec.selectable, isTrue);
    // And the find copy is not empty: Studio drew its section names, and
    // they are what a person searching for "Site map" is looking for.
    expect(DVFindInPage.paragraphs(), isNotEmpty);
    expect(
      DVFindInPage.paragraphs().map((DVFoundParagraph p) => p.block.text),
      contains('Site map'),
    );
    // A selection area above Studio's text, so a drag selects it.
    expect(find.byType(SelectionArea), findsWidgets);
  });

  testWidgets('the sign-in is a page too, and registers the same way', (
    WidgetTester tester,
  ) async {
    // The sign-in is a route like any other. It was drawn without the shell
    // for the same reason Studio was, so the one field on it that a person
    // pastes a password into was not part of any find or selection surface.
    final _Server server = _Server(granted: false);
    await _open(tester, server, '/__studio');

    expect(find.byType(DVStudioSignInScreen), findsOneWidget);
    final Finder shell = find.byType(DVPageShell);
    expect(shell, findsOneWidget);
    expect(
      find.descendant(of: shell, matching: find.byType(DVStudioSignInScreen)),
      findsOneWidget,
    );
    expect(DVFindInPage.paragraphs(), isNotEmpty);
  });

  testWidgets('the sign-in is a route for anybody, and sends a signed-in, '
      'granted person on to where they were going', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(granted: false);
    final List<String> opened = <String>[];
    final GoRouter router = await _open(
      tester,
      server,
      '/__studio/login?from=/__studio',
      opened: opened,
    );

    expect(router.state.uri.path, '/__studio/login');
    expect(find.byType(DVStudioSignInScreen), findsOneWidget);
    expect(find.byType(DVStudioScreen), findsNothing);
    expect(_dataRequested(server), isFalse, reason: '${server.calls}');

    await tester.enterText(
      find.byKey(const ValueKey<String>('dv-studio-sign-in-email')),
      'ops@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('dv-studio-sign-in-password')),
      'a-long-enough-password-1',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('dv-studio-sign-in-submit')),
    );
    await tester.pumpAndSettle();
    // Loaded from the server as a page, so the server decides on the grant
    // before Studio is rendered or its code is handed over.
    expect(opened, <String>['/__studio']);
  });

  testWidgets('Studio shows who is signed in, and signing out ends the '
      'session and leaves Studio', (WidgetTester tester) async {
    final _Server server = _Server(granted: true);
    final List<String> opened = <String>[];
    await _open(tester, server, '/__studio', opened: opened);

    expect(find.byType(DVStudioScreen), findsOneWidget);
    final Finder account =
        find.byKey(const ValueKey<String>('dv-studio-account'));
    expect(account, findsOneWidget);
    expect(find.descendant(of: account, matching: find.text('ops@example.com')),
        findsOneWidget);
    final Finder signOut =
        find.byKey(const ValueKey<String>('dv-studio-sign-out'));
    expect(signOut, findsOneWidget);
    expect(find.descendant(of: signOut, matching: find.text('Sign out')),
        findsOneWidget);

    await tester.tap(signOut);
    await tester.pumpAndSettle();
    // Ended on the server, then away to the sign-in as a page load.
    expect(server.calls, contains('POST api/auth/sign-out'));
    expect(opened, <String>['/__studio/login']);
  });

  testWidgets('the grant is asked again on every visit, not remembered', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(granted: true);
    final GoRouter router = await _open(tester, server, '/');
    router.go('/__studio');
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioScreen), findsOneWidget);

    // The grant is taken away; the next visit is refused on the client too.
    server.granted = false;
    router.go('/');
    await tester.pumpAndSettle();
    router.go('/__studio');
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/__studio/login');
    expect(find.byType(DVStudioScreen), findsNothing);
  });

  testWidgets("Studio keeps the address it was opened at: it never tells the "
      'browser it is at the root', (WidgetTester tester) async {
    // Studio's screens and its sign-in are drawn inside the application's
    // router, in a frame of their own. A frame that reported its own
    // navigator to the engine rewrote the address bar to /, so a reload
    // opened the site's home page instead of Studio.
    final List<String> reported = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation, (MethodCall call) async {
      if (call.method == 'routeInformationUpdated') {
        final Object? arguments = call.arguments;
        if (arguments is Map) reported.add('${arguments['uri'] ?? arguments['location']}');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, null));

    for (final bool granted in <bool>[true, false]) {
      reported.clear();
      final _Server server = _Server(granted: granted);
      await _open(tester, server, '/__studio');
      expect(reported, isNotEmpty);
      expect(reported.where((String uri) => Uri.parse(uri).path == '/'),
          isEmpty,
          reason: 'granted: $granted, reported: $reported');
    }
  });

  testWidgets('the first-run setup is a route of the application, drawn '
      'before anybody has signed in', (WidgetTester tester) async {
    final _Server server = _Server(granted: false);
    final GoRouter router = await _open(tester, server, '/__studio/setup');
    expect(router.state.uri.path, '/__studio/setup');
    expect(find.byType(DVStudioFirstRunScreen), findsOneWidget);
    expect(find.byType(DVStudioScreen), findsNothing);
    expect(_dataRequested(server), isFalse, reason: '${server.calls}');
  });

  testWidgets('signing in from another page Studio guards, such as the docs '
      'site, goes back there', (WidgetTester tester) async {
    final _Server server = _Server(granted: false);
    final List<String> opened = <String>[];
    await _open(tester, server, '/__studio/login?from=/docs/models',
        opened: opened, signInReturns: const <String>['/docs']);
    await tester.enterText(
        find.byKey(const ValueKey<String>('dv-studio-sign-in-email')),
        'ops@example.com');
    await tester.enterText(
        find.byKey(const ValueKey<String>('dv-studio-sign-in-password')),
        'a-long-enough-password-1');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-sign-in-submit')));
    await tester.pumpAndSettle();
    expect(opened, <String>['/docs/models']);
  });

  testWidgets('the Studio route hands Studio the application''s page views and '
      'its look, taken above Studio''s own frame', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final _Server server = _Server(granted: true);
    Widget? view(String path, {Widget? content, bool layout = true}) =>
        content ?? Text('page at $path');
    final ThemeData light = ThemeData(scaffoldBackgroundColor: const Color(0xFF123456));
    final ThemeData dark = ThemeData(brightness: Brightness.dark);
    final GoRouter router = GoRouter(
      initialLocation: '/__studio',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('the shop')),
        ...dvStudioRoutes(
          mount: '/__studio',
          transport: server.call,
          view: view,
          location: (GoRouterState state) =>
              Uri.parse('https://shop.example${state.uri}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      theme: light,
      darkTheme: dark,
      themeMode: ThemeMode.light,
    ));
    await tester.pumpAndSettle();

    final DVStudioHost host = tester.widget<DVStudioHost>(find.byType(DVStudioHost));
    expect(host.view, same(view));
    expect(host.look!.theme, same(light));
    expect(host.look!.darkTheme, same(dark));
    expect(host.look!.themeMode, ThemeMode.light);
    // Studio itself is drawn in its own theme, not the shop's.
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey<String>('dv-studio-rail'))))
          .scaffoldBackgroundColor,
      isNot(const Color(0xFF123456)),
    );
  });
}
