/// The browser's own find, reaching a page Flutter paints into a canvas.
///
/// Ctrl+F -- and "Find in page" on a phone, which has no shortcut anybody
/// could intercept -- searches the document, and the words on a Flutter page
/// are not in it. Every page Dartvel builds already carries a copy of its text
/// in the document, in the block written for crawlers, printers and readers
/// with scripting off. That block was `display:none`, which is precisely the
/// one kind of hidden a browser's find skips.
///
/// `hidden="until-found"` is the other kind: not painted, and still searched.
/// The browser finds the words, fires `beforematch` on the element holding
/// them, and Dartvel's web runtime scrolls the Flutter page to the paragraph
/// the element mirrors. This file is the part of that which is plain Dart:
/// which elements the build writes, and which rendered paragraph a match
/// means. The DOM and the scrolling live in dartvel_flutter.
library;

/// The attribute naming the paragraph a mirror section stands for.
const String dvFindAnchorAttribute = 'data-dv-anchor';

/// Elements whose content is structure rather than a paragraph.
///
/// Kept as they are, so a crawler still reads a page's landmarks, and walked
/// into: the paragraphs inside a `<main>` are what a reader searches for.
const Set<String> _containers = <String>{
  'article',
  'aside',
  'body',
  'div',
  'footer',
  'header',
  'main',
  'nav',
  'section',
};

/// Elements with no end tag, which can never open a section of their own.
const Set<String> _void = <String>{
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'source',
  'track',
  'wbr',
};

/// A tag, as the scanner reads one. Text is never matched: by the time HTML
/// reaches the block its text is escaped, so `<` in the text is `&lt;`.
final RegExp _tag = RegExp(r'<(/?)([A-Za-z][A-Za-z0-9-]*)\b[^>]*?(/?)>');

/// The opening tag of one findable section.
String _openSection(int anchor) =>
    '<section hidden="until-found" $dvFindAnchorAttribute="$anchor">';

/// [content] with each paragraph in a section the browser's find searches.
///
/// A paragraph here is any element found at container level that is not a
/// container itself -- a heading, a paragraph, a link on its own line, a code
/// block, a whole list -- wrapped in `<section hidden="until-found"
/// data-dv-anchor="N">`, N counting from zero in document order. Wrapped
/// rather than given the attribute: until-found does nothing on an inline
/// element, and an `<li>` or a `<p>` given attributes would stop being the
/// `<li>`/`<p>` every other reader of the block matches on.
///
/// A list is one section rather than one per item, because a `<section>`
/// between `<ul>` and `<li>` is not a list any more. The runtime maps a match
/// to the rendered paragraph by its text, so a coarser section costs a little
/// precision and nothing else.
String dvFindableHtml(String content) {
  final StringBuffer out = StringBuffer();
  int anchor = 0;
  int cursor = 0;

  // The leaf being written, if any: its name, and how deep inside another of
  // the same name the scanner is -- a list inside a list item.
  String? leaf;
  int depth = 0;

  for (final RegExpMatch match in _tag.allMatches(content)) {
    final bool closing = match.group(1) == '/';
    final String name = match.group(2)!.toLowerCase();
    final bool selfClosing = match.group(3) == '/' || _void.contains(name);

    if (leaf != null) {
      // Inside a section: only its own end tag matters.
      if (name == leaf && !selfClosing) {
        depth += closing ? -1 : 1;
        if (depth == 0) {
          out
            ..write(content.substring(cursor, match.end))
            ..write('</section>');
          cursor = match.end;
          leaf = null;
        }
      }
      continue;
    }

    if (closing || selfClosing || _containers.contains(name)) continue;

    // A paragraph starts here.
    out
      ..write(content.substring(cursor, match.start))
      ..write(_openSection(anchor++));
    cursor = match.start;
    leaf = name;
    depth = 1;
  }

  out.write(content.substring(cursor));
  // An element never closed -- somebody's template, not the semantics tree --
  // still ends inside its section, rather than leaving one open to swallow
  // whatever the page writes after the block.
  if (leaf != null) out.write('</section>');
  return out.toString();
}

/// One paragraph of a rendered page: its text, and its heading level if the
/// page marked it as a heading.
class DVFindBlock {
  const DVFindBlock(this.text, {this.headingLevel});

  final String text;

  /// 1 to 6 for a heading, null for everything else.
  final int? headingLevel;

  /// The element the mirror writes it as.
  String get tag {
    final int? level = headingLevel;
    return level != null && level >= 1 && level <= 6 ? 'h$level' : 'p';
  }

  @override
  bool operator ==(Object other) =>
      other is DVFindBlock &&
      other.text == text &&
      other.headingLevel == headingLevel;

  @override
  int get hashCode => Object.hash(text, headingLevel);

  @override
  String toString() => 'DVFindBlock($tag: $text)';
}

/// [text] as find compares it: whitespace collapsed, case folded.
///
/// A paragraph Flutter wrapped over three lines is one run of words to the
/// reader, and the browser's find is case-insensitive by default.
String dvFindNormalize(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// The most text the mirror holds for one page.
///
/// A mirror is a copy of what the page drew. A page that draws a novel should
/// not have the DOM carry a second one: past this the mirror stops, and what
/// is past it is not findable -- which is where section 2's own find bar, not
/// a bigger DOM, is the answer.
const int dvFindMirrorMaxChars = 200000;

/// The paragraphs a mirror is written from, cleaned.
///
/// Whitespace collapsed as the reader sees it, empty paragraphs dropped, and
/// the total held to [maxChars]. Repeats are kept: the same words twice on a
/// page are two places find can land.
List<DVFindBlock> dvFindMirrorBlocks(
  Iterable<DVFindBlock> rendered, {
  int maxChars = dvFindMirrorMaxChars,
}) {
  final List<DVFindBlock> blocks = <DVFindBlock>[];
  int total = 0;
  for (final DVFindBlock block in rendered) {
    final String text = block.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    if (total + text.length > maxChars) break;
    total += text.length;
    blocks.add(DVFindBlock(text, headingLevel: block.headingLevel));
  }
  return blocks;
}

/// The paragraphs of [blocks] whose words are not already in [existing].
///
/// On the route a build wrote the block for, that block is kept: it carries
/// the links and the landmarks the semantics tree gave it, which a crawler
/// that runs scripts reads and a mirror rebuilt from painted paragraphs
/// would throw away. What the page has drawn since -- rows a list built on
/// scrolling, text that arrived with its data -- is added beside it.
List<DVFindBlock> dvFindMissing(String existing, List<DVFindBlock> blocks) {
  final String have = dvFindNormalize(existing);
  return <DVFindBlock>[
    for (final DVFindBlock block in blocks)
      if (!have.contains(dvFindNormalize(block.text))) block,
  ];
}

/// Which of the page's rendered paragraphs [section] mirrors.
///
/// `beforematch` names the element the browser matched in, not the words or
/// the offset, so the paragraph is the finest this can be. [candidates] are
/// the page's paragraphs as they are rendered now, in order; [hint] is the
/// index the mirror was written with, which is exact while the page has not
/// changed and breaks ties when it has.
///
/// In order of confidence: the same text; a paragraph the section is part of
/// (the build wrote one sentence of a longer rendered paragraph); a run of
/// paragraphs that makes up most of the section (the build wrote a whole
/// list, the page drew an item at a time); a long paragraph inside the
/// section; and, last, the paragraph sharing most of its words, for
/// text that changed a little since the mirror was written. Null when nothing
/// is close, because scrolling somewhere wrong is worse than not scrolling.
int? dvFindMatch(String section, List<String> candidates, {int? hint}) {
  final String target = dvFindNormalize(section);
  if (target.isEmpty || candidates.isEmpty) return null;
  final List<String> normalized = candidates.map(dvFindNormalize).toList();

  int? nearest(Iterable<int> indexes) {
    int? best;
    for (final int i in indexes) {
      if (best == null) {
        best = i;
        continue;
      }
      if (hint == null) continue;
      if ((i - hint).abs() < (best - hint).abs()) best = i;
    }
    return best;
  }

  final Iterable<int> all = Iterable<int>.generate(normalized.length);

  final int? exact = nearest(all.where((int i) => normalized[i] == target));
  if (exact != null) return exact;

  final int? within = nearest(all.where(
      (int i) => normalized[i].isNotEmpty && normalized[i].contains(target)));
  if (within != null) return within;

  // A run of paragraphs that is most of the section: a list the build wrote
  // whole, drawn one short item at a time. Most of it, because a one-word
  // label at the start of a long section is not what the section says.
  bool opensRun(int i) {
    if (normalized[i].isEmpty || !target.startsWith(normalized[i])) {
      return false;
    }
    String joined = normalized[i];
    for (int j = i + 1; j < normalized.length; j++) {
      final String next = '$joined ${normalized[j]}';
      if (!target.startsWith(next)) break;
      joined = next;
    }
    return joined.length >= target.length * 0.6;
  }

  final int? run = nearest(all.where(opensRun));
  if (run != null) return run;

  // A paragraph inside the section. Short ones are left out: a one-word
  // label is inside every section that mentions it.
  final int? inside = nearest(all.where((int i) =>
      normalized[i].length >= 12 && target.contains(normalized[i])));
  if (inside != null) return inside;

  final Set<String> words = target.split(' ').toSet();
  double bestScore = 0;
  int? best;
  for (final int i in all) {
    final Set<String> theirs = normalized[i].split(' ').toSet();
    if (theirs.isEmpty) continue;
    final int shared = words.intersection(theirs).length;
    final double score = shared / words.union(theirs).length;
    final bool closer = best != null &&
        hint != null &&
        score == bestScore &&
        (i - hint).abs() < (best - hint).abs();
    if (score > bestScore || closer) {
      bestScore = score;
      best = i;
    }
  }
  return bestScore >= 0.5 ? best : null;
}

/// The index a runtime mirror wrote into [anchor], or null for one the build
/// wrote -- whose numbering counts the semantics tree's elements, not the
/// paragraphs the page renders, and so is no hint at all.
int? dvFindRuntimeAnchor(String? anchor) {
  if (anchor == null || !anchor.startsWith('r')) return null;
  return int.tryParse(anchor.substring(1));
}
