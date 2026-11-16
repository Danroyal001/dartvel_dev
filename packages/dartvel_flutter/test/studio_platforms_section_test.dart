// Studio's Platforms screen: the web page's own HTML at its three edges,
// edited without code and saved to the same dartvel.platforms code writes.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Map<String, Object?> _state({bool canEdit = true, bool development = true}) => <String, Object?>{
      'web': <String, Object?>{
        'document': <String, Object?>{
          'head': <Object?>[
            <String, Object?>{'file': 'web/head.html'},
          ],
        },
      },
      'pending': false,
      'development': development,
      'source': 'pubspec',
      'canEdit': canEdit,
      'effective': <String, Object?>{
        'head': '<meta name="built" content="1">',
        'bodyStart': '',
        'bodyEnd': '',
      },
      'files': <String, Object?>{'web/head.html': '<meta name="built" content="1">'},
      'webFiles': <Object?>['web/head.html', 'web/chat.html'],
    };

void main() {
  late List<String> calls;
  late Object? saved;

  Future<DVStudioReply> Function(String, String, {Object? body}) server(Map<String, Object?> state) =>
      (String method, String path, {Object? body}) async {
        calls.add('$method $path');
        if (path == 'api/platforms' && method == 'GET') return DVStudioReply(200, state);
        if (path == 'api/platforms/web/document' && method == 'PUT') {
          saved = body;
          return const DVStudioReply(200, <String, Object?>{'saved': true, 'written': 'pubspec.yaml'});
        }
        return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
      };

  Future<void> open(WidgetTester tester, Map<String, Object?> state,
      {String? object = 'web', void Function(String)? onSelect}) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVStudioPlatformsSection(
          client: DVStudioClient(server(state)),
          platform: object,
          onSelect: onSelect ?? (String _) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.descendant(of: _key(key), matching: find.byType(EditableText)), text);
    await tester.pump();
  }

  setUp(() {
    calls = <String>[];
    saved = null;
  });

  testWidgets('Platforms lists Web, which opens at its own address', (WidgetTester tester) async {
    String? chosen;
    await open(tester, _state(), object: null, onSelect: (String id) => chosen = id);
    expect(find.text('Web'), findsWidgets);
    await tester.tap(_key('dv-studio-platforms-open-web'));
    await tester.pumpAndSettle();
    expect(chosen, 'web');
  });

  testWidgets('a snippet added at the end of the body is saved as the same object code writes',
      (WidgetTester tester) async {
    await open(tester, _state());
    expect(find.text('Inside the head'), findsOneWidget);
    expect(find.text('Start of the page body'), findsOneWidget);
    expect(find.text('End of the page body'), findsOneWidget);

    await tester.tap(_key('dv-studio-platforms-bodyEnd-add-html'));
    await tester.pumpAndSettle();
    await type(tester, 'dv-studio-platforms-bodyEnd-0', '<script src="https://cdn.example.com/chat.js" async></script>');
    await tester.tap(_key('dv-studio-platforms-save'));
    await tester.pumpAndSettle();

    expect(saved, <String, Object?>{
      'document': <String, Object?>{
        'head': <Object?>[
          <String, Object?>{'file': 'web/head.html'},
        ],
        'bodyEnd': <Object?>[
          <String, Object?>{'html': '<script src="https://cdn.example.com/chat.js" async></script>'},
        ],
      },
    });
    expect(find.textContaining('pubspec.yaml'), findsWidgets);
  });

  testWidgets('HTML that would swallow the page is flagged as it is typed, and is not saved',
      (WidgetTester tester) async {
    await open(tester, _state());
    await tester.tap(_key('dv-studio-platforms-bodyStart-add-html'));
    await tester.pumpAndSettle();
    await type(tester, 'dv-studio-platforms-bodyStart-0', '<div class="banner">Sale');
    expect(find.textContaining('<div> is never closed'), findsOneWidget);
    await tester.tap(_key('dv-studio-platforms-save'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(calls, isNot(contains('PUT api/platforms/web/document')));
  });

  testWidgets('a snippet can come from a file under web/, and be moved and removed', (WidgetTester tester) async {
    await open(tester, _state());
    await tester.tap(_key('dv-studio-platforms-head-add-file'));
    await tester.pumpAndSettle();
    await type(tester, 'dv-studio-platforms-head-1', 'web/chat.html');
    await tester.tap(_key('dv-studio-platforms-head-1-up'));
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-platforms-head-1-remove'));
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-platforms-save'));
    await tester.pumpAndSettle();
    expect(saved, <String, Object?>{
      'document': <String, Object?>{
        'head': <Object?>[
          <String, Object?>{'file': 'web/chat.html'},
        ],
      },
    });
  });

  testWidgets("the page's edges are previewed as the build will write them", (WidgetTester tester) async {
    await open(tester, _state());
    final String preview = tester.widget<Text>(find.descendant(
      of: _key('dv-studio-platforms-preview'),
      matching: find.byType(Text),
    )).data!;
    expect(preview.indexOf('<meta name="built" content="1">'), greaterThan(preview.indexOf('<head>')));
    expect(preview.indexOf('<meta name="built" content="1">'), lessThan(preview.indexOf('</head>')));
    expect(preview, contains('</body>'));
  });

  testWidgets('somebody who may not edit raw HTML sees it, and is told who can', (WidgetTester tester) async {
    await open(tester, _state(canEdit: false));
    expect(_key('dv-studio-platforms-head-add-html'), findsNothing);
    expect(_key('dv-studio-platforms-save'), findsNothing);
    expect(find.textContaining('owner'), findsWidgets);
    expect(find.textContaining('web/head.html'), findsWidgets);
  });

  testWidgets('the Platforms screen is one of the server sections', (WidgetTester tester) async {
    final List<String> ids = <String>[
      for (final DVStudioSection section in dvStudioServerSections(DVStudioClient(server(_state())))) section.id,
    ];
    expect(ids, contains('platforms'));
  });
}
