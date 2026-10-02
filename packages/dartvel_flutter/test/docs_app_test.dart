/// The documentation site: an application that draws the document `dartvel
/// docs` writes.
///
/// The build used to write nine pages of HTML and a stylesheet, and the
/// framework's own theme never touched one of them. It writes a document now
/// and the application is the site, so these are the tests that the document
/// still means what it said: every block kind is drawn, every span kind is
/// drawn as itself, a link to a page in the document goes to that page, a
/// link to a page the document does not have is text rather than a dead
/// address, and a path nobody has is a page that says so.
library;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A document with one page of every kind, a second page to link to, and a
/// page long enough that an anchor is off the screen until it is scrolled to.
DVDocsDocument _document({List<DVDocsFinding> findings = const <DVDocsFinding>[]}) {
  return DVDocsDocument(
    application: 'shop',
    graphVersion: 7,
    navigation: const <(String, String)>[
      ('index', 'Overview'),
      ('models', 'Models'),
      ('diagnostics', 'Diagnostics'),
    ],
    pages: <DVDocsPage>[
      DVDocsPage(
        id: 'index',
        title: 'Shop',
        blocks: <DVDocsBlock>[
          const DVDocsParagraph(<DVDocsSpan>[
            DVDocsSpan.text('A shop with '),
            DVDocsSpan.code('Order'),
            DVDocsSpan.text(' and '),
            DVDocsSpan.strong('nothing else'),
            DVDocsSpan.text('.'),
          ]),
          const DVDocsParagraph(<DVDocsSpan>[
            DVDocsSpan.text('See '),
            DVDocsSpan.link('the models', DVDocsTarget.page('models')),
            DVDocsSpan.text(', '),
            DVDocsSpan.link(
              'dartvel.dev',
              DVDocsTarget.external('https://dartvel.dev'),
            ),
            DVDocsSpan.text(', '),
            DVDocsSpan.link(
              'a page that is not there',
              DVDocsTarget.page('nowhere'),
            ),
            DVDocsSpan.text('.'),
          ]),
          const DVDocsHeading(
            2,
            <DVDocsSpan>[DVDocsSpan.text('Everything else')],
            anchor: 'everything',
          ),
          const DVDocsList(false, <DVDocsListItem>[
            DVDocsListItem(<DVDocsSpan>[DVDocsSpan.text('a bullet')]),
            DVDocsListItem(<DVDocsSpan>[DVDocsSpan.text('another')], 'second'),
          ]),
          const DVDocsList(true, <DVDocsListItem>[
            DVDocsListItem(<DVDocsSpan>[DVDocsSpan.text('first')]),
            DVDocsListItem(<DVDocsSpan>[DVDocsSpan.text('second')]),
          ]),
          const DVDocsCode('Order(...).save()'),
          const DVDocsCode(
            'Future<Order?> find(String id)',
            signature: true,
          ),
          const DVDocsTable(
            <DVDocsColumn>[DVDocsColumn('Field', 'field'), DVDocsColumn('Note')],
            <DVDocsRow>[
              DVDocsRow(<List<DVDocsSpan>>[
                <DVDocsSpan>[DVDocsSpan.code('email')],
                <DVDocsSpan>[DVDocsSpan.badge('sensitive')],
              ]),
              DVDocsRow(<List<DVDocsSpan>>[
                <DVDocsSpan>[DVDocsSpan.code('total')],
                <DVDocsSpan>[DVDocsSpan.denied()],
              ], 'row-total'),
            ],
          ),
          const DVDocsParagraph(<DVDocsSpan>[
            DVDocsSpan.note('lib/models/order.dart:1'),
          ]),
          const DVDocsParagraph(<DVDocsSpan>[DVDocsSpan.gone('model:Removed')]),
          const DVDocsParagraph(<DVDocsSpan>[
            DVDocsSpan.finding('DV-DOCS-001'),
          ]),
          // Filler, so the row a link names is below the fold and scrolling
          // to it is something the test can see happen.
          for (int i = 0; i < 40; i++)
            DVDocsParagraph(<DVDocsSpan>[
              DVDocsSpan.text('Filler paragraph $i.'),
            ]),
        ],
      ),
      const DVDocsPage(
        id: 'models',
        title: 'Models',
        blocks: <DVDocsBlock>[
          DVDocsParagraph(<DVDocsSpan>[DVDocsSpan.text('Two of them.')]),
        ],
      ),
      DVDocsPage(
        id: 'diagnostics',
        title: 'Diagnostics',
        blocks: <DVDocsBlock>[
          for (final DVDocsFinding finding in findings)
            DVDocsParagraph(<DVDocsSpan>[
              DVDocsSpan.finding(finding.code),
              DVDocsSpan.text(' ${finding.message}'),
            ]),
        ],
      ),
    ],
    findings: findings,
  );
}

/// Every link on screen as the text it is drawn with and the address it goes
/// to, which is the whole of what a link is.
///
/// Read off the widget rather than the semantics tree, because a link drawn
/// inside a sentence shares its paragraph's node with the rest of the sentence:
/// the address is the only thing that says a run is a link rather than a word.
List<String> _links(WidgetTester tester) => <String>[
      for (final DVNavLink link
          in tester.widgetList<DVNavLink>(find.byType(DVNavLink)))
        '${link.child is Text ? (link.child as Text).data : ''} -> '
            '${link.externalUrl ?? link.to.path}',
    ];

/// The run of text drawn as [text], wherever in a span tree it sits.
///
/// The trees are the ones a paragraph is built from, so a run that is a
/// [WidgetSpan] -- a code chip, a badge, a link -- is not in one: those are
/// read off the widget, because that is where they are drawn.
TextSpan? _run(WidgetTester tester, String text) {
  for (final Text widget in tester.widgetList<Text>(find.byType(Text))) {
    final TextSpan? found = _inSpan(widget.textSpan, text);
    if (found != null) return found;
  }
  return null;
}

TextSpan? _inSpan(InlineSpan? span, String text) {
  if (span is! TextSpan) return null;
  if (span.text == text) return span;
  for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
    final TextSpan? found = _inSpan(child, text);
    if (found != null) return found;
  }
  return null;
}

/// Pumps the app and settles, which is what a person opening the site waits
/// for: the document read, the first frame, and any scroll an anchor asked
/// for.
Future<void> _open(
  WidgetTester tester, {
  DVDocsDocument? document,
  DVDocsSource? source,
  Uri? at,
  String base = '/',
  void Function(String url)? open,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DVDocsApp(
        document: document ?? _document(),
        source: source,
        location: at,
        base: base,
        open: open,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    DVNavigation.detach();
    DVLinkOpener.reset();
  });

  group('the site opens on the page it was asked for', () {
    testWidgets('at the root it draws the overview', (WidgetTester tester) async {
      await _open(tester);
      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('Two of them.'), findsNothing);
    });

    testWidgets('at a page path it draws that page',
        (WidgetTester tester) async {
      await _open(tester, at: Uri.parse('https://shop.test/models'));
      expect(find.text('Two of them.'), findsOneWidget);
    });

    // Mounted inside an application, the address the browser shows carries
    // the mount; the document's pages do not, and never should, because the
    // mount is the project's to move.
    testWidgets('mounted at /docs, the mount is the overview',
        (WidgetTester tester) async {
      for (final String at in <String>['/docs/', '/docs']) {
        await _open(tester, at: Uri.parse('https://shop.test$at'),
            base: '/docs');
        expect(find.text('Shop'), findsOneWidget, reason: at);
        expect(find.text('Page not found'), findsNothing, reason: at);
      }
    });

    testWidgets('mounted at /docs, a page under it is that page',
        (WidgetTester tester) async {
      await _open(tester, at: Uri.parse('https://shop.test/docs/models'),
          base: '/docs/');
      expect(find.text('Two of them.'), findsOneWidget);
    });

    testWidgets('a path with a trailing slash is the page, not a near miss',
        (WidgetTester tester) async {
      await _open(tester, at: Uri.parse('https://shop.test/models/'));
      expect(find.text('Two of them.'), findsOneWidget);
    });

    testWidgets('at a path no page has it says so, and offers the way back',
        (WidgetTester tester) async {
      await _open(tester, at: Uri.parse('https://shop.test/nope'));
      expect(find.text('Page not found'), findsOneWidget);
      expect(find.textContaining('/nope'), findsOneWidget);
      await tester.tap(find.text('Go to the home page'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A shop with '), findsOneWidget);
    });

    testWidgets('the header names the application and the pages',
        (WidgetTester tester) async {
      await _open(tester);
      expect(find.text('shop'), findsOneWidget);
      expect(
        tester
            .widgetList<DVNavLink>(find.byType(DVNavLink))
            .map((DVNavLink link) => link.to.path),
        containsAllInOrder(<String>['/', '/models', '/diagnostics']),
      );
    });
  });

  group('every block is drawn', () {
    testWidgets('a heading is a heading, and the page title is one too',
        (WidgetTester tester) async {
      await _open(tester);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((Semantics s) => s.properties.header == true),
        hasLength(2),
      );
    });

    testWidgets('a bullet list and a numbered list are told apart',
        (WidgetTester tester) async {
      await _open(tester);
      expect(find.text('•'), findsNWidgets(2), reason: 'both bullets');
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
    });

    testWidgets('code is drawn as it was written, spaces and all',
        (WidgetTester tester) async {
      await _open(tester);
      expect(find.text('Order(...).save()'), findsOneWidget);
      final Text code = tester.widget<Text>(find.text('Order(...).save()'));
      expect(code.style!.fontFamily, isNotNull);
      expect(
        tester
            .widget<Text>(find.text('Future<Order?> find(String id)'))
            .data,
        'Future<Order?> find(String id)',
      );
    });

    testWidgets('a table is a table, with its columns and its rows',
        (WidgetTester tester) async {
      await _open(tester);
      expect(find.text('Field'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('sensitive'), findsOneWidget);
      expect(find.text('denied'), findsOneWidget);
    });
  });

  group('every span is drawn as itself', () {
    testWidgets('prose, code, strong, badge, note, gone and finding all appear',
        (WidgetTester tester) async {
      await _open(tester);
      for (final String text in <String>[
        'A shop with ',
        'Order',
        'and ',
        'nothing else',
        'sensitive',
        'lib/models/order.dart:1',
        'model:Removed',
        'DV-DOCS-001',
      ]) {
        expect(find.textContaining(text), findsWidgets, reason: text);
      }
    });

    testWidgets('and each is drawn as itself, not as the run beside it',
        (WidgetTester tester) async {
      await _open(tester);
      const DVDocsTheme palette = DVDocsTheme.light();
      expect(
        _run(tester, 'nothing else')!.style!.fontWeight,
        FontWeight.w600,
        reason: 'strong',
      );
      expect(
        _run(tester, 'model:Removed')!.style!.color,
        palette.warn,
        reason: 'gone',
      );
      expect(
        _run(tester, 'DV-DOCS-001')!.style!.color,
        palette.warn,
        reason: 'finding',
      );
      expect(
        _run(tester, 'denied')!.style!.color,
        palette.muted,
        reason: 'denied',
      );
      expect(
        _run(tester, 'lib/models/order.dart:1')!.style!.fontSize,
        13,
        reason: 'note',
      );
      expect(
        tester.widget<Text>(find.text('Order')).style!.fontFamily,
        'monospace',
        reason: 'code',
      );
      expect(
        tester.widget<Text>(find.text('sensitive')).style!.fontSize,
        12,
        reason: 'badge',
      );
      expect(
        tester.widget<Text>(find.text('the models')).style!.decoration,
        TextDecoration.underline,
        reason: 'link',
      );
    });

    testWidgets('a link is a link, with the address it goes to',
        (WidgetTester tester) async {
      await _open(tester);
      expect(
        _links(tester),
        containsAll(<String>['the models -> /models', 'dartvel.dev -> https://dartvel.dev']),
        reason: 'a page of this document, and somewhere else',
      );
    });

    testWidgets('a link to a page the document does not have is text',
        (WidgetTester tester) async {
      await _open(tester);
      expect(
        find.textContaining('a page that is not there'),
        findsOneWidget,
        reason: 'the words are still on the page',
      );
      expect(
        _links(tester).where(
          (String link) => link.startsWith('a page that is not there'),
        ),
        isEmpty,
        reason: 'a link to nowhere is not a link',
      );
    });
  });

  group('a link goes where it says', () {
    testWidgets('to another page of the document',
        (WidgetTester tester) async {
      await _open(tester);
      await tester.tap(find.text('the models'));
      await tester.pumpAndSettle();
      expect(find.text('Two of them.'), findsOneWidget);
    });

    testWidgets('off the site, through the app\'s own way out',
        (WidgetTester tester) async {
      final List<String> opened = <String>[];
      await _open(tester, open: opened.add);
      await tester.tap(find.text('dartvel.dev'));
      await tester.pumpAndSettle();
      expect(opened, <String>['https://dartvel.dev']);
    });

    testWidgets('and to the row a decision record names, scrolling to it',
        (WidgetTester tester) async {
      await _open(tester);
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.pixels, 0);
      scrollable.position.jumpTo(
        scrollable.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      // Back to the top, then follow a link the document carries to a row
      // below the fold.
      scrollable.position.jumpTo(0);
      await tester.pumpAndSettle();

      await tester.tap(find.text('a bullet'));
      await tester.pumpAndSettle();
      expect(find.text('Two of them.'), findsNothing);

      await _open(
        tester,
        at: Uri.parse('https://shop.test/#row-total'),
      );
      final Rect row = tester.getRect(find.text('total'));
      final Size surface = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(row.top, greaterThanOrEqualTo(0));
      expect(row.bottom, lessThanOrEqualTo(surface.height));
    });
  });

  group('an anchor in the address is honoured on arrival', () {
    testWidgets('the block it names is on screen',
        (WidgetTester tester) async {
      await _open(tester, at: Uri.parse('https://shop.test/#everything'));
      final Rect heading = tester.getRect(find.text('Everything else'));
      expect(heading.top, greaterThanOrEqualTo(0));
    });

    testWidgets('an anchor nothing carries leaves the page at the top',
        (WidgetTester tester) async {
      await _open(tester, at: Uri.parse('https://shop.test/#nothing-here'));
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.pixels, 0);
    });
  });

  group('the document is read, not assumed', () {
    testWidgets('while it is being read the site says so',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DVDocsApp(source: () async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return _document();
          }),
        ),
      );
      expect(find.byType(DVRoutePending), findsOneWidget, reason: 'unfinished');
      expect(find.textContaining('A shop with '), findsNothing);
      await tester.pumpAndSettle();
      expect(find.textContaining('A shop with '), findsOneWidget);
    });

    testWidgets('a document that will not load is reported, not swallowed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DVDocsApp(
            source: () async => throw const FormatException('no pages'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no pages'), findsOneWidget);
    });

    testWidgets('a page the document renders from a finding list is drawn',
        (WidgetTester tester) async {
      await _open(
        tester,
        document: _document(
          findings: const <DVDocsFinding>[
            DVDocsFinding(
              code: 'DV-DOCS-001',
              message: 'route /gone is in no module',
              source: 'lib/pages/home.dart:4',
            ),
          ],
        ),
        at: Uri.parse('https://shop.test/diagnostics'),
      );
      expect(
        find.textContaining('route /gone is in no module'),
        findsOneWidget,
      );
    });
  });

  group('the payload on disk is the document the app draws', () {
    test('it decodes, and the pages come back with their paths',
        () async {
      final String json =
          '{"application":"shop","graphVersion":7,"navigation":['
          '{"id":"index","label":"Overview"}],"pages":[{"id":"index",'
          '"title":"Shop","blocks":[{"kind":"paragraph","spans":['
          '{"kind":"text","text":"Hello."}]}]}],"findings":[]}';
      final DVDocsDocument read = dvDocsDecode(json);
      expect(read.application, 'shop');
      expect(read.page('index')!.path, '/');
      expect(read.page('index')!.text, 'Hello.');
    });

    test('a payload that is not a document is refused', () {
      expect(() => dvDocsDecode('<html>'), throwsFormatException);
    });
  });
}
