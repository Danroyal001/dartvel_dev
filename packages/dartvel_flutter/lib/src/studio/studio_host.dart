/// What Studio takes from the application it is a route of, so a page on
/// Studio's canvas is drawn exactly as the application draws it.
///
/// Studio has a look of its own -- its frame sets Studio's theme -- and a
/// page drawn under it came out in Studio's fonts and colours rather than the
/// site's. The route that mounts Studio sits under the application's own
/// `MaterialApp`, so it captures the application's themes and scroll
/// behaviour there, before Studio's frame replaces them, and hands them down
/// with the application's page views: the same functions the router builds
/// each page with.
///
/// This file is in `main.dart.js`, beside the router: it is what crosses into
/// Studio's deferred library, and it holds nothing of Studio's own.
library;

import 'package:flutter/material.dart';

/// The page at `path` as its route draws it: the page, its layouts and its
/// shell. With [content], that widget stands where the page's body goes --
/// how Studio draws a document it is editing inside the page's own chrome.
/// With `layout: false`, the layouts are left out. Null for a path the
/// application has no view for.
typedef DVStudioPageView = Widget? Function(
  String path, {
  Widget? content,
  bool layout,
});

/// The application's appearance, as its `MaterialApp` declares it.
@immutable
class DVStudioAppLook {
  const DVStudioAppLook({
    required this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
    this.scrollBehavior,
  });

  /// The light theme, or the only one.
  final ThemeData theme;

  /// The dark theme, when the application has one.
  final ThemeData? darkTheme;

  /// Which of the two the application shows.
  final ThemeMode themeMode;

  /// The application's scroll behaviour: whether its pages draw scrollbars,
  /// and for which input. Part of how a page looks.
  final ScrollBehavior? scrollBehavior;

  /// Whether a dark version exists to switch to.
  bool get hasDark => darkTheme != null;

  /// The theme the application shows on a device set to [brightness]; or,
  /// with [chosen], the one somebody asked to see.
  ThemeData resolve(Brightness brightness, {Brightness? chosen}) {
    if (chosen != null) {
      return chosen == Brightness.dark ? (darkTheme ?? theme) : theme;
    }
    final bool dark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => brightness == Brightness.dark,
    };
    return dark ? (darkTheme ?? theme) : theme;
  }

  /// The look of the application [context] is inside: its `MaterialApp`'s
  /// themes when there is one, otherwise whatever theme is in force there.
  static DVStudioAppLook capture(BuildContext context) {
    final MaterialApp? app = context.findAncestorWidgetOfExactType<MaterialApp>();
    final ThemeData inForce = Theme.of(context);
    return DVStudioAppLook(
      theme: app?.theme ?? inForce,
      darkTheme: app?.darkTheme,
      themeMode: app?.themeMode ?? ThemeMode.system,
      scrollBehavior: ScrollConfiguration.of(context),
    );
  }

  /// [child] under this look, on a device set to [brightness], or in the
  /// appearance [chosen]: the theme, the scroll behaviour, and a Material so
  /// text takes the theme's style.
  Widget wrap(
    Widget child, {
    required Brightness brightness,
    Brightness? chosen,
  }) {
    // Transparent: it paints nothing, and resets the text style Studio's
    // own Material set above to the application theme's.
    Widget out = Theme(
      data: resolve(brightness, chosen: chosen),
      child: Material(type: MaterialType.transparency, child: child),
    );
    final ScrollBehavior? scroll = scrollBehavior;
    if (scroll != null) {
      out = ScrollConfiguration(behavior: scroll, child: out);
    }
    return out;
  }
}

/// What the application hands the Studio route: its page views and its look.
class DVStudioHost extends InheritedWidget {
  const DVStudioHost({
    super.key,
    this.view,
    this.look,
    this.splash,
    required super.child,
  });

  /// The application's splash, which Studio shows while it loads.
  final DVStudioSplash? splash;

  /// The application's page views, `dartvelPagePreview`.
  final DVStudioPageView? view;

  /// The application's look, captured above Studio's frame.
  final DVStudioAppLook? look;

  static DVStudioHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DVStudioHost>();

  @override
  bool updateShouldNotify(DVStudioHost oldWidget) =>
      view != oldWidget.view ||
      look != oldWidget.look ||
      splash != oldWidget.splash;
}

/// Marks a page drawn as a preview, on Studio's canvas: it is looked at, and
/// must not act as the page being visited -- it does not rewrite the
/// browser tab's title and meta tags, which belong to Studio.
class DVPagePreviewScope extends InheritedWidget {
  const DVPagePreviewScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DVPagePreviewScope>() != null;

  @override
  bool updateShouldNotify(DVPagePreviewScope oldWidget) => false;
}

/// The application's splash, as the build writes it for the web page:
/// `dartvel.splash`'s colours and image, and the loading bar's colour.
///
/// The web page's splash is removed at Flutter's first frame, which for
/// Studio is before Studio has anything to draw: its code is fetched after
/// its route opens, and the grant is asked again. Studio draws this until it
/// is ready, so nobody opening it looks at a blank page.
@immutable
class DVStudioSplash {
  const DVStudioSplash({
    required this.color,
    required this.darkColor,
    this.image,
    this.darkImage,
    this.imageWidth = 96,
    this.progressColor,
  });

  /// The page's colour, and in dark mode.
  final Color color;
  final Color darkColor;

  /// The picture in the middle, as the web page serves it
  /// (`dartvel-splash.png`), and its dark version; none when the project
  /// has no image.
  final String? image;
  final String? darkImage;
  final double imageWidth;

  /// The loading bar's colour; no bar when null.
  final Color? progressColor;
}

/// [splash], filling the space it is given: the colour for the device's
/// appearance, the picture in the middle, and a loading bar along the top.
class DVStudioSplashView extends StatelessWidget {
  const DVStudioSplashView(this.splash, {super.key});

  final DVStudioSplash splash;

  @override
  Widget build(BuildContext context) {
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final String? image =
        dark ? (splash.darkImage ?? splash.image) : splash.image;
    final Color? bar = splash.progressColor;
    return Semantics(
      label: 'Loading',
      child: ColoredBox(
        color: dark ? splash.darkColor : splash.color,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (image != null)
              Center(
                child: SizedBox(
                  width: splash.imageWidth,
                  child: Image.network(
                    image,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (bar != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: bar,
                  backgroundColor: const Color(0x00000000),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
