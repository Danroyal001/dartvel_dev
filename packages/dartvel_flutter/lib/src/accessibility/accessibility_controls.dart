// The accessibility controls an app opts into with
// `dartvel.accessibility.defaultControls` in pubspec.yaml (or
// `DartvelConfig.accessibilityDefaultControls`), with no code of its own.
//
// A button -- the framework's floating one on every page, or
// [DVAccessibilityButton] wherever the app puts it, usually its header --
// opens a panel with the reader's choices: text size, high contrast and
// reduced motion, and, with `defaultControls.voice`, where voice mode sits and
// the language it speaks. Each applies to the whole app at once, in the app's
// own theme, light and dark, and is kept for the visitor's next visit
// (models kept on the device: [DVAccessibilitySettings], [DVVoiceSettings]).
// The operating system's own settings always count: its text size is
// multiplied, and its reduce-motion and more-contrast settings cannot be
// turned off from here.
//
// On the web with SSR-first, the head reads the same stored value before the
// first paint, so the server-rendered page is already in the visitor's
// settings (see dvSsrFirstHead in dartvel_core).
import 'dart:ui' show AccessibilityFeatures;

import 'package:dartvel_core/dartvel.dart'
    show DVAccessibilityVoiceConfig, DVTextSize, DVVoiceLanguage, dvAccessibilityStorageKey;

import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart' show DV, DVAccessibility, DVBox, DVChoice, DVChoiceStyle, DVSwitch, DVText;
import '../platform/storage/preference_store.dart';
import 'accessibility_platform_stub.dart'
    if (dart.library.js_interop) 'accessibility_platform_web.dart' as platform;
import 'accessibility_settings.g.dart';
import 'former_settings.g.dart';
import 'speech.dart';
import 'voice_settings.g.dart';

export 'package:dartvel_core/dartvel.dart'
    show DVAccessibilityVoiceConfig, DVTextSize, DVVoiceLanguage, dvAccessibilityStorageKey, dvVoiceStorageKey;

export 'accessibility_settings.g.dart' show DVAccessibilitySettings;
export 'speech.dart';
export 'voice_settings.g.dart' show DVVoicePosition, DVVoiceSettings;

/// The words of the button: its tooltip and its accessible name.
const String dvAccessibilityButtonLabel = 'Accessibility: text size, contrast and motion';

/// The button's words when the panel also has voice mode's settings.
const String dvAccessibilityVoiceButtonLabel = 'Accessibility: text size, contrast, motion and voice';

/// The text size a visitor chose, by name.
extension DVAccessibilitySettingsText on DVAccessibilitySettings {
  /// The size the panel shows as chosen.
  DVTextSize get textSize => DVTextSize.fromScale(textScale);

  /// Nothing chosen.
  bool get isDefault => this == const DVAccessibilitySettings();
}

/// Where voice mode sits, as an alignment for the app's voice overlay.
extension DVVoicePositionAlignment on DVVoicePosition {
  /// Top centre, or the middle of the screen for a narrow field of view.
  Alignment get alignment => this == DVVoicePosition.centre ? Alignment.center : Alignment.topCenter;

  /// The name the panel shows.
  String get label => this == DVVoicePosition.centre ? 'Centre' : 'Top';
}

/// The 3.47.16 store interface, before settings were models kept on the
/// device.
@Deprecated('Settings are kept in DVPreferenceStore now; tests set DVPreferenceStore.instance = DVMemoryPreferenceStore().')
abstract interface class DVAccessibilityStore {
  String? read();
  void write(String value);
}

/// The 3.47.16 memory store.
@Deprecated('Use DVMemoryPreferenceStore.')
// ignore: deprecated_member_use_from_same_package
final class DVMemoryAccessibilityStore implements DVAccessibilityStore {
  String? value;

  @override
  String? read() => value;

  @override
  void write(String value) => this.value = value;
}

/// A 3.47.16 store, seen as a preference store for the accessibility key.
final class _OldStore implements DVPreferenceStore {
  _OldStore(this._old, this._rest);

  // ignore: deprecated_member_use_from_same_package
  final DVAccessibilityStore _old;
  final DVPreferenceStore _rest;

  @override
  String? read(String key) => key == dvAccessibilityStorageKey ? _old.read() : _rest.read(key);

  @override
  void write(String key, String value) => key == dvAccessibilityStorageKey ? _old.write(value) : _rest.write(key, value);

  @override
  void remove(String key) => key == dvAccessibilityStorageKey ? _old.write('') : _rest.remove(key);
}

/// The reader's accessibility choices for the whole app, reached as
/// `DV.Accessibility.controls`. Off until the generated runtime installs it
/// (`dartvel.accessibility.defaultControls`), and then the one place the panel, the
/// frame and the page shell read.
class DVAccessibilityControls extends ChangeNotifier {
  DVAccessibilityControls._();

  /// The one instance.
  static final DVAccessibilityControls instance = DVAccessibilityControls._();

  bool _enabled = false;
  bool _floatingButton = true;
  bool _watching = false;
  DVAccessibilityVoiceConfig? _voice;
  DVAccessibilitySettings _settings = const DVAccessibilitySettings();
  DVVoiceSettings _voiceSettings = const DVVoiceSettings();

  /// Whether the app opted in.
  bool get enabled => _enabled;

  /// Whether the framework draws the button over every page.
  bool get floatingButton => _floatingButton;

  /// What the reader chose (the operating system's settings are on top).
  DVAccessibilitySettings get settings => _settings;

  /// Voice mode's place in the panel (`defaultControls.voice`), or null when
  /// the app did not ask for it.
  DVAccessibilityVoiceConfig? get voice => _voice;

  /// Where the reader wants voice mode, and its language.
  DVVoiceSettings get voiceSettings => _voiceSettings;

  /// The language voice mode speaks: the reader's choice when it is one the
  /// app offers, else the app's first language.
  DVVoiceLanguage get voiceLanguage {
    final DVAccessibilityVoiceConfig config = _voice ?? const DVAccessibilityVoiceConfig();
    final DVVoiceLanguage? chosen = DVVoiceLanguage.tryCode(_voiceSettings.language);
    return chosen != null && config.languages.contains(chosen) ? chosen : config.languages.first;
  }

  /// Whether the browser says the reader wants more contrast. A device says
  /// so through MediaQuery, which the frame already reads.
  bool get systemHighContrast => platform.dvSystemPrefersContrast();

  /// Whether the browser says the reader wants less motion.
  bool get systemReducedMotion => platform.dvSystemPrefersReducedMotion();

  /// Turns the controls on, with the settings kept from the last visit. The
  /// generated runtime calls this before the first frame, from the pubspec:
  /// [voice] adds voice mode's settings to the panel, and [formerKey] names
  /// where the app kept its own settings before, read once.
  void install({
    bool floatingButton = true,
    @Deprecated('Set DVPreferenceStore.instance instead.')
    // ignore: deprecated_member_use_from_same_package
    DVAccessibilityStore? store,
    String app = 'app',
    DVAccessibilityVoiceConfig? voice,
    String? formerKey,
  }) {
    if (store != null) DVPreferenceStore.instance = _OldStore(store, DVPreferenceStore.instance);
    _enabled = true;
    _floatingButton = floatingButton;
    _voice = voice;
    if (formerKey != null) _adoptFormer(formerKey);
    // Read from the store, not the registry: install is the visit starting.
    _settings = DV.global<DVAccessibilitySettings>(
        DVAccessibilitySettings.decode(DVPreferenceStore.instance.read(DVAccessibilitySettings.storageKey)));
    _voiceSettings = DV.global<DVVoiceSettings>(DVVoiceSettings.decode(DVPreferenceStore.instance.read(DVVoiceSettings.storageKey)));
    _applyMotion();
    if (!_watching) {
      _watching = true;
      platform.dvWatchSystemPreferences(notifyListeners);
    }
    notifyListeners();
  }

  /// Carries what an app kept under [formerKey] before these controls over,
  /// once: only for a visitor with nothing kept here yet, and only what
  /// differs from the defaults. The old value is left where it was.
  void _adoptFormer(String formerKey) {
    final String? stored = DVPreferenceStore.instance.read(formerKey);
    if (stored == null) return;
    final DVFormerAccessibilitySettings former = DVFormerAccessibilitySettings.decode(stored);
    if (!DVAccessibilitySettings.isKept) {
      final DVAccessibilitySettings display = DVAccessibilitySettings(
        textScale: former.textScale ?? (former.largeText ? DVTextSize.large.scale : DVTextSize.standard.scale),
        highContrast: former.highContrast,
        reducedMotion: former.reducedMotion,
      );
      if (!display.isDefault) display.keep();
    }
    if (!DVVoiceSettings.isKept) {
      final String? place = former.position ?? former.zone;
      final DVVoiceSettings voice = DVVoiceSettings(
        position: place == DVVoicePosition.centre.name ? DVVoicePosition.centre : DVVoicePosition.top,
        language: former.language ?? const DVVoiceSettings().language,
      );
      if (voice != const DVVoiceSettings()) voice.keep();
    }
  }

  /// Applies [next] to every page and keeps it for the next visit.
  void update(DVAccessibilitySettings next) {
    if (next == _settings) return;
    _settings = next.keep();
    _applyMotion();
    notifyListeners();
  }

  /// Applies [next] to voice mode and keeps it for the next visit.
  void updateVoice(DVVoiceSettings next) {
    if (next == _voiceSettings) return;
    _voiceSettings = next.keep();
    notifyListeners();
  }

  void _applyMotion() {
    if (_settings.reducedMotion) {
      const DVAccessibility().useReducedMotion(true);
    } else {
      const DVAccessibility().clearReducedMotion();
    }
  }

  /// Off, as before install. For tests.
  void reset() {
    _enabled = false;
    _floatingButton = true;
    _voice = null;
    _settings = const DVAccessibilitySettings();
    _voiceSettings = const DVVoiceSettings();
    const DVAccessibility().clearReducedMotion();
    notifyListeners();
  }
}

/// The device's text size, then the reader's on top of it. A wrapper rather
/// than a linear factor, so a platform's non-linear scaling is kept.
@immutable
class _DVScaledTextScaler extends TextScaler {
  const _DVScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is _DVScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// Goes round the app's root (the generated runtime puts it there): the
/// reader's text size, contrast and motion in the MediaQuery every widget
/// reads, on top of what the operating system asks for. Above the
/// MaterialApp, so an app's own `highContrastTheme` is chosen as Flutter
/// chooses it. The app itself as it was when the controls are off.
class DVAccessibilityFrame extends StatelessWidget {
  const DVAccessibilityFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: DVAccessibilityControls.instance,
        builder: (BuildContext context, Widget? _) {
          final DVAccessibilityControls controls = DVAccessibilityControls.instance;
          if (!controls.enabled) return child;
          final MediaQueryData media = MediaQuery.of(context);
          final DVAccessibilitySettings settings = controls.settings;
          return MediaQuery(
            data: media.copyWith(
              textScaler: settings.textScale == 1 ? media.textScaler : _DVScaledTextScaler(media.textScaler, settings.textScale),
              highContrast: media.highContrast || settings.highContrast || controls.systemHighContrast,
              disableAnimations: media.disableAnimations || settings.reducedMotion || controls.systemReducedMotion,
            ),
            child: child,
          );
        },
      );
}

double _luminance(Color colour) => colour.computeLuminance();

double _contrast(Color a, Color b) {
  final double first = _luminance(a);
  final double second = _luminance(b);
  final double lighter = first > second ? first : second;
  final double darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

/// [base] in high contrast: pure white and black surfaces and text (black
/// and white in dark mode), outlines in the text colour, and the app's
/// accent colours kept only where they reach 7:1 on the page.
ThemeData dvHighContrastTheme(ThemeData base) {
  final bool dark = base.brightness == Brightness.dark;
  const Color black = Color(0xFF000000);
  const Color white = Color(0xFFFFFFFF);
  final Color paper = dark ? black : white;
  final Color ink = dark ? white : black;
  Color accent(Color colour) => _contrast(colour, paper) >= 7 ? colour : ink;
  Color on(Color colour) => _contrast(colour, paper) >= _contrast(colour, ink) ? paper : ink;
  final ColorScheme scheme = base.colorScheme;
  final Color primary = accent(scheme.primary);
  final Color secondary = accent(scheme.secondary);
  final Color tertiary = accent(scheme.tertiary);
  final Color error = accent(scheme.error);
  final ColorScheme contrast = scheme.copyWith(
    primary: primary,
    onPrimary: on(primary),
    primaryContainer: paper,
    onPrimaryContainer: ink,
    secondary: secondary,
    onSecondary: on(secondary),
    secondaryContainer: paper,
    onSecondaryContainer: ink,
    tertiary: tertiary,
    onTertiary: on(tertiary),
    tertiaryContainer: paper,
    onTertiaryContainer: ink,
    error: error,
    onError: on(error),
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: ink,
    surfaceDim: paper,
    surfaceBright: paper,
    surfaceContainerLowest: paper,
    surfaceContainerLow: paper,
    surfaceContainer: paper,
    surfaceContainerHigh: paper,
    surfaceContainerHighest: paper,
    surfaceTint: Colors.transparent,
    outline: ink,
    outlineVariant: ink,
    inverseSurface: ink,
    onInverseSurface: paper,
  );
  return base.copyWith(
    colorScheme: contrast,
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
    cardColor: paper,
    dividerColor: ink,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    iconTheme: base.iconTheme.copyWith(color: ink),
  );
}

/// [child] in high contrast when the reader asked for it and the app has no
/// high-contrast theme of its own for the current brightness (an app that
/// gives MaterialApp one gets it from Flutter, through the frame).
Widget dvAccessibleTheme(BuildContext context, Widget child) {
  if (!DVAccessibilityControls.instance.enabled || !(MediaQuery.maybeHighContrastOf(context) ?? false)) return child;
  final ThemeData theme = Theme.of(context);
  final MaterialApp? app = context.findAncestorWidgetOfExactType<MaterialApp>();
  final bool dark = theme.brightness == Brightness.dark;
  if ((dark ? app?.highContrastDarkTheme : app?.highContrastTheme) != null) return child;
  return Theme(data: dvHighContrastTheme(theme), child: child);
}

/// The accessibility button: the universal access icon and "Accessibility"
/// ([compact] is the icon alone), opening [DVAccessibilityPanel]. Put it in
/// the app's header with `floatingButton: false`, or leave the framework's
/// floating one on every page. Its tooltip is its name, and a 48 px target.
class DVAccessibilityButton extends StatelessWidget {
  const DVAccessibilityButton({
    super.key,
    this.compact = false,
    this.more,
    this.tooltip,
    this.floating = false,
  });

  final bool compact;

  /// Settings of the app's own at the bottom of the panel, below the
  /// framework's. Voice mode's are the framework's (`defaultControls.voice`).
  final WidgetBuilder? more;

  /// The button's name: its tooltip and accessible label. By default it
  /// names what the panel holds, voice included when the app asked for it.
  final String? tooltip;

  /// The framework's floating button: a raised round surface.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String name =
        tooltip ?? (DVAccessibilityControls.instance.voice == null ? dvAccessibilityButtonLabel : dvAccessibilityVoiceButtonLabel);
    // The row inside a box of its own, as before: the box is the control,
    // sized to the row, and the row stays packed to its icon and words.
    final DVBox<Object?> button = DVBox(DVBox.row(<Widget>[
      Icon(Icons.accessibility_new_rounded, size: 22, color: colours.onSurface),
      if (!compact) const DVText('Accessibility').fontSize(15).fontWeight(.w600).color(colours.onSurface),
    ], spacing: 8))
        .paddingSymmetric(horizontal: compact ? 12 : 14, vertical: 12)
        .minimumTapTarget(width: 48, height: 48)
        .tooltip(name)
        .semanticButton()
        .onTap(() => showDialog<void>(
              context: context,
              builder: (BuildContext context) => DVAccessibilityPanel(more: more),
            ));
    if (!floating) return button;
    return button
        .backgroundColor(colours.surface)
        .rounded(28)
        .border(Border.all(color: colours.outlineVariant))
        .shadow(const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))]);
  }
}

/// The settings, as a dialog: each change applies at once and is kept.
class DVAccessibilityPanel extends StatelessWidget {
  const DVAccessibilityPanel({super.key, this.more});

  final WidgetBuilder? more;

  @override
  Widget build(BuildContext context) => dvAccessibleTheme(
        context,
        ListenableBuilder(
          listenable: DVAccessibilityControls.instance,
          builder: (BuildContext context, Widget? _) => _panel(context),
        ),
      );

  Widget _panel(BuildContext context) {
    final DVAccessibilityControls controls = DVAccessibilityControls.instance;
    final DVAccessibilitySettings settings = controls.settings;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final AccessibilityFeatures device = View.of(context).platformDispatcher.accessibilityFeatures;
    final bool deviceCalm = device.disableAnimations || controls.systemReducedMotion;
    final bool deviceContrast = device.highContrast || controls.systemHighContrast;
    DVText heading(String words) => DVText(words).fontSize(17).fontWeight(.w700).color(colours.onSurface).paddingOnly(top: 8);
    DVText help(String words) => DVText(words).fontSize(14).color(colours.onSurfaceVariant);

    return AlertDialog(
      title: const DVText('Accessibility').fontSize(24).fontWeight(.w800).color(colours.onSurface).heading(2),
      // A set width: without one the dialog sizes to its widest child and
      // the switches run past its edge.
      // Built whole, not as a lazy list: a dialog of a dozen rows is read
      // by a screen reader and found by Ctrl+F all at once.
      content: SingleChildScrollView(
          child: DVBox.list(<Widget>[
        help('Kept on this device for your next visit.'),
        heading('Text size'),
        help('On top of your device’s own text size.'),
        // Chips that wrap rather than one segmented row: at the largest
        // size on a phone a row cut "Default" in two and ran "Larger"
        // past the panel's edge.
        DVChoice<DVTextSize>(
          label: 'Text size',
          options: DVTextSize.values,
          selected: settings.textSize,
          name: (DVTextSize size) => size.label,
          optionTooltip: (DVTextSize size) => '${size.label} text (${(size.scale * 100).round()}%)',
          onChanged: (DVTextSize size) => controls.update(settings.copyWith(textScale: size.scale)),
        ),
        DVSwitch(
          label: 'High contrast',
          explanation:
              deviceContrast ? 'Already on, because your device asks for more contrast.' : 'Pure black and white with strong outlines.',
          value: settings.highContrast || deviceContrast,
          onChanged: deviceContrast ? null : (bool value) => controls.update(settings.copyWith(highContrast: value)),
        ),
        DVSwitch(
          label: 'Reduce motion',
          explanation: deviceCalm ? 'Already on, because your device asks for less motion.' : 'No sliding or fading between screens.',
          value: settings.reducedMotion || deviceCalm,
          onChanged: deviceCalm ? null : (bool value) => controls.update(settings.copyWith(reducedMotion: value)),
        ),
        if (controls.voice != null) ..._voiceSection(controls, heading, help),
        if (more != null) more!(context),
      ], spacing: 12)
              .width(520)),
      actions: <Widget>[
        const DVText('Done')
            .fontSize(15)
            .fontWeight(.w700)
            .color(colours.onPrimary)
            .paddingSymmetric(horizontal: 20, vertical: 12)
            .minimumTapTarget(width: 48, height: 48)
            .backgroundColor(colours.primary)
            .rounded(24)
            .tooltip('Close the accessibility settings')
            .semanticButton()
            .onTap(() => Navigator.of(context).pop()),
      ],
    );
  }

  /// Where voice mode sits and its language, with what this device can do
  /// in that language.
  List<Widget> _voiceSection(
    DVAccessibilityControls controls,
    DVText Function(String) heading,
    DVText Function(String) help,
  ) {
    final DVAccessibilityVoiceConfig config = controls.voice!;
    final DVVoiceSettings voice = controls.voiceSettings;
    final DVVoiceLanguage language = controls.voiceLanguage;
    return <Widget>[
      heading('Where voice mode sits'),
      help('Centre keeps voice mode, its confirmations and receipts in the middle of the screen, for a narrow field of view.'),
      DVChoice<DVVoicePosition>(
        label: 'Where voice mode sits',
        options: DVVoicePosition.values,
        selected: voice.position,
        name: (DVVoicePosition position) => position.label,
        optionTooltip: (DVVoicePosition position) =>
            position == DVVoicePosition.centre ? 'Voice mode in the centre of the screen' : 'Voice mode at the top of the screen',
        onChanged: (DVVoicePosition position) => controls.updateVoice(voice.copyWith(position: position)),
      ),
      if (config.languages.length > 1) ...<Widget>[
        heading('Voice language'),
        DVChoice<DVVoiceLanguage>(
          label: 'Language',
          style: DVChoiceStyle.menu,
          options: config.languages,
          selected: language,
          name: (DVVoiceLanguage language) => language.displayName,
          onChanged: (DVVoiceLanguage language) => controls.updateVoice(voice.copyWith(language: language.code)),
        ),
      ],
      help(dvVoiceAvailability(language, speech: DVSpeech.instance, machineTranslated: config.isMachineTranslated(language))),
    ];
  }
}

/// The framework's floating button for a page, or nothing: only when the app
/// opted in and left the button to the framework. In the bottom corner on
/// the reading side, clear of the page's own "To the bottom" button.
Widget dvFloatingAccessibilityButton() {
  final DVAccessibilityControls controls = DVAccessibilityControls.instance;
  if (!controls.enabled || !controls.floatingButton) return const SizedBox.shrink();
  return const PositionedDirectional(
    start: 16,
    bottom: 16,
    child: SafeArea(top: false, child: DVAccessibilityButton(compact: true, floating: true)),
  );
}
