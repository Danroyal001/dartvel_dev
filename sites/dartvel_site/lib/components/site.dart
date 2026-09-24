// Shared shell, palette and building blocks for the site.
//
// Every component here is a @DVFunctionalWidget: Dartvel generates the widget
// class, decides whether it needs to be stateless, and gives it a const
// constructor. Nothing in this file is a raw Flutter widget, a Container, a
// Text or a MediaQuery -- which was the point. A framework's own site written
// half in the framework and half around it is an argument against the
// framework.
//
// The palette is resolved from the ambient theme rather than held as
// constants, so light and dark are one set of pages rather than two. The app
// follows the system by default: a visitor who has chosen dark should not be
// handed white.
import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import 'docs.dart' show kDocsSpecStatus;
import 'record.dart';

/// The palette, resolved for whichever brightness is in effect.
///
/// A value class rather than a widget: it answers questions, it does not
/// draw.
class Palette {
  const Palette._(this.dark);

  factory Palette.of(BuildContext context) =>
      Palette._(Theme.of(context).brightness == Brightness.dark);

  /// The palette for [brightness], without a widget tree. For a test, and
  /// for anything that has to reason about both modes at once.
  factory Palette.forBrightness(Brightness brightness) =>
      Palette._(brightness == Brightness.dark);

  final bool dark;

  Color get ink => dark ? const Color(0xFFF6F1EA) : const Color(0xFF191210);
  Color get muted => dark ? const Color(0xFFA8998C) : const Color(0xFF5C5049);
  Color get faint => dark ? const Color(0xFF8A7B6D) : const Color(0xFF7D6F64);
  Color get accent => dark ? const Color(0xFFF0824B) : const Color(0xFFB03E19);
  Color get surface => dark ? const Color(0xFF1B1815) : const Color(0xFFF7F1E9);
  Color get page => dark ? const Color(0xFF12100E) : const Color(0xFFFFFCF8);
  Color get rule => dark ? const Color(0xFF342D27) : const Color(0xFFDFD1BE);

  /// The one ground that stops the scroll: a band that is darker than the
  /// page in either mode, so a section can sit apart without a gradient.
  ///
  /// It is also what a code block and a terminal sit on, so the dark thing
  /// in the middle of a light page and the dark band around it are the same
  /// colour instead of two nearly-equal ones.
  static const Color deep = Color(0xFF16110E);

  /// The text colours for [deep], which does not change with the mode.
  static const Color deepInk = Color(0xFFF6F1EA);
  static const Color deepMuted = Color(0xFFB5A697);
  static const Color deepAccent = Color(0xFFF0824B);
}

/// One figure in a row of statistics.
///
/// A named pair rather than a record: a record type in a generated widget's
/// parameter list is a comma inside parentheses, which is the one shape a
/// signature parser has to be careful about, and a name reads better at the
/// call site than `.$1`.
class Figure {
  const Figure(this.value, this.label);
  final String value;
  final String label;
}

/// Where the site's claims can be checked: what each spec section has built,
/// and what each build target has been verified to produce.
const String kSpecStatusUrl =
    'https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json';
const String kBuildTargetsUrl =
    'https://github.com/Danroyal001/dartvel_dev/blob/main/docs/build-targets.md';

/// The sizes the site sets type at, and the only ones it may.
///
/// Not a rule imposed from outside: these are the sizes the pages actually
/// needed, with the near-duplicates collapsed. There were fourteen, among
/// them 12.5, 13.5 and 19, each one written because something had to be a
/// little smaller than the thing above it. No single one of them is wrong,
/// and together they are why a page reads as assembled rather than designed.
///
/// `test/type_scale_test.dart` holds every fontSize on the site to this
/// list, and holds this list to being used: a step nothing sets is a step
/// somebody hoped for.
const List<double> kTypeScale = <double>[
  12, // labels, eyebrows, chips
  13, // small print
  14, // captions and the quiet line under a figure
  15, // secondary body
  17, // body
  20, // a lead paragraph
  24, // a section heading on a phone
  30, // a section heading, and a figure on a phone
  38, // a figure
  50, // the one h1
];

/// The corner radii the site uses, and the only ones it may.
///
/// Small, because a radius chosen by feel is how a page ends up with an 8, a
/// 9 and a 10 doing the same job. The rule for a shape inside another shape
/// is concentric: where the gap between them is under 32 points, the inner
/// radius is the outer one minus the gap, which is what keeps the two curves
/// parallel. [insideBorder] is that rule for the common case.
///
/// `test/corner_radius_test.dart` holds the site to it.
const List<double> kRadii = <double>[
  3, // a bullet dot: a square with the corner taken off
  6, // something sitting inside a 10, with 4 points of padding
  10, // a code block, a panel, an inset
  12, // a card, a figure, a framed screenshot
  14, // the outermost thing on a band: the hero terminal
  999, // a pill, which is not a radius but a shape
];

/// A shape clipped inside a framed one takes its frame's radius less the
/// border between them, which is what keeps the two curves parallel.
///
/// `StudioShot` is the worked example: a 12 frame with a one-point border
/// around an 11 image. So 11 is a legal radius and 9 is not, and the
/// difference is whether there is an outer shape it was derived from.
double insideBorder(double outer, [double border = 1]) => outer - border;

/// The reading column every band shares.
const double kColumn = 1040;

/// The page gutter, which narrows on a phone.
///
/// 56pt of margin on each side of a 390pt screen leaves 278pt of text. This
/// is the single number that decides whether the site is readable on a phone.
double gutterFor(BuildContext context) =>
    context.screen.value<double>(mobile: 22, desktop: 56);

@DVFunctionalWidget()
Widget _siteHeader(BuildContext context) {
  final Palette palette = Palette.of(context);
  final DVScreenInfo screen = context.screen;

  return DVBox(
    DVBox(
      // A row when there is room for one, so the site links sit left and the
      // outbound ones sit right. On a phone that row does not fit: the
      // wordmark takes a line and the four site links share the next, which
      // they fit on down to 320 points. Wrapping them all together left
      // Cloud alone on a second line.
      screen.isMobile
          ? const DVBox.list(<Widget>[
              Wordmark(),
              DVBox.wrapLine(<Widget>[
                NavLink('Docs', '/docs'),
                NavLink('Features', '/features'),
                NavLink('Studio', '/studio'),
                NavLink('Cloud', '/cloud'),
                NavLink('Compared', '/vs'),
              ], spacing: 12),
            ], spacing: 6)
          : DVBox.row(<Widget>[
              const DVBox.row(<Widget>[
                Wordmark(),
                NavLink('Docs', '/docs'),
                NavLink('Features', '/features'),
                NavLink('Studio', '/studio'),
                NavLink('Cloud', '/cloud'),
                NavLink('Compared', '/vs'),
              ], spacing: 18),
              // Four site links and two outbound ones do not fit a tablet or a
              // phone on its side, and the site links are the ones a visitor
              // came for. GitHub and pub.dev are in the footer too.
              if (!screen.isTablet)
                const DVBox.row(<Widget>[
                  ExternalLink('GitHub', 'https://github.com/Danroyal001/dartvel_dev'),
                  ExternalLink('pub.dev', 'https://pub.dev/packages/dartvel_dev'),
                ], spacing: 18),
            ], align: DVAlign.spaceBetween),
      const DVModifier().maxWidth(kColumn).centered(),
    ),
    const DVModifier()
        // Opaque, so the header paints its own ground rather than depending
        // on whatever the layout happens to put behind it.
        .backgroundColor(palette.page)
        .border(Border(bottom: BorderSide(color: palette.rule)))
        .paddingSymmetric(horizontal: gutterFor(context), vertical: 14),
  );
}

@DVFunctionalWidget()
Widget _siteFooter(BuildContext context) {
  final Palette palette = Palette.of(context);
  return DVBox(
    DVBox(
      DVBox.list(<Widget>[
        const DVBox.wrapLine(<Widget>[
          ExternalLink('GitHub', 'https://github.com/Danroyal001/dartvel_dev'),
          ExternalLink('pub.dev', 'https://pub.dev/packages/dartvel_dev'),
          ExternalLink('npm', 'https://www.npmjs.com/package/dartvel_dev'),
        ], spacing: 20),
        // The mark again, quietly, at the size a piece of small print takes.
        // Flat rather than gradient: at sixteen points the fold is two
        // pixels of grey, and the footer is not where the logo argues.
        // Wrapped, not a row. The line beside it is thirty-three characters
        // and a phone gutter leaves 276 points: a row put the mark and the
        // text side by side at their natural widths and ran 185 points off
        // the edge, which in release is silently clipped.
        DVBox.wrapLine(<Widget>[
          DartvelMark(size: 16, color: palette.faint),
          const DVText('MIT licensed. Built with Dartvel.')
              .modifier(const DVModifier().fontSize(13).color(palette.faint)),
        ], spacing: 8),
      ], spacing: 12),
      const DVModifier().maxWidth(kColumn).centered(),
    ),
    const DVModifier()
        .border(Border(top: BorderSide(color: palette.rule)))
        .paddingSymmetric(horizontal: gutterFor(context), vertical: 32),
  );
}

/// A band of content, optionally on the tinted surface.
///
/// [dark] is ink-dark, for the one or two bands that should stop the scroll:
/// a page that is eight shades of the same cream reads as one very long
/// section however good the type is.
///
/// [grain] textures the band. It used to be a radial bloom of the accent,
/// which is the most recognisable mark of an interface nobody art-directed:
/// a flat page does need depth, and a gradient is the wrong way to get it.
/// Grain is a 96-point tile of monochrome noise, repeated, at an opacity
/// low enough that you notice it only when it is taken away. Used on the
/// hero and nowhere else, because a page where every band is textured is a
/// page with no texture.
@DVFunctionalWidget()
Widget _section(
  BuildContext context, {
  required List<Widget> children,
  bool tint = false,
  bool dark = false,
  bool grain = false,
}) {
  final Palette palette = Palette.of(context);
  final Color background =
      dark ? Palette.deep : (tint ? palette.surface : palette.page);

  DVModifier band = const DVModifier()
      .width(double.infinity)
      .backgroundColor(background)
      .paddingSymmetric(
        horizontal: gutterFor(context),
        vertical: context.screen.value<double>(mobile: 40, desktop: 64),
      );

  if (grain) {
    // The tile is black, so it reads as grain over a light ground and
    // needs more of itself over a dark one.
    band = band.backgroundImage(
      const DVImage.asset('assets/texture/grain.png'),
      fit: BoxFit.none,
      repeat: ImageRepeat.repeat,
      opacity: palette.dark ? 0.30 : 0.14,
    );
  }

  return DVBox(
    DVBox(
      DVBox.list(children, spacing: 22),
      // Fades and rises as it comes into view. The band's own background is
      // outside this, so the colour is already painted when the content
      // arrives -- a section that faded in whole would flash the page colour
      // behind it.
      const DVModifier().maxWidth(kColumn).centered().revealOnScroll(),
    ),
    band,
  );
}

@DVFunctionalWidget()
Widget _eyebrow(BuildContext context, String text, {bool onDark = false}) =>
    DVText(text).modifier(
      const DVModifier()
          .fontSize(12)
          .fontWeight(FontWeight.w700)
          // On an ink band the page's own accent sits too dark to read.
          .color(onDark ? Palette.deepAccent : Palette.of(context).accent)
          .letterSpacing(1.8),
    );

/// [level] is the document outline, not the size. A section heading two
/// thirds of the way down a page is still an h2, and a page has one h1 --
/// which is why the hero passes 1 and every section leaves the default.
@DVFunctionalWidget()
Widget _heading(
  BuildContext context,
  String text, {
  int level = 2,
  bool onDark = false,
}) =>
    DVText(text).modifier(
      const DVModifier()
          .fontSize(context.screen.value<double>(mobile: 24, desktop: 30))
          .fontWeight(FontWeight.w700)
          .color(onDark ? Palette.deepInk : Palette.of(context).ink)
          .lineHeight(1.15)
          // Declared, so the outline exists for a screen reader moving by
          // heading and for the crawler-visible HTML built from the semantics
          // tree. Without it every heading was a paragraph.
          .semanticHeading(level),
    );

/// A paragraph, held to a readable measure.
///
/// [width] is a maximum rather than a width: on a phone the paragraph is as
/// wide as the gutter allows, and 640 would paint off the side of the screen.
@DVFunctionalWidget()
Widget _body(BuildContext context, String text, {double width = 640}) =>
    DVText(text).modifier(
      const DVModifier()
          .fontSize(17)
          .color(Palette.of(context).muted)
          .lineHeight(1.65)
          .maxWidth(width),
    );

/// A card that lifts under the pointer, and the border takes the accent.
///
/// Small on purpose: a card that jumps is a card that draws attention away
/// from the one being read.
@DVFunctionalWidget()
/// A card, and whether the thing it describes exists yet.
///
/// [built] is a badge rather than a word at the end of the prose. Nine cards
/// on the cloud page closed their paragraph with a bare "Built." and one with
/// "Planned; not yet built." -- a status marker written as a sentence. It read
/// as filler, it repeated nine times down one page, and a reader scanning for
/// what is ready had to reach the end of every paragraph to find out. Null is
/// a card that is not claiming anything either way.
Widget _siteCard(
  BuildContext context,
  String title,
  String body, {
  bool? built,
  String? section,
  String? href,
}) {
  final Palette palette = Palette.of(context);
  // Copied to a local before it is tested. The body of a
  // @DVFunctionalWidget is lowered into the generated widget class, where
  // `built` is a field -- and Dart does not promote a nullable field, so
  // `if (built != null) ... built ? a : b` compiles here and fails there,
  // in a file nobody wrote.
  //
  // A card that names a spec section takes its badge from the status the
  // index records for it, so a partly built section reads Partial and
  // cannot be badged Built by hand.
  final String? named = section;
  final bool? declared = built;
  final String? recorded = named == null ? null : kDocsSpecStatus[named];
  final String? label = recorded != null
      ? (recorded == 'Shipped'
          ? 'Built'
          : (recorded == 'Partial' ? 'Partial' : 'Planned'))
      : (declared == null ? null : (declared ? 'Built' : 'Planned'));
  final bool? status = label == null ? null : label != 'Planned';
  final bool partial = label == 'Partial';
  // A card that names a page is a link to it, not a box with a hover state
  // that does nothing: it navigates, previews, preloads, takes keyboard focus
  // and opens in a new tab on a middle click, and a crawler follows it.
  final String? to = href;
  final Widget card = DVBox(
    DVBox.list(<Widget>[
      DVBox.wrapLine(<Widget>[
        DVText(title).modifier(const DVModifier()
            .fontSize(17)
            .fontWeight(FontWeight.w700)
            .color(palette.ink)),
        if (status != null && label != null)
          DVText(label).modifier(const DVModifier()
              .fontSize(12)
              .fontWeight(FontWeight.w700)
              .color(partial
                  ? palette.ink
                  : (status ? palette.accent : palette.faint))
              .paddingSymmetric(horizontal: 8, vertical: 3)
              // The same amber the docs pages give a partial section.
              .backgroundColor(partial
                  ? const Color(0xFFFFC857).withValues(alpha: 0.45)
                  : (status
                      ? palette.accent.withValues(alpha: 0.10)
                      : palette.rule.withValues(alpha: 0.45)))
              .rounded(999)),
      ], spacing: 8),
      DVText(body).modifier(
          const DVModifier().fontSize(14).color(palette.muted).lineHeight(1.55)),
    ], spacing: 8),
    const DVModifier()
        .width(context.screen.value<double>(mobile: double.infinity, tablet: 300))
        .padding(20)
        .backgroundColor(palette.page)
        .border(Border.all(color: palette.rule))
        .rounded(12)
        .animate(const Duration(milliseconds: 180))
        .hover(
          const DVModifier()
              .border(Border.all(color: palette.accent.withValues(alpha: 0.5)))
              .shadow(<BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: palette.dark ? 0.4 : 0.09),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ]),
        ),
  );
  if (to == null) return card;
  return DVNavLink(to: DVRouteTarget(to), child: card);
}

@DVFunctionalWidget()
Widget _siteChip(BuildContext context, String text, {bool onDark = false}) {
  final Palette palette = Palette.of(context);
  return DVBox(
    DVText(text).modifier(const DVModifier()
        .fontSize(13)
        .color(onDark ? const Color(0xFFD3DCF3) : palette.ink)),
    const DVModifier()
        .paddingSymmetric(horizontal: 12, vertical: 7)
        // On an ink band the page's surface and rule colours disappear.
        .backgroundColor(onDark ? const Color(0xFF161E33) : palette.surface)
        .border(Border.all(
            color: onDark ? const Color(0xFF2A3557) : palette.rule))
        .rounded(999),
  );
}

@DVFunctionalWidget()
Widget _stat(BuildContext context, String value, String label) {
  final Palette palette = Palette.of(context);
  return DVBox(
    DVBox.list(<Widget>[
      DVText(value).modifier(const DVModifier()
          .fontSize(30)
          .fontWeight(FontWeight.w700)
          .color(palette.accent)),
      DVText(label)
          .modifier(const DVModifier().fontSize(13).color(palette.muted)),
    ], spacing: 4),
    const DVModifier()
        .width(200)
        .padding(18)
        .backgroundColor(palette.surface)
        .rounded(12),
  );
}

/// A row of numbers.
///
/// Dartvel's are genuinely interesting and were buried in prose: fifteen
/// build targets, six packages. A number set large is the cheapest visual
/// interest a technical page has, and it is the part people screenshot.
@DVFunctionalWidget()
Widget _stats(
  BuildContext context,
  List<Figure> items, {
  bool onDark = false,
}) {
  final Palette palette = Palette.of(context);
  final double size = context.screen.value<double>(mobile: 30, desktop: 38);

  return DVBox.wrapLine(<Widget>[
    for (final Figure item in items)
      // crossAlign start, so each figure shrinks to its own content. A
      // stretched list inside a wrap takes the whole line, and four numbers
      // meant to sit in a row stack into a column.
      DVBox.list(<Widget>[
        // Counts up the first time it is seen.
        CountUp(
          item.value,
          size: size,
          color: onDark ? Palette.deepAccent : palette.accent,
        ),
        DVText(item.label).modifier(const DVModifier()
            .fontSize(14)
            .fontWeight(FontWeight.w600)
            .color(onDark ? Palette.deepMuted : palette.muted)
            .lineHeight(1.4)),
      ], spacing: 4, crossAlign: DVCrossAlign.start),
  ], spacing: context.screen.value<double>(mobile: 28, desktop: 56));
}

/// A block of code. Monospaced, coloured, selectable, and copyable.
@DVFunctionalWidget()
Widget _codeBlock(BuildContext context, List<String> lines) =>
    CodeSample(lines);

/// The wordmark: a mark and the name, so the header has something to anchor
/// on other than a bold word.
@DVFunctionalWidget()
Widget _wordmark(BuildContext context) {
  final Palette palette = Palette.of(context);
  return DVNavLink(
    to: DVRoutes.index,
    padding: EdgeInsets.zero,
    semanticLabel: 'Dartvel, home',
    child: DVBox.row(<Widget>[
      // The mark itself, not a letter in a box. The placeholder was a bold
      // D on an accent square, which is what a header has before anybody
      // draws a logo.
      const DartvelMark(size: 24),
      const DVText('Dartvel').modifier(const DVModifier()
          .fontSize(17)
          .fontWeight(FontWeight.w700)
          .color(palette.ink)),
    ], spacing: 9),
  );
}

/// A header link.
///
/// Whether it points at the page being shown is read from the router rather
/// than passed down. It used to be a `current` string threaded from every
/// page -- `SitePage(current: '/features')` -- which is the route written out
/// by hand in the one place that already knows it from the file it lives in.
/// A route repeated as a literal drifts the moment the page file moves, and
/// nothing catches it: the nav simply stops highlighting.
@DVFunctionalWidget()
Widget _navLink(BuildContext context, String label, String href) {
  final Palette palette = Palette.of(context);
  final String path = GoRouterState.of(context).uri.path;
  // A prefix match, so /docs stays lit on /docs/anything, but compared
  // segment-wise: /docs must not light up on /docsomething.
  final bool active =
      href == '/' ? path == '/' : path == href || path.startsWith('$href/');

  return DVNavLink(
    to: DVRouteTarget(href),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: DVText(label).modifier(const DVModifier()
        .fontSize(15)
        .fontWeight(active ? FontWeight.w700 : FontWeight.w500)
        .color(active ? palette.accent : palette.muted)),
  );
}

@DVFunctionalWidget()
Widget _primaryLink(BuildContext context, String label, String href) =>
    SiteButton(label, href, filled: true);

@DVFunctionalWidget()
Widget _ghostLink(BuildContext context, String label, String href) =>
    SiteButton(label, href, filled: false);

/// A button that is a link: it navigates, previews, preloads, takes keyboard
/// focus and opens in a new tab on a middle click, because DVNavLink does all
/// of that and a tap handler does none of it.
@DVFunctionalWidget()
Widget _siteButton(
  BuildContext context,
  String label,
  String href, {
  bool filled = false,
}) {
  final Palette palette = Palette.of(context);
  return DVNavLink(
    to: DVRouteTarget(href),
    padding: EdgeInsets.zero,
    child: DVBox(
      DVText(label).modifier(const DVModifier()
          .fontSize(15)
          .fontWeight(FontWeight.w600)
          .lineHeight(1.2)
          .color(filled ? const Color(0xFFFFFFFF) : palette.ink)),
      const DVModifier()
          .paddingSymmetric(horizontal: 22, vertical: 15)
          .backgroundColor(filled ? palette.accent : const Color(0x00000000))
          .border(filled
              ? Border.all(color: const Color(0x00000000), width: 0)
              : Border.all(color: palette.rule, width: 1.5))
          .rounded(10),
    ),
  );
}

@DVFunctionalWidget()
Widget _externalLink(BuildContext context, String label, String url,
        {bool onDark = false}) =>
    DVNavLink.external(
      url,
      // It was styled text with no handler: the url argument was never used,
      // so every footer link was dead and looked exactly like a working one.
      child: DVText(label).modifier(const DVModifier()
          .fontSize(14)
          .fontWeight(FontWeight.w600)
          .color(onDark ? Palette.deepAccent : Palette.of(context).accent)),
    );

/// A feature record, drawn as the two things it says rather than one block.
///
/// The text arrives as a single string, which is how spec-status.json holds it
/// and how the cards drew it: one paragraph, with "Present:" and "Absent:"
/// inside it as words. Trimming the records made that wall shorter without
/// making it a shape -- no paragraph breaks, and the two halves a reader most
/// wants to tell apart distinguished only by punctuation in the middle of a
/// line.
///
/// So it is parsed and laid out. Paragraphs where there were sentences, and
/// where a record says both, a heading over each half.
///
/// The headings are level 3 because the area above them is level 2 and the
/// page title is level 1. Skipping to a paragraph would leave a reader moving
/// by heading with no way into the half of a card they came for, and the
/// features page is a page people arrive at with one question.
@DVFunctionalWidget()
Widget _siteRecord(BuildContext context, {required String body}) {
  final Palette palette = Palette.of(context);
  final SiteRecordParts parts = siteRecordParts(body);
  final bool labelled = parts.absent.isNotEmpty;

  final DVModifier prose = const DVModifier()
      .fontSize(15)
      // 1.65 rather than 1.6: at fifteen points these run long, and the extra
      // is the difference between lines a reader tracks and lines they lose
      // their place in.
      .lineHeight(1.65);

  final List<Widget> children = <Widget>[];

  // Only labelled when there are two halves to tell apart. A record that is
  // all built would be a "Built" heading over the whole thing, which is a
  // heading that divides nothing.
  if (labelled) {
    children.add(const SiteRecordLabel(text: 'Built', tone: 'accent'));
  }
  for (final String paragraph in parts.present) {
    children.add(DVText(paragraph).modifier(prose.color(palette.muted)));
  }

  if (labelled) {
    children.add(const SiteRecordLabel(text: 'Not yet', tone: 'muted'));
    for (final String paragraph in parts.absent) {
      children.add(DVText(paragraph).modifier(prose.color(palette.muted)));
    }
  }

  // Ten between paragraphs. Enough that a break reads as a break at fifteen
  // points and 1.65, and not so much that it becomes a list of unrelated
  // sentences.
  return DVBox.list(children, spacing: 10);
}

/// One entry in the full record: what it is called, what you type, what it
/// does and does not do.
///
/// The cards above are summaries and this is the thing itself, which is the
/// split Laravel makes between a homepage and its docs. Nothing here is
/// folded: somebody who has scrolled to the record has already said they want
/// it, and a control that hides it again is in their way.
@DVFunctionalWidget()
Widget _siteRecordEntry(BuildContext context,
    {required String area, required String surface, required String body}) {
  final Palette palette = Palette.of(context);
  return DVBox.list(<Widget>[
    DVBox.wrapLine(<Widget>[
      DVText(area).modifier(const DVModifier()
          .fontSize(20)
          .fontWeight(FontWeight.w700)
          .color(palette.ink)
          // Level 3 under the section's level 2, so the record is reachable
          // by heading rather than being one long scroll.
          .semanticHeading(3)),
      SiteChip(surface),
    ], spacing: 10),
    SiteRecord(body: body),
  ], spacing: 12);
}
/// The small heading over half a record.
@DVFunctionalWidget()
Widget _siteRecordLabel(BuildContext context,
    {required String text, required String tone}) {
  final Palette palette = Palette.of(context);
  // A local, because a functional widget's parameters become fields and a
  // field does not promote -- the conditional has to read something the
  // compiler can see is not going to change under it.
  final String which = tone;
  return DVText(text).modifier(const DVModifier()
      .fontSize(12)
      .fontWeight(FontWeight.w700)
      // Wide, because it is two or three words set small and the spacing is
      // what makes it read as a label rather than as a very short sentence.
      .letterSpacing(0.8)
      .color(which == 'accent' ? palette.accent : palette.muted)
      .semanticHeading(3));
}

/// The worry a reader has at this point, answered, right before the button.
///
/// A call to action with nothing in front of it asks somebody to click while
/// they are still wondering whether they should. The question is set in ink so
/// a skimmer finds it, and the answer is one or two short sentences.
@DVFunctionalWidget()
Widget _objection(
  BuildContext context,
  String question,
  String answer, {
  bool onDark = false,
}) {
  final Palette palette = Palette.of(context);
  return DVBox.list(<Widget>[
    DVText(question).modifier(const DVModifier()
        .fontSize(17)
        .fontWeight(FontWeight.w700)
        .color(onDark ? Palette.deepInk : palette.ink)
        .lineHeight(1.4)),
    DVText(answer).modifier(const DVModifier()
        .fontSize(17)
        .color(onDark ? const Color(0xFF9AA6C4) : palette.muted)
        .lineHeight(1.55)
        .maxWidth(600)),
  ], spacing: 4, crossAlign: DVCrossAlign.start);
}

/// A short list, for the points a skimmer reads instead of a paragraph.
///
/// A Row with a Flexible, because a bullet whose second line wraps back under
/// the dot is not a list any more, and DVBox has no flexible child.
@DVFunctionalWidget()
Widget _bullets(BuildContext context, List<String> items, {bool onDark = false}) {
  final Palette palette = Palette.of(context);
  final Color text = onDark ? const Color(0xFFC9D3EA) : palette.ink;
  final Color dot = onDark ? Palette.deepAccent : palette.accent;
  return DVBox.list(<Widget>[
    for (final String item in items)
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 9, right: 12),
            child: DVBox(
              const SizedBox(width: 6, height: 6),
              const DVModifier().backgroundColor(dot).rounded(3),
            ),
          ),
          Flexible(
            child: DVText(item).modifier(const DVModifier()
                .fontSize(17)
                .color(text)
                .lineHeight(1.5)
                .maxWidth(620)),
          ),
        ],
      ),
  ], spacing: 10, crossAlign: DVCrossAlign.start);
}
