// Studio's GitHub section: name the repository, see what would change as a
// diff, and send it as a pull request or a push.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  testWidgets('a named repository shows what would change, and a pull '
      'request is opened from it', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<String> calls = <String>[];
    bool connected = false;
    Object? synced;
    Future<DVStudioReply> server(String method, String path, {Object? body}) async {
      calls.add('$method $path');
      if (path == 'api/repository' && method == 'PUT') {
        connected = true;
        return const DVStudioReply(200, <String, Object?>{'connected': true});
      }
      if (path == 'api/repository' && method == 'GET') {
        return DVStudioReply(200, <String, Object?>{
          'connected': connected,
          'repository': connected ? 'roastery/site' : null,
          'base': connected ? 'main' : null,
          'token': true,
          'tokenHelp': 'From DARTVEL_GITHUB_TOKEN.',
          'changes': connected
              ? <Object?>[
                  <String, Object?>{
                    'path': 'studio/pages/landing.json',
                    'kind': 'added',
                    'diff': '+{\n+  "route": "/landing"\n+}',
                  },
                ]
              : <Object?>[],
        });
      }
      if (path == 'api/repository/sync') {
        synced = body;
        return const DVStudioReply(200, <String, Object?>{
          'branch': 'studio/20260930-120000',
          'url': 'https://github.com/roastery/site/pull/7',
        });
      }
      return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
    }

    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVStudioRepositorySection(client: DVStudioClient(server))),
    ));
    await tester.pumpAndSettle();

    Future<void> type(String key, String text) async {
      await tester.enterText(
          find.descendant(of: _key(key), matching: find.byType(EditableText)), text);
      await tester.pump();
    }

    await type('dv-studio-repository-name', 'roastery/site');
    await tester.tap(_key('dv-studio-repository-connect'));
    await tester.pumpAndSettle();
    expect(calls, contains('PUT api/repository'));
    expect(find.text('studio/pages/landing.json'), findsOneWidget);
    expect(find.textContaining('"route": "/landing"'), findsOneWidget);

    await type('dv-studio-repository-message', 'A landing page');
    await tester.tap(_key('dv-studio-repository-pull-request'));
    await tester.pumpAndSettle();
    expect(synced, <String, Object?>{'mode': 'pullRequest', 'message': 'A landing page'});
    expect(find.textContaining('pull/7'), findsOneWidget);
  });
}
