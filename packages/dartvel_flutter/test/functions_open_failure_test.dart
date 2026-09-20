// A function that will not open says so.
//
// Tapping a name in the Frontend or Backend list loads the document and shows
// it in the builder. When the load threw, nothing happened at all: the panel
// went on reading "No function open" beside a list with that very function in
// it, and the person tapping had no way to tell a broken document from a
// click that missed.
//
// Found while photographing Studio. The Frontend list had orderAhead in it,
// the tap landed, and the builder stayed empty in every capture.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A store that lists a function and refuses to load it.
class _RefusingStore implements DVFunctionStore {
  const _RefusingStore();

  @override
  Future<List<String>> names({DVWorkflowSide? side}) async =>
      <String>['orderAhead'];

  @override
  Future<DVWorkflowDocument?> load(String name) async =>
      throw StateError('that document does not parse');

  @override
  Future<void> save(DVWorkflowDocument document) async {}

  @override
  Future<void> delete(String name) async {}
}

void main() {
  testWidgets('a function whose document will not load reports it',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVStudioScreen(
          sections: <DVStudioSection>[
            dvWorkflowStudioSection(
              side: DVWorkflowSide.frontend,
              store: const _RefusingStore(),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey<String>('dv-studio-section-frontend')));
    await tester.pumpAndSettle();

    expect(find.text('orderAhead'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey<String>('dv-studio-function-orderAhead')));
    await tester.pumpAndSettle();

    expect(find.textContaining('orderAhead'), findsWidgets);
    expect(find.textContaining('does not parse'), findsOneWidget,
        reason: 'the reason it would not open has to reach the person who '
            'tapped it');
  });
}
