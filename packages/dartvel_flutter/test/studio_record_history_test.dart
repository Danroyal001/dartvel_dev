// A record of a data model that keeps a history shows its versions in
// Studio, and one is put back from there -- wp-admin's revisions, for any
// data model that asked for them.
import 'package:dartvel_core/dartvel.dart'
    show
        DVHistory,
        DVStudioApi,
        DVStudioFieldSpec,
        DVStudioModelSpec,
        MemoryDVDatabaseAdapter;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const DVStudioModelSpec _article = DVStudioModelSpec(
  model: 'Article',
  table: 'articles',
  key: 'slug',
  history: DVHistory(),
  fields: <DVStudioFieldSpec>[
    DVStudioFieldSpec(name: 'slug', type: 'String'),
    DVStudioFieldSpec(name: 'title', type: 'String'),
  ],
);

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  late DVStudioClient client;

  setUp(() async {
    final DVStudioTransport api = dvStudioInProcessTransport(DVStudioApi(
      database: MemoryDVDatabaseAdapter(),
      models: const <DVStudioModelSpec>[_article],
      caller: (_) async => 'ada',
    ));
    // The grant is the admin server's to decide, before the API; this is a
    // signed-in operator.
    client = DVStudioClient((String method, String path, {Object? body}) async =>
        method == 'GET' && path == 'api/access'
            ? const DVStudioReply(200, <String, Object?>{'granted': true})
            : api(method, path, body: body));
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DVStudioApp(client: client, screen: 'models', object: 'Article/hello'),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a record\'s versions are listed, and one is put back',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await client.create('Article',
          <String, Object?>{'slug': 'hello', 'title': 'Hello'});
      final DVStudioRecordData read = await client.record('Article', 'hello');
      await client.update('Article', read,
          <String, Object?>{'title': 'Hello, world'});
    });
    await open(tester);

    await tester.tap(_key('dv-studio-record-history'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Version 1'), findsOneWidget);
    expect(find.textContaining('Version 2'), findsOneWidget);
    expect(find.textContaining('ada'), findsWidgets);

    await tester.tap(_key('dv-studio-record-restore-1'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    final DVStudioRecordData now =
        (await tester.runAsync(() => client.record('Article', 'hello')))!;
    expect(now.values['title'], 'Hello');
  });

  testWidgets('every control on the history is named', (WidgetTester tester) async {
    await tester.runAsync(() => client.create('Article',
        <String, Object?>{'slug': 'hello', 'title': 'Hello'}));
    await open(tester);
    expect(find.byTooltip('Show versions'), findsOneWidget);
  });
}
