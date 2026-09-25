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
