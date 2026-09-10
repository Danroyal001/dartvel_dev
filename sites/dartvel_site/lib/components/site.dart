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
import 'record.dart';

/// The palette, resolved for whichever brightness is in effect.
///
/// A value class rather than a widget: it answers questions, it does not
/// draw.
class Palette {
  const Palette._(this.dark);

  factory Palette.of(BuildContext context) =>
      Palette._(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  Color get ink => dark ? const Color(0xFFF2F5FA) : const Color(0xFF0B1020);
  Color get muted => dark ? const Color(0xFF9AA7BD) : const Color(0xFF5A6478);
  Color get faint => dark ? const Color(0xFF6E7B92) : const Color(0xFF8A93A6);
  Color get accent => dark ? const Color(0xFF7BA2FF) : const Color(0xFF2F6BFF);
  Color get surface => dark ? const Color(0xFF11161F) : const Color(0xFFF4F6FB);
  Color get page => dark ? const Color(0xFF0A0D13) : const Color(0xFFFFFFFF);
  Color get rule => dark ? const Color(0xFF222A38) : const Color(0xFFE3E7EF);
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
      // outbound ones sit right. On a phone that row does not fit, and a
      // wrapped line of links reads better than a row scrolled off the edge.
      screen.isMobile
          ? const DVBox.wrapLine(<Widget>[
              Wordmark(),
              NavLink('Docs', '/docs'),
              NavLink('Features', '/features'),
              NavLink('Cloud', '/cloud'),
            ], spacing: 18)
          : const DVBox.row(<Widget>[
              DVBox.row(<Widget>[
                Wordmark(),
                NavLink('Docs', '/docs'),
                NavLink('Features', '/features'),
                NavLink('Cloud', '/cloud'),
              ], spacing: 18),
              DVBox.row(<Widget>[
                ExternalLink('GitHub', 'https://github.com/Danroyal001/dartvel_dev'),
                ExternalLink('pub.dev', 'https://pub.dev/packages/dartvel_dev'),
              ], spacing: 18),
            ], align: DVAlign.spaceBetween),
      const DVModifier().maxWidth(kColumn).centered(),
    ),
    const DVModifier()
        // Opaque. In deck mode the header floats over the slides, and without
        // its own background the slide scrolled visibly through it.
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
/// section however good the type is. [glow] is a soft accent bloom in the
/// corner -- the hero, and nothing else, because a page where everything
/// glows is a page where nothing does.
@DVFunctionalWidget()
Widget _section(
  BuildContext context, {
  required List<Widget> children,
  bool tint = false,
  bool dark = false,
  bool glow = false,
}) {
  final Palette palette = Palette.of(context);
  final Color background =
      dark ? const Color(0xFF0B1020) : (tint ? palette.surface : palette.page);

  DVModifier band = const DVModifier()
      .width(double.infinity)
      .backgroundColor(background)
      .paddingSymmetric(
        horizontal: gutterFor(context),
        vertical: context.screen.value<double>(mobile: 40, desktop: 64),
      );

  if (glow) {
    band = band.gradient(RadialGradient(
      center: const Alignment(0.92, -1.1),
      radius: 1.15,
      colors: <Color>[
        palette.accent.withValues(alpha: palette.dark ? 0.20 : 0.13),
        background.withValues(alpha: 0),
      ],
    ));
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
          .color(onDark ? const Color(0xFF7AA2F7) : Palette.of(context).accent)
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
          .fontSize(context.screen.value<double>(mobile: 26, desktop: 34))
          .fontWeight(FontWeight.w800)
          .color(onDark ? const Color(0xFFF2F5FC) : Palette.of(context).ink)
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
}) {
  final Palette palette = Palette.of(context);
  // Copied to a local before it is tested. The body of a
  // @DVFunctionalWidget is lowered into the generated widget class, where
  // `built` is a field -- and Dart does not promote a nullable field, so
  // `if (built != null) ... built ? a : b` compiles here and fails there,
  // in a file nobody wrote.
  final bool? status = built;
  return DVBox(
    DVBox.list(<Widget>[
      DVBox.wrapLine(<Widget>[
        DVText(title).modifier(const DVModifier()
            .fontSize(17)
            .fontWeight(FontWeight.w700)
            .color(palette.ink)),
        if (status != null)
          DVText(status ? 'Built' : 'Planned').modifier(const DVModifier()
              .fontSize(11)
              .fontWeight(FontWeight.w700)
              .color(status ? palette.accent : palette.faint)
              .paddingSymmetric(horizontal: 8, vertical: 3)
              .backgroundColor(status
                  ? palette.accent.withValues(alpha: 0.10)
                  : palette.rule.withValues(alpha: 0.45))
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
          .fontWeight(FontWeight.w800)
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
  final double size = context.screen.value<double>(mobile: 32, desktop: 42);

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
          color: onDark ? const Color(0xFF7AA2F7) : palette.accent,
        ),
        DVText(item.label).modifier(const DVModifier()
            .fontSize(13.5)
            .fontWeight(FontWeight.w600)
            .color(onDark ? const Color(0xFF98A6C9) : palette.muted)
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
    to: const DVRouteTarget('/'),
    padding: EdgeInsets.zero,
    semanticLabel: 'Dartvel, home',
    child: DVBox.row(<Widget>[
      // The mark itself, not a letter in a box. The placeholder was a bold
      // D on an accent square, which is what a header has before anybody
      // draws a logo.
      const DartvelMark(size: 24),
      const DVText('Dartvel').modifier(const DVModifier()
          .fontSize(17)
          .fontWeight(FontWeight.w800)
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
          .rounded(9),
    ),
  );
}

@DVFunctionalWidget()
Widget _externalLink(BuildContext context, String label, String url) =>
    DVNavLink.external(
      url,
      // It was styled text with no handler: the url argument was never used,
      // so every footer link was dead and looked exactly like a working one.
      child: DVText(label).modifier(const DVModifier()
          .fontSize(14)
          .fontWeight(FontWeight.w600)
          .color(Palette.of(context).accent)),
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
  final int total = parts.present.length + parts.absent.length;

  final DVModifier prose = const DVModifier()
      .fontSize(15)
      // 1.65 rather than 1.6: at fifteen points these run long, and the extra
      // is the difference between lines a reader tracks and lines they lose
      // their place in.
      .lineHeight(1.65);

  // Whole already. A record of one paragraph with nothing withheld should not
  // be offered a control that opens nothing.
  if (total <= 1 && !labelled) {
    return DVText(parts.present.isEmpty ? body : parts.present.first)
        .modifier(prose.color(palette.muted));
  }

  // Folded, still. The records are data, they grew to six thousand characters
  // once already, and a card twenty-five times the height of the one beside
  // it stops the page being a comparison. What changed is what gets folded:
  // paragraphs and their headings rather than one run of text.
  final DVSignal<bool> open = context.signal(false);
  final bool showAll = open.value;

  final List<Widget> children = <Widget>[];

  if (labelled) {
    children.add(const SiteRecordLabel(text: 'Built', tone: 'accent'));
  }
  if (showAll) {
    for (final String paragraph in parts.present) {
      children.add(DVText(paragraph).modifier(prose.color(palette.muted)));
    }
  } else {
    // The opening, clipped to four lines. A paragraph is up to two hundred
    // and eighty characters, which in one column on a phone is seven lines
    // and a card too tall to compare with the one beside it -- so the fold
    // bounds the height as well as choosing where to stop.
    children.add(DVText(parts.present.first).modifier(prose
        .color(palette.muted)
        .maxLines(kSiteFoldedLines)
        .overflow(TextOverflow.ellipsis)));
  }

  if (labelled && showAll) {
    children.add(const SiteRecordLabel(text: 'Not yet', tone: 'muted'));
    for (final String paragraph in parts.absent) {
      children.add(DVText(paragraph).modifier(prose.color(palette.muted)));
    }
  }

  children.add(DVText(showAll ? 'Show less' : 'Read the whole record').modifier(
      const DVModifier()
          .fontSize(13)
          .fontWeight(FontWeight.w600)
          .color(palette.accent)
          // A button, and announced as one. It is text that does something,
          // which is the thing a screen reader has no way to guess.
          .semanticButton()
          .onTap(() => open.value = !open.value)));

  // Ten between paragraphs. Enough that a break reads as a break at fifteen
  // points and 1.65, and not so much that a card becomes a list of unrelated
  // sentences.
  return DVBox.list(children, spacing: 10);
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
