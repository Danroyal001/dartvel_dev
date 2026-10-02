/// The documentation site's colours and measure.
///
/// The build used to write this as a stylesheet into the site directory, which
/// meant it was the one surface in an application nothing else could reach:
/// the framework's theme did not touch it, a reader's dark mode was whatever
/// `@media (prefers-color-scheme: dark)` happened to say, and a page that
/// opened the documentation in its own frame looked like a different product.
///
/// So it is a theme here. The palette is the stylesheet's, value for value --
/// changing a colour now has to be a decision in a file a reviewer reads,
/// rather than a hex in a template string.
///
/// It is a [ThemeExtension] rather than a global for the same reason it is not
/// [DVStudioColor]: Studio's flag follows the Studio app, and a documentation
/// page is a page of the application it documents. A docs page inside a light
/// application must stay light.
library dartvel_flutter.docs.style;

import 'package:flutter/material.dart';

/// The measure a page is set to: 64rem, as the stylesheet had it.
///
/// A line of prose longer than this is hard to find the end of, and the whole
/// point of the documentation is being read.
const double dvDocsMeasure = 64 * 16;

/// Where the site draws: [canvas] behind everything, [ink] on it, [muted] for
/// the asides, [rule] for the lines between sections, [codeSurface] behind
/// source, and [warn] for the one thing a page has to flag.
@immutable
class DVDocsTheme extends ThemeExtension<DVDocsTheme> {
  const DVDocsTheme({
    required this.brightness,
    required this.canvas,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.codeSurface,
    required this.warn,
  });

  /// The stylesheet's light palette: `#fbfbfa` `#1d1d1b` `#63635e` `#e2e2dd`
  /// `#f1f1ee` `#9a3b00`.
  const DVDocsTheme.light()
    : brightness = .light,
      canvas = const Color(0xFFFBFBFA),
      ink = const Color(0xFF1D1D1B),
      muted = const Color(0xFF63635E),
      rule = const Color(0xFFE2E2DD),
      codeSurface = const Color(0xFFF1F1EE),
      warn = const Color(0xFF9A3B00);

  /// The stylesheet's dark palette: `#161615` `#ececea` `#a3a39e` `#33332f`
  /// `#22221f` `#ffab70`.
  const DVDocsTheme.dark()
    : brightness = .dark,
      canvas = const Color(0xFF161615),
      ink = const Color(0xFFECECEA),
      muted = const Color(0xFFA3A39E),
      rule = const Color(0xFF33332F),
      codeSurface = const Color(0xFF22221F),
      warn = const Color(0xFFFFAB70);

  /// This site's colours for [context], light when there is no theme to ask.
  ///
  /// The fallback matters: a documentation page reached from the framework's
  /// own error pages, or built by a test with no theme above it, has to be
  /// legible rather than transparent.
  static DVDocsTheme of(BuildContext context) =>
      Theme.of(context).extension<DVDocsTheme>() ?? const DVDocsTheme.light();

  final Brightness brightness;
  final Color canvas;
  final Color ink;
  final Color muted;
  final Color rule;
  final Color codeSurface;

  /// What has to stand out: a reference to something that is gone, a finding,
  /// and the page you are on.
  final Color warn;

  @override
  DVDocsTheme copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? ink,
    Color? muted,
    Color? rule,
    Color? codeSurface,
    Color? warn,
  }) => DVDocsTheme(
    brightness: brightness ?? this.brightness,
    canvas: canvas ?? this.canvas,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    rule: rule ?? this.rule,
    codeSurface: codeSurface ?? this.codeSurface,
    warn: warn ?? this.warn,
  );

  @override
  DVDocsTheme lerp(covariant DVDocsTheme? other, double t) {
    if (other is! DVDocsTheme) return this;
    return DVDocsTheme(
      brightness: t < .5 ? brightness : other.brightness,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      codeSurface: Color.lerp(codeSurface, other.codeSurface, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DVDocsTheme &&
      other.brightness == brightness &&
      other.canvas == canvas &&
      other.ink == ink &&
      other.muted == muted &&
      other.rule == rule &&
      other.codeSurface == codeSurface &&
      other.warn == warn;

  @override
  int get hashCode =>
      Object.hash(brightness, canvas, ink, muted, rule, codeSurface, warn);
}

/// The site's type scale, in one place.
///
/// Every size the stylesheet asked for: 15px on 1.55 for prose, 13px on 1.45
/// for source, and the heading sizes a browser's defaults used to supply. The
/// prose family is left as the platform's own, which is what `system-ui` named
/// and what Flutter already draws with -- a fallback list would only be
/// consulted for glyphs the default family has.
@immutable
class DVDocsStyle {
  const DVDocsStyle(this.theme);

  factory DVDocsStyle.of(BuildContext context) =>
      DVDocsStyle(DVDocsTheme.of(context));

  final DVDocsTheme theme;

  /// 15px on 1.55.
  TextStyle get body => TextStyle(
    color: theme.ink,
    fontSize: 15,
    height: 1.55,
  );

  /// The monospace family, named as the stylesheet named it.
  ///
  /// `ui-monospace` is not a family Flutter resolves, so the real names are
  /// what is asked for, with the generic one last for a platform that has
  /// neither.
  static const List<String> _mono = <String>[
    'Menlo',
    'Consolas',
    'Courier New',
    'monospace',
  ];

  /// 13px on 1.45, monospace: a signature, an example record, a fenced block.
  TextStyle get code => TextStyle(
    color: theme.ink,
    fontFamily: 'monospace',
    fontFamilyFallback: _mono,
    fontSize: 13,
    height: 1.45,
  );

  /// 13px and [muted]: the file a decision record was read from, a block of
  /// source with no meaning of its own.
  TextStyle get source => TextStyle(
    color: theme.muted,
    fontSize: 13,
    height: 1.55,
  );

  /// A page's own title.
  TextStyle get title => TextStyle(
    color: theme.ink,
    fontSize: 30,
    height: 1.25,
    fontWeight: .w600,
  );

  TextStyle heading(int level) => TextStyle(
    color: theme.ink,
    fontSize: switch (level) {
      1 => 26,
      2 => 21,
      3 => 17,
      _ => 15,
    },
    height: 1.3,
    fontWeight: .w600,
  );

  /// The one chip the site draws: a label rather than a sentence.
  TextStyle get badge => TextStyle(
    color: theme.ink,
    fontSize: 12,
    height: 1.4,
  );

  /// A link, and the page you are on. Underlined because it is the one run in
  /// a paragraph that goes somewhere.
  TextStyle get link => TextStyle(
    color: theme.warn,
    fontSize: 15,
    height: 1.55,
    decoration: .underline,
    decorationColor: theme.warn,
  );
}

/// The [ThemeData] the documentation site is drawn with.
///
/// A real Material theme rather than a bare [ThemeData], because the pages the
/// framework hands it -- the not-found page above all -- take their text
/// styles and their canvas from the theme, and a page with no text style comes
/// out in Flutter's fallback error colours.
ThemeData dvDocsTheme(Brightness brightness) {
  final DVDocsTheme docs = brightness == .dark
      ? const DVDocsTheme.dark()
      : const DVDocsTheme.light();
  final DVDocsStyle style = DVDocsStyle(docs);
  return ThemeData(
    brightness: brightness,
    // The accent the stylesheet already had, so the few Material bits the
    // shared pages draw from it land in the same palette rather than in a
    // default purple nothing else on the site has seen.
    colorScheme: ColorScheme.fromSeed(
      seedColor: docs.warn,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: docs.canvas,
    canvasColor: docs.canvas,
    dividerColor: docs.rule,
    textTheme: TextTheme(
      bodySmall: style.source,
      bodyMedium: style.body,
      bodyLarge: style.body,
      titleLarge: style.title,
      titleMedium: style.heading(2),
      titleSmall: style.heading(3),
      headlineSmall: style.heading(1),
      headlineMedium: style.title,
    ),
    extensions: <ThemeExtension<dynamic>>[docs],
  );
}
