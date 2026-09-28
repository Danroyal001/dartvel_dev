// Data models are made in Studio, not only shown there.
//
// Studio listed the records of models written in code, so an owner who
// wanted a new kind of record had to write Dart and rebuild. Here a model is
// designed -- its name, fields and their types, rules, relations, indexes
// and who may use its data -- and it takes records straight away. These run
// Studio inside an application, over the real Studio API in the same
// process: the path a phone, a desktop or a served Studio takes differs only
// in where the database is.
import 'package:dartvel_core/dartvel.dart'
    show DVStudioApi, DVStudioFieldSpec, DVStudioModelSpec;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A project's generated model specs.
const List<DVStudioModelSpec> _models = <DVStudioModelSpec>[
  DVStudioModelSpec(
    model: 'Author',
    table: 'authors',
    key: 'slug',
    fields: <DVStudioFieldSpec>[
      DVStudioFieldSpec(name: 'slug', type: 'String'),
      DVStudioFieldSpec(name: 'name', type: 'String', minLength: 2),
    ],
  ),
];

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(EditableText)),
    text,
  );
  await tester.pump();
}

Future<void> _openData(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Material(child: DVStudioInApp(models: _models)),
  ));
  await tester.pumpAndSettle();
  await tester.tap(_key('dv-studio-section-models'));
  await tester.pumpAndSettle();
}

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
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the project\'s own models are listed, marked as code',
      (WidgetTester tester) async {
    desktop(tester);
    await _openData(tester);

    expect(_key('dv-studio-model-Author'), findsOneWidget);
    expect(
      find.descendant(
          of: _key('dv-studio-model-Author'), matching: find.text('Code')),
      findsOneWidget,
    );
    // Its rules are shown and not offered for change: it is changed in code.
    await tester.tap(_key('dv-studio-model-design'));
    await tester.pumpAndSettle();
    expect(find.text('Written in code'), findsWidgets);
    expect(_key('dv-studio-model-save'), findsNothing);
    expect(find.text('2'), findsWidgets, reason: 'the shortest a name is');
  });

  testWidgets(
      'a model is designed in Studio and takes records at once, with its '
      'rules checked', (WidgetTester tester) async {
    desktop(tester);
    await _openData(tester);

    await tester.tap(_key('dv-studio-model-new'));
    await tester.pumpAndSettle();
    await _type(tester, _key('dv-studio-model-name'), 'Article');
    // The designer starts with an id and a title; the title is at least
    // three characters.
    await _type(tester, _key('dv-studio-field-design-1-min-length'), '3');
    // A field refers to an author.
    await tester.tap(_key('dv-studio-field-add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('dv-studio-field-design-2-kind'));
    await tester.tap(_key('dv-studio-field-design-2-kind'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relation').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('dv-studio-field-design-2-relation'));
    await tester.tap(_key('dv-studio-field-design-2-relation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Author').last);
    await tester.pumpAndSettle();
    // Named the way the generator recognises a reference.
    expect(find.text('authorSlug'), findsWidgets);
    await tester.tap(_key('dv-studio-field-design-2-required'));
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-model-save'));
    await tester.pumpAndSettle();

    expect(_key('dv-studio-model-problem'), findsNothing,
        reason: find
            .descendant(
                of: _key('dv-studio-model-problem'),
                matching: find.byType(Text))
            .evaluate()
            .map((Element e) => (e.widget as Text).data)
            .join());
    expect(_key('dv-studio-model-Article'), findsOneWidget);
    expect(
      find.descendant(
          of: _key('dv-studio-model-Article'), matching: find.text('Studio')),
      findsOneWidget,
    );

    // A record, made through the form the model now has.
    await tester.tap(_key('dv-studio-record-new'));
    await tester.pumpAndSettle();
    await _type(tester, _key('dv-studio-field-title'), 'Hi');
    await tester.tap(_key('dv-studio-record-save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 3 characters'), findsOneWidget,
        reason: 'the rule is checked where the record is written');

    await _type(tester, _key('dv-studio-field-title'), 'Hello there');
    await tester.tap(_key('dv-studio-record-save'));
    await tester.pumpAndSettle();
    expect(find.text('Hello there'), findsWidgets);
    expect(find.text('1 record'), findsOneWidget);
  });

  testWidgets('a model\'s records are searched by any value they hold',
      (WidgetTester tester) async {
    desktop(tester);
    final DVStudioClient client = DVStudioClient(
        dvStudioInProcessTransport(DVStudioApi(database: database)));
    await client.saveModel('Place', <String, Object?>{
      'key': 'id',
      'fields': <Object?>[
        <String, Object?>{'name': 'id', 'type': 'String'},
        <String, Object?>{'name': 'city', 'type': 'String'},
      ],
    });
    for (final String city in <String>['Lagos', 'Lisbon', 'Uyo']) {
      await client.create('Place', <String, Object?>{'city': city});
    }
    await _openData(tester);
    await tester.tap(_key('dv-studio-model-Place'));
    await tester.pumpAndSettle();
    expect(find.text('Uyo'), findsOneWidget);

    await _type(tester, _key('dv-studio-records-search'), 'l');
    expect(find.text('Lagos'), findsOneWidget);
    expect(find.text('Lisbon'), findsOneWidget);
    expect(find.text('Uyo'), findsNothing);
  });

  testWidgets('a definition Studio cannot store says why',
      (WidgetTester tester) async {
    desktop(tester);
    await _openData(tester);

    await tester.tap(_key('dv-studio-model-new'));
    await tester.pumpAndSettle();
    await _type(tester, _key('dv-studio-model-name'), 'article');
    await tester.tap(_key('dv-studio-model-save'));
    await tester.pumpAndSettle();

    expect(_key('dv-studio-model-problem'), findsOneWidget);
    expect(find.textContaining('PascalCase'), findsOneWidget);
  });
}
