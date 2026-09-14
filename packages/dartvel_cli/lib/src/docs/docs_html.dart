/// HTML building blocks for the documentation site.
///
/// Everything that reaches a page from the project goes through [dvDocsText]
/// or [dvDocsAttr]. Doc comments and decision records are written by people,
/// and the site is meant to mount inside the application it documents, on
/// the application's own origin -- a doc comment that could inject a script
/// would run with the signed-in user's session.
library;

/// [value] escaped for element content.
String dvDocsText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// [value] escaped for a double-quoted attribute.
String dvDocsAttr(String value) => dvDocsText(value).replaceAll('"', '&quot;');

/// Renders one inline code span. [line] is the 1-based source line it is on.
typedef DVDocsCodeSpan = String Function(String code, int line);

String _plainCode(String code, int line) => '<code>${dvDocsText(code)}</code>';

/// A link target the site will emit: http(s), a fragment, or a relative
/// path. Anything with another scheme -- `javascript:` above all -- is
/// rendered as its text.
bool _safeHref(String href) {
  if (href.startsWith('http://') || href.startsWith('https://')) return true;
  if (href.startsWith('#')) return true;
  final int colon = href.indexOf(':');
  final int slash = href.indexOf('/');
  return colon == -1 || (slash != -1 && slash < colon);
}

/// One line of markdown-ish prose: code spans, `**strong**` and links.
String dvDocsInline(String text, {int line = 0, DVDocsCodeSpan? code}) {
  final DVDocsCodeSpan span = code ?? _plainCode;
  final StringBuffer out = StringBuffer();
  final List<String> parts = text.split('`');
  for (int i = 0; i < parts.length; i++) {
    // An unmatched trailing backtick is text, not the start of a span.
    final bool isCode = i.isOdd && i < parts.length - 1;
    if (isCode) {
      out.write(span(parts[i], line));
      continue;
    }
    String chunk = i.isOdd ? '`${parts[i]}' : parts[i];
    chunk = dvDocsText(chunk);
    chunk = chunk.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (Match m) => '<strong>${m.group(1)}</strong>',
    );
    chunk = chunk.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'), (
      Match m,
    ) {
      // Unescape only for the scheme check; the attribute is escaped again.
      final String href = m.group(2)!.replaceAll('&amp;', '&');
      if (!_safeHref(href)) return m.group(1)!;
      return '<a href="${dvDocsAttr(href)}">${m.group(1)}</a>';
    });
    out.write(chunk);
  }
  return out.toString();
}

/// The first `# heading` in [source], or null.
String? dvDocsMarkdownTitle(String source) {
  for (final String line in source.split('\n')) {
    final RegExpMatch? m = RegExp(r'^#{1,6}\s+(.+?)\s*$').firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}

/// A small, deliberately limited markdown renderer: headings, paragraphs,
/// bullet and numbered lists, fenced code, and the inline forms above.
///
/// Limited because what it renders is decision records and doc comments, and
/// because every construct it does not know is shown as text rather than
/// guessed at. [code] sees every inline code span with its source line, which
/// is how decision records find the graph nodes they name. Code inside a
/// fenced block is not a span and names nothing.
String dvDocsMarkdown(String source, {DVDocsCodeSpan? code}) {
  final List<String> lines = source.replaceAll('\r\n', '\n').split('\n');
  final StringBuffer out = StringBuffer();
  final List<String> paragraph = <String>[];
  String? list; // 'ul' or 'ol' while one is open
  bool fenced = false;
  final List<String> fence = <String>[];

  void closeParagraph() {
    if (paragraph.isEmpty) return;
    out.writeln('<p>${paragraph.join('\n')}</p>');
    paragraph.clear();
  }

  void closeList() {
    if (list == null) return;
    out.writeln('</$list>');
    list = null;
  }

  for (int i = 0; i < lines.length; i++) {
    final int number = i + 1;
    final String raw = lines[i];
    final String trimmed = raw.trim();

    if (trimmed.startsWith('```')) {
      if (fenced) {
        out.writeln('<pre><code>${dvDocsText(fence.join('\n'))}</code></pre>');
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
      final int level = heading.group(1)!.length;
      out.writeln(
        '<h$level>'
        '${dvDocsInline(heading.group(2)!, line: number, code: code)}</h$level>',
      );
      continue;
    }
    final RegExpMatch? bullet = RegExp(r'^[-*]\s+(.*)$').firstMatch(trimmed);
    final RegExpMatch? numbered = RegExp(r'^\d+\.\s+(.*)$').firstMatch(trimmed);
    if (bullet != null || numbered != null) {
      closeParagraph();
      final String kind = bullet != null ? 'ul' : 'ol';
      if (list != kind) {
        closeList();
        out.writeln('<$kind>');
        list = kind;
      }
      final String item = (bullet ?? numbered)!.group(1)!;
      out.writeln('<li>${dvDocsInline(item, line: number, code: code)}</li>');
      continue;
    }
    closeList();
    paragraph.add(dvDocsInline(trimmed, line: number, code: code));
  }
  if (fenced) {
    out.writeln('<pre><code>${dvDocsText(fence.join('\n'))}</code></pre>');
  }
  closeParagraph();
  closeList();
  return out.toString();
}

/// The site's pages, in navigation order.
const List<(String, String)> dvDocsNavigation = <(String, String)>[
  ('index.html', 'Overview'),
  ('models.html', 'Models'),
  ('functions.html', 'Functions'),
  ('routes.html', 'Routes'),
  ('jobs.html', 'Jobs and cron'),
  ('policies.html', 'Policies'),
  ('modules.html', 'Modules'),
  ('diagnostics.html', 'Diagnostics'),
];

const String _style = '''
:root{--bg:#fbfbfa;--fg:#1d1d1b;--muted:#63635e;--line:#e2e2dd;--code:#f1f1ee;--warn:#9a3b00}
@media (prefers-color-scheme: dark){:root{--bg:#161615;--fg:#ececea;--muted:#a3a39e;--line:#33332f;--code:#22221f;--warn:#ffab70}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 system-ui,sans-serif}
header,main{max-width:64rem;margin:0 auto;padding-inline:1rem}
header{border-bottom:1px solid var(--line);padding-block:.75rem}
nav a{margin-right:1rem;color:inherit}
main{padding-block:1rem 4rem}
section{border-top:1px solid var(--line);padding-block:1rem}
code,pre{background:var(--code);border-radius:4px;font:13px/1.45 ui-monospace,monospace}
code{padding:0 .25em}pre{padding:.75rem;overflow-x:auto}
table{border-collapse:collapse;display:block;overflow-x:auto}
th,td{border-bottom:1px solid var(--line);padding:.35rem .6rem;text-align:left;vertical-align:top}
.source,.unmapped{color:var(--muted);font-size:13px}
.badge{border:1px solid currentColor;border-radius:999px;padding:0 .45em;font-size:12px}
.sensitive .badge,.gone,.finding{color:var(--warn)}
''';

/// A whole page. [depth] is how many directories below the site root it is,
/// so every link stays relative and the site works wherever it is mounted.
String dvDocsPage({
  required String title,
  required String application,
  required String body,
  int depth = 0,
}) {
  final String up = '../' * depth;
  final String nav = dvDocsNavigation
      .map(((String, String) e) => '<a href="$up${e.$1}">${e.$2}</a>')
      .join('\n');
  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${dvDocsText(title)} · ${dvDocsText(application)}</title>
<style>$_style</style>
</head>
<body>
<header>
<strong>${dvDocsText(application)}</strong>
<nav>
$nav
</nav>
</header>
<main>
<h1>${dvDocsText(title)}</h1>
$body</main>
</body>
</html>
''';
}
