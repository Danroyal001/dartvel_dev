// A Studio screen's selection is the address, and the address is the
// selection.
//
// Studio's rail was state inside one page: every screen was drawn at
// `<mount>`, so a section could not be linked, bookmarked, reloaded or
// reached with Back, and a reload always opened Pages whatever the person was
// looking at. The server renders a document at `<mount>/<screen>` (see
// docs/studio/PARITY.md), so the client has to read that address or the two
// halves disagree: a printed link would open Pages.
//
// Object paths are addressed too: `<mount>/<screen>/<object>`, where an
// object keeps its slashes so a page is at the route it answers.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Server {
  _Server({
    required this.granted,
    this.routes = const <String>[],
    this.functions,
    this.graph = const <String, Object?>{},
    this.queues = const <Object?>[],
  });

  bool granted;

  /// The pages Studio has published, as their routes.
  final List<String> routes;
  final List<Object?>? functions;

  /// What `api/graph` answers: `jobs`, `modules` and whatever else the build
  /// wrote, keyed the way the build writes it.
  final Map<String, Object?> graph;

  /// The queues `api/queues` answers.
  final List<Object?> queues;
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
      case 'GET api/models':
        return const DVStudioReply(200, <String, Object?>{
          'models': <Object?>[
            <String, Object?>{
              'model': 'Product',
              'table': 'products',
              'key': 'id',
              'fields': <Object?>[
                <String, Object?>{'name': 'name', 'type': 'String'},
                <String, Object?>{'name': 'price', 'type': 'double'},
              ],
            },
          ],
          'studioModels': <Object?>[],
        });
      case 'GET api/models/Product/records':
        return const DVStudioReply(200, <String, Object?>{
          'records': <Object?>[
            <String, Object?>{
              'key': 'p-1',
              'version': 1,
              'values': <String, Object?>{'name': 'Chair', 'price': 40},
            },
          ],
        });
      case 'GET api/site':
        return DVStudioReply(200, <String, Object?>{
          'pages': <Object?>[],
        });
      case 'GET api/pages':
        return DVStudioReply(200, <String, Object?>{
          'pages': <Object?>[
            for (final String route in routes)
              <String, Object?>{
                'document': <String, Object?>{
                  'route': route,
                  'title': route,
                  'root': <String, Object?>{'type': 'list'},
                },
              },
          ],
        });
      case 'GET api/functions':
        return DVStudioReply(200, <String, Object?>{
          'functions': functions ?? const <Object?>[],
        });
      case 'GET api/graph':
        return DVStudioReply(200, graph);
      case 'GET api/queues':
        return DVStudioReply(200, <String, Object?>{'queues': queues});
    }
    return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
  }
}

Future<GoRouter> _at(
  WidgetTester tester,
  _Server server,
  String location,
) async {
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
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

/// The section the screen is showing, read off the body key.
String? openSection(WidgetTester tester) {
  for (final String id in <String>[
    'pages',
    'components',
    'shortcuts',
    'models',
    'routes',
    'frontend',
    'functions',
    'modules',
    'jobs',
    'queues',
    'cache',
    'repository',
    'access',
  ]) {
    if (find
        .byKey(ValueKey<String>('dv-studio-body-$id'))
        .evaluate()
        .isNotEmpty) {
      return id;
    }
  }
  return null;
}

/// Whether the thing under [key] is the one the address names.
///
/// Read from whichever widget the screen draws for it: a list row says so with
/// its own flag, and a table row or a card is marked by the colour of the
/// background behind it.
bool _selected(WidgetTester tester, String key) {
  final Finder row = find.byKey(ValueKey<String>(key));
  final Iterable<DVStudioListRow> listRows = tester
      .widgetList<DVStudioListRow>(
        find.byWidgetPredicate((Widget widget) => widget is DVStudioListRow),
      )
      .where((DVStudioListRow listRow) => listRow.key == ValueKey<String>(key));
  if (listRows.isNotEmpty) return listRows.first.selected;
  return tester
      .widgetList<Container>(
        find.descendant(of: row, matching: find.byType(Container)),
      )
      .any((Container container) =>
          container.decoration is BoxDecoration &&
          (container.decoration! as BoxDecoration).color == DVStudioStyle.selected);
}

void main() {
  setUpAll(dvStudioLoadLibrariesForTest);

  testWidgets('the address names the section, and the mount is Pages', (
    WidgetTester tester,
  ) async {
    for (final (String path, String section) in <(String, String)>[
      ('/__studio', 'pages'),
      ('/__studio/pages', 'pages'),
      ('/__studio/models', 'models'),
      ('/__studio/jobs', 'jobs'),
      ('/__studio/access', 'access'),
    ]) {
      final _Server server = _Server(granted: true);
      await _at(tester, server, path);
      expect(openSection(tester), section, reason: path);
    }
  });

  testWidgets('choosing a section in the rail moves the address', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(granted: true);
    final GoRouter router = await _at(tester, server, '/__studio');

    await tester.tap(
      find.byKey(const ValueKey<String>('dv-studio-section-access')),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/__studio/access');
    expect(openSection(tester), 'access');
  });

  testWidgets('an object in the address is opened, and stays in the address', (
    WidgetTester tester,
  ) async {
    // `/__studio/models/Product` is the Data section with Product open: the
    // list beside the records, with the records of that one model.
    final _Server server = _Server(granted: true);
    final GoRouter router = await _at(tester, server, '/__studio/models/Product');

    expect(openSection(tester), 'models');
    expect(find.text('Chair'), findsWidgets,
        reason: 'the records of the named model, not the first model there is');
    expect(router.state.uri.path, '/__studio/models/Product');
  });

  testWidgets('choosing another model in the list moves the address', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(granted: true);
    final GoRouter router = await _at(tester, server, '/__studio/models');

    await tester.tap(
      find.byKey(const ValueKey<String>('dv-studio-model-Product')),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/__studio/models/Product');
  });

  testWidgets('a page in the address is the one open on the canvas', (
    WidgetTester tester,
  ) async {
    // The object half of a page's address is its route, slashes and all, so
    // `/__studio/pages/shop/product` is the page at `/shop/product` and not
    // two segments of some other name.
    final _Server server = _Server(
      granted: true,
      routes: <String>['/', '/shop/product'],
    );
    await _at(tester, server, '/__studio/pages/shop/product');

    expect(openSection(tester), 'pages');
    expect(
      _selected(tester, 'dv-studio-route-/shop/product'),
      isTrue,
      reason: 'the page the address names',
    );
    expect(
      _selected(tester, 'dv-studio-route-/'),
      isFalse,
      reason: 'not the first page there is',
    );
  });

  testWidgets('choosing a page in the list moves the address', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(
      granted: true,
      routes: <String>['/', '/shop/product'],
    );
    final GoRouter router = await _at(tester, server, '/__studio/pages');

    await tester.tap(
      find.byKey(const ValueKey<String>('dv-studio-route-/shop/product')),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/__studio/pages/shop/product');
    expect(_selected(tester, 'dv-studio-route-/shop/product'), isTrue);
  });

  testWidgets('a function in the address is the one open in the builder', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(
      granted: true,
      functions: <Object?>[
        <String, Object?>{
          'document': <String, Object?>{'name': 'sendReceipt'},
        },
        <String, Object?>{
          'document': <String, Object?>{'name': 'chargeCard'},
        },
      ],
    );
    await _at(tester, server, '/__studio/functions/chargeCard');

    expect(openSection(tester), 'functions');
    expect(_selected(tester, 'dv-studio-function-chargeCard'), isTrue,
        reason: 'the function the address names');
    expect(_selected(tester, 'dv-studio-function-sendReceipt'), isFalse);
  });

  testWidgets('choosing a function in the list moves the address', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(
      granted: true,
      functions: <Object?>[
        <String, Object?>{
          'document': <String, Object?>{'name': 'sendReceipt'},
        },
      ],
    );
    final GoRouter router = await _at(tester, server, '/__studio/functions');

    await tester.tap(
      find.byKey(const ValueKey<String>('dv-studio-function-sendReceipt')),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/__studio/functions/sendReceipt');
  });

  testWidgets('an address naming no section is the application\'s own answer',
      (WidgetTester tester) async {
    // The server draws no document at a path that names no screen, and
    // answers it as a path nothing serves; the client must agree, or a
    // scanner walking the mount would find a Studio screen at every guess.
    final _Server server = _Server(granted: true);
    await _at(tester, server, '/__studio/nope');

    expect(find.byType(DVStudioScreen), findsNothing);
  });

  testWidgets('the browser''s Back goes back through the sections', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(granted: true);
    final GoRouter router = await _at(tester, server, '/__studio');

    await tester.tap(
      find.byKey(const ValueKey<String>('dv-studio-section-jobs')),
    );
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/__studio/jobs');

    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/__studio');
    expect(openSection(tester), 'pages');
  });

  testWidgets('a task in the address is the row the address names', (
    WidgetTester tester,
  ) async {
    // The server prints a document at `<mount>/jobs/<name>` for every task the
    // graph declares, so a task has an address of its own whether or not the
    // list here has anything to show for it.
    final _Server server = _Server(
      granted: true,
      graph: <String, Object?>{
        'jobs': <Object?>[
          <String, Object?>{'name': 'sendReceipt', 'queue': 'mail'},
          <String, Object?>{'name': 'chargeCard', 'queue': 'payments'},
        ],
      },
    );
    final GoRouter router = await _at(tester, server, '/__studio/jobs/chargeCard');

    expect(openSection(tester), 'jobs');
    expect(_selected(tester, 'dv-studio-job-chargeCard'), isTrue);
    expect(_selected(tester, 'dv-studio-job-sendReceipt'), isFalse);
    expect(router.state.uri.path, '/__studio/jobs/chargeCard');
  });

  testWidgets('choosing a task in the list moves the address', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(
      granted: true,
      graph: <String, Object?>{
        'jobs': <Object?>[
          <String, Object?>{'name': 'sendReceipt', 'queue': 'mail'},
        ],
      },
    );
    final GoRouter router = await _at(tester, server, '/__studio/jobs');

    await tester.tap(
      find.byKey(const ValueKey<String>('dv-studio-job-sendReceipt')),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/__studio/jobs/sendReceipt');
  });

  testWidgets('a queue in the address is the queue that is open', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(
      granted: true,
      queues: <Object?>[
        <String, Object?>{'name': 'mail', 'pending': <Object?>[]},
        <String, Object?>{'name': 'payments', 'pending': <Object?>[]},
      ],
    );
    final GoRouter router = await _at(tester, server, '/__studio/queues/payments');

    expect(openSection(tester), 'queues');
    expect(_selected(tester, 'dv-studio-queue-payments'), isTrue);
    expect(_selected(tester, 'dv-studio-queue-mail'), isFalse);
    expect(router.state.uri.path, '/__studio/queues/payments');
  });

  testWidgets('choosing a queue moves the address', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(
      granted: true,
      queues: <Object?>[
        <String, Object?>{'name': 'mail', 'pending': <Object?>[]},
        <String, Object?>{'name': 'payments', 'pending': <Object?>[]},
      ],
    );
    final GoRouter router = await _at(tester, server, '/__studio/queues');

    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-queue-payments')));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/__studio/queues/payments');
  });

  testWidgets('a module in the address is the card the address names', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server(
      granted: true,
      graph: <String, Object?>{
        'modules': <Object?>[
          <String, Object?>{'id': 'shop', 'mount': '/store', 'pages': 3},
          <String, Object?>{'id': 'help', 'mount': '/help', 'pages': 2},
        ],
      },
    );
    final GoRouter router = await _at(tester, server, '/__studio/modules/help');

    expect(openSection(tester), 'modules');
    expect(_selected(tester, 'dv-studio-module-help'), isTrue);
    expect(_selected(tester, 'dv-studio-module-shop'), isFalse);
    expect(router.state.uri.path, '/__studio/modules/help');
  });

  testWidgets('a screen whose object this build has no list for keeps its '
      'address', (WidgetTester tester) async {
    // The modules screen has no list to select from when nothing is declared,
    // and the address still names a screen: rewriting it to the first screen
    // would move a person off the link they followed.
    final _Server server = _Server(granted: true);
    final GoRouter router = await _at(tester, server, '/__studio/queues/mail');

    expect(openSection(tester), 'queues');
    expect(router.state.uri.path, '/__studio/queues/mail');
  });

  testWidgets('the sign-in and the setup are not screens and answer as '
      'themselves', (WidgetTester tester) async {
    final _Server server = _Server(granted: false);
    final GoRouter router = await _at(tester, server, '/__studio/setup');
    expect(router.state.uri.path, '/__studio/setup');
    expect(find.byType(DVStudioFirstRunScreen), findsOneWidget);
  });

  testWidgets('a signed-out visit to a screen keeps where it was going', (
    WidgetTester tester,
  ) async {
    // The screen is in the address, so the sign-in has to hand it back: a
    // person sent to the sign-in from `/__studio/models` must arrive at the
    // Data section, not at Pages.
    final _Server server = _Server(granted: false);
    final GoRouter router = await _at(tester, server, '/__studio/models');

    expect(router.state.uri.path, '/__studio/login');
    expect(router.state.uri.queryParameters['from'], '/__studio/models');
  });
}