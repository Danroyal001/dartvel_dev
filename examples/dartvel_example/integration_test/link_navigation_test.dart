// Link navigation, on whatever platform is running this.
//
// Widget tests tap a widget in a fake tree, and that is not the same thing.
// The dartvel.dev header shipped dead while a widget suite passed it: the tap
// handler built a callback and never called it, which a fake tree cannot tell
// apart from a working link. Only a running application can.
//
// This runs wherever the example runs — a desktop window, an Android
// emulator, an iOS or tvOS simulator, a browser, a virtual eLinux device — so
// "links work" means on every platform rather than on the one that was easy.
//
// Run with: dartvel test e2e   (or: flutter test integration_test -d <device>)
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Start the app and wait for the first page to arrive.
  ///
  /// Generated pages load their bundle on demand, and on a real device that
  /// is a genuine wait rather than a microtask. Polling rather than
  /// pumpAndSettle: a page with any continuous animation never settles, and
  /// the timeout would read as a broken link.
  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(createDartvelExampleApp());
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byKey(const Key('link-about')).evaluate().isNotEmpty) return;
    }
    fail('the index page never rendered; the app did not start');
  }

  Future<void> waitForPath(WidgetTester tester, String path) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (DV.Navigation.currentPath == path) return;
    }
  }

  group('links navigate on this platform', () {
    testWidgets('tapping a link goes to its route', (WidgetTester tester) async {
      await start(tester);

      await tester.tap(find.byKey(const Key('link-about')));
      await waitForPath(tester, '/about');

      expect(DV.Navigation.currentPath, '/about',
          reason: 'tapping About did not navigate on this platform');
    });

    testWidgets('a second link goes somewhere else',
        (WidgetTester tester) async {
      // One working link could be a coincidence of layout; two that go to
      // different places is navigation.
      await start(tester);

      await tester.tap(find.byKey(const Key('link-pricing')));
      await waitForPath(tester, '/pricing');

      expect(DV.Navigation.currentPath, '/pricing');
    });

    testWidgets('the padding around a link is part of the target',
        (WidgetTester tester) async {
      // Bare glyphs leave the gaps between letters dead, so a tap that looks
      // on-target misses — and on a phone, where the target is a fingertip,
      // it misses often.
      await start(tester);

      final rect = tester.getRect(find.byKey(const Key('link-about')));
      await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
      await waitForPath(tester, '/about');

      expect(DV.Navigation.currentPath, '/about');
    });

    testWidgets('a link announces itself as a link',
        (WidgetTester tester) async {
      // On a device this is the semantics tree assistive technology actually
      // reads, which a widget test's is not.
      final SemanticsHandle handle = tester.ensureSemantics();
      await start(tester);

      expect(
        tester.getSemantics(find.byKey(const Key('link-about'))),
        isSemantics(isLink: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });
}
