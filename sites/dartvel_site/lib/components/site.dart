// Shared shell, palette and building blocks for the site.
//
// The palette is resolved from the ambient theme rather than held as
// constants, so light and dark are one set of pages rather than two. The app
// follows the system by default -- a visitor who has chosen dark should not be
// handed white.
import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

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
            child: DVBox.wrapLine(<Widget>[
        DVText('Dartvel').modifier(
          DVModifier()
              .fontSize(18)
              .fontWeight(FontWeight.w800)
              .color(palette.ink),
        ),
        NavLink('Docs', '/docs', active: current == '/docs'),
        NavLink('Features', '/features', active: current == '/features'),
        NavLink('Cloud', '/cloud', active: current == '/cloud'),
            ], spacing: 22),
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
        DVBox.wrapLine(<Widget>[
          const ExternalLink('GitHub', 'https://github.com/Danroyal001/dartvel_dev'),
          const ExternalLink('pub.dev', 'https://pub.dev/packages/dartvel_dev'),
          const ExternalLink('npm', 'https://www.npmjs.com/package/dartvel_dev'),
        ], spacing: 20),
        DVText('MIT licensed. Built with Dartvel.').modifier(
          DVModifier().fontSize(13).color(palette.faint),
        ),
          ], spacing: 12),
        ),
      ),
    );
  }
}

/// A band of content, optionally on the tinted surface.
class Section extends StatelessWidget {
  const Section({super.key, required this.children, this.tint = false});

  final List<Widget> children;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final responsive = Responsive.of(context);
    return Container(
      width: double.infinity,
      color: tint ? palette.surface : palette.page,
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
          child: DVBox.list(children, spacing: 22),
        ),
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => DVText(text).modifier(
        DVModifier()
            .fontSize(12)
            .fontWeight(FontWeight.w700)
            .color(Palette.of(context).accent)
            .letterSpacing(1.8),
      );
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => DVText(text).modifier(
        DVModifier()
            .fontSize(Responsive.of(context).narrow ? 26 : 34)
            .fontWeight(FontWeight.w800)
            .color(Palette.of(context).ink)
            .height(1.15),
      );
}

class Body extends StatelessWidget {
  const Body(this.text, {super.key, this.width = 640});
  final String text;
  final double width;

  @override
  Widget build(BuildContext context) => DVText(text).modifier(
        DVModifier()
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
    return Container(
      width: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: palette.rule),
        borderRadius: BorderRadius.circular(12),
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
    );
  }
}

class Chip_ extends StatelessWidget {
  const Chip_(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.rule),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DVText(text).modifier(
        DVModifier().fontSize(13).color(palette.ink),
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
          DVModifier()
              .fontSize(30)
              .fontWeight(FontWeight.w800)
              .color(palette.accent),
        ),
        DVText(label).modifier(
          DVModifier().fontSize(13).color(palette.muted),
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
      child: SelectableText(
        lines.join('\n'),
        style: TextStyle(
          // Bundled, not named. Flutter web cannot resolve the generic
          // "monospace" family and silently falls back to the body font, so
          // every Dart sample on this site rendered in proportional text --
          // on a page whose whole argument is what the code looks like.
          fontFamily: 'RobotoMono',
          fontFamilyFallback: const <String>['Menlo', 'Consolas', 'monospace'],
          fontSize: 13.5,
          height: 1.65,
          color: palette.dark
              ? const Color(0xFFD7E1F5)
              : const Color(0xFFE8EEFA),
        ),
      ),
    );
  }
}

/// A header link. A DVNavLink with the header's look, rather than a tap
/// handler wired by hand -- which is what shipped dead twice.
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
  Widget build(BuildContext context) => DVText(label).modifier(
        DVModifier()
            .fontSize(14)
            .fontWeight(FontWeight.w600)
            .color(Palette.of(context).accent),
      );
}
