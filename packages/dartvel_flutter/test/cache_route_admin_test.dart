// The cache/tag explorer and the route/page explorer, against real state.
//
// Both replace pages that were static labels. What makes them worth having is
// that they answer questions the running app cannot: what would revalidating
// this tag drop, and which routes are currently served by a stored document
// instead of the page that was compiled in.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument documentFor(String route) {
  final document = DVPageDocument(route: route, title: route);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(route), parent: document.root.id);
  return document;
}

const List<DVRouteInfo> manifest = <DVRouteInfo>[
  DVRouteInfo(path: '/', page: 'IndexPage', directory: 'lib/pages'),
  DVRouteInfo(path: '/pricing', page: 'PricingPage', directory: 'lib/pages'),
  DVRouteInfo(
    path: '/posts/:slug',
    page: 'PostsSlugPage',
    directory: 'lib/pages/posts',
    parameters: <String>['slug'],
  ),
];

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    const DVTestHarness().resetCacheTags();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
    const DVTestHarness().resetCacheTags();
  });

  group('cache explorer', () {
    Widget host() => const MaterialApp(home: Material(child: DVCacheAdmin()));

    testWidgets('an untagged cache says so rather than looking broken',
        (WidgetTester tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('No tagged cache entries.'), findsOneWidget);
    });

    testWidgets('tags list the keys they cover', (WidgetTester tester) async {
      const cache = DVCache();
      await cache.set('posts:1', 'a');
      await cache.set('posts:2', 'b');
      cache.tag('posts:1', <String>['posts']);
      cache.tag('posts:2', <String>['posts']);
      cache.tag('posts:1', <String>['home']);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // The keys are the answer to "what would revalidating this drop?".
      expect(find.text('posts'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);
      expect(find.text('2 keys'), findsOneWidget);
      expect(find.text('1 key'), findsOneWidget);
    });

    testWidgets('revalidating a tag drops its entries',
        (WidgetTester tester) async {
      const cache = DVCache();
      await cache.set('posts:1', 'a');
      cache.tag('posts:1', <String>['posts']);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('dv-cache-revalidate-posts')));
      await tester.pumpAndSettle();

      expect(await cache.get<String>('posts:1'), isNull);
      // The count distinguishes clearing a hundred entries from clearing none.
      expect(find.text('Revalidated posts: 1 entry dropped.'), findsOneWidget);
      expect(find.text('No tagged cache entries.'), findsOneWidget);
    });
  });

  group('route explorer', () {
    Widget host() => const MaterialApp(
          home: Material(child: DVRouteAdmin(routes: manifest)),
        );

    testWidgets('every compiled route is listed with its page',
        (WidgetTester tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('/pricing'), findsOneWidget);
      expect(find.text('PricingPage'), findsOneWidget);
      expect(find.text('lib/pages/posts'), findsOneWidget);
      expect(find.text('3 compiled, 0 overridden, 0 from the store only'),
          findsOneWidget);
    });

    testWidgets('a dynamic route names its parameters',
        (WidgetTester tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('parameters: slug'), findsOneWidget);
    });

    testWidgets('a route with a stored document is reported as overridden',
        (WidgetTester tester) async {
      await const DVPageStore().save(documentFor('/pricing'));

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // The running app looks identical either way; this is the only place
      // that says which source is winning.
      expect(
        find.text('served from the store, overriding the compiled page'),
        findsOneWidget,
      );
      expect(find.text('served from the compiled page'), findsNWidgets(2));
      expect(find.text('3 compiled, 1 overridden, 0 from the store only'),
          findsOneWidget);
    });

    testWidgets('a stored route with no compiled page is still shown',
        (WidgetTester tester) async {
      // The editor adds pages as well as editing them, and those exist
      // nowhere in the generated manifest.
      await const DVPageStore().save(documentFor('/launch'));

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('/launch'), findsOneWidget);
      expect(find.text('added in the Studio; no compiled page'), findsOneWidget);
      expect(find.text('3 compiled, 0 overridden, 1 from the store only'),
          findsOneWidget);
    });

    testWidgets('an app with no routes says so', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Material(child: DVRouteAdmin(routes: <DVRouteInfo>[])),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No routes generated yet.'), findsOneWidget);
    });
  });

  testWidgets('more routes than fit the screen scroll instead of overflowing',
      (WidgetTester tester) async {
    // A route explorer is a list of unknown length. Rendered in a plain
    // column, everything past the fold is not merely off screen — it throws
    // a layout overflow and cannot be reached at all.
    final many = <DVRouteInfo>[
      for (var i = 0; i < 40; i++)
        DVRouteInfo(path: '/page$i', page: 'Page$i', directory: 'lib/pages'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVRouteAdmin(routes: many)),
    ));
    await tester.pumpAndSettle();

    // The overflow was a thrown layout assertion, not merely clipping.
    expect(tester.takeException(), isNull);

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);
    expect(position.maxScrollExtent, greaterThan(0),
        reason: 'the list must have somewhere to scroll to');

    await tester.drag(find.byType(DVRouteAdmin), const Offset(0, -2000));
    await tester.pumpAndSettle();

    // The rest of the list is reachable, which is the whole point.
    expect(position.pixels, greaterThan(0));
    expect(find.text('/page39'), findsOneWidget);
  });
}
