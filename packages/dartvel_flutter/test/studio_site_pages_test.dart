// Studio's Pages lists every page the application answers, and opens each.
//
// It listed only what Studio had stored, so a site whose fifty pages are all
// compiled opened on "0 / No stored pages yet". A site is its compiled
// routes -- from the application's own route manifest, or from the graph a
// build writes beside a served Studio -- and its stored pages, each marked
// code, Studio, or override. A compiled page opens as what it is made of,
// read-only; editing it makes an override that takes the route over when it
// is deployed, and deleting the override brings the compiled page back
// (NEW_SPEC.md, Dartvel Studio, Publishing).
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A project's route manifest, as the generator writes one.
const List<DVRouteInfo> _shopRoutes = <DVRouteInfo>[
  DVRouteInfo(path: '/', page: 'indexPage', directory: 'lib/pages/index.dart'),
  DVRouteInfo(
    path: '/about',
    page: 'aboutPage',
    directory: 'lib/pages/about.dart',
  ),
  DVRouteInfo(
    path: '/products/:slug',
    page: 'productPage',
    directory: 'lib/pages/products/[slug].dart',
    parameters: <String>['slug'],
  ),
];

/// A compiled page, as its route would build it.
Widget _about() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          headingLevel: 1,
          child: const Text('About the shop'),
        ),
        const Text('We roast on Tuesdays.'),
        const DVNavLink(to: DVRouteTarget('/'), child: Text('Home')),
      ],
    );

Widget _host({
  List<DVRouteInfo> routes = _shopRoutes,
  Widget? Function(String path)? preview,
}) =>
    MaterialApp(
      home: Material(
        child: DVStudioInApp(routes: routes, preview: preview),
      ),
    );

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('every compiled page is listed, marked as code, with no store',
      (WidgetTester tester) async {
    desktop(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    for (final String route in <String>['/', '/about', '/products/:slug']) {
      expect(_key('dv-studio-route-$route'), findsOneWidget, reason: route);
      expect(_key('dv-studio-route-kind-$route'), findsOneWidget,
          reason: route);
    }
    expect(find.text('No pages yet.'), findsNothing);
    // The overview counts them, rather than "0, stored in Studio".
    expect(
      find.descendant(
          of: _key('dv-studio-stat-pages'), matching: find.text('3')),
      findsOneWidget,
    );
    expect(find.text('3 in code'), findsOneWidget);
    // A dynamic route says what it takes.
    expect(find.textContaining('One page per slug'), findsWidgets);
  });

  testWidgets('a stored page and an override are told apart from code',
      (WidgetTester tester) async {
    desktop(tester);
    await const DVPageStore()
        .save(DVPageDocument(route: '/about', title: 'About us'));
    await const DVPageStore()
        .save(DVPageDocument(route: '/landing', title: 'Landing'));

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(
      find.descendant(
          of: _key('dv-studio-route-kind-/about'),
          matching: find.text('Override')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: _key('dv-studio-route-kind-/'), matching: find.text('Code')),
      findsOneWidget,
    );
    expect(_key('dv-studio-route-/landing'), findsOneWidget);
    expect(_key('dv-studio-route-kind-/landing'), findsNothing,
        reason: 'a page only Studio serves is not compiled');
    expect(find.text('3 in code · 1 made in Studio · 1 overridden'),
        findsOneWidget);
  });

  testWidgets(
      'a compiled page opens as the app draws it, read-only, until an edit '
      'makes an override that takes the route over', (WidgetTester tester) async {
    desktop(tester);
    await tester.pumpWidget(_host(
      preview: (String path) => path == '/about' ? _about() : null,
    ));
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-route-/about'));
    await tester.pumpAndSettle();

    expect(_key('dv-studio-live-page'), findsOneWidget);
    expect(find.text('We roast on Tuesdays.'), findsOneWidget);
    expect(find.text('Written in code'), findsOneWidget);
    // Nothing is offered for inserting into a page only being looked at.
    expect(find.text('Insert'), findsNothing);
    expect(find.text('Layers'), findsOneWidget);
    expect(
      find.descendant(
          of: _key('dv-studio-page-kind'), matching: find.text('Code')),
      findsOneWidget,
    );
    // Deploying a page nobody has edited would replace the compiled one with
    // a copy of it.
    await tester.tap(_key('dv-studio-publish'));
    await tester.pumpAndSettle();
    expect(await const DVPageStore().routes(), isEmpty);

    await tester.tap(_key('dv-studio-override'));
    await tester.pumpAndSettle();
    expect(_key('dv-studio-live-page'), findsNothing,
        reason: 'the override is edited on the canvas');
    expect(find.text('Editing a copy'), findsOneWidget);
    expect(find.text('Insert'), findsOneWidget);

    await tester.tap(_key('dv-studio-publish'));
    await tester.pumpAndSettle();

    final DVPageDocument? stored = await const DVPageStore().load('/about');
    expect(stored, isNotNull, reason: 'deploying stores the override');
    final List<String> texts = <String>[];
    void walk(DVPageNode node) {
      if (node.properties['text'] case final String text) texts.add(text);
      node.children.forEach(walk);
    }

    walk(stored!.root);
    // What the compiled page is made of, read off it: its heading, its text
    // and its link, which still goes where it went.
    expect(texts, containsAll(<String>['About the shop', 'We roast on Tuesdays.', 'Home']));
    // In the editor the page list marks a page's kind with a dot and names
    // it on hover; the toolbar names it outright.
    expect(
      find.descendant(
          of: _key('dv-studio-route-kind-/about'),
          matching: find.byTooltip('Override')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: _key('dv-studio-page-kind'), matching: find.text('Override')),
      findsOneWidget,
    );
    expect(find.text('Studio is serving this page'), findsOneWidget);

    // Restoring it is deleting the override: the compiled page is back.
    await tester.tap(_key('dv-studio-restore-compiled'));
    await tester.pumpAndSettle();
    expect(await const DVPageStore().load('/about'), isNull);
    expect(_key('dv-studio-live-page'), findsOneWidget);
    expect(
      find.descendant(
          of: _key('dv-studio-route-kind-/about'),
          matching: find.byTooltip('Code')),
      findsOneWidget,
    );
    expect(find.text('Written in code'), findsOneWidget);
  });

  testWidgets('a dynamic route opens as the pattern it is, not a page to copy',
      (WidgetTester tester) async {
    desktop(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-route-/products/:slug'));
    await tester.pumpAndSettle();

    expect(find.text('A page for every slug'), findsOneWidget);
    expect(_key('dv-studio-override'), findsNothing);
  });

  testWidgets('a served Studio opens a compiled page from its captured '
      'structure', (WidgetTester tester) async {
    desktop(tester);
    final List<String> asked = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVStudioScreen(
          site: DVStudioSiteSource(
            pages: () async => const <DVStudioSitePage>[
              DVStudioSitePage(
                path: '/features',
                kind: DVStudioPageKind.code,
                source: 'lib/pages/features.dart:5',
                structure: true,
              ),
            ],
            structure: (String route) async {
              asked.add(route);
              return <Object?>[
                <String, Object?>{
                  'role': null,
                  'level': 1,
                  'label': 'Twenty-five shipped sections.',
                  'href': null,
                  'children': <Object?>[],
                },
              ];
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-route-/features'));
    await tester.pumpAndSettle();

    expect(asked, <String>['/features']);
    expect(find.text('Twenty-five shipped sections.'), findsWidgets);
    expect(find.text('Written in code'), findsOneWidget);
    expect(find.textContaining('features.dart'), findsWidgets);
  });

  test('a captured structure becomes a page document', () {
    final DVPageDocument document = dvStudioDocumentFromStructure(
      '/pricing',
      <Object?>[
        <String, Object?>{
          'role': 'group',
          'label': '',
          'children': <Object?>[
            <String, Object?>{'level': 1, 'label': 'Plans'},
            <String, Object?>{'label': 'Pick one.'},
            <String, Object?>{'role': 'link', 'label': 'Docs', 'href': '/docs'},
            <String, Object?>{'role': 'button', 'label': 'Buy'},
            <String, Object?>{'role': 'img', 'label': 'A cup', 'src': 'cup.png'},
          ],
        },
      ],
    );

    expect(document.title, 'Plans');
    final List<DVPageNode> nodes = <DVPageNode>[];
    void walk(DVPageNode node) {
      nodes.add(node);
      node.children.forEach(walk);
    }

    walk(document.root);
    final DVPageNode heading =
        nodes.firstWhere((DVPageNode n) => n.properties['text'] == 'Plans');
    expect(heading.properties['fontSize'], 40);
    final DVPageNode link =
        nodes.firstWhere((DVPageNode n) => n.properties['text'] == 'Docs');
    expect(link.action, <String, Object?>{'type': 'navigate', 'to': '/docs'});
    expect(nodes.where((DVPageNode n) => n.type == 'button'), hasLength(1));
    final DVPageNode image = nodes.firstWhere((DVPageNode n) => n.type == 'image');
    expect(image.properties['src'], 'cup.png');
    expect(image.properties['alt'], 'A cup');
  });
}
