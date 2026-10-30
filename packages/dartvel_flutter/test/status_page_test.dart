// Status pages are generated per code.
//
// Error, Empty, and Loading States: "a 500 is not a stack trace in front of a
// customer, and the detail a developer needs goes to the log while the
// visitor gets a sentence." DVStatusPage is that sentence for each code a
// server answers a page request with. It never takes the error: there is no
// parameter through which a detail could reach the reader.
import 'package:dartvel_core/dartvel.dart' show dvStatusPageCodes;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

List<String> _headings(WidgetTester tester) {
  final List<String> headings = <String>[];
  void walk(SemanticsNode node) {
    if (node.headingLevel == 1 && node.label.isNotEmpty) {
      headings.add(node.label);
    }
    node.visitChildren((SemanticsNode child) {
      walk(child);
      return true;
    });
  }

  walk(tester.getSemantics(find.byType(MaterialApp).first));
  return headings;
}

void main() {
  tearDown(() => DV.I18n.reset());

  testWidgets('each code has its own level-1 heading', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final Set<String> seen = <String>{};
    for (final int code in dvStatusPageCodes) {
      await _pump(tester, DVStatusPage(code: code));
      final List<String> headings = _headings(tester);
      expect(headings, hasLength(1), reason: '$code has one heading');
      seen.add(headings.single);
    }
    // Four codes, four different headings: a 429 that says "Something went
    // wrong" tells a person to report a fault rather than to wait.
    expect(seen, hasLength(dvStatusPageCodes.length));
    handle.dispose();
  });

  testWidgets('a 500 says a sentence and offers the way home', (WidgetTester tester) async {
    await _pump(tester, const DVStatusPage(code: 500));
    expect(find.text('Something went wrong on our side'), findsOneWidget);
    expect(find.text('Go to the home page'), findsOneWidget);
    expect(tester.widget<DVNavLink>(find.byType(DVNavLink)).to.path, '/');
  });

  testWidgets('a 503 says the application is down for now', (WidgetTester tester) async {
    await _pump(tester, const DVStatusPage(code: 503));
    expect(find.text('This application is unavailable'), findsOneWidget);
  });

  testWidgets('a code with no page of its own still gets a sentence', (WidgetTester tester) async {
    await _pump(tester, const DVStatusPage(code: 502));
    expect(find.text('Something went wrong on our side'), findsOneWidget);
  });

  testWidgets('the words are framework strings, so a catalogue replaces them', (WidgetTester tester) async {
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{
        DVFrameworkStrings.status500Title: 'Un problème est survenu de notre côté',
      },
    ));
    DV.I18n.useLocale(LocaleTag.frFR);
    await _pump(tester, const DVStatusPage(code: 500));
    expect(find.text('Un problème est survenu de notre côté'), findsOneWidget);
  });
}
