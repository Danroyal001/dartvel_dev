/// What a build leaves in build/web, without the indentation.
///
/// `dartvel build web` and `dartvel build web-server` both finish by writing
/// HTML, CSS and JavaScript that a reader downloads on the first request. The
/// pass here takes the whitespace and the comments back out of them. The
/// web-server target is covered by the same pass: it renders a page from
/// build/web/index.html on request, so a minified shell is a minified page.
///
/// It is deliberately a whitespace-and-comments minifier and not a compressor.
/// It does not rename a variable, fold a constant or drop dead code, because
/// doing any of that safely needs a parser for the whole language and the
/// files it is pointed at are small: a shell, a service worker, a stylesheet.
/// The one file where compression would pay -- main.dart.js -- arrives already
/// minified by dart2js and is skipped.
///
/// Every scanner here is written around the cases where a wrong answer still
/// looks like the language: a descendant selector whose space was taken, a
/// `calc()` whose operators lost theirs, a `//` inside a string read as a
/// comment, two statements joined across the newline that was standing in for
/// a semicolon. A minifier that throws is a bug that gets fixed; one that
/// silently changes what a page means is a bug that ships.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// What a pass over a built web output changed.
class DVMinifyReport {
  const DVMinifyReport({required this.files, required this.saved});

  /// How many files were rewritten. A file that was already as small as the
  /// pass can make it is not counted, because it was not touched.
  final int files;

  /// Bytes the rewritten files no longer carry.
  final int saved;

  /// Nothing to report, for a build that asked not to be minified.
  static const DVMinifyReport none = DVMinifyReport(files: 0, saved: 0);
}

/// Elements whose surrounding whitespace is part of the sentence.
///
/// `<span>a</span> <span>b</span>` reads "a b"; dropping that space runs the
/// two words together, which is exactly the kind of change that renders
/// without complaint. Between anything else -- a div, a section, a list item
/// -- the whitespace is indentation and goes.
const Set<String> _inline = <String>{
  'a', 'abbr', 'b', 'bdi', 'bdo', 'big', 'br', 'button', 'cite', 'code',
  'data', 'del', 'dfn', 'em', 'font', 'i', 'img', 'input', 'ins', 'kbd',
  'label', 'map', 'mark', 'meter', 'output', 'picture', 'q', 'ruby', 's',
  'samp', 'select', 'small', 'span', 'strong', 'sub', 'sup', 'svg', 'textarea',
  'time', 'tt', 'u', 'var', 'wbr',
};

/// Elements whose contents are not markup and are copied as they were typed.
const Set<String> _verbatim = <String>{'pre', 'textarea'};

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\f';

/// [html] without its comments, its indentation or the whitespace between
/// its tags, with `<pre>` and `<textarea>` left exactly as they were written
/// and inline `<style>` and `<script>` blocks minified as what they are.
String dvMinifyHtml(String html) {
  final StringBuffer out = StringBuffer();
  // The tag last written, and the one coming, decide whether the whitespace
  // between them was a word break or an indent.
  String previousTag = '';
  int i = 0;

  while (i < html.length) {
    final String c = html[i];

    if (c == '<') {
      // A comment. `<!--[if IE]>` is markup a browser acts on, not a note.
      if (html.startsWith('<!--', i)) {
        final int end = html.indexOf('-->', i + 4);
        final int stop = end < 0 ? html.length : end + 3;
        if (html.startsWith('<!--[', i)) out.write(html.substring(i, stop));
        i = stop;
        continue;
      }
      final int close = _tagEnd(html, i);
      final String tag = html.substring(i, close);
      final String name = _tagName(tag);
      out.write(tag);
      i = close;

      if (_verbatim.contains(name) && !tag.startsWith('</')) {
        final int end = _closingTag(html, name, i);
        out.write(html.substring(i, end));
        i = end;
        previousTag = name;
        continue;
      }
      if ((name == 'script' || name == 'style') && !tag.startsWith('</')) {
        final int end = _closingTag(html, name, i);
        final String body = html.substring(i, end == html.length ? end : _bodyEnd(html, name, i));
        final String minified = name == 'style'
            ? dvMinifyCss(body)
            : _isJsonScript(tag)
                ? _minifyJson(body)
                : dvMinifyJs(body);
        out.write(minified);
        i = i + body.length;
        previousTag = name;
        continue;
      }
      previousTag = name;
      continue;
    }

    // A text node, up to the next tag.
    final int next = html.indexOf('<', i);
    final int stop = next < 0 ? html.length : next;
    final String text = html.substring(i, stop);
    i = stop;
    final String collapsed = _collapse(text);
    if (collapsed.trim().isEmpty) {
      // Whitespace on its own. Keep one space only where both sides are
      // elements that sit in a line of text.
      final String nextTag = next < 0 ? '' : _tagName(html.substring(next, _tagEnd(html, next)));
      final bool between = _inline.contains(previousTag) && _inline.contains(nextTag);
      if (between && collapsed.isNotEmpty) out.write(' ');
      continue;
    }
    out.write(collapsed);
  }
  return out.toString();
}

/// Whitespace runs in [text] as one space each, the leading and trailing runs
/// included: `Read ` before a link is a word break and `one\n  two` is one.
String _collapse(String text) {
  if (text.isEmpty) return '';
  final bool leading = _isSpace(text[0]);
  final bool trailing = _isSpace(text[text.length - 1]);
  final List<String> words =
      text.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();
  if (words.isEmpty) return ' ';
  return '${leading ? ' ' : ''}${words.join(' ')}${trailing ? ' ' : ''}';
}

/// The index just past the `>` that closes the tag opening at [start], with
/// quoted attribute values skipped so a `>` inside one does not end it.
int _tagEnd(String html, int start) {
  String? quote;
  for (int i = start + 1; i < html.length; i++) {
    final String c = html[i];
    if (quote != null) {
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      continue;
    }
    if (c == '>') return i + 1;
  }
  return html.length;
}

/// The lower-case name of the element [tag] opens or closes.
String _tagName(String tag) {
  int i = 1;
  if (i < tag.length && tag[i] == '/') i++;
  final int start = i;
  while (i < tag.length && !_isSpace(tag[i]) && tag[i] != '>' && tag[i] != '/') {
    i++;
  }
  return tag.substring(start, i).toLowerCase();
}

/// Where the `</[name]>` after [from] begins, or the end of [html].
int _bodyEnd(String html, String name, int from) {
  final int at = html.toLowerCase().indexOf('</$name', from);
  return at < 0 ? html.length : at;
}

/// Where the content that started at [from] ends, the closing tag included.
int _closingTag(String html, String name, int from) {
  final int at = _bodyEnd(html, name, from);
  if (at == html.length) return html.length;
  return _tagEnd(html, at);
}

/// Whether [tag] opens a script holding data rather than code: structured
/// data, a state blob, an import map. Minifying those as JavaScript would
/// strip nothing and risks reading a `//` inside a URL as a comment.
bool _isJsonScript(String tag) {
  final String lower = tag.toLowerCase();
  return lower.contains('application/ld+json') ||
      lower.contains('application/json') ||
      lower.contains('importmap') ||
      lower.contains('speculationrules');
}

/// [json] without the whitespace outside its strings.
String _minifyJson(String json) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < json.length; i++) {
    final String c = json[i];
    if (c == '"') {
      final int end = _stringEnd(json, i, '"');
      out.write(json.substring(i, end));
      i = end - 1;
      continue;
    }
    if (_isSpace(c)) continue;
    out.write(c);
  }
  return out.toString();
}

/// The index just past the quote that closes the string opening at [start],
/// with backslash escapes skipped.
int _stringEnd(String source, int start, String quote) {
  for (int i = start + 1; i < source.length; i++) {
    if (source[i] == r'\') {
      i++;
      continue;
    }
    if (source[i] == quote) return i + 1;
  }
  return source.length;
}

/// [css] without its comments or the whitespace that only made it readable.
///
/// The spaces that carry meaning stay: the one between `nav` and `a` that
/// makes a descendant selector, the ones around the operators in `calc()`,
/// and every character inside a string.
String dvMinifyCss(String css) {
  final StringBuffer out = StringBuffer();
  int depth = 0;
  int parens = 0;
  bool space = false;
  // Nothing needs a space before it at the start of a file, and nothing needs
  // one after a brace, a semicolon or a comma.
  bool tightAfter = true;

  for (int i = 0; i < css.length; i++) {
    final String c = css[i];

    if (c == '/' && i + 1 < css.length && css[i + 1] == '*') {
      final int end = css.indexOf('*/', i + 2);
      i = end < 0 ? css.length : end + 1;
      // A comment separates two tokens exactly as whitespace does.
      space = true;
      continue;
    }
    if (_isSpace(c)) {
      space = true;
      continue;
    }

    // In a declaration or inside parentheses, `:` separates a property from
    // its value. In a selector it starts a pseudo-class, where the space in
    // `p :first-child` is a combinator and not decoration.
    final bool inValue = depth > 0 || parens > 0;
    final bool selector = depth == 0 && parens == 0;
    final bool combinator = selector && (c == '>' || c == '+' || c == '~');
    final bool tightBefore =
        c == '{' || c == '}' || c == ';' || c == ',' || c == ')' || (c == ':' && inValue) || combinator;
    final bool nowTightAfter =
        c == '{' || c == '}' || c == ';' || c == ',' || c == '(' || (c == ':' && inValue) || combinator;

    if (c == '}') {
      // The last declaration's semicolon closes nothing.
      final String written = out.toString();
      if (written.endsWith(';')) {
        out.clear();
        out.write(written.substring(0, written.length - 1));
      }
    }

    if (space && !tightBefore && !tightAfter && out.isNotEmpty) out.write(' ');
    space = false;

    if (c == '"' || c == "'") {
      final int end = _stringEnd(css, i, c);
      out.write(css.substring(i, end));
      i = end - 1;
      tightAfter = false;
      continue;
    }

    out.write(c);
    tightAfter = nowTightAfter;

    if (c == '{') depth++;
    if (c == '}' && depth > 0) depth--;
    if (c == '(') parens++;
    if (c == ')' && parens > 0) parens--;
  }
  return out.toString().trim();
}

/// [js] without its comments and without the indentation, and with every
/// line it had.
///
/// Lines are never joined. JavaScript inserts semicolons at newlines, so
/// `const a = 1` followed by `const b = 2` is two statements on two lines and
/// one syntax error on one. Nothing inside a string, a template literal or a
/// regular expression is touched.
String dvMinifyJs(String js) {
  final StringBuffer out = StringBuffer();
  bool space = false;
  bool newline = false;
  // What was written last decides whether the next `/` opens a regular
  // expression or divides: `return /x/` is a pattern, `a / x` is division.
  String previous = '';

  void flush() {
    if (out.isEmpty) return;
    if (newline) {
      out.write('\n');
    } else if (space) {
      out.write(' ');
    }
    space = false;
    newline = false;
  }

  void write(String text) {
    flush();
    out.write(text);
    previous = text.trimRight();
    space = false;
    newline = false;
  }

  for (int i = 0; i < js.length; i++) {
    final String c = js[i];

    if (c == '/' && i + 1 < js.length && js[i + 1] == '/') {
      final int end = js.indexOf('\n', i);
      i = end < 0 ? js.length : end - 1;
      space = true;
      continue;
    }
    if (c == '/' && i + 1 < js.length && js[i + 1] == '*') {
      final int end = js.indexOf('*/', i + 2);
      final String comment = js.substring(i, end < 0 ? js.length : end + 2);
      if (comment.contains('\n')) newline = true;
      space = true;
      i = end < 0 ? js.length : end + 1;
      continue;
    }
    if (c == '\n') {
      newline = true;
      space = true;
      continue;
    }
    if (_isSpace(c)) {
      space = true;
      continue;
    }
    if (c == '"' || c == "'") {
      final int end = _stringEnd(js, i, c);
      write(js.substring(i, end));
      i = end - 1;
      continue;
    }
    if (c == '`') {
      final int end = _templateEnd(js, i);
      write(js.substring(i, end));
      i = end - 1;
      continue;
    }
    if (c == '/' && _regexCanStart(previous)) {
      final int end = _regexEnd(js, i);
      write(js.substring(i, end));
      i = end - 1;
      continue;
    }
    write(c);
  }
  return out.toString();
}

/// Whether a `/` written after [previous] opens a regular expression.
bool _regexCanStart(String previous) {
  if (previous.isEmpty) return true;
  final String last = previous[previous.length - 1];
  if ('(,=:[!&|?{};+-*%^~<>'.contains(last)) return true;
  // `return /x/` and `typeof /x/` are patterns; `a /x/` is two divisions.
  for (final String word in const <String>[
    'return', 'typeof', 'case', 'in', 'of', 'new', 'delete', 'void',
    'instanceof', 'do', 'else', 'yield', 'await', 'throw',
  ]) {
    if (previous == word || previous.endsWith(' $word')) return true;
  }
  return false;
}

/// The index just past the backtick closing the template starting at [start],
/// with `${...}` interpolations -- which may hold another template -- spanned.
int _templateEnd(String js, int start) {
  int braces = 0;
  for (int i = start + 1; i < js.length; i++) {
    final String c = js[i];
    if (c == r'\') {
      i++;
      continue;
    }
    if (braces == 0 && c == '`') return i + 1;
    if (c == r'$' && i + 1 < js.length && js[i + 1] == '{') {
      braces++;
      i++;
      continue;
    }
    if (braces > 0) {
      if (c == '{') braces++;
      if (c == '}') braces--;
      if (c == '`') i = _templateEnd(js, i) - 1;
    }
  }
  return js.length;
}

/// The index just past the `/` closing the regular expression at [start], its
/// flags included, with escapes and character classes spanned.
int _regexEnd(String js, int start) {
  bool inClass = false;
  for (int i = start + 1; i < js.length; i++) {
    final String c = js[i];
    if (c == r'\') {
      i++;
      continue;
    }
    if (c == '\n') return start + 1;
    if (c == '[') inClass = true;
    if (c == ']') inClass = false;
    if (c == '/' && !inClass) {
      int end = i + 1;
      while (end < js.length && RegExp('[a-z]').hasMatch(js[end])) {
        end++;
      }
      return end;
    }
  }
  return js.length;
}

/// Minifies every page, stylesheet and script under [web] that the build
/// itself wrote, and reports what that came to.
///
/// What it leaves alone is as much of the contract as what it rewrites: the
/// compiler's own output, which dart2js has already minified and which is
/// large enough that a second pass could only cost time or correctness, and
/// the application's bundled assets, which are its files rather than the
/// page's -- a `.css` under assets/ may be a sample the app reads back and
/// compares.
DVMinifyReport dvMinifyWebOutput(Directory web) {
  if (!web.existsSync()) return DVMinifyReport.none;
  int files = 0;
  int saved = 0;

  for (final FileSystemEntity entity in web.listSync(recursive: true)) {
    if (entity is! File) continue;
    final String relative = p.relative(entity.path, from: web.path);
    if (_leaveAlone(relative)) continue;
    final String extension = p.extension(relative).toLowerCase();

    String source;
    try {
      source = entity.readAsStringSync();
    } on FileSystemException {
      // Not text, whatever it is named. A build that stops here has minified
      // nothing and broken something.
      continue;
    } on FormatException {
      continue;
    }

    final String minified = switch (extension) {
      '.html' || '.htm' => dvMinifyHtml(source),
      '.css' => dvMinifyCss(source),
      '.js' || '.mjs' => dvMinifyJs(source),
      _ => source,
    };
    if (minified.length >= source.length) continue;

    entity.writeAsStringSync(minified);
    files++;
    saved += source.length - minified.length;
  }
  return DVMinifyReport(files: files, saved: saved);
}

/// Whether [relative] is a file the pass does not own.
bool _leaveAlone(String relative) {
  final List<String> parts = p.split(relative);
  // The application's own files, and the engine's.
  if (parts.first == 'assets') return true;
  if (parts.contains('canvaskit') || parts.contains('skwasm')) return true;

  final String name = parts.last;
  if (name.endsWith('.min.js') || name.endsWith('.min.css')) return true;
  // dart2js output, including the deferred parts it splits off.
  if (name.startsWith('main.dart.')) return true;
  // The loader and the bootstrap belong to the Flutter tool.
  // flutter_service_worker.js is not in this list on purpose: the name is
  // Flutter's, the file is Dartvel's, written over theirs by the PWA pass.
  if (name == 'flutter.js' || name == 'flutter_bootstrap.js') return true;
  return false;
}
