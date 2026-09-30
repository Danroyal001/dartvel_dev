import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mouse can move into and use the custom card', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVNavLink(
              to: const DVRouteTarget('/custom'),
              preload: .none,
              preview: DVLinkPreview.widget(
                TextButton(
                  onPressed: () => taps++,
                  child: const Text('Card action'),
                ),
              ),
              child: const Text('Preview'),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: .mouse);
    await mouse.addPointer(location: .zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Preview')));
    await tester.pump(dvLinkPreviewDelay);
    await tester.idle();
    await tester.pump();
    final position = tester.getCenter(find.text('Card action'));
    await mouse.moveTo(position);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Card action'), findsOneWidget);
    await mouse.down(position);
    await mouse.up();
    await tester.pump();
    expect(taps, 1);
  });
  testWidgets(
    'custom preview works without a registered destination and stays bounded',
    (tester) async {
      tester.view.physicalSize = const Size(280, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Size? available;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: .bottomRight,
              child: DVNavLink(
                to: const DVRouteTarget('/custom'),
                preload: .none,
                preview: DVLinkPreview.widget(
                  LayoutBuilder(
                    builder: (_, constraints) {
                      available = constraints.biggest;
                      return const ColoredBox(
                        color: Colors.blue,
                        child: Text('Custom card'),
                      );
                    },
                  ),
                ),
                child: const Text('Preview'),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Custom card'), findsOneWidget);
      expect(available!.width, lessThanOrEqualTo(264));
      expect(available!.height, lessThanOrEqualTo(304));
      final bounds = tester.getRect(find.text('Custom card'));
      expect(bounds.left, greaterThanOrEqualTo(8));
      expect(bounds.right, lessThanOrEqualTo(272));
      expect(bounds.top, greaterThanOrEqualTo(8));
      expect(bounds.bottom, lessThanOrEqualTo(312));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom preview replaces destination and is interactive', (
    tester,
  ) async {
    var taps = 0;
    DVRoutePreviews.register('/custom', (_) => const Text('Default page'));
    addTearDown(DVRoutePreviews.clear);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVNavLink(
              to: const DVRouteTarget('/custom'),
              preload: .none,
              preview: DVLinkPreview.widget(
                TextButton(
                  onPressed: () => taps++,
                  child: const Text('Card action'),
                ),
              ),
              child: const Text('Preview'),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Default page'), findsNothing);
    await tester.tap(find.text('Card action'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.text('Card action'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Card action'), findsNothing);
  });
}
