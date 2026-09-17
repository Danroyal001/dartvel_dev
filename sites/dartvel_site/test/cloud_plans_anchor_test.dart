// The CLI tells an account with no plan to open dartvel.dev/cloud#plans. That
// link has to land somewhere: the Cloud page has a Plans section, and opening
// the page at #plans scrolls to it.
import 'package:dartvel_core/cloud.dart' show dvCloudPlansUrl;
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String plansHeading = 'Cloud builds are paid only.';

void main() {
  setUpAll(() async => CloudPageGeneratedPage.loadLibrary());
  setUp(dvResetDeferredPages);

  Future<double> plansTopAt(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final GoRouter router = GoRouter(
      initialLocation: location,
      routes: <RouteBase>[
        GoRoute(
          path: '/cloud',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: SelectionArea(child: CloudPageGeneratedPage())),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    for (int frame = 0; frame < 8; frame += 1) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text(plansHeading), findsOneWidget);
    return tester.getTopLeft(find.text(plansHeading)).dy;
  }

  test('the CLI links the Cloud page at the plans fragment', () {
    final Uri link = Uri.parse(dvCloudPlansUrl);
    expect(link.path, '/cloud');
    expect(link.fragment, 'plans');
  });

  testWidgets('without the fragment the plans section is below the fold',
      (WidgetTester tester) async {
    expect(await plansTopAt(tester, '/cloud'), greaterThan(900));
  });

  testWidgets('with #plans the page opens on the plans section',
      (WidgetTester tester) async {
    final double top = await plansTopAt(tester, '/cloud#plans');
    expect(top, inInclusiveRange(0, 900));
  });
}
