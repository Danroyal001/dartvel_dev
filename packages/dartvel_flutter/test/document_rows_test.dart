// Unbuilt lazy rows read from the server-rendered document instead of built.
//
// A row a lazy DVBox collection has not built has no semantics node, so a
// screen reader reading line by line stopped at the last row built (Tori and
// Learnacer, Dartvel 3.47.7). Building the rest while the page was idle
// reached them at ~20 ms of main thread a row, and 3.47.9 shipped it off by
// default. The build captures every page whole and marks each lazy
// collection's rows in the document; the running app gives an unbuilt row a
// stand-in from what the document says it holds -- a semantics node per
// link, heading and paragraph -- and builds nothing of the row.
import 'package:dartvel_core/dartvel.dart' show DVDocumentCollection, dvDocumentRows;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/lists/document_rows.dart';
import 'package:dartvel_flutter/src/lists/lazy_lists.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Header, page and footer as one scrollable DVBox list: Learnacer's layout.
Widget layoutPage({int paragraphs = 80, void Function(int)? built}) => DVBox.list(<Widget>[
      const Text('Site header'),
      DVBox.list(<Widget>[
        for (int i = 0; i < paragraphs; i++)
          Builder(builder: (BuildContext context) {
            built?.call(i);
            return Text('Paragraph $i about records.');
          }),
        const Text('Last paragraph'),
      ], spacing: 12),
      const Text('Footer made by somebody'),
    ], spacing: 0).scrollable();

/// The document the build writes for [layoutPage], marks and all.
String layoutDocument({int paragraphs = 80}) {
  String row(String inner) => '<!-- dartvel:row -->$inner<!-- /dartvel:row -->';
  return '<!-- dartvel:rows -->'
      '${row('<p>Site header</p>')}'
      '${row('<!-- dartvel:rows -->${<String>[
        for (int i = 0; i < paragraphs; i++) row('<p>Paragraph $i about records.</p>'),
        row('<p>Last paragraph</p>'),
      ].join()}<!-- /dartvel:rows -->')}'
      '${row('<p>Footer made by somebody</p>')}'
      '<!-- /dartvel:rows -->';
}

/// Every label in the semantics tree, in tree order.
List<String> semanticsLabels(WidgetTester tester) {
  final List<String> labels = <String>[];
  void visit(SemanticsNode node) {
    final String label = node.getSemanticsData().label;
    if (label.isNotEmpty) labels.add(label);
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return labels;
}

/// Gives every unbuilt row its stand-in, a frame per batch.
Future<int> standIn(WidgetTester tester, List<DVDocumentCollection> document) async {
  int total = 0;
  for (int round = 0; round < 50; round++) {
    final int given = dvApplyDocumentRows(tester.binding.rootElement!, document, limit: 16);
    await tester.pump();
    if (given == 0) break;
    total += given;
  }
  return total;
}

void main() {
  Widget screen(Widget child) => MaterialApp(
        home: DVPageShell(spec: const DVPageScaffoldSpec(title: 'Long page'), child: child),
      );

  testWidgets('a screen reader reaches every row and the footer, and no row is built for it', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final Set<int> built = <int>{};
    await tester.pumpWidget(screen(layoutPage(built: built.add)));
    await tester.pumpAndSettle();
    expect(semanticsLabels(tester).join('\n'), isNot(contains('Last paragraph')), reason: 'the first frame is as lazy as before');
    final int before = built.length;

    expect(await standIn(tester, dvDocumentRows(layoutDocument())), greaterThan(0));
    final String read = semanticsLabels(tester).join('\n');
    expect(read, contains('Paragraph 79 about records.'));
    expect(read, contains('Last paragraph'));
    expect(read, contains('Footer made by somebody'));
    // In order: the rows, then the footer after them.
    expect(read.indexOf('Paragraph 40 about records.'), lessThan(read.indexOf('Last paragraph')));
    expect(read.indexOf('Last paragraph'), lessThan(read.indexOf('Footer made by somebody')));
    expect(built.length, before, reason: 'no row was built to be read');
    expect(find.text('Paragraph 79 about records.'), findsNothing);
    expect(tester.getTopLeft(find.text('Site header')).dy, lessThan(100), reason: 'nothing scrolled');
    semantics.dispose();
  });

  testWidgets('a row scrolled to is built and replaces its stand-in', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(screen(layoutPage()));
    await tester.pumpAndSettle();
    await standIn(tester, dvDocumentRows(layoutDocument()));
    await tester.scrollUntilVisible(find.text('Paragraph 60 about records.'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Paragraph 60 about records.'), findsOneWidget);
    expect(RegExp('Paragraph 60 about').allMatches(semanticsLabels(tester).join('\n')), hasLength(1),
        reason: 'read once, from the row itself');
    semantics.dispose();
  });

  testWidgets('a collection the document does not match is given nothing', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(screen(layoutPage()));
    await tester.pumpAndSettle();
    // A document whose inner list has fewer rows than this page's: its rows
    // would be other rows' words.
    await standIn(tester, dvDocumentRows(layoutDocument(paragraphs: 50)));
    final String read = semanticsLabels(tester).join('\n');
    expect(read, isNot(contains('Last paragraph')));
    expect(read, isNot(contains('Paragraph 49 about')));
    semantics.dispose();
  });

  testWidgets('a link in a stand-in is a link, and opens what it names', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final List<String> opened = <String>[];
    DVLinkOpener.install((String path, {bool newTab = false}) => opened.add(path));
    await tester.pumpWidget(screen(DVBox.list(<Widget>[
      for (int i = 0; i < 40; i++) Text('Tool $i'),
    ])));
    await tester.pumpAndSettle();
    final String document = '<!-- dartvel:rows -->${<String>[
      for (int i = 0; i < 40; i++)
        '<!-- dartvel:row --><a href="https://t$i.tools.example.com/" title="Tool $i" aria-label="Tool $i">Tool $i</a><!-- /dartvel:row -->',
    ].join()}<!-- /dartvel:rows -->';
    await standIn(tester, dvDocumentRows(document));
    final SemanticsNode link = tester.getSemantics(find.bySemanticsLabel('Tool 39'));
    final SemanticsData data = link.getSemanticsData();
    expect(data.flagsCollection.isLink, isTrue);
    expect(data.linkUrl.toString(), 'https://t39.tools.example.com/');
    tester.binding.pipelineOwner.semanticsOwner!.performAction(link.id, SemanticsAction.tap);
    expect(opened, <String>['https://t39.tools.example.com/']);
    semantics.dispose();
  });

  group('while the build captures the page', () {
    setUp(() => DVLazyLists.buildWhole = true);
    tearDown(() => DVLazyLists.buildWhole = false);

    testWidgets('each lazy collection and each of its rows is marked for the document', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(screen(DVBox.list(<Widget>[
        const Text('Intro'),
        DVBox.list(<Widget>[for (int i = 0; i < 30; i++) Text('Row $i')]),
        // Short and not scrolling: not lazy anywhere, not marked.
        DVBox.list(<Widget>[for (int i = 0; i < 3; i++) Text('Short $i')]),
      ]).scrollable()));
      await tester.pumpAndSettle();
      final List<String> identifiers = <String>[];
      void visit(SemanticsNode node) {
        final String identifier = node.getSemanticsData().identifier;
        if (identifier.startsWith('dartvel:row')) identifiers.add(identifier);
        node.visitChildren((SemanticsNode child) {
          visit(child);
          return true;
        });
      }

      visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      // The scrollable list (3 rows) and the long one (30 rows) inside it.
      expect(identifiers.where((String id) => id == dvRowsIdentifier), hasLength(2));
      expect(identifiers.where((String id) => id == dvRowIdentifier), hasLength(33));
      semantics.dispose();
    });
  });
}
