import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the terminal is complete on its first frame', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HeroTerminal())),
    );
    // The preloaded picture must not turn back into an unfinished command
    // when Flutter takes over. No elapsed animation time is needed to read it.
    expect(
      find.textContaining(
        '[dartvel] [dev] restarting backend...',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
}
