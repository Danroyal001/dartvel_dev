/// The rows of a page's lazy collections, read from its server-rendered
/// document.
///
/// A long DVBox collection builds only the rows near the screen. A row that
/// is not built has no semantics node and no text, so a screen reader reading
/// line by line stopped at the last row built, and the browser's find after a
/// navigation inside the app searched only what was drawn. Building the rest
/// while the page is idle reached them, at about 20 ms of main thread a row
/// (Dartvel 3.47.9 shipped it off by default for that).
///
/// The document the server sends for every route already holds every row:
/// the build captures each page whole. So the build marks where each lazy
/// collection and each of its rows start and end, and the running app reads
/// an unbuilt row's links, headings and text from the document instead of
/// building it. The marks are comments the minifier keeps (`dartvel:` is the
/// shape it keeps), so nothing a reader, a crawler or a stylesheet sees
/// changes:
///
/// ```html
/// <!-- dartvel:rows -->
///   <!-- dartvel:row --> ...row 0... <!-- /dartvel:row -->
///   <!-- dartvel:row --> ...row 1... <!-- /dartvel:row -->
/// <!-- /dartvel:rows -->
/// ```
///
/// This file is the plain-Dart half: reading the marks. The widgets that
/// stand in for unbuilt rows live in dartvel_flutter.
library;

/// The mark opening a lazy collection's rows in the document.
const String dvRowsOpen = '<!-- dartvel:rows -->';

/// The mark closing a lazy collection's rows.
const String dvRowsClose = '<!-- /dartvel:rows -->';

/// The mark opening one row.
const String dvRowOpen = '<!-- dartvel:row -->';

/// The mark closing one row.
const String dvRowClose = '<!-- /dartvel:row -->';

/// One thing a row says: a link, a heading or a paragraph.
class DVDocumentRowPart {
  const DVDocumentRowPart(this.text, {this.href, this.headingLevel});

  /// What a screen reader reads.
  final String text;

  /// Where a link goes; null for anything else.
  final String? href;

  /// 1 to 6 for a heading; null for anything else.
  final int? headingLevel;

  @override
  String toString() => href != null
      ? 'link($text -> $href)'
      : headingLevel != null
      ? 'h$headingLevel($text)'
      : text;
}

final RegExp _token = RegExp(r'<!--(.*?)-->|<(/?)([A-Za-z][A-Za-z0-9-]*)\b([^>]*?)(/?)>', dotAll: true);

/// Elements whose text is part of whatever paragraph holds them.
const Set<String> _inline = <String>{
  'a', 'abbr', 'b', 'bdi', 'bdo', 'br', 'cite', 'code', 'data', 'dfn', 'em', //
  'i', 'kbd', 'label', 'mark', 'q', 's', 'samp', 'small', 'span', 'strong',
  'sub', 'sup', 'time', 'u', 'var', 'wbr', 'img',
};

/// Elements nothing in reads: copied over whole.
const Set<String> _skipped = <String>{'style', 'script', 'template', 'noscript', 'svg'};

const Set<String> _void = <String>{
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', //
  'source', 'track', 'wbr',
};

String _attribute(String attributes, String name) {
  final RegExpMatch? match =
      RegExp('\\b$name\\s*=\\s*"([^"]*)"').firstMatch(attributes);
  return match == null ? '' : _decode(match.group(1)!);
}

String _decode(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// A lazy collection the document marks: its rows, in order.
class DVDocumentCollection {
  DVDocumentCollection();

  final List<DVDocumentRow> rows = <DVDocumentRow>[];
}

/// One row of a lazy collection, as the document has it.
class DVDocumentRow {
  DVDocumentRow();

  /// What it says, in reading order, the rows of any collection inside it
  /// included: what stands in for it while it is not built.
  final List<DVDocumentRowPart> parts = <DVDocumentRowPart>[];

  /// The lazy collections inside it, for when it is built and they are not.
  final List<DVDocumentCollection> collections = <DVDocumentCollection>[];
}

/// Every top-level lazy collection [document] marks, in document order:
/// each its rows, each row what it says in reading order and the
/// collections inside it.
///
/// A collection inside a row is that row's: when the row is not built, the
/// collection does not exist in the app, and its words are the row's. What is
/// hidden from readers (`aria-hidden`), styles and scripts say nothing.
List<DVDocumentCollection> dvDocumentRows(String document) {
  final List<DVDocumentCollection> top = <DVDocumentCollection>[];
  // The open marks, innermost last: a collection, or a row in one.
  final List<DVDocumentCollection> collections = <DVDocumentCollection>[];
  final List<DVDocumentRow> rows = <DVDocumentRow>[];
  // Each open collection's depth in rows when it opened.
  final List<int> rowDepthAt = <int>[];

  // The paragraph being read.
  final StringBuffer text = StringBuffer();
  String? href;
  int? heading;
  // An element skipped whole, and how deep in it the scanner is.
  String? skip;
  int skipDepth = 0;

  void add(DVDocumentRowPart part) {
    // Every open row says it: the inner row, and each row it is inside.
    for (final DVDocumentRow row in rows) {
      row.parts.add(part);
    }
  }

  void flush() {
    final String said = _clean(text.toString());
    text.clear();
    if (said.isNotEmpty) add(DVDocumentRowPart(said, href: href, headingLevel: heading));
  }

  int cursor = 0;
  for (final RegExpMatch match in _token.allMatches(document)) {
    if (skip == null && rows.isNotEmpty && match.start > cursor) {
      text.write(_decode(document.substring(cursor, match.start)));
    }
    cursor = match.end;
    final String? comment = match.group(1)?.trim();
    if (comment != null) {
      if (skip != null) continue;
      switch (comment) {
        case 'dartvel:rows':
          flush();
          final DVDocumentCollection collection = DVDocumentCollection();
          if (rows.isEmpty) {
            top.add(collection);
          } else {
            rows.last.collections.add(collection);
          }
          collections.add(collection);
          rowDepthAt.add(rows.length);
        case '/dartvel:rows':
          flush();
          if (collections.isNotEmpty) {
            collections.removeLast();
            final int depth = rowDepthAt.removeLast();
            // A row left open inside it ends with it.
            while (rows.length > depth) {
              rows.removeLast();
            }
          }
        case 'dartvel:row':
          flush();
          if (collections.isNotEmpty && rows.length == rowDepthAt.last) {
            final DVDocumentRow row = DVDocumentRow();
            collections.last.rows.add(row);
            rows.add(row);
            href = null;
            heading = null;
          }
        case '/dartvel:row':
          flush();
          if (collections.isNotEmpty && rows.length > rowDepthAt.last) rows.removeLast();
      }
      continue;
    }
    final bool closing = match.group(2) == '/';
    final String name = match.group(3)!.toLowerCase();
    final String attributes = match.group(4) ?? '';
    final bool selfClosing = match.group(5) == '/' || _void.contains(name);
    if (skip != null) {
      if (name == skip && !selfClosing) {
        skipDepth += closing ? -1 : 1;
        if (skipDepth == 0) skip = null;
      }
      continue;
    }
    if (!closing && !selfClosing &&
        (_skipped.contains(name) || attributes.contains('aria-hidden="true"'))) {
      skip = name;
      skipDepth = 1;
      continue;
    }
    if (rows.isEmpty) continue;
    if (name == 'a') {
      // A link is its own part: its words, where it goes.
      flush();
      if (closing) {
        href = null;
        continue;
      }
      final String label = _attribute(attributes, 'aria-label');
      if (label.isNotEmpty) {
        // Its name, as the app reads it; its text would say it again.
        add(DVDocumentRowPart(_clean(label), href: _attribute(attributes, 'href')));
        skip = 'a';
        skipDepth = 1;
      } else {
        href = _attribute(attributes, 'href');
      }
      continue;
    }
    final RegExpMatch? level = RegExp(r'^h([1-6])$').firstMatch(name);
    if (level != null) {
      flush();
      heading = closing ? null : int.parse(level.group(1)!);
      continue;
    }
    if (name == 'br') {
      text.write(' ');
      continue;
    }
    // Any other block starts or ends a paragraph.
    if (!_inline.contains(name)) flush();
  }
  flush();
  return top;
}

/// The document a page the server sent carries for its route: the content of
/// its `.dv-fallback` block, less what only the SSR-first first paint needs
/// (its stylesheets and picture layer). Null when the page has none.
String? dvDocumentOfPage(String page) {
  final int open = page.indexOf('<!-- dartvel:text -->');
  if (open < 0) return null;
  final int close = page.indexOf('<!-- /dartvel:text -->', open);
  if (close < 0) return null;
  final String region = page.substring(open, close);
  final RegExpMatch? block = RegExp(r'<div class="dv-fallback"[^>]*>').firstMatch(region);
  if (block == null) return null;
  final int end = region.lastIndexOf('</div>');
  if (end < block.end) return null;
  return region
      .substring(block.end, end)
      .replaceAll(RegExp(r'<(style|script)\b[^>]*>.*?</\1>', dotAll: true), '')
      .replaceAll(RegExp(r'<div class="dvp"[^>]*>.*?</div>', dotAll: true), '')
      .trim();
}
