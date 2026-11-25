// The footer is a component placed in one place, never a line each page
// repeats. Every page returns its content in SiteScroll, the site's page
// frame, which scrolls it and puts the one SiteFooter after it; the docs put
// theirs in DocsArticle, once for every docs page. A page that forgets the
// footer, or carries two, is the drift this exists to stop.
import 'dart:io';

import 'package:dartvel_site/components/site.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every page file of the site outside the docs, and not a layout or a
/// loading or error companion.
List<File> sitePages() => <File>[
      for (final FileSystemEntity file
          in Directory('lib/pages').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.replaceAll(r'\', '/').contains('/docs/') &&
            !file.path.endsWith('_layout.dart') &&
            !file.path.endsWith('.loading.dart') &&
            !file.path.endsWith('.error.dart'))
          file,
    ];

void main() {
  test('no page places the footer itself', () {
    final List<String> placing = <String>[
      for (final FileSystemEntity file
          in Directory('lib/pages').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('SiteFooter('))
          file.path,
    ];
    expect(placing, isEmpty);
  });

  test('every page returns its content in SiteScroll, so every page has the footer', () {
    final List<String> missing = <String>[
      for (final File page in sitePages())
        if (!page.readAsStringSync().contains('SiteScroll(')) page.path,
    ];
    expect(sitePages(), isNotEmpty);
    expect(missing, isEmpty);
  });

  testWidgets('SiteScroll puts one footer after the page, inside its scroll',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SiteScroll(<Widget>[DVText('Terms body')]),
      ),
    ));
    await tester.pump();
    expect(find.byType(SiteFooter, skipOffstage: false), findsOneWidget);
    final Finder scroll = find.byType(SingleChildScrollView);
    expect(scroll, findsOneWidget);
    expect(find.descendant(of: scroll, matching: find.text('Terms body')), findsOneWidget);
    expect(
      find.descendant(of: scroll, matching: find.byType(SiteFooter, skipOffstage: false)),
      findsOneWidget,
      reason: 'the footer scrolls with the page, after it',
    );
    expect(
      tester.getTopLeft(find.byType(SiteFooter, skipOffstage: false)).dy,
      greaterThan(tester.getTopLeft(find.text('Terms body')).dy),
    );
  });
}
