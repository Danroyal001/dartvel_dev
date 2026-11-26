// The accessibility controls an app opts into with
// `dartvel.accessibility.controls`: a button (the framework's floating one,
// or DVAccessibilityButton where the app puts it) opening a panel whose
// text size, high contrast and reduced motion apply to the whole app, are
// kept for the visitor's next visit, and never undo what the operating
// system asks for.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const String _tooltip = 'Accessibility: text size, contrast and motion';

late MediaQueryData _seen;
late ThemeData _theme;

Widget _probe() => Builder(builder: (BuildContext context) {
      _seen = MediaQuery.of(context);
      _theme = Theme.of(context);
      return const Text('Page body');
    });

Widget _app({Widget? home, ThemeData? highContrastTheme}) => DVAccessibilityFrame(
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.green),
        highContrastTheme: highContrastTheme,
        home: home ?? Scaffold(body: _probe()),
      ),
    );

Widget _page({Widget? header}) => DVPageShell(
      spec: const DVPageScaffoldSpec(title: 'Home'),
      child: Column(children: <Widget>[if (header != null) header, Expanded(child: _probe())]),
    );

void main() {
  late DVMemoryAccessibilityStore store;

  setUp(() {
    store = DVMemoryAccessibilityStore();
    DVAccessibilityControls.instance.install(store: store);
  });

  tearDown(() {
    DVAccessibilityControls.instance.reset();
  });

  test('DV.Accessibility.controls is the one instance', () {
    expect(const DVAccessibility().controls, same(DVAccessibilityControls.instance));
    expect(DVAccessibilityControls.instance.enabled, isTrue);
  });

  test('install reads what the visitor chose last time', () {
    final DVMemoryAccessibilityStore kept = DVMemoryAccessibilityStore()
      ..value = const DVAccessibilitySettings(textSize: DVTextSize.larger, highContrast: true).encode();
    DVAccessibilityControls.instance.install(store: kept);
    expect(DVAccessibilityControls.instance.settings.textSize, DVTextSize.larger);
    expect(DVAccessibilityControls.instance.settings.highContrast, isTrue);
  });

  test('a change is kept, and reduced motion reaches DV.Accessibility.reducedMotion', () {
    DVAccessibilityControls.instance.update(const DVAccessibilitySettings(reducedMotion: true));
    expect(DVAccessibilitySettings.decode(store.value).reducedMotion, isTrue);
    expect(const DVAccessibility().reducedMotion, isTrue);
    DVAccessibilityControls.instance.update(const DVAccessibilitySettings());
    expect(DVAccessibilitySettings.decode(store.value).reducedMotion, isFalse);
  });

  testWidgets('the settings apply to the whole app: text size, contrast and motion', (WidgetTester tester) async {
    DVAccessibilityControls.instance
        .update(const DVAccessibilitySettings(textSize: DVTextSize.large, highContrast: true, reducedMotion: true));
    await tester.pumpWidget(_app());
    expect(_seen.textScaler.scale(10), closeTo(13.5, 0.001));
    expect(_seen.highContrast, isTrue);
    expect(_seen.disableAnimations, isTrue);

    DVAccessibilityControls.instance.update(const DVAccessibilitySettings());
    await tester.pump();
    expect(_seen.textScaler.scale(10), closeTo(10, 0.001));
    expect(_seen.highContrast, isFalse);
    expect(_seen.disableAnimations, isFalse);
  });

  testWidgets('the device\'s own text size and reduce-motion setting still count', (WidgetTester tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    DVAccessibilityControls.instance.update(const DVAccessibilitySettings(textSize: DVTextSize.large));
    await tester.pumpWidget(_app());
    expect(_seen.textScaler.scale(10), closeTo(10 * 1.2 * 1.35, 0.01));
    expect(_seen.disableAnimations, isTrue);
  });

  testWidgets('nothing changes when the app has not opted in', (WidgetTester tester) async {
    DVAccessibilityControls.instance.reset();
    await tester.pumpWidget(_app());
    expect(_seen.textScaler.scale(10), closeTo(10, 0.001));
  });

  group('high contrast', () {
    testWidgets('an app with no high-contrast theme gets one made from its own', (WidgetTester tester) async {
      DVAccessibilityControls.instance.update(const DVAccessibilitySettings(highContrast: true));
      await tester.pumpWidget(_app(home: _page()));
      expect(_theme.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(_theme.colorScheme.onSurface, const Color(0xFF000000));
      expect(_theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    });

    testWidgets("an app's own high-contrast theme is the one used", (WidgetTester tester) async {
      DVAccessibilityControls.instance.update(const DVAccessibilitySettings(highContrast: true));
      final ThemeData own = ThemeData(colorScheme: const ColorScheme.highContrastLight(primary: Color(0xFF123456)));
      await tester.pumpWidget(_app(home: _page(), highContrastTheme: own));
      expect(_theme.colorScheme.primary, const Color(0xFF123456));
    });

    test('the made theme is pure black and white in dark mode too', () {
      final ThemeData dark = dvHighContrastTheme(ThemeData(brightness: Brightness.dark, colorSchemeSeed: Colors.green));
      expect(dark.colorScheme.surface, const Color(0xFF000000));
      expect(dark.colorScheme.onSurface, const Color(0xFFFFFFFF));
      expect(dark.brightness, Brightness.dark);
    });
  });

  group('the button', () {
    testWidgets('has its name as a tooltip and as its accessible label', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(home: Scaffold(body: Center(child: DVAccessibilityButton()))));
      expect(find.byTooltip(_tooltip), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Accessibility')), findsWidgets);
      expect(find.text('Accessibility'), findsOneWidget);
      final Size size = tester.getSize(find.byType(DVAccessibilityButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });

    testWidgets('compact is the icon alone, still named', (WidgetTester tester) async {
      await tester.pumpWidget(_app(home: Scaffold(body: Center(child: DVAccessibilityButton(compact: true)))));
      expect(find.text('Accessibility'), findsNothing);
      expect(find.byTooltip(_tooltip), findsOneWidget);
    });

    testWidgets('opens the panel; each choice applies at once and is kept', (WidgetTester tester) async {
      await tester.pumpWidget(_app(home: Scaffold(body: Column(children: <Widget>[DVAccessibilityButton(), Expanded(child: _probe())]))));
      await tester.tap(find.byType(DVAccessibilityButton));
      await tester.pumpAndSettle();
      expect(find.text('Text size'), findsOneWidget);
      expect(find.text('High contrast'), findsOneWidget);
      expect(find.text('Reduce motion'), findsOneWidget);

      await tester.tap(find.text('Larger'));
      await tester.pumpAndSettle();
      expect(DVAccessibilityControls.instance.settings.textSize, DVTextSize.larger);
      expect(_seen.textScaler.scale(10), closeTo(17, 0.001));

      // At the larger text size the panel scrolls.
      await tester.ensureVisible(find.text('High contrast'));
      await tester.tap(find.text('High contrast'));
      await tester.pumpAndSettle();
      expect(DVAccessibilitySettings.decode(store.value).highContrast, isTrue);

      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Text size'), findsNothing);
    });

    testWidgets('on a phone at the largest text every size still reads on one line', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DVAccessibilityControls.instance.update(const DVAccessibilitySettings(textSize: DVTextSize.larger));
      await tester.pumpWidget(_app(home: Scaffold(body: Center(child: DVAccessibilityButton()))));
      await tester.tap(find.byType(DVAccessibilityButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final double dialogRight = tester.getRect(find.byType(AlertDialog)).right;
      for (final String size in <String>['Default', 'Large', 'Larger']) {
        final Rect label = tester.getRect(find.text(size));
        final double line = tester.getRect(find.text('Text size')).height;
        expect(label.height, lessThan(line * 1.5), reason: '$size on one line');
        expect(label.right, lessThanOrEqualTo(dialogRight), reason: '$size inside the panel');
      }
    });

    testWidgets('the panel itself is pure black and white in high contrast', (WidgetTester tester) async {
      DVAccessibilityControls.instance.update(const DVAccessibilitySettings(highContrast: true));
      await tester.pumpWidget(_app(home: Scaffold(body: Center(child: DVAccessibilityButton()))));
      await tester.tap(find.byType(DVAccessibilityButton));
      await tester.pumpAndSettle();
      final Material dialog = tester.widget<Material>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first);
      expect(dialog.color, const Color(0xFFFFFFFF));
    });

    testWidgets('reduce motion the device asks for shows as on, and cannot be turned off here', (WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(_app(home: Scaffold(body: Center(child: DVAccessibilityButton()))));
      await tester.tap(find.byType(DVAccessibilityButton));
      await tester.pumpAndSettle();
      expect(find.text('Already on, because your device asks for less motion.'), findsOneWidget);
      final SwitchListTile motion = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Reduce motion'));
      expect(motion.value, isTrue);
      expect(motion.onChanged, isNull);
    });

    testWidgets('an app whose panel has more in it can say so in the name', (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        home: Scaffold(body: Center(child: DVAccessibilityButton(tooltip: 'Accessibility: text size, contrast, motion and voice language'))),
      ));
      expect(find.byTooltip('Accessibility: text size, contrast, motion and voice language'), findsOneWidget);
      expect(find.byTooltip(_tooltip), findsNothing);
    });

    testWidgets("an app's own settings can join the panel", (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        home: Scaffold(
          body: Center(child: DVAccessibilityButton(more: (BuildContext context) => const Text('Voice language'))),
        ),
      ));
      await tester.tap(find.byType(DVAccessibilityButton));
      await tester.pumpAndSettle();
      expect(find.text('Voice language'), findsOneWidget);
    });
  });

  group('the floating button', () {
    testWidgets('is on every page by default', (WidgetTester tester) async {
      await tester.pumpWidget(_app(home: _page()));
      expect(find.byTooltip(_tooltip), findsOneWidget);
    });

    testWidgets('is left out when the app places the button itself', (WidgetTester tester) async {
      DVAccessibilityControls.instance.install(store: store, floatingButton: false);
      await tester.pumpWidget(_app(home: _page(header: DVAccessibilityButton())));
      expect(find.byTooltip(_tooltip), findsOneWidget, reason: 'only the header one');
    });

    testWidgets('is not there when the app has not opted in', (WidgetTester tester) async {
      DVAccessibilityControls.instance.reset();
      await tester.pumpWidget(_app(home: _page()));
      expect(find.byTooltip(_tooltip), findsNothing);
    });
  });
}
