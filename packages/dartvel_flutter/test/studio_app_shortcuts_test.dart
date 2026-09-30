// Keyboard shortcuts for the application, set in Studio.
//
// Studio writes them in DVShortcut's own JSON -- keys, command, label -- to a
// document beside the pages, and every page's shell answers them, with the
// application's '?' sheet listing them. A no-code command is a page to go
// to ("go:/menu"); a definition that does not parse is left out rather than
// breaking every page.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('the shortcuts are DVShortcut JSON, kept beside the pages', () {
    final DVPageDocument document = dvStudioAppShortcutsDocument(const <DVShortcut>[
      DVShortcut(keys: 'Ctrl+M', command: 'go:/menu', label: 'The menu'),
    ]);
    expect(document.route, '/_dartvel/shortcuts');
    final List<DVShortcut> back =
        dvStudioAppShortcutsOf(DVPageDocument.fromJson(document.toJson()));
    expect(back.single.toJson(), <String, Object?>{
      'keys': 'Ctrl+M',
      'command': 'go:/menu',
      'label': 'The menu',
      'allowInTextFields': false,
    });
  });

  testWidgets('every page answers them, and a broken one is left out',
      (WidgetTester tester) async {
    await const DVPageStore().save(dvStudioAppShortcutsDocument(const <DVShortcut>[
      DVShortcut(keys: 'Ctrl+M', command: 'go:/menu', label: 'The menu'),
      DVShortcut(keys: 'Ctrl+Nope', command: 'go:/', label: 'Broken'),
    ]));
    Widget page(String text) => DVPageShell(
          spec: const DVPageScaffoldSpec(),
          child: Center(child: Text(text)),
        );
    final GoRouter router = GoRouter(routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => page('home')),
      GoRoute(path: '/menu', builder: (_, _) => page('the menu')),
    ]);
    addTearDown(router.dispose);
    DVNavigation.attach(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('home'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('the menu'), findsOneWidget);
  });

  testWidgets('Studio sets them: a key, a name, and the page it opens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Material(child: DVStudioScreen())));
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-section-shortcuts'));
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-shortcut-add'));
    await tester.pumpAndSettle();
    Future<void> type(String field, String text) async {
      await tester.enterText(
          find.descendant(of: _key(field), matching: find.byType(EditableText)), text);
      await tester.pump();
    }

    await type('dv-studio-shortcut-keys-0', 'Ctrl+Nope');
    await type('dv-studio-shortcut-label-0', 'The menu');
    await type('dv-studio-shortcut-page-0', '/menu');
    await tester.tap(_key('dv-studio-shortcuts-save'));
    await tester.pumpAndSettle();
    expect(_key('dv-studio-shortcut-problem-0'), findsOneWidget);
    expect(await const DVPageStore().load('/_dartvel/shortcuts'), isNull,
        reason: 'nothing is saved while one does not parse');

    await type('dv-studio-shortcut-keys-0', 'Ctrl+M');
    await tester.tap(_key('dv-studio-shortcuts-save'));
    await tester.pumpAndSettle();
    final DVPageDocument? saved = await const DVPageStore().load('/_dartvel/shortcuts');
    expect(dvStudioAppShortcutsOf(saved).single.command, 'go:/menu');
  });
}
