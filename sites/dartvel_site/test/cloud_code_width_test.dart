// The Cloud page's commands read on a phone.
//
// A comment beside a command wrapped under it at 390 pixels, so the block read
// as a command, half a comment, then the rest of the comment where the next
// command should be. Each line is measured in the monospace font the block
// uses, at the width the block is laid out at.
import 'dart:io';

import 'package:dartvel_site/components/highlight.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/pages/_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final ByteData font = ByteData.sublistView(File('fonts/RobotoMono.ttf').readAsBytesSync());
    await (FontLoader('RobotoMono')..addFont(Future<ByteData>.value(font))).load();
    await CloudPageGeneratedPage.loadLibrary();
  });

  setUp(dvResetDeferredPages);

  testWidgets('no line of a code block on the Cloud page wraps at 390 pixels', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp.router(
      routerConfig: GoRouter(routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Layout(child: CloudPageGeneratedPage())),
        ),
      ]),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final Finder blocks = find.descendant(of: find.byType(CodeSample), matching: find.byType(SelectableText));
    expect(blocks, findsWidgets);
    final List<String> wrapped = <String>[];
    for (final Element element in blocks.evaluate()) {
      final SelectableText text = element.widget as SelectableText;
      final double width = tester.getSize(find.byElementPredicate((Element e) => e == element)).width;
      for (final String line in text.textSpan!.toPlainText().split('\n')) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: line, style: text.style),
          textDirection: TextDirection.ltr,
        )..layout();
        if (painter.width > width) wrapped.add('${painter.width.toStringAsFixed(0)} > ${width.toStringAsFixed(0)}: $line');
        painter.dispose();
      }
    }
    expect(wrapped, isEmpty);
  });
}
