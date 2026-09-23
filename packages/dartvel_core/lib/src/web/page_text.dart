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

/// The fallback's own stylesheet, and the rules that print it.
///
/// The crawler-visible block is real semantic HTML -- headings, links, code
/// blocks -- and it shipped with none. Viewed with scripting off, or by
/// anything that does not run the app, every line ran the full width of the
/// window in the browser's default serif.
///
/// Every rule is scoped to `.dv-fallback`, so none of it reaches the running
/// application: a `max-width` on `body` would break every Dartvel app's own
/// layout, and nothing here sets one.
///
/// The block is hidden from the screen and shown again in two places. A
/// reader with scripting off gets it from the `<noscript>` override below,
/// which is the one thing noscript is still needed for. A printer gets it
/// from the `@media print` rules, which also take away what Flutter paints
/// into: a canvas prints as one bitmap the width of the window -- clipped, at
/// screen resolution, with no text to select and no page break anywhere
/// sensible. The page's own HTML is already here; printing it is a
/// stylesheet, not a feature.
///
/// A reading column, a system font, and the reader's colour scheme. Nothing
/// decorative: this is the page someone sees when the app cannot run, and it
/// should look like a document rather than like a broken site.
const String dvFallbackStyle = '<style class="dv-fallback-style">'
    // In the document, off the screen. The application is what the reader
    // came for; this is what the crawler, the printer and a browser with no
    // scripting get instead.
    '.dv-fallback{display:none}'
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
    // What the printer is given. Flutter's own host elements go first: they
    // are what the page looks like and not what it says.
    '@media print{'
    'flutter-view,flt-glass-pane,flt-scene-host,flt-semantics-host,canvas'
    '{display:none!important}'
    '.dv-fallback{display:block!important;max-width:none;margin:0;padding:0;'
    'color:#000;background:#fff;font-size:11pt}'
    '.dv-fallback a{color:#000;text-decoration:underline}'
    // Nobody clicks a printed link, so it has to say where it went.
    '.dv-fallback a[href]::after{content:" (" attr(href) ")";font-size:.85em}'
    '.dv-fallback pre{background:#fff;color:#000;border:1px solid #999;'
    'white-space:pre-wrap}'
    '.dv-fallback h1,.dv-fallback h2,.dv-fallback h3{break-after:avoid}'
    '@page{margin:18mm}'
    '}'
    '</style>'
    // The reader whose browser will never run the app. A style element here
    // rather than the content itself: the content is in the document now, and
    // this only turns it back on.
    '<noscript class="dv-fallback-style">'
    '<style>.dv-fallback{display:block}</style></noscript>';

/// Whether the block a page was served with is no longer the page on screen.
///
/// The application routes on the client, so one navigation later the block in
/// the document describes the page the reader arrived on. Printing that is a
/// worse answer than printing nothing, and it is the kind that looks right:
/// the right title in the tab, somebody else's page on the paper. [stamped]
/// is what the build wrote on the block, [current] is where the reader is.
///
/// Nothing stamped means nothing to compare, and a block dropped on a guess
/// is a page that stops printing for no reason.
bool dvFallbackIsStale(String? stamped, String current) {
  if (stamped == null || stamped.isEmpty) return false;
  String trim(String path) {
    final String trimmed = path.replaceAll(RegExp(r'/+$'), '');
    return trimmed.isEmpty ? '/' : trimmed;
  }

  return trim(stamped) != trim(current);
}

/// The block's opening tag, carrying the path it was written for.
String _openFallback(String? path) {
  if (path == null || path.isEmpty) return '<div class="dv-fallback">';
  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  return '<div class="dv-fallback" data-dv-path="${escape.convert(path)}">';
}

/// Markers, so a rebuild replaces the block rather than adding another.
const String _open = '<!-- dartvel:text -->';
const String _close = '<!-- /dartvel:text -->';

/// Put [lines] into [html] as the page's own document.
///
/// In the document rather than inside `<noscript>`: a browser that is running
/// the app does not parse noscript content into the page at all, so nothing
/// there can be styled, read by a screen reader or printed. It is hidden from
/// the screen by [dvFallbackStyle], shown again for a reader with scripting
/// off, and shown again for a printer -- which is the only copy of the page
/// worth printing, since the app itself is a canvas.
String dvApplyPageText(String html, List<String> lines, {String? path}) {
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
    ..writeln(dvFallbackStyle)
    ..writeln(_openFallback(path));
  // The first line is the page's own heading; a document with no h1 reads as
  // a fragment to a crawler.
  buffer.writeln('<h1>${escape.convert(lines.first)}</h1>');
  for (final String line in lines.skip(1)) {
    buffer.writeln('<p>${escape.convert(line)}</p>');
  }
  buffer
    ..writeln('</div>')
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
String dvApplyPageHtml(String html, String content, {String? path}) {
  final cleaned =
      html.replaceAll(RegExp('$_open.*?$_close\n?', dotAll: true), '');
  if (content.trim().isEmpty) return cleaned;

  final at = cleaned.indexOf('</body>');
  // No body to put it in. Unchanged beats inventing structure around
  // someone's template.
  if (at < 0) return cleaned;

  final buffer = StringBuffer()
    ..writeln(_open)
    ..writeln(dvFallbackStyle)
    ..writeln(_openFallback(path))
    ..writeln(content.trim())
    ..writeln('</div>')
    ..writeln(_close);
  return cleaned.substring(0, at) + buffer.toString() + cleaned.substring(at);
}
