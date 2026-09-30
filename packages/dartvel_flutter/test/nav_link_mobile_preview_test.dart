import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> page(WidgetTester tester, {DVLinkPreview preview = .auto}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  DVRoutePreviews.register(
    '/destination',
    (_) => const Text('Preview content'),
  );
  addTearDown(DVRoutePreviews.clear);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            DVNavLink(
              to: const DVRouteTarget('/destination'),
              preload: .none,
              preview: preview,
              child: const Text('Open preview'),
            ),
            const SizedBox(height: 1800),
          ],
        ),
      ),
    ),
  );
  await tester.longPress(find.text('Open preview'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone tap outside dismisses preview', (tester) async {
    await page(tester);
    expect(find.text('Preview content'), findsOneWidget);
    await tester.tapAt(const Offset(380, 700));
    await tester.pumpAndSettle();
    expect(find.text('Preview content'), findsNothing);
  });
  testWidgets('phone scroll outside dismisses preview', (tester) async {
    await page(tester);
    await tester.dragFrom(const Offset(380, 700), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('Preview content'), findsNothing);
  });
  testWidgets('system back dismisses preview without leaving page', (
    tester,
  ) async {
    await page(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Preview content'), findsNothing);
    expect(find.text('Open preview'), findsOneWidget);
  });
  testWidgets('disabled preview does not open on long press', (tester) async {
    await page(tester, preview: .none);
    expect(find.text('Preview content'), findsNothing);
  });
}
