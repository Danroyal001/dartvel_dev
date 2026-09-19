// Frontend and Backend functions in the Studio a web-server binary serves.
//
// The builders are free -- designing a page is of little use if a button
// cannot be made to do anything -- and they run in a browser, which has no
// database. So the sections keep their functions through the Studio API, the
// way the page builder keeps pages.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A backend that answers api/functions out of a map.
class _Server {
  final Map<String, Map<String, Object?>> functions =
      <String, Map<String, Object?>>{};

  Future<DVStudioReply> call(String method, String path,
      {Object? body}) async {
    final Uri uri = Uri.parse(path);
    if (uri.path != 'api/functions') return const DVStudioReply(404, null);
    switch (method) {
      case 'GET':
        return DVStudioReply(200, <String, Object?>{
          'functions': <Object?>[
            for (final MapEntry<String, Map<String, Object?>> e
                in functions.entries)
              <String, Object?>{'name': e.key, 'document': e.value},
          ],
        });
      case 'PUT':
        final Map<String, Object?> document =
            ((body! as Map)['document']! as Map).cast<String, Object?>();
        functions['${document['name']}'] = document;
        return DVStudioReply(200, <String, Object?>{'name': document['name']});
      case 'DELETE':
        functions.remove(uri.queryParameters['name']);
        return const DVStudioReply(200, <String, Object?>{});
    }
    return const DVStudioReply(405, null);
  }
}

void main() {
  late _Server server;
  late DVStudioClient client;

  setUp(() {
    server = _Server();
    client = DVStudioClient(server.call);
  });

  group('the store over the API', () {
    test('saves, lists by side, loads and deletes', () async {
      final DVFunctionStore store = DVStudioRemoteFunctionStore(client);
      await store.save(DVWorkflowDocument(
          name: 'joinOakline', side: DVWorkflowSide.frontend));
      await store.save(DVWorkflowDocument(name: 'welcomeCustomer'));

      expect(await store.names(), <String>['joinOakline', 'welcomeCustomer']);
      expect(await store.names(side: DVWorkflowSide.frontend),
          <String>['joinOakline']);
      expect((await store.load('joinOakline'))!.side, DVWorkflowSide.frontend);

      await store.delete('joinOakline');
      expect(await store.names(), <String>['welcomeCustomer']);
    });
  });

  group('the served Studio', () {
    testWidgets('has Frontend and Backend sections, and no separate list',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: DVStudioScreen(sections: dvStudioServerSections(client)),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Frontend'), findsOneWidget);
      expect(find.text('Backend'), findsOneWidget);
    });

    testWidgets('a function built in Frontend is stored on the server',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: DVStudioScreen(sections: dvStudioServerSections(client)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-section-frontend')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).first, 'orderAhead');
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-function-create')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-function-deploy')));
      await tester.pumpAndSettle();

      expect(find.text('No function open'), findsNothing,
          reason: 'Create should have opened the builder');
      expect(server.functions.keys, <String>['orderAhead']);
      expect(server.functions['orderAhead']!['side'], 'frontend');
    });
  });
}
// Probe: what the Frontend section shows after Create.
