/// A project's own HTML at the three edges of every web page: inside
/// `<head>`, right after `<body>` opens and right before `</body>` closes
/// (`dartvel.platforms.web.document`, see `DVWebDocumentSlots`).
///
/// The build writes the snippets into the shell once, with [dvApplyDocumentSlots],
/// and the shell is what every page is made from: the static build's
/// prerendered pages, the web server's pages rendered on request, the not-found
/// and offline pages, Studio's own screens. So the snippets are in the
/// server-rendered document from the first byte, and Flutter starting up
/// later neither removes them nor runs them a second time: they are parsed
/// once, by the browser, with the page.
///
/// Each slot sits between `<!-- dartvel:<slot> -->` markers, which the
/// minifier copies verbatim (a vendor's script runs exactly as written, and
/// the hash a policy lists for it is the hash of what the browser receives),
/// and which keep the body-end slot after the page's own document.
library;

import '../config/platforms.dart' show DVHtmlSnippet, DVWebDocumentSlots;
import 'csp_sources.dart' show dvAddContentSecurityPolicySources, dvAddContentSecurityPolicyHashes;
import 'inline_script_csp.dart' show dvInlineScriptsSource, dvInlineScriptHashes;

/// One of the three edges.
enum DVDocumentSlot {
  head('head', 'head'),
  bodyStart('bodyStart', 'body-start'),
  bodyEnd('bodyEnd', 'body-end');

  const DVDocumentSlot(this.key, this.marker);

  /// The key under `dartvel.platforms.web.document`.
  final String key;

  /// The name in the page's markers, `<!-- dartvel:body-end -->`.
  final String marker;

  String get open => '<!-- dartvel:$marker -->';
  String get close => '<!-- /dartvel:$marker -->';
}

/// Whether [comment] opens one of the slot regions the minifier must copy
/// as written; the matching close marker when it does.
String? dvDocumentSlotCloseFor(String comment) {
  for (final DVDocumentSlot slot in DVDocumentSlot.values) {
    if (comment == slot.open) return slot.close;
  }
  return null;
}

/// Where content that belongs at the end of the body goes: before the
/// body-end slot when the page has one, so that slot stays last, and before
/// `</body>` otherwise. -1 when the page has no body.
int dvBodyEndInsertionPoint(String html) {
  final int slot = html.lastIndexOf(DVDocumentSlot.bodyEnd.open);
  if (slot >= 0) return slot;
  return html.indexOf('</body>');
}

/// The HTML each slot resolves to: inline snippets as written, file snippets
/// through [readFile], in order.
Map<DVDocumentSlot, String> dvResolveDocumentSlots(
  DVWebDocumentSlots slots, {
  String Function(String path)? readFile,
}) => <DVDocumentSlot, String>{
  for (final DVDocumentSlot slot in DVDocumentSlot.values)
    slot: <String>[
      for (final DVHtmlSnippet snippet in slots.of(slot))
        snippet.html ??
            (readFile ??
                (String path) => throw ArgumentError.value(path, 'readFile', 'is needed to read a snippet file'))(
              snippet.file!.path,
            ),
    ].join('\n'),
};

/// [html] with [slots] at their edges, replacing any slots it already had, so
/// a build over a previous build's output does not add a second copy.
String dvApplyDocumentSlots(String html, DVWebDocumentSlots slots, {String Function(String path)? readFile}) {
  final Map<DVDocumentSlot, String> resolved = dvResolveDocumentSlots(slots, readFile: readFile);
  String out = html;
  for (final DVDocumentSlot slot in DVDocumentSlot.values) {
    out = out.replaceAll(
      // With the line break the slot was written with, and only that one.
      RegExp(
        '${RegExp.escape(slot.open)}.*?${RegExp.escape(slot.close)}${slot == DVDocumentSlot.bodyStart ? '' : r'\n?'}',
        dotAll: true,
      ),
      '',
    );
  }
  String region(DVDocumentSlot slot) => '${slot.open}${resolved[slot]}${slot.close}';

  final String head = resolved[DVDocumentSlot.head]!;
  if (head.trim().isNotEmpty) {
    final int at = out.indexOf('</head>');
    if (at >= 0) out = '${out.substring(0, at)}${region(DVDocumentSlot.head)}\n${out.substring(at)}';
  }
  final String start = resolved[DVDocumentSlot.bodyStart]!;
  if (start.trim().isNotEmpty) {
    final RegExpMatch? body = RegExp(r'<body\b[^>]*>', caseSensitive: false).firstMatch(out);
    if (body != null)
      out = '${out.substring(0, body.end)}${region(DVDocumentSlot.bodyStart)}${out.substring(body.end)}';
  }
  final String end = resolved[DVDocumentSlot.bodyEnd]!;
  if (end.trim().isNotEmpty) {
    final int at = out.lastIndexOf('</body>');
    if (at >= 0) out = '${out.substring(0, at)}${region(DVDocumentSlot.bodyEnd)}\n${out.substring(at)}';
  }
  return out;
}

// --- Checking a snippet -----------------------------------------------------

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
  'param',
  'source',
  'track',
  'wbr',
};

/// Elements whose contents are text up to their own closing tag: left open,
/// each turns the rest of the page into its text.
const Set<String> _rawText = <String>{
  'script',
  'style',
  'textarea',
  'title',
  'noscript',
  'iframe',
  'xmp',
  'noembed',
  'noframes',
};

/// Elements a browser closes by itself when the next one starts.
const Set<String> _optionalEnd = <String>{
  'p',
  'li',
  'dt',
  'dd',
  'option',
  'optgroup',
  'tr',
  'td',
  'th',
  'thead',
  'tbody',
  'tfoot',
  'colgroup',
  'rp',
  'rt',
  'caption',
};

/// What a `<head>` can hold. Anything else makes the browser close the head
/// early and start the body there, before the page's own tags.
const Set<String> _headElements = <String>{'meta', 'link', 'script', 'style', 'noscript', 'base', 'template', 'title'};

const Set<String> _structure = <String>{'html', 'head', 'body'};

/// Why [html] would break the page if placed in [slot]: an element left open
/// that would swallow what follows, a closing tag that closes the page's own
/// elements, page structure, or (in the head) an element a head cannot hold.
///
/// Not a validator of HTML in general -- a browser is forgiving and so is
/// this -- but of the mistakes that turn a page blank or move the app.
List<String> dvHtmlSnippetProblems(String html, {required DVDocumentSlot slot}) {
  final List<String> problems = <String>[];
  final List<String> open = <String>[];
  final String lower = html.toLowerCase();
  int i = 0;
  while (i < html.length) {
    final int lt = html.indexOf('<', i);
    if (lt < 0) break;
    if (html.startsWith('<!--', lt)) {
      final int end = html.indexOf('-->', lt + 4);
      if (end < 0) {
        problems.add('A comment "<!--" is never closed with "-->", so it would hide the rest of the page.');
        break;
      }
      i = end + 3;
      continue;
    }
    if (html.startsWith('<!', lt) || html.startsWith('<?', lt)) {
      final int end = html.indexOf('>', lt);
      i = end < 0 ? html.length : end + 1;
      continue;
    }
    final Match? name = RegExp(r'<(/?)([A-Za-z][A-Za-z0-9-]*)').matchAsPrefix(html, lt);
    if (name == null) {
      i = lt + 1;
      continue;
    }
    final bool closing = name.group(1) == '/';
    final String tag = name.group(2)!.toLowerCase();
    final int end = _tagEnd(html, name.end);
    if (end < 0) {
      problems.add('The tag <$tag is never finished with ">".');
      break;
    }
    i = end + 1;
    if (_structure.contains(tag)) {
      problems.add('<${closing ? '/' : ''}$tag> is part of the page itself, which Dartvel writes; leave it out.');
      continue;
    }
    if (closing) {
      final int at = open.lastIndexOf(tag);
      if (at < 0) {
        problems.add('</$tag> closes nothing this snippet opened, so it would close part of the page around it.');
        continue;
      }
      for (final String inner in open.sublist(at + 1)) {
        if (!_optionalEnd.contains(inner)) problems.add('<$inner> is not closed before </$tag>.');
      }
      open.removeRange(at, open.length);
      continue;
    }
    if (open.isEmpty && slot == DVDocumentSlot.head) {
      if (tag == 'title') {
        problems.add('<title> is set per page by each page\'s SEO settings; a second one would be removed.');
      } else if (tag == 'meta' &&
          RegExp(r'''\sname\s*=\s*["']?description\b''', caseSensitive: false).hasMatch(html.substring(lt, end))) {
        problems.add(
          '<meta name="description"> is set per page by each page\'s SEO settings; a second one would be removed.',
        );
      } else if (!_headElements.contains(tag)) {
        problems.add('<$tag> cannot be inside <head>; the browser would end the head there. Use bodyStart or bodyEnd.');
      }
    }
    final bool selfClosed = html.substring(lt, end).trimRight().endsWith('/');
    if (_void.contains(tag) || selfClosed) continue;
    if (_rawText.contains(tag)) {
      final int close = lower.indexOf('</$tag', i);
      if (close < 0) {
        problems.add('<$tag> is never closed, so the rest of the page would become its content.');
        return problems;
      }
      final int closeEnd = html.indexOf('>', close);
      i = closeEnd < 0 ? html.length : closeEnd + 1;
      continue;
    }
    if (_optionalEnd.contains(tag) && open.isNotEmpty && open.last == tag) open.removeLast();
    open.add(tag);
  }
  for (final String tag in open) {
    if (_optionalEnd.contains(tag)) continue;
    problems.add(
      slot == DVDocumentSlot.bodyStart
          ? '<$tag> is never closed, so the app and the whole page would end up inside it.'
          : '<$tag> is never closed, so it would take in what follows it on the page.',
    );
  }
  return problems;
}

/// The index of the `>` ending a tag whose name ends at [from], skipping
/// quoted attribute values; -1 when there is none.
int _tagEnd(String html, int from) {
  String? quote;
  for (int i = from; i < html.length; i++) {
    final String c = html[i];
    if (quote != null) {
      if (c == quote) quote = null;
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '>') {
      return i;
    }
  }
  return -1;
}

// --- Content-Security-Policy ------------------------------------------------

final RegExp _loader = RegExp(r'<(script|link|iframe|img|frame|audio|video|source)\b([^>]*)>', caseSensitive: false);

String? _attribute(String attributes, String name) {
  final RegExpMatch? match = RegExp(
    '\\s$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(' $attributes');
  return match == null ? null : (match.group(1) ?? match.group(2) ?? match.group(3));
}

String? _origin(String? url) {
  if (url == null) return null;
  final String trimmed = url.trim();
  final Uri? uri = Uri.tryParse(trimmed.startsWith('//') ? 'https:$trimmed' : trimmed);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri.hasPort && uri.port != 443 ? 'https://${uri.host}:${uri.port}' : 'https://${uri.host}';
}

/// The third-party origins the snippets load from, by the directive that
/// governs each load: `script-src` for a `<script src>`, `style-src` for a
/// stylesheet, `frame-src` for an iframe, `img-src` for an image,
/// `media-src` for audio and video. Same-origin and relative URLs need no
/// addition, and plain-http URLs are left out: a secure page refuses them
/// whatever its policy says.
Map<String, List<String>> dvDocumentSlotCspSources(DVWebDocumentSlots slots, {String Function(String path)? readFile}) {
  final Map<String, List<String>> sources = <String, List<String>>{};
  void add(String directive, String? origin) {
    if (origin == null) return;
    final List<String> list = sources.putIfAbsent(directive, () => <String>[]);
    if (!list.contains(origin)) list.add(origin);
  }

  for (final String html in dvResolveDocumentSlots(slots, readFile: readFile).values) {
    for (final RegExpMatch match in _loader.allMatches(html)) {
      final String attributes = match.group(2) ?? '';
      switch (match.group(1)!.toLowerCase()) {
        case 'script':
          add('script-src', _origin(_attribute(attributes, 'src')));
        case 'link':
          final String rel = (_attribute(attributes, 'rel') ?? '').toLowerCase();
          if (rel.split(RegExp(r'\s+')).contains('stylesheet'))
            add('style-src', _origin(_attribute(attributes, 'href')));
        case 'iframe' || 'frame':
          add('frame-src', _origin(_attribute(attributes, 'src')));
        case 'img':
          add('img-src', _origin(_attribute(attributes, 'src')));
        default:
          add('media-src', _origin(_attribute(attributes, 'src')));
      }
    }
  }
  return sources;
}

/// [policy] allowing what [slots] load.
///
/// The third-party origins are added by directive. Inline scripts are
/// covered by the policy's own `'inline-scripts'` source when it has one --
/// each page's hashes are then worked out from the page it is sent with --
/// and otherwise each inline script in the snippets is hashed into
/// `script-src` here, from the text exactly as the page will carry it. A
/// `script-src` that allows `'unsafe-inline'` without any hash is left as it
/// is: adding a hash would switch `'unsafe-inline'` off for every other
/// script on the page.
String dvPageCspWithDocumentSlots(String policy, DVWebDocumentSlots slots, {String Function(String path)? readFile}) {
  if (slots.isEmpty) return policy;
  String out = dvAddContentSecurityPolicySources(policy, dvDocumentSlotCspSources(slots, readFile: readFile));
  if (out.contains(dvInlineScriptsSource)) return out;
  final List<String> hashes = <String>[
    for (final String html in dvResolveDocumentSlots(slots, readFile: readFile).values) ...dvInlineScriptHashes(html),
  ];
  if (hashes.isEmpty) return out;
  out = dvAddContentSecurityPolicyHashes(out, hashes.toSet().toList());
  return out;
}
