// Reusable components, in free Studio.
//
// A component is made once and used on any page: edited once, it changes
// everywhere it is used. Its props -- text, a picture, a colour, what a tap
// does -- are what each use sets for itself. A component is stored as a
// document beside the pages, at /_dartvel/components/<Name>, so it travels
// the way a page does; a page stores only where it uses one, and the page is
// drawn from the component each time.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A card: a title, a picture, a colour behind it, and a button whose tap
/// each use decides.
DVPageDocument _card() => dvStudioComponent(
      'PriceCard',
      root: DVPageNode(
        type: 'box',
        properties: <String, Object?>{
          'padding': 16,
          'backgroundColor': '{{tint}}',
        },
        children: <DVPageNode>[
          DVPageNode(
            type: 'text',
            properties: <String, Object?>{'text': '{{title}} a month'},
          ),
          DVPageNode(
            type: 'image',
            properties: <String, Object?>{'src': '{{picture}}'},
          ),
          DVPageNode(
            type: 'button',
            properties: <String, Object?>{'text': 'Choose'},
            action: <String, Object?>{'type': 'prop', 'name': 'onChoose'},
          ),
        ],
      ),
      props: const <DVStudioComponentProp>[
        DVStudioComponentProp('title', DVStudioPropKind.text, '£5'),
        DVStudioComponentProp('picture', DVStudioPropKind.image, ''),
        DVStudioComponentProp('tint', DVStudioPropKind.colour, '#FFFFFF'),
        DVStudioComponentProp('onChoose', DVStudioPropKind.action, null),
      ],
    );

List<DVPageNode> _all(DVPageNode node) => <DVPageNode>[
      node,
      for (final DVPageNode child in node.children) ..._all(child),
    ];

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

  test('a component is kept at its own address, with its props', () {
    final DVPageDocument card = _card();
    expect(card.route, '/_dartvel/components/PriceCard');
    expect(dvStudioComponentName(card.route), 'PriceCard');
    expect(dvStudioComponentName('/pricing'), isNull);
    expect(
      <String>[for (final p in dvStudioComponentPropsOf(card)) p.name],
      <String>['title', 'picture', 'tint', 'onChoose'],
    );
    // The props survive the store's round trip.
    final DVPageDocument back = DVPageDocument.fromJson(card.toJson());
    expect(dvStudioComponentPropsOf(back).first.value, '£5');
    expect(dvStudioComponentPropsOf(back).last.kind, DVStudioPropKind.action);
  });

  test('a use of it is the component with its own props filled in, and the '
      'component\'s defaults for the rest', () {
    final DVPageNode use = dvStudioComponentInstance('PriceCard', props: <String, Object?>{
      'title': '£9',
      'tint': '#FFE7C2',
      'onChoose': <String, Object?>{'type': 'navigate', 'to': '/checkout'},
    });
    final DVPageNode? drawn = dvStudioExpandComponent(
      use,
      lookup: (String route) => route == _card().route ? _card() : null,
    );
    expect(drawn, isNotNull);
    final List<DVPageNode> nodes = _all(drawn!);
    expect(nodes.first.properties['backgroundColor'], '#FFE7C2');
    expect(nodes.first.properties['padding'], 16);
    expect(nodes[1].properties['text'], '£9 a month');
    expect(nodes[2].properties['src'], '', reason: 'the default');
    expect(nodes[3].action, <String, Object?>{'type': 'navigate', 'to': '/checkout'});

    final DVPageNode? plain = dvStudioExpandComponent(
      dvStudioComponentInstance('PriceCard'),
      lookup: (String route) => _card(),
    );
    expect(_all(plain!)[1].properties['text'], '£5 a month');
    expect(_all(plain)[3].action, isNull,
        reason: 'a tap nobody decided does nothing');
  });

  test('a component that is gone, or that uses itself, draws nothing rather '
      'than failing the page', () {
    expect(
      dvStudioExpandComponent(dvStudioComponentInstance('Gone'),
          lookup: (_) => null),
      isNull,
    );
    final DVPageDocument loop = dvStudioComponent(
      'Loop',
      root: DVPageNode(type: 'box', children: <DVPageNode>[
        dvStudioComponentInstance('Loop'),
      ]),
    );
    final DVPageNode? drawn = dvStudioExpandComponent(
      dvStudioComponentInstance('Loop'),
      lookup: (_) => loop,
    );
    expect(drawn, isNotNull);
    expect(_all(drawn!).where((DVPageNode n) => n.type == 'component'), isEmpty);
  });

  testWidgets('a page draws each use from the stored component, and an edit '
      'to the component changes every use at once', (WidgetTester tester) async {
    await const DVPageStore().save(_card());
    final DVPageDocument page = DVPageDocument(
      route: '/pricing',
      root: DVPageNode(type: 'box', children: <DVPageNode>[
        dvStudioComponentInstance('PriceCard', props: <String, Object?>{'title': '£9'}),
        dvStudioComponentInstance('PriceCard', props: <String, Object?>{'title': '£19'}),
      ]),
    );
    await tester.pumpWidget(MaterialApp(home: Material(child: DVPageDocumentRenderer(page))));
    await tester.pumpAndSettle();
    expect(find.text('£9 a month'), findsOneWidget);
    expect(find.text('£19 a month'), findsOneWidget);

    final DVPageDocument edited = _card();
    edited.root.children.first.properties['text'] = '{{title}} per month';
    await const DVPageStore().save(edited);
    await tester.pumpAndSettle();
    expect(find.text('£9 per month'), findsOneWidget);
    expect(find.text('£19 per month'), findsOneWidget);
  });

  test('the exported code has the component\'s widgets in it', () async {
    await const DVPageStore().save(_card());
    final DVPageDocument page = DVPageDocument(
      route: '/pricing',
      root: DVPageNode(type: 'box', children: <DVPageNode>[
        dvStudioComponentInstance('PriceCard', props: <String, Object?>{'title': '£9'}),
      ]),
    );
    final String source = page.toDartSource();
    expect(source, contains("'£9 a month'"));
    expect(source, isNot(contains('{{title}}')));
  });

  testWidgets('nothing is served as a page at a component\'s address',
      (WidgetTester tester) async {
    await const DVPageStore().save(_card());
    await tester.pumpWidget(MaterialApp(
      home: DVStudioPageRoute(_card().route),
    ));
    await tester.pumpAndSettle();
    expect(find.text('£5 a month'), findsNothing);
    expect(find.byType(DVNotFoundPage), findsOneWidget);
  });
}
