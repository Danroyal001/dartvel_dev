/// The text a page contains, taken from its source.
///
/// A Flutter web app has an empty body until JavaScript runs, so a crawler, a
/// link preview and a reader with scripting turned off all see nothing.
/// `dartvel prerender` can fix that, but it drives a real browser, and
/// `dartvel build web` does not run one — so pages shipped blank.
///
/// The generator already reads the page, and the text is in the source:
/// `DVText('...')` and `Text('...')` literals, in the order they are written.
/// That is not everything a rendered page says, and it is most of it, for the
/// cost of a regular expression rather than a browser.
library;

import 'dart:convert';

/// Every string literal in the source.
///
/// Not "the first argument of DVText or Text": matching framework widget
/// names is hardcoding one level down, and real pages wrap their text in
/// their own components -- Heading, Body, Eyebrow, a code block holding a
/// list of strings. A generator that knows only the framework's names finds
/// nothing on them, which is what the site's own pages returned.
///
/// So: take every literal and decide by what it looks like, not by what
/// enclosed it.
final RegExp _literal = RegExp(r'''(?:'([^'\\\n]*)'|"([^"\\\n]*)")''');

/// Lines that are code rather than content.
///
/// An import or a library directive, whose URI is a string literal nobody
/// should read on the page. And an annotation: `@pragma('vm:entry-point')`
/// put "vm:entry-point" at the top of every page, and `@DVPage(title: ...)`
/// repeated the title inside the body it already titles.
final RegExp _directive =
    RegExp(r'^\s*(?:@|import\b|export\b|part\b|library\b)', multiLine: true);

/// Strings that are on the page as data rather than as prose.
bool _isProse(String value) {
  final text = value.trim();
  if (text.isEmpty) return false;
  // A route, an asset, a colour, a key: present in the source, meaningless in
  // a paragraph, and actively misleading in a search result.
  if (text.startsWith('/') || text.startsWith('#')) return false;
  if (RegExp(r'^[\w./-]+\.(png|jpg|svg|webp|json|dart|css|js)$')
      .hasMatch(text)) {
    return false;
  }
  // A single token with no spaces that looks like an identifier rather than a
  // word — snake_case, a path fragment, a hex value.
  if (!text.contains(' ') && RegExp(r'[_/\\]|^[0-9A-Fa-f]{6}$').hasMatch(text)) {
    return false;
  }
  return true;
}

/// The prose in [source], in order, without repeats.
///
/// Interpolated strings are skipped. `'Loaded at: $when'` in a body is worse
/// than nothing: it is visibly broken text on a page a crawler is reading.
List<String> dvPageText(String source) {
  final found = <String>[];
  final seen = <String>{};

  // Directive lines removed first: a package URI is a string literal and is
  // not something anyone should read on the page.
  final body = source
      .split('\n')
      .where((String line) => !_directive.hasMatch(line))
      .join('\n');

  for (final RegExpMatch match in _literal.allMatches(body)) {
    final value = (match.group(1) ?? match.group(2) ?? '').trim();
    if (value.contains(r'$')) continue;
    if (!_isProse(value)) continue;
    if (seen.add(value)) found.add(value);
  }
  return found;
}

/// The fallback's own stylesheet.
///
/// The crawler-visible block is real semantic HTML -- headings, links, code
/// blocks -- and it shipped with none. Viewed with scripting off, or by
/// anything that does not run the app, every line ran the full width of the
/// window in the browser's default serif.
///
/// Inside the noscript block, deliberately. Outside it these rules would
/// apply to the running application too, and a max-width on body would break
/// every Dartvel app's own layout.
///
/// A reading column, a system font, and the reader's colour scheme. Nothing
/// decorative: this is the page someone sees when the app cannot run, and it
/// should look like a document rather than like a broken site.
const String dvFallbackStyle = '<style>'
    '.dv-fallback{max-width:44rem;margin:0 auto;padding:2rem 1.25rem;'
    'font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;'
    'color:#0b1020;background:#fff}'
    '.dv-fallback h1{font-size:1.9rem;line-height:1.2;margin:0 0 1rem}'
    '.dv-fallback h2{font-size:1.35rem;line-height:1.25;margin:2rem 0 .75rem}'
    '.dv-fallback h3{font-size:1.1rem;margin:1.5rem 0 .5rem}'
    '.dv-fallback p{margin:0 0 1rem}'
    '.dv-fallback a{color:#2f6bff}'
    '.dv-fallback pre{overflow-x:auto;padding:1rem;border-radius:8px;'
    'background:#0b1020;color:#c0caf5}'
    '.dv-fallback code{font:13.5px/1.6 ui-monospace,Menlo,Consolas,monospace}'
    '@media (prefers-color-scheme:dark){'
    '.dv-fallback{color:#f2f5fa;background:#0a0d13}'
    '.dv-fallback a{color:#7ba2ff}}'
    '</style>';

/// Markers, so a rebuild replaces the block rather than adding another.
const String _open = '<!-- dartvel:text -->';
const String _close = '<!-- /dartvel:text -->';

/// Put [lines] into [html] as a `noscript` block.
///
/// `noscript` rather than a hidden div: a hidden div is for crawlers, and this
/// is for people too — someone with scripting off gets the page's words
/// instead of a blank rectangle. Crawlers read it as readily.
String dvApplyPageText(String html, List<String> lines) {
  final cleaned =
      html.replaceAll(RegExp('$_open.*?$_close\n?', dotAll: true), '');
  if (lines.isEmpty) return cleaned;

  final at = cleaned.indexOf('</body>');
  // No body to put it in. Unchanged beats inventing structure around
  // someone's template.
  if (at < 0) return cleaned;

  const escape = HtmlEscape(HtmlEscapeMode.element);
  final buffer = StringBuffer()
    ..writeln(_open)
    ..writeln('<noscript>')
    ..writeln(dvFallbackStyle)
    ..writeln('<div class="dv-fallback">');
  // The first line is the page's own heading; a document with no h1 reads as
  // a fragment to a crawler.
  buffer.writeln('<h1>${escape.convert(lines.first)}</h1>');
  for (final String line in lines.skip(1)) {
    buffer.writeln('<p>${escape.convert(line)}</p>');
  }
  buffer
    ..writeln('</div>')
    ..writeln('</noscript>')
    ..writeln(_close);

  return '${cleaned.substring(0, at)}$buffer${cleaned.substring(at)}';
}

/// Put ready-made semantic HTML into the crawler-visible region.
///
/// [dvApplyPageText] escapes what it is given, because it is given plain
/// strings pulled out of the page source. The semantics tree produces markup
/// — headings, anchors, landmarks — and passing that through the same path
/// would ship `&lt;h2&gt;` on every page, which is worse than the paragraphs
/// it replaces.
///
/// Both write into the same marked region, so calling this after the text
/// extractor replaces its output rather than appending to it.
String dvApplyPageHtml(String html, String content) {
  final cleaned =
      html.replaceAll(RegExp('$_open.*?$_close\n?', dotAll: true), '');
  if (content.trim().isEmpty) return cleaned;

  final at = cleaned.indexOf('</body>');
  // No body to put it in. Unchanged beats inventing structure around
  // someone's template.
  if (at < 0) return cleaned;

  final buffer = StringBuffer()
    ..writeln(_open)
    ..writeln('<noscript>')
    ..writeln(dvFallbackStyle)
    ..writeln('<div class="dv-fallback">')
    ..writeln(content.trim())
    ..writeln('</div>')
    ..writeln('</noscript>')
    ..writeln(_close);
  return cleaned.substring(0, at) + buffer.toString() + cleaned.substring(at);
}
