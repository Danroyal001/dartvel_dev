// When a page was changed in code since Studio last saved it, Studio says so
// and asks: keep the version in code, or save Studio's over it. It never
// writes over the code's version on its own.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _page(String text) => DVPageDocument(
      route: '/landing',
      title: '/landing',
      root: DVPageNode(type: 'box', children: <DVPageNode>[
        DVPageNode(type: 'text', properties: <String, Object?>{'text': text}),
      ]),
    ).toJson();

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  testWidgets('a save refused because code changed the page shows both ways '
      'on, and does what is chosen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final List<Map<String, Object?>> puts = <Map<String, Object?>>[];
    Map<String, Object?> stored = _page('Hello');
    Future<DVStudioReply> server(String method, String path, {Object? body}) async {
      if (method == 'GET' && path == 'api/pages') {
        return DVStudioReply(200, <String, Object?>{
          'pages': <Object?>[
            <String, Object?>{'route': '/landing', 'title': '/landing', 'document': stored},
          ],
        });
      }
      if (method == 'PUT' && path == 'api/pages') {
        final Map<String, Object?> sent = (body! as Map).cast<String, Object?>();
        puts.add(sent);
        if (sent['force'] != true) {
          return DVStudioReply(409, <String, Object?>{
            'error': 'changed_in_code',
            'message': 'studio/pages/landing.json was changed in code.',
            'path': 'studio/pages/landing.json',
            'inCode': _page('Edited in code'),
          });
        }
        stored = (sent['document']! as Map).cast<String, Object?>();
        return const DVStudioReply(200, <String, Object?>{'route': '/landing'});
      }
      return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
    }

    final DVStudioClient client = DVStudioClient(server);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVStudioScreen(store: DVStudioRemotePageStore(client)),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-route-/landing'));
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-publish'));
    await tester.pumpAndSettle();
    expect(_key('dv-studio-changed-in-code'), findsOneWidget);
    expect(stored['root'].toString(), contains('Hello'),
        reason: 'nothing was written over the code\'s version');

    await tester.tap(_key('dv-studio-use-code-version'));
    await tester.pumpAndSettle();
    expect(find.text('Edited in code'), findsOneWidget);
    expect(_key('dv-studio-changed-in-code'), findsNothing);

    await tester.tap(_key('dv-studio-publish'));
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-save-over-code'));
    await tester.pumpAndSettle();
    expect(puts.last['force'], isTrue);
    expect(_key('dv-studio-changed-in-code'), findsNothing);
  });
}
