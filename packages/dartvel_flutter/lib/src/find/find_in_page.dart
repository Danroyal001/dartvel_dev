/// The Flutter half of the browser's own find: what the page on top has
/// drawn, and scrolling to the paragraph a match means.
///
/// On the web the browser searches a hidden copy of the page's text and
/// fires `beforematch` on the element it matched in (find_platform_web.dart).
/// That element names a paragraph and nothing finer, so the reader is
/// scrolled to the paragraph and shown it, not the word. Nothing here needs a
/// browser, which is why it is here and not in the web glue.
///
/// Not in the barrel. A page is findable because the page shell registers
/// it, as it carries selection and keyboard scrolling; there is nothing for
/// an application to call, and `@DVPage(findable: false)` is the one thing it
/// can say.
library;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVFindBlock, dvFindMatch;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A page the browser's find can reach: what `DVPageShell` registers.
abstract class DVFindPage {
  /// Whether the page lets the browser's find reach it.
  bool get findable;

  /// Whether the page is the one on top of its navigator.
  bool get findOnTop;

  /// The page's own content, below its chrome.
  BuildContext? get findRoot;
}

/// One paragraph the page has drawn, and where it is.
class DVFoundParagraph {
  const DVFoundParagraph(this.context, this.block);

  /// The element that owns the paragraph's [RenderParagraph], which is what
  /// `Scrollable.ensureVisible` scrolls to.
  final BuildContext context;

  final DVFindBlock block;
}

/// The pages the browser's find can reach, and what it does when it lands.
abstract final class DVFindInPage {
  /// The highlight drawn over a paragraph the browser matched.
  static const Key highlightKey = ValueKey<String>('dartvel.find.highlight');

  /// How long the highlight stays, fading, before it is gone.
  static const Duration highlightDuration = Duration(milliseconds: 1600);

  static final List<DVFindPage> _pages = <DVFindPage>[];

  /// Called by the page shell as a page is built.
  static void register(DVFindPage page) => _pages.add(page);

  /// Called by the page shell as a page goes away.
  static void unregister(DVFindPage page) => _pages.remove(page);

  /// The page the reader is looking at, or null when no page shell is up.
  ///
  /// The first registered of the pages on top: a page pushed over another
  /// makes the one beneath not current, and a page shell nested inside
  /// another registers after it, so the outer one -- whose content includes
  /// the inner -- is the one read.
  static DVFindPage? get active {
    for (final DVFindPage page in _pages) {
      final BuildContext? root = page.findRoot;
      if (root == null || !root.mounted) continue;
      if (page.findOnTop) return page;
    }
    return null;
  }

  /// Every paragraph the page on top has drawn, in the order it is laid out
  /// in the tree, or none when that page opted out of find.
  ///
  /// Read from the render tree rather than from the page source: this is the
  /// text a reader can see, including text that arrived with data after the
  /// build captured the page. A row a lazy list has not built is not here;
  /// that is section 3 of the proposal, not this.
  static List<DVFoundParagraph> paragraphs() {
    final DVFindPage? page = active;
    if (page == null || !page.findable) return const <DVFoundParagraph>[];
    final BuildContext? root = page.findRoot;
    if (root is! Element) return const <DVFoundParagraph>[];

    final List<DVFoundParagraph> found = <DVFoundParagraph>[];
    void visit(Element element, int? heading) {
      final Widget widget = element.widget;
      // What the page keeps built and does not show -- a tab behind another,
      // a step not reached -- is not what the reader is searching.
      if (widget is Offstage && widget.offstage) return;
      int? level = heading;
      if (widget is Semantics) {
        final int? declared = widget.properties.headingLevel;
        if (declared != null && declared > 0) level = declared;
      }
      if (element is RenderObjectElement) {
        final RenderObject render = element.renderObject;
        if (render is RenderParagraph) {
          final String text = render.text.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          );
          if (text.trim().isNotEmpty) {
            found.add(DVFoundParagraph(
                element, DVFindBlock(text, headingLevel: level)));
          }
        }
      }
      element.visitChildElements((Element child) => visit(child, level));
    }

    root.visitChildElements((Element child) => visit(child, null));
    return found;
  }

  /// Scrolls the page on top to the paragraph [section] mirrors, and
  /// highlights it.
  ///
  /// [section] is the text of the element the browser matched; [hint] the
  /// index a runtime mirror wrote it at. False, and nothing moved, when the
  /// page has no paragraph that is close: scrolling somewhere plausible and
  /// wrong is worse than staying put.
  static Future<bool> reveal(String section, {int? hint}) async {
    final List<DVFoundParagraph> found = paragraphs();
    final int? index = dvFindMatch(
      section,
      <String>[for (final DVFoundParagraph p in found) p.block.text],
      hint: hint,
    );
    if (index == null) return false;
    final BuildContext target = found[index].context;

    // The reader's own answer about motion, where they gave one.
    final bool still = MediaQuery.maybeDisableAnimationsOf(target) ?? false;
    await Scrollable.ensureVisible(
      target,
      // A little below the top, so the paragraph is read with what leads
      // into it rather than jammed against the edge.
      alignment: 0.25,
      duration: still ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (target.mounted) _highlight(target);
    return true;
  }

  static OverlayEntry? _shown;

  /// A tinted box over [target] that fades away.
  ///
  /// The browser draws its own match highlight on the hidden copy, which the
  /// reader never sees, so the page draws one of its own over the paragraph.
  /// In the root overlay, over the page and under nothing, and never in the
  /// way: it takes no pointer and says nothing to a screen reader.
  static void _highlight(BuildContext target) {
    final OverlayState? overlay = Overlay.maybeOf(target, rootOverlay: true);
    final RenderObject? box = target.findRenderObject();
    final RenderObject? over = overlay?.context.findRenderObject();
    if (overlay == null ||
        box is! RenderBox ||
        over is! RenderBox ||
        !box.hasSize ||
        !box.attached) {
      return;
    }
    final Rect rect = MatrixUtils.transformRect(
      box.getTransformTo(over),
      Offset.zero & box.size,
    ).inflate(4);

    _shown?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (BuildContext context) => Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: _DVFindHighlight(
              key: highlightKey,
              onDone: () {
                if (identical(_shown, entry)) _shown = null;
                if (entry.mounted) entry.remove();
              },
            ),
          ),
        ),
      ),
    );
    _shown = entry;
    overlay.insert(entry);
  }
}

/// The highlight itself: the colour a browser marks a find match in, held and
/// then faded out.
class _DVFindHighlight extends StatefulWidget {
  const _DVFindHighlight({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<_DVFindHighlight> createState() => _DVFindHighlightState();
}

class _DVFindHighlightState extends State<_DVFindHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DVFindInPage.highlightDuration,
  );

  /// Held for the first half, so it is seen after the scroll lands, then
  /// faded.
  late final Animation<double> _opacity = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 1),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
    ],
  ).animate(_controller);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    }));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0x55FFC83D),
            borderRadius: BorderRadius.all(Radius.circular(6)),
            border: Border.fromBorderSide(
              BorderSide(color: Color(0xCCFFB300), width: 2),
            ),
          ),
        ),
      );
}
