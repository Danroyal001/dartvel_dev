// The browser's own find, in a browser.
//
// find_in_page_test.dart proves the Flutter half with no document. This
// proves the half that only exists in one: the runtime writes the page's
// text into the document as sections the browser's find searches, a
// `beforematch` on one of them scrolls the Flutter page to the paragraph it
// mirrors, and the section is hidden again so it never paints over the canvas.
//
// Run with: flutter test --platform chrome test/find_in_page_browser_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

const String _below = 'Records are deleted after seven years.';

Widget longPage({bool findable = true}) => MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Policy', findable: findable),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(headingLevel: 1, child: const Text('Retention policy')),
              for (int i = 0; i < 60; i++)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Paragraph $i says something about records.'),
                ),
              const Text(_below),
            ],
          ),
        ),
      ),
    );

/// Long enough for the page to settle and the mirror to be written.
///
/// Real time, not the test's clock: the mirror is document housekeeping on
/// the browser's own timer.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 700)));
  await tester.pump();
}

/// Every block the document holds, runtime or build.
void clearBlocks() {
  final web.NodeList parts =
      web.document.querySelectorAll('.dv-fallback,.dv-fallback-style');
  for (int i = parts.length - 1; i >= 0; i--) {
    (parts.item(i) as web.Element?)?.remove();
  }
}

/// The mirror section whose text is [text].
web.Element? sectionFor(String text) {
  final web.NodeList sections =
      web.document.querySelectorAll('.dv-fallback [data-dv-anchor]');
  for (int i = 0; i < sections.length; i++) {
    final web.Element section = sections.item(i) as web.Element;
    if ((section.textContent ?? '').trim() == text) return section;
  }
  return null;
}

bool onScreen(WidgetTester tester, Finder finder) {
  final Rect rect = tester.getRect(finder);
  final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.top >= 0 && rect.bottom <= screen.height;
}

/// What the browser does when its find lands in a hidden section: reveal it,
/// and fire beforematch on it.
void browserMatches(web.Element section) {
  section.removeAttribute('hidden');
  section.dispatchEvent(
      web.Event('beforematch', web.EventInit(bubbles: true)));
}

void main() {
  setUp(clearBlocks);
  tearDown(clearBlocks);

  testWidgets('the page is written into the document as findable sections',
      (WidgetTester tester) async {
    await tester.pumpWidget(longPage());
    await settle(tester);

    final web.Element? block = web.document.querySelector('.dv-fallback');
    expect(block, isNotNull, reason: 'a page served with no block gets one');
    expect(block!.getAttribute('aria-hidden'), 'true',
        reason: 'screen readers read the semantics tree, not the copy too');

    final web.Element? section = sectionFor(_below);
    expect(section, isNotNull, reason: 'text below the fold is in the copy');
    expect(section!.getAttribute('hidden'), 'until-found');
    expect(section.querySelector('p'), isNotNull);
    expect(sectionFor('Retention policy')!.querySelector('h1'), isNotNull,
        reason: 'a heading is still a heading, for print');

    // Chrome's own search over the document reaches it.
    final bool found = web.window
        .callMethod<JSBoolean>('find'.toJS, 'deleted after seven'.toJS)
        .toDart;
    expect(found, isTrue);
  });

  testWidgets('a match in a section scrolls the page to the paragraph',
      (WidgetTester tester) async {
    await tester.pumpWidget(longPage());
    await settle(tester);
    final Finder target = find.text(_below);
    expect(onScreen(tester, target), isFalse, reason: 'starts below the fold');

    final web.Element section = sectionFor(_below)!;
    browserMatches(section);
    await settle(tester);

    expect(onScreen(tester, target), isTrue);
    expect(section.getAttribute('hidden'), 'until-found',
        reason: 'hidden again, so it never paints over the canvas');
  });

  testWidgets('the build\'s block for this page is kept, and topped up',
      (WidgetTester tester) async {
    // What `dartvel build web` writes, for the page being viewed: its links
    // and landmarks stay for a crawler that runs scripts.
    final web.Element built = web.document.createElement('div')
      ..className = 'dv-fallback'
      ..setAttribute('data-dv-path', web.window.location.pathname);
    built.innerHTML = '<main><section hidden="until-found" data-dv-anchor="0">'
            '<h1>Retention policy</h1></section>'
            '<section hidden="until-found" data-dv-anchor="1">'
            '<a href="/policy">Paragraph 3 says something about records.</a>'
            '</section></main>'
        .toJS;
    web.document.body!.append(built);

    await tester.pumpWidget(longPage());
    await settle(tester);

    expect(web.document.querySelectorAll('.dv-fallback').length, 1);
    expect(built.querySelector('a[href="/policy"]'), isNotNull,
        reason: 'the build\'s link is still there');
    expect(sectionFor(_below), isNotNull,
        reason: 'what the build did not write is added beside it');
    expect(
        web.document
            .querySelectorAll('.dv-fallback [data-dv-anchor]')
            .length,
        // The build's two, and the page's 62 paragraphs less those two.
        2 + (62 - 2),
        reason: 'the heading and paragraph 3 are not written twice');

    // And a match in the build's own section lands on its paragraph.
    browserMatches(sectionFor('Paragraph 3 says something about records.')!);
    await settle(tester);
    expect(onScreen(tester, find.text('Paragraph 3 says something about records.')),
        isTrue);
  });

  testWidgets('a block written for another page is replaced by this one',
      (WidgetTester tester) async {
    // The reader arrived on /elsewhere and routed here on the client.
    final web.Element stale = web.document.createElement('div')
      ..className = 'dv-fallback'
      ..setAttribute('data-dv-path', '/somewhere-else');
    stale.innerHTML =
        '<section hidden="until-found" data-dv-anchor="0"><p>Old page</p></section>'
            .toJS;
    web.document.body!.append(stale);

    await tester.pumpWidget(longPage());
    await settle(tester);

    expect(sectionFor('Old page'), isNull);
    expect(sectionFor(_below), isNotNull);
    expect(web.document.querySelector('.dv-fallback')!.getAttribute('data-dv-path'),
        web.window.location.pathname);
  });

  testWidgets('a page that opted out is not written, and not searched',
      (WidgetTester tester) async {
    final web.Element built = web.document.createElement('div')
      ..className = 'dv-fallback'
      ..setAttribute('data-dv-path', web.window.location.pathname);
    built.innerHTML =
        '<section hidden="until-found" data-dv-anchor="0"><p>Vault</p></section>'
            .toJS;
    web.document.body!.append(built);

    await tester.pumpWidget(longPage(findable: false));
    await settle(tester);

    expect(sectionFor(_below), isNull, reason: 'nothing mirrored');
    expect(sectionFor('Vault')!.getAttribute('hidden'), '',
        reason: 'plainly hidden: still printed, no longer found');
  });
}
