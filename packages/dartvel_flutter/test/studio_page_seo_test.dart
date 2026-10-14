import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );

void main() {
  group('DVPageDocument SEO metadata & export', () {
    test('serializes and deserializes SEO fields', () {
      final DVPageDocument doc = DVPageDocument(
        route: '/about',
        title: 'About Us',
        description: 'Learn more about our company and mission.',
        image: 'https://example.com/images/about.png',
        robots: 'noindex, follow',
        schemaType: 'AboutPage',
        canonicalUrl: 'https://example.com/about-us',
        sitemap: false,
      );

      final Map<String, Object?> json = doc.toJson();
      expect(json['route'], '/about');
      expect(json['title'], 'About Us');
      expect(json['description'], 'Learn more about our company and mission.');
      expect(json['image'], 'https://example.com/images/about.png');
      expect(json['robots'], 'noindex, follow');
      expect(json['schemaType'], 'AboutPage');
      expect(json['canonicalUrl'], 'https://example.com/about-us');
      expect(json['sitemap'], false);

      final DVPageDocument restored = DVPageDocument.fromJson(json);
      expect(restored.route, '/about');
      expect(restored.title, 'About Us');
      expect(restored.description, 'Learn more about our company and mission.');
      expect(restored.image, 'https://example.com/images/about.png');
      expect(restored.robots, 'noindex, follow');
      expect(restored.schemaType, 'AboutPage');
      expect(restored.canonicalUrl, 'https://example.com/about-us');
      expect(restored.sitemap, isFalse);
    });

    test('copyWith updates SEO fields selectively', () {
      final DVPageDocument doc = DVPageDocument(
        route: '/pricing',
        title: 'Pricing Plans',
        description: 'Affordable pricing for teams of any size.',
      );

      final DVPageDocument updated = doc.copyWith(
        description: 'Updated pricing overview',
        image: 'https://example.com/pricing.png',
        sitemap: false,
      );

      expect(updated.title, 'Pricing Plans');
      expect(updated.description, 'Updated pricing overview');
      expect(updated.image, 'https://example.com/pricing.png');
      expect(updated.sitemap, isFalse);
    });

    test('toDartSource exports @DVPage description', () {
      final DVPageDocument doc = DVPageDocument(
        route: '/docs',
        title: 'Documentation',
        description: 'Guides and API references for developers.',
      );

      final String source = doc.toDartSource();
      expect(
        source,
        contains(
            "@DVPage(title: 'Documentation', description: 'Guides and API references for developers.')"),
      );
    });
  });

  group('DVStudioEditorController updatePageSeo', () {
    test('updates SEO fields and supports undo/redo', () {
      final DVPageDocument doc = DVPageDocument(
        route: '/blog',
        title: 'Blog',
      );
      final DVStudioEditorController controller =
          DVStudioEditorController(doc);

      expect(controller.canUndo, isFalse);
      controller.updatePageSeo(
        title: 'Latest News & Blog',
        description: 'Read the latest updates from our engineering team.',
        image: 'https://example.com/blog.png',
        robots: 'index, follow',
        schemaType: 'Article',
        canonicalUrl: 'https://example.com/blog',
        sitemap: true,
      );

      expect(controller.document.title, 'Latest News & Blog');
      expect(controller.document.description,
          'Read the latest updates from our engineering team.');
      expect(controller.document.image, 'https://example.com/blog.png');
      expect(controller.document.robots, 'index, follow');
      expect(controller.document.schemaType, 'Article');
      expect(controller.document.canonicalUrl, 'https://example.com/blog');
      expect(controller.document.sitemap, isTrue);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.document.title, 'Blog');
      expect(controller.document.description, isNull);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.document.title, 'Latest News & Blog');
      expect(controller.document.description,
          'Read the latest updates from our engineering team.');
    });

    test('readOnly controller refuses updatePageSeo', () {
      final DVPageDocument doc = DVPageDocument(route: '/terms');
      final DVStudioEditorController controller =
          DVStudioEditorController(doc, readOnly: true);

      expect(
        () => controller.updatePageSeo(title: 'New Terms'),
        throwsStateError,
      );
    });
  });

  group('DVStudioPageSeoPanel Widget Tests', () {
    testWidgets('renders route, title counter, description counter, and live previews',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final DVPageDocument doc = DVPageDocument(
        route: '/products/widget-pro',
        title: 'Widget Pro - Next-gen Tooling',
        description: 'Build fast and scalable apps with Widget Pro.',
        image: 'https://example.com/widget-pro.png',
        canonicalUrl: 'https://example.com/products/widget-pro',
      );
      final DVStudioEditorController controller =
          DVStudioEditorController(doc);

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 500,
          height: 800,
          child: DVStudioPageSeoPanel(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      // Route display
      expect(find.byKey(const ValueKey<String>('dv-studio-page-seo-route')),
          findsOneWidget);
      expect(find.text('/products/widget-pro'), findsOneWidget);

      // Character counters
      expect(find.byKey(const ValueKey<String>('dv-studio-page-seo-title-count')),
          findsOneWidget);
      expect(find.text('${doc.title.length} / 60'), findsOneWidget);

      expect(find.byKey(const ValueKey<String>('dv-studio-page-seo-desc-count')),
          findsOneWidget);
      expect(find.text('${doc.description!.length} / 160'), findsOneWidget);

      // Google Search Snippet Preview
      expect(
          find.byKey(const ValueKey<String>('dv-studio-page-seo-search-preview')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>(
              'dv-studio-page-seo-search-preview-title')),
          findsOneWidget);
      expect(find.text('Widget Pro - Next-gen Tooling'), findsWidgets);

      // Social Share Card Preview
      expect(
          find.byKey(const ValueKey<String>('dv-studio-page-seo-social-preview')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('dv-studio-page-seo-social-card')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('dv-studio-page-seo-social-title')),
          findsOneWidget);
    });

    testWidgets('editing title and description updates document and counters',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final DVPageDocument doc = DVPageDocument(route: '/features');
      final DVStudioEditorController controller =
          DVStudioEditorController(doc);

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 500,
          height: 800,
          child: DVStudioPageSeoPanel(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      // Enter Title
      final Finder titleInput =
          find.byKey(const ValueKey<String>('dv-studio-page-seo-title'));
      await tester.enterText(titleInput, 'Amazing Features');
      await tester.pumpAndSettle();

      expect(controller.document.title, 'Amazing Features');
      expect(find.text('16 / 60'), findsOneWidget);

      // Enter Description
      final Finder descInput =
          find.byKey(const ValueKey<String>('dv-studio-page-seo-description'));
      await tester.enterText(descInput, 'Explore all features in depth.');
      await tester.pumpAndSettle();

      expect(controller.document.description, 'Explore all features in depth.');
      expect(find.text('30 / 160'), findsOneWidget);

      // Verify Google search preview updated
      expect(
        find.descendant(
          of: find.byKey(
              const ValueKey<String>('dv-studio-page-seo-search-preview')),
          matching: find.text('Amazing Features'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('toggles sitemap inclusion switch',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final DVPageDocument doc =
          DVPageDocument(route: '/secret', sitemap: true);
      final DVStudioEditorController controller =
          DVStudioEditorController(doc);

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 500,
          height: 800,
          child: DVStudioPageSeoPanel(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      final Finder sitemapSwitch =
          find.byKey(const ValueKey<String>('dv-studio-page-seo-sitemap'));
      expect(sitemapSwitch, findsOneWidget);
      await tester.ensureVisible(sitemapSwitch);
      await tester.pumpAndSettle();
      await tester.tap(sitemapSwitch);
      await tester.pumpAndSettle();

      expect(controller.document.sitemap, isFalse);

      await tester.tap(sitemapSwitch);
      await tester.pumpAndSettle();

      expect(controller.document.sitemap, isTrue);
    });

    testWidgets('inspector shows Page SEO action when no node is selected',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final DVPageDocument doc =
          DVPageDocument(route: '/contact', title: 'Contact Us');
      final DVStudioEditorController controller =
          DVStudioEditorController(doc);

      // Initially no node is selected
      expect(controller.selectedNode, isNull);

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 320,
          height: 800,
          child: DVStudioInspector(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Nothing selected'), findsOneWidget);
      final Finder openSeo =
          find.byKey(const ValueKey<String>('dv-studio-open-page-seo'));
      expect(openSeo, findsOneWidget);

      await tester.tap(openSeo);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('dv-studio-page-seo-panel')),
          findsOneWidget);
      expect(find.text('Contact Us'), findsWidgets);
    });

    testWidgets('dvShowStudioPageSeoDialog launches modal with SEO panel',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final DVPageDocument doc =
          DVPageDocument(route: '/services', title: 'Our Services');
      final DVStudioEditorController controller =
          DVStudioEditorController(doc);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => dvShowStudioPageSeoDialog(context, controller),
            child: const Text('Open SEO Settings'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open SEO Settings'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('dv-studio-page-seo-panel')),
          findsOneWidget);
      expect(find.text('Our Services'), findsWidgets);
    });
  });
}
