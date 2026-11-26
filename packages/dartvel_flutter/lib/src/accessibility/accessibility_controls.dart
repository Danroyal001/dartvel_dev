// The accessibility controls an app opts into with
// `dartvel.accessibility.defaultControls` in pubspec.yaml (or
// `DartvelConfig.accessibilityDefaultControls`).
//
// A button -- the framework's floating one on every page, or
// [DVAccessibilityButton] wherever the app puts it, usually its header --
// opens a panel with the reader's choices: text size, high contrast and
// reduced motion. Each applies to the whole app at once, in the app's own
// theme, light and dark, and is kept for the visitor's next visit
// (`localStorage` in a browser, a small file on a device). The operating
// system's own settings always count: its text size is multiplied, and its
// reduce-motion and more-contrast settings cannot be turned off from here.
//
// On the web with SSR-first, the head reads the same stored value before the
// first paint, so the server-rendered page is already in the visitor's
// settings (see dvSsrFirstHead in dartvel_core).
import 'package:dartvel_core/dartvel.dart'
    show DVAccessibilitySettings, DVTextSize;
import 'dart:ui' show AccessibilityFeatures;

import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart' show DVAccessibility, DVBox, DVModifier, DVText;
import 'accessibility_platform_stub.dart'
    if (dart.library.js_interop) 'accessibility_platform_web.dart'
    if (dart.library.io) 'accessibility_platform_io.dart' as platform;
import 'accessibility_store.dart';

export 'package:dartvel_core/dartvel.dart' show DVAccessibilitySettings, DVTextSize, dvAccessibilityStorageKey;

export 'accessibility_store.dart';

/// The words of the button: its tooltip and its accessible name.
const String dvAccessibilityButtonLabel = 'Accessibility: text size, contrast and motion';

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
  DVAccessibilitySettings _settings = const DVAccessibilitySettings();
  DVAccessibilityStore _store = DVMemoryAccessibilityStore();

  /// Whether the app opted in.
  bool get enabled => _enabled;

  /// Whether the framework draws the button over every page.
  bool get floatingButton => _floatingButton;

  /// What the reader chose (the operating system's settings are on top).
  DVAccessibilitySettings get settings => _settings;

  /// Whether the browser says the reader wants more contrast. A device says
  /// so through MediaQuery, which the frame already reads.
  bool get systemHighContrast => platform.dvSystemPrefersContrast();

  /// Whether the browser says the reader wants less motion.
  bool get systemReducedMotion => platform.dvSystemPrefersReducedMotion();

  /// Turns the controls on, with the settings kept from the last visit.
  /// The generated runtime calls this before the first frame; [store] and
  /// [app] choose where the settings are kept.
  void install({bool floatingButton = true, DVAccessibilityStore? store, String app = 'app'}) {
    _enabled = true;
    _floatingButton = floatingButton;
    _store = store ?? platform.dvPlatformAccessibilityStore(app);
    _settings = DVAccessibilitySettings.decode(_store.read());
    _applyMotion();
    if (!_watching) {
      _watching = true;
      platform.dvWatchSystemPreferences(notifyListeners);
    }
    notifyListeners();
  }

  /// Applies [next] to every page and keeps it for the next visit.
  void update(DVAccessibilitySettings next) {
    if (next == _settings) return;
    _settings = next;
    _store.write(next.encode());
    _applyMotion();
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
    _settings = const DVAccessibilitySettings();
    _store = DVMemoryAccessibilityStore();
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
///
/// [more] adds the app's own settings to the bottom of the panel (a voice
/// language, where an overlay sits); the app keeps those itself.
class DVAccessibilityButton extends StatelessWidget {
  const DVAccessibilityButton({
    super.key,
    this.compact = false,
    this.more,
    this.tooltip = dvAccessibilityButtonLabel,
    this.floating = false,
  });

  final bool compact;
  final WidgetBuilder? more;

  /// The button's name: its tooltip and accessible label. An app that adds
  /// settings with [more] names them here.
  final String tooltip;

  /// The framework's floating button: a raised round surface.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    DVModifier modifier = const DVModifier()
        .paddingSymmetric(horizontal: compact ? 12 : 14, vertical: 12)
        .minimumTapTarget(width: 48, height: 48)
        .tooltip(tooltip)
        .semanticButton()
        .onTap(() => showDialog<void>(
              context: context,
              builder: (BuildContext context) => DVAccessibilityPanel(more: more),
            ));
    if (floating) {
      modifier = modifier
          .backgroundColor(colours.surface)
          .rounded(28)
          .border(Border.all(color: colours.outlineVariant))
          .shadow(const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))]);
    }
    return DVBox(
      DVBox.row(<Widget>[
        Icon(Icons.accessibility_new_rounded, size: 22, color: colours.onSurface),
        if (!compact)
          DVText('Accessibility', const DVModifier().fontSize(15).fontWeight(FontWeight.w600).color(colours.onSurface)),
      ], spacing: 8),
      modifier,
    );
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
    final DVModifier heading = const DVModifier().fontSize(17).fontWeight(FontWeight.w700).color(colours.onSurface);
    final DVModifier help = const DVModifier().fontSize(14).color(colours.onSurfaceVariant);

    Widget toggle(String label, String explanation, {required bool value, required bool fromDevice, required void Function(bool) changed}) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: DVText(label, heading),
          subtitle: DVText(explanation, help),
          value: value || fromDevice,
          onChanged: fromDevice ? null : changed,
        );

    return AlertDialog(
      title: DVText('Accessibility', const DVModifier().fontSize(24).fontWeight(FontWeight.w800).color(colours.onSurface).heading(2)),
      // A set width: without one the dialog sizes to its widest child and
      // the switches run past its edge.
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: DVBox.list(<Widget>[
            DVText('Kept on this device for your next visit.', help),
            DVText('Text size', heading.paddingOnly(top: 8)),
            DVText('On top of your device’s own text size.', help),
            // Chips that wrap rather than one segmented row: at the largest
            // size on a phone a row cut "Default" in two and ran "Larger"
            // past the panel's edge.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final DVTextSize size in DVTextSize.values)
                  ChoiceChip(
                    label: Text(size.label),
                    tooltip: '${size.label} text (${(size.scale * 100).round()}%)',
                    selected: settings.textSize == size,
                    showCheckmark: true,
                    onSelected: (bool _) => controls.update(settings.copyWith(textSize: size)),
                  ),
              ],
            ),
            toggle(
              'High contrast',
              deviceContrast ? 'Already on, because your device asks for more contrast.' : 'Pure black and white with strong outlines.',
              value: settings.highContrast,
              fromDevice: deviceContrast,
              changed: (bool value) => controls.update(settings.copyWith(highContrast: value)),
            ),
            toggle(
              'Reduce motion',
              deviceCalm ? 'Already on, because your device asks for less motion.' : 'No sliding or fading between screens.',
              value: settings.reducedMotion,
              fromDevice: deviceCalm,
              changed: (bool value) => controls.update(settings.copyWith(reducedMotion: value)),
            ),
            if (more != null) more!(context),
          ], spacing: 12),
        ),
      ),
      actions: <Widget>[
        DVBox(
          DVText('Done', const DVModifier().fontSize(15).fontWeight(FontWeight.w700).color(colours.onPrimary)),
          const DVModifier()
              .paddingSymmetric(horizontal: 20, vertical: 12)
              .minimumTapTarget(width: 48, height: 48)
              .backgroundColor(colours.primary)
              .rounded(24)
              .tooltip('Close the accessibility settings')
              .semanticButton()
              .onTap(() => Navigator.of(context).pop()),
        ),
      ],
    );
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
