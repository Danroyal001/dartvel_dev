// A widget in a sentence that is read where it sits.
//
// Flutter reads a Text.rich in one of two ways. When none of its spans needs
// a semantics node of its own, the paragraph merges its text and whatever
// its placeholders (WidgetSpans) say into one label, in reading order, and a
// placeholder that cannot merge -- a link next to another link: two links
// never share a node -- becomes a node after all of that text. A sentence
// with several links was read, and server-rendered, as "Questions, or a
// project in mind? . Our , and explain how we handle your data" with every
// link at the end (sigmadev.digital/about, Dartvel 3.47.8).
//
// When a span does need its own node, the paragraph gives each run of text a
// node of its own, in order, and puts each placeholder's nodes beside them;
// but the text nodes carry ordinal sort keys and the placeholder's do not, so
// a screen reader still met all the text first.
//
// DVWidgetSpan asks for the second way and gives its widget a sort key
// between the runs of text on either side of it, so every link, button or
// chip in a sentence is read, found and server-rendered in its place, and
// stays a node of its own (a link keeps its address and its tap).
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [WidgetSpan] whose widget is read in its place in the sentence: by a
/// screen reader, by the browser's find, and in the server-rendered page.
///
/// Use it for a link inside a run of text, and for anything else a sentence
/// holds that has something to say of its own:
///
/// ```dart
/// Text.rich(TextSpan(children: [
///   const TextSpan(text: 'Read our '),
///   DVWidgetSpan(child: DVNavLink(to: DVRoutes.privacy, child: const Text('privacy policy'))),
///   const TextSpan(text: ' and '),
///   DVWidgetSpan(child: DVNavLink(to: DVRoutes.terms, child: const Text('terms'))),
///   const TextSpan(text: '.'),
/// ]))
/// ```
///
/// A plain [WidgetSpan] keeps one link in place; with two or more, every
/// link is read after the sentence.
class DVWidgetSpan extends WidgetSpan {
  /// Places [child] in the run of text, as [WidgetSpan] does.
  DVWidgetSpan({
    required Widget child,
    super.alignment,
    super.baseline,
    super.style,
  }) : super(child: _InSentence(child: child));

  /// The semantics identifier of each widget placed in a sentence, and of the
  /// placeholder that asks the paragraph for nodes of its own.
  static const String inSentenceIdentifier = 'dartvel:in-sentence';

  /// A placeholder that tells the paragraph to give each of its pieces a node
  /// of its own (the identifier is what asks; it names nothing).
  static const InlineSpanSemanticsInformation _ownNodes = InlineSpanSemanticsInformation(
    '￼',
    isPlaceholder: true,
    semanticsIdentifier: inSentenceIdentifier,
  );

  @override
  void computeSemanticsInformation(List<InlineSpanSemanticsInformation> collector) {
    collector.add(_ownNodes);
  }
}

/// [child] as one node, sorted between the runs of text around its
/// placeholder.
class _InSentence extends StatelessWidget {
  const _InSentence({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double? place = dvPlaceInSentence(context);
    if (place == null) return child;
    // The identifier tells the server-rendered document that this node sits
    // in a sentence, so it writes the sentence as one paragraph with the
    // link in its place (semantic_html.dart in dartvel_cli). It names
    // nothing a reader hears.
    return Semantics(
      container: true,
      sortKey: OrdinalSortKey(place),
      identifier: DVWidgetSpan.inSentenceIdentifier,
      child: child,
    );
  }
}

/// Where the placeholder holding [context] is read among its paragraph's
/// runs of text, as an [OrdinalSortKey] order: between the run before it
/// and the run after it. Null outside a paragraph, or in one whose runs of
/// text are not nodes of their own (there the paragraph's single label
/// already reads everything in order, and a sort key would move the whole
/// paragraph among its siblings).
double? dvPlaceInSentence(BuildContext context) {
  int? placeholder;
  RichText? paragraph;
  context.visitAncestorElements((Element element) {
    final Widget widget = element.widget;
    if (placeholder == null &&
        widget is Semantics &&
        widget.properties.tagForChildren is PlaceholderSpanIndexSemanticsTag) {
      placeholder = (widget.properties.tagForChildren! as PlaceholderSpanIndexSemanticsTag).index;
    }
    if (widget is RichText) {
      paragraph = widget;
      return false;
    }
    return true;
  });
  final RichText? found = paragraph;
  final int? index = placeholder;
  if (found == null || index == null) return null;
  final List<InlineSpanSemanticsInformation> pieces = combineSemanticsInfo(found.text.getSemanticsInformation());
  if (!pieces.any((InlineSpanSemanticsInformation piece) =>
      piece.recognizer != null || piece.semanticsIdentifier != null)) {
    return null;
  }
  // RenderParagraph numbers its runs of text 0, 1, 2... in order, skipping
  // placeholders and runs with no text.
  int runsBefore = 0;
  int placeholders = 0;
  for (final InlineSpanSemanticsInformation piece in pieces) {
    if (piece.isPlaceholder) {
      if (placeholders == index) break;
      placeholders += 1;
    } else if (piece.text.isNotEmpty) {
      runsBefore += 1;
    }
  }
  return runsBefore - 0.5;
}
