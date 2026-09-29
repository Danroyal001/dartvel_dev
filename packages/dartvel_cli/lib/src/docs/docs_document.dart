/// Turning what somebody wrote into blocks the application can draw.
///
/// `dartvel docs` does not author the documentation site any more — it
/// compiles `DVDocsApp` and writes the document beside it — but it is still
/// the thing that reads a project's doc comments and decision records, and
/// this is where a sentence becomes data. The document itself is in
/// `dartvel_core`, because the application draws it and the two packages do
/// not depend on each other.
///
/// The prose forms are deliberately few: inline code, `**strong**`, and
/// links, at the top of a block and inside one. A doc comment is written by
/// whoever wrote the page, and a construct this does not know is shown as
/// text rather than guessed at — a documentation build that rendered a
/// markdown implementation would be a second thing to keep right about the
/// same sentences.
library;

import 'package:dartvel_core/dartvel.dart';

export 'package:dartvel_core/dartvel.dart'
    show
        DVDocsBlock,
        DVDocsCode,
        DVDocsColumn,
        DVDocsDocument,
        DVDocsFinding,
        DVDocsHeading,
        DVDocsList,
        DVDocsListItem,
        DVDocsPage,
        DVDocsParagraph,
        DVDocsRow,
        DVDocsSpan,
        DVDocsTable,
        DVDocsTarget,
        dvDocsGraphFile,
        dvDocsNavigation,
        dvDocsPayloadFile;

/// A link target the document will carry: http(s), a fragment, or a path
/// relative to the site's own root. Anything with another scheme --
/// `javascript:` above all -- is rendered as its text.
///
/// A doc comment is written by whoever wrote the page, and the site is served
/// on the application's own origin, so this is the one place a value from the
/// project becomes a navigation.
bool dvDocsSafeHref(String href) {
  if (href.startsWith('http://') || href.startsWith('https://')) return true;
  if (href.startsWith('#')) return true;
  final int colon = href.indexOf(':');
  final int slash = href.indexOf('/');
  return colon == -1 || (slash != -1 && slash < colon);
}

/// One inline code span, as the caller needs it. [line] is the 1-based source
/// line it is on, which is how a decision record's `` `kind:target` `` spans
/// find the node they name.
typedef DVDocsCodeSpan = DVDocsSpan Function(String code, int line);

/// One line of markdown-ish prose: code spans, `**strong**` and links.
///
/// One pass, left to right, first construct wins. Constructs do not nest: a
/// link's label is its own text rather than a paragraph of it, because a
/// decision record naming a node writes `` [`model:User`](…) `` or the reverse
/// and never both, and a parser that grew to cover the third case would be a
/// markdown implementation in a documentation build.
List<DVDocsSpan> dvDocsInline(String text, {int line = 0, DVDocsCodeSpan? code}) {
  final List<DVDocsSpan> out = <DVDocsSpan>[];
  int at = 0;
  for (final RegExpMatch match in _inline.allMatches(text)) {
    if (match.start > at) {
      out.add(DVDocsSpan.text(text.substring(at, match.start)));
    }
    if (match.group(1) != null) {
      final String span = match.group(1)!;
      out.add(code?.call(span, line) ?? DVDocsSpan.code(span));
    } else if (match.group(2) != null) {
      out.add(DVDocsSpan.strong(match.group(2)!));
    } else {
      final String label = match.group(3)!;
      final String href = match.group(4)!;
      // A link with a scheme nobody should follow is its own text. A doc
      // comment is written by whoever wrote the page, and this site is served
      // on the application's own origin, so the reader's session is what a
      // `javascript:` href would be spent on.
      out.add(
        dvDocsSafeHref(href)
            ? DVDocsSpan.link(label, DVDocsTarget.external(href))
            : DVDocsSpan.text(label),
      );
    }
    at = match.end;
  }
  if (at < text.length) out.add(DVDocsSpan.text(text.substring(at)));
  if (out.isEmpty && text.isNotEmpty) out.add(DVDocsSpan.text(text));
  return out;
}

final RegExp _inline = RegExp(
  r'`([^`]+)`'
  r'|\*\*(.+?)\*\*'
  r'|\[([^\]]+)\]\(([^)\s]+)\)',
);

/// A small, deliberately limited markdown renderer: headings, paragraphs,
/// bullet and numbered lists, fenced code, and the inline forms above.
///
/// Limited because what it renders is decision records and doc comments, and
/// because every construct it does not know is shown as text rather than
/// guessed at. [code] sees every inline code span with its source line.
List<DVDocsBlock> dvDocsProse(String source, {DVDocsCodeSpan? code}) {
  final List<String> lines = source.replaceAll('\r\n', '\n').split('\n');
  final List<DVDocsBlock> out = <DVDocsBlock>[];

  // One line at a time rather than the paragraph joined, because a decision
  // record's `` `kind:target` `` is reported with the line it is on, and a
  // paragraph has three.
  final List<({int line, String text})> paragraph = <({int line, String text})>[];

  void closeParagraph() {
    if (paragraph.isEmpty) return;
    final List<DVDocsSpan> spans = <DVDocsSpan>[];
    for (int i = 0; i < paragraph.length; i++) {
      if (i > 0) spans.add(const DVDocsSpan.text(' '));
      spans.addAll(
        dvDocsInline(
          paragraph[i].text,
          line: paragraph[i].line,
          code: code,
        ),
      );
    }
    out.add(DVDocsParagraph(spans));
    paragraph.clear();
  }

  // One list open at a time, and its kind remembered: a bullet between two
  // numbered items ends the first list and starts a second, which is what
  // the source said.
  final List<DVDocsListItem> items = <DVDocsListItem>[];
  bool? ordered;
  void closeList() {
    if (ordered == null) return;
    out.add(DVDocsList(ordered!, <DVDocsListItem>[...items]));
    items.clear();
    ordered = null;
  }

  bool fenced = false;
  final List<String> fence = <String>[];

  for (int i = 0; i < lines.length; i++) {
    final int number = i + 1;
    final String raw = lines[i];
    final String trimmed = raw.trim();

    if (trimmed.startsWith('```')) {
      if (fenced) {
        out.add(DVDocsCode(fence.join('\n')));
        fence.clear();
        fenced = false;
      } else {
        closeParagraph();
        closeList();
        fenced = true;
      }
      continue;
    }
    if (fenced) {
      fence.add(raw);
      continue;
    }
    if (trimmed.isEmpty) {
      closeParagraph();
      closeList();
      continue;
    }
    final RegExpMatch? heading = RegExp(
      r'^(#{1,6})\s+(.*)$',
    ).firstMatch(trimmed);
    if (heading != null) {
      closeParagraph();
      closeList();
      out.add(
        DVDocsHeading(
          heading.group(1)!.length,
          dvDocsInline(heading.group(2)!, line: number, code: code),
        ),
      );
      continue;
    }
    final RegExpMatch? bullet = RegExp(r'^[-*]\s+(.*)$').firstMatch(trimmed);
    final RegExpMatch? numbered = RegExp(r'^\d+\.\s+(.*)$').firstMatch(trimmed);
    if (bullet != null || numbered != null) {
      closeParagraph();
      final bool kind = bullet == null;
      if (ordered != null && ordered != kind) closeList();
      ordered = kind;
      items.add(
        DVDocsListItem(
          dvDocsInline(
            (bullet ?? numbered)!.group(1)!,
            line: number,
            code: code,
          ),
        ),
      );
      continue;
    }
    closeList();
    paragraph.add((line: number, text: trimmed));
  }
  if (fenced) out.add(DVDocsCode(fence.join('\n')));
  closeParagraph();
  closeList();
  return out;
}

/// The first `# heading` in [source], or null.
String? dvDocsMarkdownTitle(String source) {
  for (final String line in source.split('\n')) {
    final RegExpMatch? m = RegExp(r'^#{1,6}\s+(.+?)\s*$').firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}
