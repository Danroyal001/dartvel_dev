// Shared shell, palette and building blocks for the site.
//
// The palette is resolved from the ambient theme rather than held as
// constants, so light and dark are one set of pages rather than two. The app
// follows the system by default -- a visitor who has chosen dark should not be
// handed white.
import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import 'highlight.dart';
import 'motion.dart';

/// The palette, resolved for whichever brightness is in effect.
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

/// Layout figures that change with the viewport.
class Responsive {
  const Responsive._(this.width);

  factory Responsive.of(BuildContext context) =>
      Responsive._(MediaQuery.sizeOf(context).width);

  final double width;

  bool get narrow => width < 760;
  double get heroSize => narrow ? 36 : 54;
  double get gutter => narrow ? 22 : 56;
}

/// The page frame: header, content, footer, on the themed background.
class SitePage extends StatelessWidget {
  const SitePage({super.key, required this.current, required this.children});

  final String current;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Container(
      color: palette.page,
      child: SingleChildScrollView(
        child: DVBox.list(<Widget>[
          SiteHeader(current: current),
          ...children,
          const SiteFooter(),
        ], spacing: 0),
      ),
    );
  }
}

class SiteHeader extends StatelessWidget {
  const SiteHeader({super.key, required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final responsive = Responsive.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.rule)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: responsive.gutter,
        vertical: 14,
      ),
      // The same 1040 column as the sections, so the wordmark sits above the
      // headings rather than out at the window edge.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          // Full width inside the column, so the wordmark sits at the left of
          // the content rather than in the middle of the window: a Wrap
          // shrinks to its children, and a shrunken Wrap inside a Center is
          // centred.
          child: SizedBox(
            width: double.infinity,
            // A row rather than a wrap, so the site links sit left and the
            // outbound ones sit right. Everything crammed into the left
            // quarter was the header reading as a list rather than a bar.
            child: responsive.narrow
                ? DVBox.wrapLine(<Widget>[
                    const _Wordmark(),
                    NavLink('Docs', '/docs', active: current == '/docs'),
                    NavLink('Features', '/features',
                        active: current == '/features'),
                    NavLink('Cloud', '/cloud', active: current == '/cloud'),
                  ], spacing: 18)
                : Row(
                    children: <Widget>[
                      const _Wordmark(),
                      const SizedBox(width: 28),
                      NavLink('Docs', '/docs', active: current == '/docs'),
                      const SizedBox(width: 18),
                      NavLink('Features', '/features',
                          active: current == '/features'),
                      const SizedBox(width: 18),
                      NavLink('Cloud', '/cloud', active: current == '/cloud'),
                      const Spacer(),
                      const ExternalLink(
                          'GitHub', 'https://github.com/Danroyal001/dartvel_dev'),
                      const SizedBox(width: 18),
                      const ExternalLink(
                          'pub.dev', 'https://pub.dev/packages/dartvel_dev'),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final responsive = Responsive.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.rule)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: responsive.gutter,
        vertical: 32,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: DVBox.list(<Widget>[
        const DVBox.wrapLine(<Widget>[
          ExternalLink('GitHub', 'https://github.com/Danroyal001/dartvel_dev'),
          ExternalLink('pub.dev', 'https://pub.dev/packages/dartvel_dev'),
          ExternalLink('npm', 'https://www.npmjs.com/package/dartvel_dev'),
        ], spacing: 20),
        const DVText('MIT licensed. Built with Dartvel.').modifier(
          const DVModifier().fontSize(13).color(palette.faint),
        ),
          ], spacing: 12),
        ),
      ),
    );
  }
}

/// A band of content, optionally on the tinted surface.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.children,
    this.tint = false,
    this.dark = false,
    this.glow = false,
  });

  final List<Widget> children;
  final bool tint;

  /// Ink-dark, for the one or two bands that should stop the scroll.
  ///
  /// A page that is eight shades of the same cream reads as one very long
  /// section however good the type is.
  final bool dark;

  /// A soft accent bloom in the corner. The hero, and nothing else -- a page
  /// where everything glows is a page where nothing does.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final responsive = Responsive.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF0B1020)
            : (tint ? palette.surface : palette.page),
        gradient: glow
            ? RadialGradient(
                center: const Alignment(0.92, -1.1),
                radius: 1.15,
                colors: <Color>[
                  palette.accent.withValues(alpha: palette.dark ? 0.20 : 0.13),
                  (tint ? palette.surface : palette.page).withValues(alpha: 0),
                ],
              )
            : null,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: responsive.gutter,
        vertical: responsive.narrow ? 40 : 64,
      ),
      // Centred, not pinned left. A 1040-wide column aligned topLeft on a
      // 1440 screen leaves 400px of dead margin on one side and none on the
      // other, which is what made the page look unfinished rather than
      // spacious.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          // Fades and rises as it comes into view. The band's own background
          // is outside this, so the colour is already painted when the
          // content arrives -- a section that faded in whole would flash the
          // page colour behind it.
          child: Reveal(child: DVBox.list(children, spacing: 22)),
        ),
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {this.onDark = false, super.key});
  final String text;

  /// On an ink band, where the page's own accent sits too dark to read.
  final bool onDark;

  @override
  Widget build(BuildContext context) => DVText(text).modifier(
        DVModifier()
            .fontSize(12)
            .fontWeight(FontWeight.w700)
            .color(onDark
                ? const Color(0xFF7AA2F7)
                : Palette.of(context).accent)
            .letterSpacing(1.8),
      );
}

class Heading extends StatelessWidget {
  /// [level] is the document outline, not the size. A section heading two
  /// thirds of the way down a page is still an h2, and a page has one h1 --
  /// which is why the hero passes 1 and every section leaves the default.
  const Heading(this.text, {this.level = 2, this.onDark = false, super.key});
  final String text;
  final int level;

  /// On an ink band.
  final bool onDark;

  @override
  Widget build(BuildContext context) => DVText(text).modifier(
        const DVModifier()
            .fontSize(Responsive.of(context).narrow ? 26 : 34)
            .fontWeight(FontWeight.w800)
            .color(onDark ? const Color(0xFFF2F5FC) : Palette.of(context).ink)
            .height(1.15)
            // Declared, so the outline exists for a screen reader moving by
            // heading and for the crawler-visible HTML built from the
            // semantics tree. Without it every heading was a paragraph.
            .semanticHeading(level),
      );
}

class Body extends StatelessWidget {
  const Body(this.text, {super.key, this.width = 640});
  final String text;
  final double width;

  @override
  Widget build(BuildContext context) => DVText(text).modifier(
        const DVModifier()
            .fontSize(17)
            .color(Palette.of(context).muted)
            .height(1.65)
            .width(width),
      );
}

class Card_ extends StatelessWidget {
  const Card_(this.title, this.body, {super.key});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    // Lifts under the pointer, and the border takes the accent. Small: a card
    // that jumps pulls attention off the one being read.
    return Lift(
      builder: (BuildContext context, bool hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: palette.page,
          border: Border.all(
            color: hovered
                ? palette.accent.withValues(alpha: 0.5)
                : palette.rule,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: hovered ? (palette.dark ? 0.4 : 0.09) : 0),
              blurRadius: hovered ? 22 : 0,
              offset: Offset(0, hovered ? 8 : 0),
            ),
          ],
        ),
        child: DVBox.list(<Widget>[
          DVText(title).modifier(
            DVModifier()
                .fontSize(17)
                .fontWeight(FontWeight.w700)
                .color(palette.ink),
          ),
          DVText(body).modifier(
            DVModifier().fontSize(14).color(palette.muted).height(1.55),
          ),
        ], spacing: 8),
      ),
    );
  }
}

class Chip_ extends StatelessWidget {
  const Chip_(this.text, {this.onDark = false, super.key});
  final String text;

  /// On an ink band, where the page's surface and rule colours disappear.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: onDark ? const Color(0xFF161E33) : palette.surface,
        border: Border.all(
          color: onDark ? const Color(0xFF2A3557) : palette.rule,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DVText(text).modifier(
        DVModifier()
            .fontSize(13)
            .color(onDark ? const Color(0xFFD3DCF3) : palette.ink),
      ),
    );
  }
}

class Stat extends StatelessWidget {
  const Stat(this.value, this.label, {super.key});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DVBox.list(<Widget>[
        DVText(value).modifier(
          const DVModifier()
              .fontSize(30)
              .fontWeight(FontWeight.w800)
              .color(palette.accent),
        ),
        DVText(label).modifier(
          const DVModifier().fontSize(13).color(palette.muted),
        ),
      ], spacing: 4),
    );
  }
}

/// A block of code. Monospaced, and selectable like the rest of the page.
class CodeBlock extends StatelessWidget {
  const CodeBlock(this.lines, {super.key});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.dark ? const Color(0xFF0E141D) : const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(10),
      ),
      // Labelled, because Flutter renders SelectableText as a textarea whose
      // value it manages: without this the code is absent from the semantics
      // tree entirely, so a crawler never sees the install commands and a
      // screen reader never reads them.
      child: Semantics(
        identifier: 'dartvel:code',
        label: lines.join('\n'),
        excludeSemantics: true,
        child: SelectableText.rich(
          TextSpan(
            // Coloured, because on a framework's site the code is the demo.
            // One colour on navy is the same amount of information as a
            // screenshot of a wall, and the annotations -- which are the
            // whole argument of most of these pages -- read as ordinary text.
            children: Code.spans(lines.join('\n')),
          ),
          style: const TextStyle(
            // Bundled, not named. Flutter web cannot resolve the generic
            // "monospace" family and silently falls back to the body font, so
            // every Dart sample on this site rendered in proportional text --
            // on a page whose whole argument is what the code looks like.
            fontFamily: 'RobotoMono',
            fontFamilyFallback: <String>['Menlo', 'Consolas', 'monospace'],
            fontSize: 13.5,
            height: 1.65,
          ),
        ),
      ),
    );
  }
}

/// A header link. A DVNavLink with the header's look, rather than a tap
/// handler wired by hand -- which is what shipped dead twice.
/// The wordmark: a mark and the name, so the header has something to anchor
/// on other than a bold word.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DVNavLink(
      to: const DVRouteTarget('/'),
      padding: EdgeInsets.zero,
      semanticLabel: 'Dartvel, home',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: const Text(
              'D',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            'Dartvel',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: palette.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class NavLink extends StatelessWidget {
  const NavLink(this.label, this.href, {super.key, this.active = false});
  final String label;
  final String href;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DVNavLink(
      to: DVRouteTarget(href),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? palette.accent : palette.muted,
        ),
      ),
    );
  }
}

class PrimaryLink extends StatelessWidget {
  const PrimaryLink(this.label, this.href, {super.key});
  final String label;
  final String href;

  @override
  Widget build(BuildContext context) =>
      _Button(label: label, href: href, filled: true);
}

class GhostLink extends StatelessWidget {
  const GhostLink(this.label, this.href, {super.key});
  final String label;
  final String href;

  @override
  Widget build(BuildContext context) =>
      _Button(label: label, href: href, filled: false);
}

/// A button that is a link: it navigates, previews, preloads, takes keyboard
/// focus and opens in a new tab on a middle click, because DVNavLink does all
/// of that and a GestureDetector does none of it.
class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.href,
    required this.filled,
  });

  final String label;
  final String href;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DVNavLink(
      to: DVRouteTarget(href),
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        decoration: BoxDecoration(
          color: filled ? palette.accent : Colors.transparent,
          border: filled ? null : Border.all(color: palette.rule, width: 1.5),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: filled ? Colors.white : palette.ink,
          ),
        ),
      ),
    );
  }
}

class ExternalLink extends StatelessWidget {
  const ExternalLink(this.label, this.url, {super.key});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => DVNavLink.external(
        url,
        // It was styled text with no handler: the url argument was never
        // used, so every footer link was dead and looked exactly like a
        // working one.
        child: DVText(label).modifier(
          const DVModifier()
              .fontSize(14)
              .fontWeight(FontWeight.w600)
              .color(Palette.of(context).accent),
        ),
      );
}

/// A row of numbers.
///
/// Dartvel's are genuinely interesting and were buried in prose: fifteen build
/// targets, twenty-two shipped sections, six packages. A number set large is
/// the cheapest visual interest a technical page has, and it is the part
/// people screenshot.
class Stats extends StatelessWidget {
  const Stats(this.items, {this.onDark = false, super.key});

  /// Each entry is the number and what it counts.
  final List<(String, String)> items;

  /// On an ink band, where the page accent sits too dark to read.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final responsive = Responsive.of(context);
    return Wrap(
      spacing: responsive.narrow ? 28 : 56,
      runSpacing: 22,
      children: <Widget>[
        for (final (String value, String label) item in items)
          // A Column that shrinks to its content. DVBox.list stretches to the
          // width it is given, so inside a Wrap every entry took a full line
          // and four numbers meant to sit in a row stacked into a column.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Counts up the first time it is seen. The one animation on
              // this page that carries meaning rather than decoration: it
              // says the figure is a count of something.
              CountUp(
                item.$1,
                style: TextStyle(
                  fontSize: responsive.narrow ? 32 : 42,
                  fontWeight: FontWeight.w800,
                  color: onDark ? const Color(0xFF7AA2F7) : palette.accent,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 4),
              DVText(item.$2).modifier(
                DVModifier()
                    .fontSize(13.5)
                    .fontWeight(FontWeight.w600)
                    .color(onDark
                        ? const Color(0xFF98A6C9)
                        : palette.muted)
                    .height(1.4),
              ),
            ],
          ),
      ],
    );
  }
}
