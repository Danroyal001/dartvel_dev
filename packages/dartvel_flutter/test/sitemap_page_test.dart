// The human /sitemap page every Dartvel site gets (queue 6d10): the site's own
// sitemap.xml laid out like its XSL view, as a real page with links.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String sitemap = '''<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://example.com/</loc><lastmod>2026-11-12</lastmod></url>
  <url><loc>https://example.com/docs/getting-started</loc><lastmod>2026-11-10</lastmod></url>
  <url><loc>https://example.com/pricing</loc></url>
</urlset>''';

Widget page({required Future<String> Function() load}) => MaterialApp(
      home: DVSitemapPage(siteName: 'Example Co', description: 'Things we make.', siteUrl: 'https://example.com', load: load),
    );

void main() {
  testWidgets('it reads like the XML sitemap: label, site, count, then every page with its date', (WidgetTester tester) async {
    await tester.pumpWidget(page(load: () async => sitemap));
    await tester.pumpAndSettle();
    expect(find.text('XML SITEMAP'), findsOneWidget);
    expect(find.text('Example Co'), findsOneWidget);
    expect(find.text('Things we make.'), findsOneWidget);
    expect(find.text('3 pages'), findsOneWidget);
    expect(find.text('/docs/getting-started'), findsOneWidget);
    expect(find.text('12 Nov 2026'), findsOneWidget);
    expect(find.text('10 Nov 2026'), findsOneWidget);
    expect(find.text('/pricing'), findsOneWidget);
  });

  testWidgets('the site name is the page heading, for a screen reader too', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(page(load: () async => sitemap));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('Example Co')), matchesSemantics(label: 'Example Co', isHeader: true));
    semantics.dispose();
  });

  testWidgets('each page is a link to it', (WidgetTester tester) async {
    await tester.pumpWidget(page(load: () async => sitemap));
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.text('/docs/getting-started'), matching: find.byType(DVNavLink)), findsOneWidget);
  });

  testWidgets('no sitemap yet says so instead of an empty table', (WidgetTester tester) async {
    await tester.pumpWidget(page(load: () async => '<html>Not found</html>'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no pages listed'), findsOneWidget);
    expect(find.text('0 pages'), findsNothing);
  });
}
