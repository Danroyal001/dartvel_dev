// The accessibility controls an app opts into with
// `dartvel.accessibility.defaultControls`: a button (the framework's floating one,
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
  late DVMemoryPreferenceStore store;
  DVAccessibilitySettings kept() => DVAccessibilitySettings.decode(store.read(dvAccessibilityStorageKey));

  setUp(() {
    store = DVMemoryPreferenceStore();
    DVPreferenceStore.instance = store;
    DVSpeech.instance = const DVSilentSpeech();
    DVAccessibilityControls.instance.install();
  });

  tearDown(() {
    DVAccessibilityControls.instance.reset();
    DVPreferenceStore.reset();
    DVSpeech.reset();
  });

  test('DV.Accessibility.controls is the one instance', () {
    expect(const DVAccessibility().controls, same(DVAccessibilityControls.instance));
    expect(DVAccessibilityControls.instance.enabled, isTrue);
  });

  test('install reads what the visitor chose last time', () {
    store.write(dvAccessibilityStorageKey, DVAccessibilitySettings(textScale: DVTextSize.larger.scale, highContrast: true).encode());
    DVAccessibilityControls.instance.install();
    expect(DVAccessibilityControls.instance.settings.textSize, DVTextSize.larger);
    expect(DVAccessibilityControls.instance.settings.highContrast, isTrue);
  });

  test('a change is kept, and reduced motion reaches DV.Accessibility.reducedMotion', () {
    DVAccessibilityControls.instance.update(const DVAccessibilitySettings(reducedMotion: true));
    expect(kept().reducedMotion, isTrue);
    expect(const DVAccessibility().reducedMotion, isTrue);
    DVAccessibilityControls.instance.update(const DVAccessibilitySettings());
    expect(kept().reducedMotion, isFalse);
  });

  testWidgets('the settings apply to the whole app: text size, contrast and motion', (WidgetTester tester) async {
    DVAccessibilityControls.instance
        .update(const DVAccessibilitySettings(textScale: 1.35, highContrast: true, reducedMotion: true));
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
    DVAccessibilityControls.instance.update(const DVAccessibilitySettings(textScale: 1.35));
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
      expect(kept().highContrast, isTrue);

      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Text size'), findsNothing);
    });

    testWidgets('on a phone at the largest text every size still reads on one line', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DVAccessibilityControls.instance.update(const DVAccessibilitySettings(textScale: 1.7));
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
      final DVSwitch motion = tester.widget<DVSwitch>(find.widgetWithText(DVSwitch, 'Reduce motion'));
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
      DVAccessibilityControls.instance.install(floatingButton: false);
      await tester.pumpWidget(_app(home: _page(header: DVAccessibilityButton())));
      expect(find.byTooltip(_tooltip), findsOneWidget, reason: 'only the header one');
    });

    testWidgets('is not there when the app has not opted in', (WidgetTester tester) async {
      DVAccessibilityControls.instance.reset();
      await tester.pumpWidget(_app(home: _page()));
      expect(find.byTooltip(_tooltip), findsNothing);
    });
  });

  // What a visitor chose is a model kept on the device: generated from
  // @DVModel(storage: DVModelStorage.device), so equality, copyWith and the
  // stored JSON come from the framework's own generator.
  group('the settings model', () {
    test('defaults: standard text, normal contrast, motion as the device asks', () {
      const DVAccessibilitySettings settings = DVAccessibilitySettings();
      expect(settings.textSize, DVTextSize.standard);
      expect(settings.textScale, 1.0);
      expect(settings.highContrast, isFalse);
      expect(settings.reducedMotion, isFalse);
      expect(settings.isDefault, isTrue);
    });

    test('stored as the JSON the SSR-first head reads, and read back equal', () {
      const DVAccessibilitySettings settings = DVAccessibilitySettings(textScale: 1.35, highContrast: true, reducedMotion: true);
      final String stored = settings.encode();
      expect(stored, contains('"textScale":1.35'));
      expect(stored, contains('"highContrast":true'));
      expect(stored, contains('"reducedMotion":true'));
      expect(DVAccessibilitySettings.decode(stored), settings);
      expect(DVAccessibilitySettings.decode(stored).hashCode, settings.hashCode);
    });

    test('anything unreadable is the default, so a broken value never stops a page', () {
      for (final String? stored in <String?>[null, '', '{', '[1]', '{"textScale":"huge"}']) {
        expect(DVAccessibilitySettings.decode(stored), const DVAccessibilitySettings(), reason: '$stored');
      }
      // 3.47.16-3.47.18 wrote a version number beside the fields.
      expect(DVAccessibilitySettings.decode('{"v":1,"textScale":1.7}').textSize, DVTextSize.larger);
    });
  });

  group('voice mode in the panel (defaultControls.voice)', () {
    const DVAccessibilityVoiceConfig voice = DVAccessibilityVoiceConfig(
      languages: <DVVoiceLanguage>[DVVoiceLanguage.english, DVVoiceLanguage.yoruba],
      machineTranslated: <DVVoiceLanguage>{DVVoiceLanguage.yoruba},
    );

    testWidgets('absent: no voice settings, and the button does not mention voice', (WidgetTester tester) async {
      await tester.pumpWidget(_app(home: Scaffold(body: Center(child: DVAccessibilityButton()))));
      expect(find.byTooltip(_tooltip), findsOneWidget);
      await tester.tap(find.byType(DVAccessibilityButton));
      await tester.pumpAndSettle();
      expect(find.text('Where voice mode sits'), findsNothing);
    });

    testWidgets('on: the button names voice, the panel offers where voice mode sits, kept for the next visit',
        (WidgetTester tester) async {
      DVAccessibilityControls.instance.install(voice: voice);
      await tester.pumpWidget(_app(home: Scaffold(body: Center(child: DVAccessibilityButton()))));
      expect(find.byTooltip(dvAccessibilityVoiceButtonLabel), findsOneWidget);
      await tester.tap(find.byType(DVAccessibilityButton));
      await tester.pumpAndSettle();
      expect(find.text('Where voice mode sits'), findsWidgets);
      await tester.ensureVisible(find.text('Centre'));
      await tester.tap(find.text('Centre'));
      await tester.pumpAndSettle();
      expect(DVAccessibilityControls.instance.voiceSettings.position, DVVoicePosition.centre);
      expect(DVVoiceSettings.decode(store.read(dvVoiceStorageKey)).position, DVVoicePosition.centre);
      expect(DVVoicePosition.centre.alignment, Alignment.center);
      expect(find.text('Voice language'), findsOneWidget);
    });

    testWidgets('the panel says what this device can do in the chosen language', (WidgetTester tester) async {
      DVSpeech.instance = const _Speech(canSpeak: true, voices: <String>{'en-US'});
      DVAccessibilityControls.instance.install(voice: voice);
      await tester.pumpWidget(_app(home: Scaffold(body: Center(child: DVAccessibilityButton()))));
      await tester.tap(find.byType(DVAccessibilityButton));
      await tester.pumpAndSettle();
      expect(find.text('Voice available.'), findsOneWidget);
      DVAccessibilityControls.instance.updateVoice(const DVVoiceSettings(language: 'yo'));
      await tester.pumpAndSettle();
      expect(DVAccessibilityControls.instance.voiceLanguage, DVVoiceLanguage.yoruba);
      expect(
        find.text('Prompts translated by AI, not yet checked by a native speaker; '
            'no Yoruba voice on this device; shown as text, read in English.'),
        findsOneWidget,
      );
    });

    test('a kept language the app no longer offers falls back to its first one', () {
      store.write(dvVoiceStorageKey, const DVVoiceSettings(language: 'ha').encode());
      DVAccessibilityControls.instance.install(voice: voice);
      expect(DVAccessibilityControls.instance.voiceLanguage, DVVoiceLanguage.english);
    });
  });

  group('availability notes', () {
    test('a device that cannot speak shows prompts as text', () {
      expect(dvVoiceAvailability(DVVoiceLanguage.english, speech: const DVSilentSpeech()),
          'This browser cannot speak; prompts are shown as text.');
    });

    test('no voice for the language', () {
      expect(dvVoiceAvailability(DVVoiceLanguage.igbo, speech: const _Speech(canSpeak: true, voices: <String>{'en-GB'})),
          'No Igbo voice on this device; shown as text, read in English.');
    });

    test('a voice for the language', () {
      expect(dvVoiceAvailability(DVVoiceLanguage.yoruba, speech: const _Speech(canSpeak: true, voices: <String>{'yo-NG'})),
          'Voice available.');
    });
  });

  group('formerKey: settings the app kept itself before', () {
    test('are carried over once: large text, contrast, voice position and language', () {
      store.write('shop.display', '{"v":1,"largeText":true,"highContrast":true,"zone":"centre","language":"yo"}');
      DVAccessibilityControls.instance.install(formerKey: 'shop.display', voice: const DVAccessibilityVoiceConfig(
        languages: <DVVoiceLanguage>[DVVoiceLanguage.english, DVVoiceLanguage.yoruba],
      ));
      final DVAccessibilityControls controls = DVAccessibilityControls.instance;
      expect(controls.settings.textSize, DVTextSize.large);
      expect(controls.settings.highContrast, isTrue);
      expect(controls.voiceSettings.position, DVVoicePosition.centre);
      expect(controls.voiceLanguage, DVVoiceLanguage.yoruba);
      expect(store.read('shop.display'), isNotNull, reason: 'the old value is left where it was');
    });

    test('never overwrite what the visitor chose in the framework panel', () {
      store.write(dvAccessibilityStorageKey, const DVAccessibilitySettings(reducedMotion: true).encode());
      store.write('shop.display', '{"largeText":true}');
      DVAccessibilityControls.instance.install(formerKey: 'shop.display');
      expect(DVAccessibilityControls.instance.settings, const DVAccessibilitySettings(reducedMotion: true));
    });

    test('an unreadable former value changes nothing', () {
      store.write('shop.display', 'not json');
      DVAccessibilityControls.instance.install(formerKey: 'shop.display');
      expect(DVAccessibilityControls.instance.settings.isDefault, isTrue);
      expect(store.read(dvAccessibilityStorageKey), isNull);
    });
  });
}

final class _Speech implements DVSpeech {
  const _Speech({required this.canSpeak, required this.voices});

  @override
  final bool canSpeak;

  final Set<String> voices;

  @override
  bool get canListen => canSpeak;

  @override
  Set<String> get voiceLanguages => voices;

  @override
  Future<void> speak(String text, {required DVVoiceLanguage language}) async {}

  @override
  Future<String?> listen({required DVVoiceLanguage language}) async => null;

  @override
  void stop() {}
}
