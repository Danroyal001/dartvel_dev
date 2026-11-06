import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(dvResetDeferredPages);

  testWidgets('a preloaded page draws its body on its first frame', (
    tester,
  ) async {
    await tester.runAsync(DocsRoutingPageGeneratedPage.loadLibrary);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DocsRoutingPageGeneratedPage())),
    );
    expect(
      find.byType(DvDefaultLoading),
      findsNothing,
      reason: 'an already loaded page must not insert another loading frame',
    );
    expect(find.byType(DocsArticle), findsOneWidget);
  });

  testWidgets('a preloaded route loader never inserts a waiting frame', (
    tester,
  ) async {
    await tester.runAsync(DocsRoutingPageGeneratedPage.loadLibrary);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DvDataLoader(
            load: () => const DocsRoutingPageGeneratedPage().loadData({}, {}),
            child: const DocsRoutingPageGeneratedPage(),
          ),
        ),
      ),
    );
    expect(find.byType(DvDefaultLoading), findsNothing,
        reason: 'preloaded UI-only route data is already ready');
    expect(find.byType(DocsArticle), findsOneWidget);
  });
}
