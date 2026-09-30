import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'app builder scope shows help and updated callbacks take effect',
    (tester) async {
      var calls = 0;
      Widget app(int amount) => MaterialApp(
        builder: (_, child) =>
            DVShortcutScope({'ctrl+k': () => calls += amount}, child: child!),
        home: const Scaffold(body: Text('App')),
      );
      await tester.pumpWidget(app(1));
      await tester.pump();
      await chord(tester, .controlLeft, .keyK);
      await tester.pumpWidget(app(10));
      await chord(tester, .controlLeft, .keyK);
      expect(calls, 11);
      await chord(tester, .shiftLeft, .slash);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
    },
  );

  testWidgets('help lists inherited commands once with nearest labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DVShortcutScope.commands(
          const [
            DVShortcut(keys: 'ctrl+k', command: 'old', label: 'App search'),
            DVShortcut(keys: 'ctrl+s', command: 'save', label: 'Save'),
          ],
          actions: {'old': () {}, 'save': () {}},
          child: DVShortcutScope.commands(
            const [
              DVShortcut(keys: 'ctrl+k', command: 'new', label: 'Page search'),
            ],
            actions: {'new': () {}},
            child: const Scaffold(body: Text('Page')),
          ),
        ),
      ),
    );
    await tester.pump();
    await chord(tester, .shiftLeft, .slash);
    expect(find.text('App search'), findsNothing);
    expect(find.text('Page search'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('question mark while editing does not open help', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DVShortcutScope({}, child: Scaffold(body: TextField())),
      ),
    );
    await tester.tap(find.byType(TextField));
    await chord(tester, .shiftLeft, .slash);
    expect(find.text('Keyboard shortcuts'), findsNothing);
  });
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets(
      'mod resolves for $platform and does not accept the other modifier',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: DVShortcutScope({
              'mod+k': () => calls++,
            }, child: const Scaffold(body: Text('Page'))),
          ),
        );
        await tester.pump();
        await chord(
          tester,
          platform == .macOS ? .metaLeft : .controlLeft,
          .keyK,
        );
        expect(calls, 1);
        await chord(
          tester,
          platform == .macOS ? .controlLeft : .metaLeft,
          .keyK,
        );
        expect(calls, 1);
      },
    );
  }

  testWidgets(
    'text input keeps typing and shortcuts unless explicitly allowed',
    (tester) async {
      var blocked = 0;
      var allowed = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DVShortcutScope.commands(
            const [
              DVShortcut(keys: 'ctrl+k', command: 'blocked', label: 'Search'),
              DVShortcut(
                keys: 'ctrl+enter',
                command: 'send',
                label: 'Send',
                allowInTextFields: true,
              ),
            ],
            actions: {'blocked': () => blocked++, 'send': () => allowed++},
            child: Scaffold(body: TextField(controller: controller)),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'hello?');
      await chord(tester, .controlLeft, .keyK);
      await chord(tester, .controlLeft, .enter);
      expect(blocked, 0);
      expect(allowed, 1);
      expect(controller.text, 'hello?');
      expect(find.text('Keyboard shortcuts'), findsNothing);
    },
  );

  testWidgets('nearest scope wins and disposal restores app shortcut', (
    tester,
  ) async {
    var app = 0;
    var page = 0;
    var showPage = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: DVShortcutScope(
          {'ctrl+k': () => app++},
          child: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return showPage
                  ? DVShortcutScope({
                      'ctrl+k': () => page++,
                    }, child: const Scaffold(body: Text('Page')))
                  : const Scaffold(body: Text('App'));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await chord(tester, .controlLeft, .keyK);
    expect([app, page], [0, 1]);
    update(() => showPage = false);
    await tester.pumpAndSettle();
    await chord(tester, .controlLeft, .keyK);
    expect([app, page], [1, 1]);
  });

  testWidgets('question mark lists commands and escape closes the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DVShortcutScope.commands(
          const [
            DVShortcut(
              keys: 'mod+k',
              command: 'search',
              label: 'Search everything',
            ),
          ],
          actions: {'search': () {}},
          child: const Scaffold(body: Text('Page')),
        ),
      ),
    );
    await tester.pump();
    await chord(tester, .shiftLeft, .slash);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Search everything'), findsOneWidget);
    await tester.sendKeyEvent(.escape);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsNothing);
  });

  test('command data round trips through JSON', () {
    const definition = DVShortcut(
      keys: 'mod+k',
      command: 'search',
      label: 'Search',
      allowInTextFields: true,
    );
    final restored = DVShortcut.fromJson(
      jsonDecode(jsonEncode(definition.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), definition.toJson());
  });

  testWidgets('duplicate platform chords and missing commands report errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: .windows),
        home: DVShortcutScope({
          'mod+k': () {},
          'ctrl+k': () {},
        }, child: const SizedBox()),
      ),
    );
    expect(tester.takeException(), isArgumentError);
    await tester.pumpWidget(
      const MaterialApp(
        home: DVShortcutScope.commands(
          [DVShortcut(keys: 'ctrl+k', command: 'missing', label: 'Missing')],
          actions: {},
          child: SizedBox(),
        ),
      ),
    );
    expect(tester.takeException(), isArgumentError);
  });

  test('bad key syntax is rejected instead of silently never firing', () {
    for (final keys in ['mod+wat', 'ctrl+ctrl+k', 'k+x', '', 'mod+']) {
      expect(
        () => DVShortcut(keys: keys, command: 'test', label: 'Test').validate(),
        throwsArgumentError,
      );
    }
  });
}
