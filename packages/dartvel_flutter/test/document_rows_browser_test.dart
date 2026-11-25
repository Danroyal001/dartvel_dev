// Run with: flutter test --platform chrome test/document_rows_browser_test.dart
//
// In a browser, with nothing opted in: once the page is idle, the rows a
// lazy list has not built stand in from the server-rendered document of the
// page (the .dv-fallback block the build writes, marks and all), so a screen
// reader reads every row and the footer, and no row is built to be read.
// See document_rows_test.dart, which drives the same steps off the web.
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

String layoutDocument() {
  String row(String inner) => '<!-- dartvel:row -->$inner<!-- /dartvel:row -->';
  return '<!-- dartvel:rows -->'
      '${row('<section hidden="until-found" data-dv-anchor="0"><p>Site header</p></section>')}'
      '${row('<!-- dartvel:rows -->${<String>[
        for (int i = 0; i < 80; i++) row('<section hidden="until-found" data-dv-anchor="${i + 1}"><p>Paragraph $i</p></section>'),
      ].join()}<!-- /dartvel:rows -->')}'
      '${row('<section hidden="until-found" data-dv-anchor="90"><p>Footer made by somebody</p></section>')}'
      '<!-- /dartvel:rows -->';
}

void main() {
  Widget longLayout() => MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Long page'),
        child: DVBox.list(<Widget>[
          const Text('Site header'),
          DVBox.list(<Widget>[for (int i = 0; i < 80; i++) Text('Paragraph $i')], spacing: 12),
          const Text('Footer made by somebody'),
        ], spacing: 0).scrollable(),
      ),
    );

  String semanticsText(WidgetTester tester) {
    final StringBuffer text = StringBuffer();
    void visit(SemanticsNode node) {
      text.writeln(node.getSemanticsData().label);
      node.visitChildren((SemanticsNode child) {
        visit(child);
        return true;
      });
    }

    visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    return text.toString();
  }

  testWidgets('unbuilt rows stand in from the document of the page, and none is built', (WidgetTester tester) async {
    final web.Element block = web.document.createElement('div')
      ..className = 'dv-fallback'
      ..setAttribute('data-dv-path', web.window.location.pathname);
    block.innerHTML = layoutDocument().toJS;
    web.document.body!.append(block);
    addTearDown(block.remove);
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(longLayout());
    await tester.pumpAndSettle();
    expect(semanticsText(tester), isNot(contains('Footer made by somebody')), reason: 'the first frame is as lazy as before');
    for (int wait = 0; wait < 20 && !semanticsText(tester).contains('Footer made by somebody'); wait++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 450)));
      await tester.pump();
    }
    final String read = semanticsText(tester);
    expect(read, contains('Paragraph 79'));
    expect(read, contains('Footer made by somebody'));
    expect(find.text('Footer made by somebody', skipOffstage: false), findsNothing, reason: 'read, not built');
    expect(find.text('Paragraph 79', skipOffstage: false), findsNothing);
    semantics.dispose();
  });
}
