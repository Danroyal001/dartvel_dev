/// SSR-first in the app's own look: the server-rendered document laid out the
/// way the app's first frame draws the page (`dartvel.web.ssrFirst`).
///
/// The build's capture runs every public route in Chrome and, at each width
/// it lays the document out for, in light and dark, asks the app what it
/// painted (`dvPaintSnapshot` in dartvel_flutter) and reads each link,
/// button and field's box from the semantics host. [dvSsrFirstLayout] keeps
/// the document exactly as it is -- the same headings, links, fields and
/// order, so find, selection, Tab and screen readers read what they read
/// before -- and adds:
///
/// * an id on each run of its text the app paints, and on each link, button
///   and field the capture found a box for;
/// * an `aria-hidden` layer of empty elements for what the app paints that is
///   not the document's text: surfaces, borders, shadows, images, icons and
///   decorative text (as CSS `content`, so nothing is selectable, findable or
///   indexed twice);
/// * one stylesheet that places all of it at its captured box in its
///   captured style. Between two captured widths every box moves linearly
///   (`calc(Apx + Bvw)`); something on screen at one width and not the next
///   switches at the midpoint.
///
/// The stylesheet applies only on a screen, with scripting, before the
/// handover (`html:not([data-dv-app])`), and only in a browser that reads
/// nested CSS. Print, a browser with scripting off, an older browser and the
/// page after the handover all get the reading column as before.
///
/// It runs at build time, into the route's captured HTML, so the static build
/// and the web-server binary serve the same bytes through the one render path
/// (`dvRenderRoutePage`).
library;

import 'dart:convert';
import 'dart:math' as math;

/// One font file of a family the app draws with: its URL under the web root
/// (from FontManifest.json), and the weight and style it declares.
class DVLayoutFont {
  const DVLayoutFont(this.url, {this.weight, this.style});

  final String url;

  /// Null for a file that declares none: one file for every weight, as a
  /// variable font is.
  final int? weight;
  final String? style;
}

/// The id of the element that ends the first screen of a laid-out document:
/// the SSR-first head holds the first paint until it is parsed.
const String dvFirstScreenId = 'dv-first-screen';

/// The family the engine draws with when a style names none.
const String dvLayoutDefaultFamily = 'Roboto';

const HtmlEscape _attribute = HtmlEscape(HtmlEscapeMode.attribute);
const HtmlEscape _elementText = HtmlEscape(HtmlEscapeMode.element);

/// [html] laid out from [capture]: `{"widths": [{"width", "height", "light",
/// "dark", "controls"}]}`, `light` and `dark` being paint snapshots. [fonts]
/// is FontManifest.json by family. Unchanged when [capture] has no width.
String dvSsrFirstLayout(
  String html,
  Map<String, Object?> capture, {
  Map<String, List<DVLayoutFont>> fonts = const <String, List<DVLayoutFont>>{},
}) {
  final List<_Width> widths = <_Width>[
    for (final Object? entry
        in (capture['widths'] as List<Object?>? ?? const <Object?>[]))
      if (entry is Map) _Width.fromJson(entry.cast<String, Object?>()),
  ]..sort((_Width a, _Width b) => a.width.compareTo(b.width));
  if (widths.isEmpty) return html;
  return _Layout(widths, fonts).run(html);
}

// ---------------------------------------------------------------------------
// The capture.

class _Item {
  _Item(this.json)
    : kind = json['k'] as String? ?? '',
      rect = _rect(json['r']),
      z = (json['z'] as num?)?.toInt() ?? 0,
      scrolls = json['s'] == true;

  final Map<String, Object?> json;
  final String kind;
  final List<double> rect;
  final int z;
  final bool scrolls;
  _Item? dark;

  /// The same item in the capture at a second screen height, when there is
  /// one: how far it moves and grows with the screen's height.
  _Item? tall;
  bool used = false;

  String get text => json['text'] as String? ?? '';
  String get norm => _norm(text);
  List<Map<String, Object?>> get runs => <Map<String, Object?>>[
    for (final Object? run
        in (json['runs'] as List<Object?>? ?? const <Object?>[]))
      if (run is Map) run.cast<String, Object?>(),
  ];
}

class _Control {
  _Control(Map<String, Object?> json)
    : key = _controlKey(
        json['k'] as String? ?? '',
        json['href'] as String?,
        json['name'] as String?,
      ),
      rect = _rect(json['r']);

  final String key;
  final List<double> rect;

  /// Its box at the second screen height.
  List<double>? tall;
  bool used = false;
}

String _controlKey(String kind, String? href, String? name) => switch (kind) {
  'a' => 'a|${href ?? ''}|${_norm(name ?? '')}',
  'b' => 'b|${_norm(name ?? '')}',
  'f' => 'f|${_norm(name ?? '')}',
  'r' => 'r|',
  _ => '?|',
};

List<double> _rect(Object? value) {
  final List<Object?> list = value is List
      ? value
      : const <Object?>[0, 0, 0, 0];
  return <double>[
    for (int index = 0; index < 4; index++)
      index < list.length && list[index] is num
          ? (list[index]! as num).toDouble()
          : 0,
  ];
}

class _Width {
  _Width(this.width, this.height, this.items, this.controls, [this.tallHeight]);

  factory _Width.fromJson(Map<String, Object?> json) {
    List<_Item> itemsOf(Object? snapshot) => <_Item>[
      if (snapshot is Map)
        for (final Object? item
            in (snapshot['items'] as List<Object?>? ?? const <Object?>[]))
          if (item is Map) _Item(item.cast<String, Object?>()),
    ];
    final List<_Item> light = itemsOf(json['light']);
    final List<_Item> dark = itemsOf(json['dark']);
    // Each dark item is the light one at the same place: layout does not
    // change with the scheme, colours and pictures do.
    final Map<String, List<_Item>> byPlace = <String, List<_Item>>{};
    for (final _Item item in dark) {
      byPlace.putIfAbsent(_place(item), () => <_Item>[]).add(item);
    }
    for (final _Item item in light) {
      final List<_Item>? same = byPlace[_place(item)];
      if (same != null && same.isNotEmpty) item.dark = same.removeAt(0);
    }
    final List<_Control> controls = <_Control>[
      for (final Object? control
          in (json['controls'] as List<Object?>? ?? const <Object?>[]))
        if (control is Map) _Control(control.cast<String, Object?>()),
    ];
    final double height = (json['height'] as num?)?.toDouble() ?? 0;
    // The same width at a second screen height (light only: the layout does
    // not change with the scheme). Each item and control is paired with its
    // own by what it is and its place among its kind, and only when it is
    // as wide there: a lazy list that built another row or a layout that
    // switched is left as it is at the first height.
    double? tallHeight;
    final Object? tall = json['tall'];
    if (tall is Map && tall['height'] is num) {
      final double second = (tall['height']! as num).toDouble();
      if ((second - height).abs() >= 1) {
        tallHeight = second;
        final Map<String, List<_Item>> byKind = <String, List<_Item>>{};
        for (final Object? item
            in (tall['items'] as List<Object?>? ?? const <Object?>[])) {
          if (item is! Map) continue;
          final _Item other = _Item(item.cast<String, Object?>());
          byKind.putIfAbsent(_identity(other), () => <_Item>[]).add(other);
        }
        final Map<String, int> seen = <String, int>{};
        for (final _Item item in light) {
          final String key = _identity(item);
          final int index = seen[key] = (seen[key] ?? -1) + 1;
          final List<_Item>? same = byKind[key];
          if (same == null || index >= same.length) continue;
          final _Item other = same[index];
          if ((other.rect[0] - item.rect[0]).abs() < 1 &&
              (other.rect[2] - item.rect[2]).abs() < 1) {
            item.tall = other;
          }
        }
        final Map<String, List<List<double>>> controlsByKey =
            <String, List<List<double>>>{};
        for (final Object? control
            in (tall['controls'] as List<Object?>? ?? const <Object?>[])) {
          if (control is! Map) continue;
          final _Control other = _Control(control.cast<String, Object?>());
          controlsByKey.putIfAbsent(other.key, () => <List<double>>[]).add(other.rect);
        }
        final Map<String, int> seenControls = <String, int>{};
        for (final _Control control in controls) {
          final int index = seenControls[control.key] =
              (seenControls[control.key] ?? -1) + 1;
          final List<List<double>>? same = controlsByKey[control.key];
          if (same == null || index >= same.length) continue;
          if ((same[index][0] - control.rect[0]).abs() < 1 &&
              (same[index][2] - control.rect[2]).abs() < 1) {
            control.tall = same[index];
          }
        }
      }
    }
    return _Width(
      (json['width'] as num?)?.toDouble() ?? 0,
      height,
      light,
      controls,
      tallHeight,
    );
  }

  final double width;
  final double height;
  final List<_Item> items;
  final List<_Control> controls;

  /// The second screen height the width was captured at, if any.
  final double? tallHeight;

  int get topZ =>
      items.fold<int>(0, (int top, _Item item) => math.max(top, item.z));
}

/// What an item is, apart from where: paired across screen heights by it.
String _identity(_Item item) => switch (item.kind) {
  't' => 't|${item.text}',
  'b' => 'b|${item.json['bg']}|${item.json['g']}|${item.json['bd']}',
  'i' => 'i|${item.json['src']}',
  _ => '${item.kind}|',
};

String _place(_Item item) =>
    '${item.kind}|${item.rect.map((double v) => v.round()).join(',')}|${item.kind == 't' ? item.text : ''}';

// ---------------------------------------------------------------------------
// The document.

/// One token of the document: a tag, a comment or a run of text.
class _Token {
  _Token(this.source, {required this.isTag});
  String source;
  final bool isTag;
  String? name;
  bool closing = false;

  /// What replaces a text token: the same text, with its runs wrapped.
  String? replacement;
}

final RegExp _tokens = RegExp(r'<!--.*?-->|<[^>]*>', dotAll: true);
final RegExp _tagName = RegExp(r'^<(/?)([A-Za-z][A-Za-z0-9-]*)');
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
const Set<String> _rawText = <String>{
  'style',
  'script',
  'textarea',
  'title',
  'option',
};

String? _attr(String tag, String name) {
  final RegExpMatch? match = RegExp('\\s$name="([^"]*)"').firstMatch(tag);
  return match == null ? null : _unescape(match.group(1)!);
}

String _withAttr(String tag, String name, String value) {
  final int at = _tagName.firstMatch(tag)!.end;
  return '${tag.substring(0, at)} $name="${_attribute.convert(value)}"${tag.substring(at)}';
}

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&#x2F;', '/')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

String _norm(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// A text node: where it is, its raw text, the control it sits in.
class _TextNode {
  _TextNode(
    this.token,
    this.raw,
    this.control, {
    this.slotOpen,
    this.slotClose,
  });
  final _Token token;
  final String raw;
  final _Element? control;

  /// A slot (`<span data-dv-slot>`) is wrapped whole, from outside, so the
  /// server can still fill it.
  final _Token? slotOpen;
  final _Token? slotClose;

  late final String norm;
  late final List<int> normToRaw;

  /// The runs: ranges of [norm] and the node id of each.
  final List<_Segment> segments = <_Segment>[];
}

class _Segment {
  _Segment(this.start, this.end);
  final int start;
  final int end;
  late _Node node;
}

/// A positioned element: a run of text, a control, a piece of the layer.
class _Node {
  _Node(this.id, this.kind);
  final String id;

  /// 'run', 'sub', 'control', 'box', 'image', 'decor', 'field'.
  final String kind;

  /// Per width: the item it shows (runs and layer pieces).
  final Map<int, _Item> items = <int, _Item>{};

  /// Per width: its box (controls).
  final Map<int, List<double>> boxes = <int, List<double>>{};

  /// Per width: its box at the second screen height (controls).
  final Map<int, List<double>> tallBoxes = <int, List<double>>{};
  _Node? container;

  /// A control the semantics host reported a box for at some width.
  bool captured = false;
  int subIndex = 0;
  int controlZ = 0;

  /// Per width: a field's inner padding, left and right, where the app
  /// starts its text.
  final Map<int, (double, double)> pads = <int, (double, double)>{};

  /// Per width: a multi-line field's inner padding, top and bottom, where
  /// the app starts its first line. A one-line input centres its line as the
  /// app does, so it has none.
  final Map<int, (double, double)> verticalPads = <int, (double, double)>{};

  /// Per width: the hint the app paints in an empty field, which the
  /// document's field shows as its placeholder.
  final Map<int, _Item> hints = <int, _Item>{};

  /// In the line of a sentence placed as one block: a link, or its words,
  /// that flows with the sentence's text rather than sitting at a box of
  /// its own. Styled in place, never positioned.
  bool inline = false;
}

class _Element {
  _Element(this.node);
  final _Node node;
}

/// A paragraph of the document with links in its line (`<p>words <a>link</a>
/// words</p>`): what the build writes for a sentence the app lays out with
/// DVWidgetSpan. The app paints its words as one paragraph with a gap for
/// each link, and each link's words in that gap; the document's paragraph is
/// placed as that one block, its links flowing in it.
class _Sentence {
  _Sentence(this.open, this.close, this.words, this.links, this.container);
  final _Token open;
  final _Token close;

  /// Its own text nodes, outside its links, in order.
  final List<_TextNode> words;

  /// Its links.
  final List<_Node> links;

  /// What the paragraph itself sits in.
  final _Node? container;
  _Node? node;
}

/// A paragraph holds no block of its own; one of these inside it means it is
/// not a single line of text.
const Set<String> _blocks = <String>{
  'address', 'article', 'aside', 'blockquote', 'button', 'details', 'div',
  'dl', 'fieldset', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5',
  'h6', 'header', 'hr', 'iframe', 'img', 'input', 'li', 'main', 'nav', 'ol',
  'p', 'pre', 'section', 'select', 'table', 'textarea', 'ul', 'video', 'audio',
};

String _stripped(String text) => text.replaceAll(RegExp(r'\s+'), '');

class _Layout {
  _Layout(this.widths, this.fonts);

  final List<_Width> widths;
  final Map<String, List<DVLayoutFont>> fonts;
  final List<_Node> runs = <_Node>[];
  final List<_Node> controls = <_Node>[];
  final List<_Node> layer = <_Node>[];
  final Set<String> families = <String>{};
  int _ids = 0;

  /// The lowest z-index of anything painted inside a link or field, at any
  /// width; null when no control holds anything painted.
  int? _firstControlContentZ;

  /// What lifts a pinned piece above every control: one past the highest.
  int _lift = 0;

  String run(String html) {
    final List<_Token> tokens = <_Token>[];
    int cursor = 0;
    for (final RegExpMatch match in _tokens.allMatches(html)) {
      if (match.start > cursor) {
        tokens.add(_Token(html.substring(cursor, match.start), isTag: false));
      }
      final _Token tag = _Token(match.group(0)!, isTag: true);
      final RegExpMatch? name = _tagName.firstMatch(tag.source);
      if (name != null) {
        tag.closing = name.group(1) == '/';
        tag.name = name.group(2)!.toLowerCase();
      }
      tokens.add(tag);
      cursor = match.end;
    }
    if (cursor < html.length) {
      tokens.add(_Token(html.substring(cursor), isTag: false));
    }

    final List<_TextNode> all = _readDocument(tokens);
    _assignControlBoxes();
    _fillFields();
    // A sentence placed as one block takes its own words out of the
    // piece-by-piece matching: they are its text, in its line.
    final Set<_TextNode> inSentences = _matchSentences(_findSentences(tokens, all));
    final List<_TextNode> texts = <_TextNode>[
      for (final _TextNode text in all)
        if (!inSentences.contains(text)) text,
    ];
    _matchText(texts);
    for (final _Node run in runs) {
      if (run.container?.inline ?? false) run.inline = true;
    }
    _matchControls();
    _markReaderControls();
    _buildLayer();
    _wrapText(texts);
    _wrapSentences();

    final StringBuffer body = StringBuffer();
    for (final _Token token in tokens) {
      body.write(token.replacement ?? token.source);
    }
    final (String first, String rest) = _css();
    // What is below the fold is placed by a second stylesheet after the
    // document, so the first screen paints without waiting for it. The
    // marker between them ends the first screen: the SSR-first head holds
    // the first paint until it is parsed (dvSsrFirstHead), so the first frame
    // is the first screen in place, never the bare canvas or half of it.
    return '<div class="dvl"><style class="dvl-style">$first</style>'
        '${_layerHtml()}$body<i id="$dvFirstScreenId" aria-hidden="true" hidden></i>'
        '${rest.isEmpty ? '' : '<style class="dvl-style">$rest</style>'}</div>';
  }

  // -- Reading the document.

  final List<(_Node node, String key, _Token token)> _docControls =
      <(_Node, String, _Token)>[];

  /// Each `<textarea>` the document leaves empty.
  final Set<_Token> _emptyTextareas = <_Token>{};

  List<_TextNode> _readDocument(List<_Token> tokens) {
    final List<_TextNode> texts = <_TextNode>[];
    final List<(String name, _Element? control)> stack =
        <(String, _Element?)>[];
    String? raw;
    for (int index = 0; index < tokens.length; index++) {
      final _Token token = tokens[index];
      if (raw != null) {
        if (token.isTag && token.closing && token.name == raw) raw = null;
        continue;
      }
      if (!token.isTag) {
        if (token.source.trim().isEmpty) continue;
        texts.add(
          _TextNode(
            token,
            _unescape(token.source),
            stack.isEmpty ? null : stack.last.$2,
          ),
        );
        continue;
      }
      final String? name = token.name;
      if (name == null) continue;
      if (token.closing) {
        final int at = stack.lastIndexWhere(
          ((String, _Element?) open) => open.$1 == name,
        );
        if (at >= 0) stack.removeRange(at, stack.length);
        continue;
      }
      if (_rawText.contains(name)) {
        if (name == 'textarea') {
          _control(
            token,
            'f|${_norm(_attr(token.source, 'data-dv-field') ?? '')}',
            'field',
          );
          // Empty in the document: the app's starting text goes in after it.
          if (index + 1 < tokens.length &&
              tokens[index + 1].isTag &&
              tokens[index + 1].closing &&
              tokens[index + 1].name == 'textarea') {
            _emptyTextareas.add(token);
          }
        }
        raw = name;
        continue;
      }
      // A slot: its text is one unit, wrapped from outside.
      if (name == 'span' &&
          token.source.contains('data-dv-slot=') &&
          index + 2 < tokens.length &&
          !tokens[index + 1].isTag &&
          tokens[index + 2].isTag &&
          tokens[index + 2].closing &&
          tokens[index + 2].name == 'span') {
        texts.add(
          _TextNode(
            tokens[index + 1],
            _unescape(tokens[index + 1].source),
            stack.isEmpty ? null : stack.last.$2,
            slotOpen: token,
            slotClose: tokens[index + 2],
          ),
        );
        index += 2;
        continue;
      }
      _Element? control = stack.isEmpty ? null : stack.last.$2;
      if (name == 'a' && _attr(token.source, 'href') != null) {
        control = _control(
          token,
          'a|${_attr(token.source, 'href')}|${_norm(_attr(token.source, 'aria-label') ?? '')}',
          'control',
        );
      } else if (name == 'strong' && _attr(token.source, 'role') == 'button') {
        // A button is a Tab stop and takes Enter and Space like the app's:
        // the SSR-first head queues the press for the app's button.
        if (_attr(token.source, 'tabindex') == null) {
          token.source = _withAttr(token.source, 'tabindex', '0');
        }
        control = _control(
          token,
          'b|${_norm(_attr(token.source, 'aria-label') ?? '')}',
          'control',
        );
      } else if (name == 'input' &&
          _attr(token.source, 'data-dv-field') != null) {
        _control(
          token,
          'f|${_norm(_attr(token.source, 'data-dv-field')!)}',
          'field',
        );
      } else if (name == 'button' &&
          (_attr(token.source, 'class') ?? '').contains('dv-reveal')) {
        control = _control(token, 'r|', 'control');
      } else if (const <String>{
        'video',
        'audio',
        'img',
        'iframe',
      }.contains(name)) {
        // Something the document draws by itself that the app draws its own
        // way: kept for readers, hidden from the eye.
        token.replacement = _withClass(token.source, 'dvu');
      }
      if (!_void.contains(name) && !token.source.endsWith('/>')) {
        stack.add((name, control));
      }
    }
    return texts;
  }

  _Element _control(_Token token, String key, String kind) {
    final String? existing = _attr(token.source, 'id');
    final _Node node = _Node(existing ?? 'dva${_ids++}', kind);
    if (existing == null) token.source = _withAttr(token.source, 'id', node.id);
    _docControls.add((node, key, token));
    controls.add(node);
    return _Element(node);
  }

  String _withClass(String tag, String name) {
    final String? existing = _attr(tag, 'class');
    if (existing == null) return _withAttr(tag, 'class', name);
    return tag.replaceFirst(
      'class="${_attribute.convert(existing)}"',
      'class="${_attribute.convert('$existing $name')}"',
    );
  }

  // -- Sentences: a paragraph with links in its line.

  final List<_Sentence> _sentences = <_Sentence>[];

  /// Each `<p>` that is one line of text with links in it: words and links
  /// only, no block inside, at least one link and some words of its own.
  List<_Sentence> _findSentences(List<_Token> tokens, List<_TextNode> texts) {
    final Map<_Token, _TextNode> byToken = <_Token, _TextNode>{
      for (final _TextNode text in texts) text.token: text,
    };
    final Map<_Token, _Node> linkByToken = <_Token, _Node>{
      for (final (_Node node, String key, _Token token) in _docControls)
        if (key.startsWith('a|')) token: node,
    };
    final List<_Sentence> found = <_Sentence>[];
    for (int index = 0; index < tokens.length; index++) {
      final _Token open = tokens[index];
      if (!open.isTag || open.closing || open.name != 'p') continue;
      final List<_TextNode> words = <_TextNode>[];
      final List<_Node> links = <_Node>[];
      final Set<_Node> linkSet = <_Node>{};
      _Token? close;
      bool plain = true;
      int end = index + 1;
      for (; end < tokens.length; end++) {
        final _Token token = tokens[end];
        if (token.isTag) {
          if (token.name == 'p') {
            if (token.closing) close = token;
            break;
          }
          if (_blocks.contains(token.name) ||
              token.source.contains('data-dv-slot=')) {
            plain = false;
          }
          final _Node? link = linkByToken[token];
          if (link != null) {
            links.add(link);
            linkSet.add(link);
          }
          continue;
        }
        final _TextNode? text = byToken[token];
        if (text == null) continue;
        if (text.control != null && linkSet.contains(text.control!.node)) continue;
        words.add(text);
      }
      index = end - 1;
      if (close == null || !plain || links.isEmpty || words.isEmpty) continue;
      found.add(_Sentence(open, close, words, links, words.first.control?.node));
    }
    return found;
  }

  /// Each sentence the app paints as one paragraph at some width: the
  /// painted words are the sentence's own, its links being gaps in them
  /// (placeholders) or runs of them. Returns the text nodes the matched
  /// sentences hold.
  Set<_TextNode> _matchSentences(List<_Sentence> sentences) {
    final Set<_TextNode> held = <_TextNode>{};
    for (final _Sentence sentence in sentences) {
      final String own = _stripped(
        sentence.words.map((_TextNode text) => text.raw).join(),
      );
      if (own.isEmpty) continue;
      final _Node node = _Node('dvr${_ids++}', 'run')
        ..container = sentence.container;
      for (int w = 0; w < widths.length; w++) {
        for (final _Item item in widths[w].items) {
          if (item.used || item.kind != 't') continue;
          if (_stripped(item.text) != own) continue;
          node.items[w] = item;
          item.used = true;
          break;
        }
      }
      if (node.items.isEmpty) continue;
      sentence.node = node;
      runs.add(node);
      _sentences.add(sentence);
      held.addAll(sentence.words);
      for (final _Node link in sentence.links) {
        link.inline = true;
      }
    }
    return held;
  }

  /// Each matched sentence wrapped in its run, and each stretch of its words
  /// styled unlike its first run in a span of its own, as [_subRuns] does
  /// for a paragraph with no links.
  void _wrapSentences() {
    for (final _Sentence sentence in _sentences) {
      final _Node node = sentence.node!;
      sentence.open.replacement = '${sentence.open.source}<span id="${node.id}">';
      sentence.close.replacement = '</span>${sentence.close.source}';
      final List<Map<String, Object?>> styles = node.items.values.first.runs;
      // Which run each visible character of the painted words is in: the
      // sentence's words are those characters in order, whatever the spaces.
      final List<int> owner = <int>[
        for (int run = 0; run < styles.length; run++)
          for (final String char in (styles[run]['t'] as String? ?? '').split(''))
            if (char.trim().isNotEmpty) run,
      ];
      final String base = styles.isEmpty ? '' : _inlineStyle(styles.first);
      final Map<int, int> uses = <int, int>{};
      int at = 0;
      for (final _TextNode text in sentence.words) {
        final StringBuffer out = StringBuffer();
        int? open;
        int run = 0;
        bool styled = false;
        for (int index = 0; index < text.raw.length; index++) {
          final String char = text.raw[index];
          if (char.trim().isNotEmpty && at < owner.length) run = owner[at++];
          final bool differs = run > 0 && run < styles.length && _inlineStyle(styles[run]) != base;
          final int? want = differs ? run : null;
          if (want != open) {
            if (open != null) out.write('</span>');
            if (want != null) {
              final int use = uses[want] = (uses[want] ?? -1) + 1;
              final _Node sub = _Node('${node.id}-$want${use == 0 ? '' : 'x$use'}', 'sub')
                ..container = node
                ..subIndex = want;
              sub.items.addAll(node.items);
              runs.add(sub);
              out.write('<span id="${sub.id}">');
              styled = true;
            }
            open = want;
          }
          out.write(_elementText.convert(char));
        }
        if (open != null) out.write('</span>');
        if (styled) text.token.replacement = out.toString();
      }
    }
  }

  // -- Matching the document's text to the painted paragraphs.

  void _matchText(List<_TextNode> texts) {
    for (final _TextNode text in texts) {
      final StringBuffer norm = StringBuffer();
      final List<int> map = <int>[];
      bool space = true;
      for (int index = 0; index < text.raw.length; index++) {
        final String char = text.raw[index];
        if (RegExp(r'\s').hasMatch(char)) {
          if (!space) {
            norm.write(' ');
            map.add(index);
          }
          space = true;
        } else {
          norm.write(char);
          map.add(index);
          space = false;
        }
      }
      String value = norm.toString();
      if (value.endsWith(' ')) {
        value = value.substring(0, value.length - 1);
        map.removeLast();
      }
      text
        ..norm = value
        ..normToRaw = map;
    }

    // Each width on its own: which painted paragraph each piece of each text
    // node is, in document order, each paragraph used once.
    final List<List<List<(int, int, _Item)>>> perWidth =
        <List<List<(int, int, _Item)>>>[];
    for (final _Width width in widths) {
      final Map<String, List<_Item>> queues = <String, List<_Item>>{};
      for (final _Item item in width.items) {
        if (item.used || item.kind != 't' || item.norm.isEmpty) continue;
        queues.putIfAbsent(item.norm, () => <_Item>[]).add(item);
      }
      final List<String> keys = queues.keys.toList()
        ..sort((String a, String b) => b.length.compareTo(a.length));
      final int w = perWidth.length;
      final List<List<(int, int, _Item)>> found =
          List<List<(int, int, _Item)>>.generate(texts.length, (_) => <(int, int, _Item)>[]);
      // Text in a control the semantics host found at some width and not at
      // this one (a menu link while the menu is closed) is matched last: the
      // same words painted at this width are more likely something else's,
      // a footer heading's, and taking them first would leave that without
      // its text and the link a Tab stop of no size.
      //
      // The same goes for a control laid out at this width with no text
      // painted in its box: a link below the fold of a panel that scrolls on
      // its own (dartvel.dev's docs menu at 1024 and 1366), which took the
      // footer's "Privacy" for its "Privacy and erasure".
      bool late(_TextNode text) {
        final _Node? control = text.control?.node;
        if (control == null || control.boxes.isEmpty) return false;
        final List<double>? box = control.boxes[w];
        if (box == null) return true;
        for (final _Item item in width.items) {
          if (item.kind != 't') continue;
          final List<double> r = item.rect;
          if (r[0] >= box[0] - 1 && r[1] >= box[1] - 1 &&
              r[0] + r[2] <= box[0] + box[2] + 1 && r[1] + r[3] <= box[1] + box[3] + 1) {
            return false;
          }
        }
        return true;
      }

      final List<int> order = <int>[
        for (int index = 0; index < texts.length; index++)
          if (!late(texts[index])) index,
        for (int index = 0; index < texts.length; index++)
          if (late(texts[index])) index,
      ];
      for (final int textIndex in order) {
        final _TextNode text = texts[textIndex];
        final List<(int, int, _Item)> pieces = found[textIndex];
        final String value = text.norm;
        final List<String> candidates = <String>[
          for (final String key in keys)
            if (value.contains(key) && queues[key]!.isNotEmpty) key,
        ];
        int at = 0;
        while (at < value.length && candidates.isNotEmpty) {
          int bestStart = -1;
          String? best;
          for (final String key in candidates) {
            if (queues[key]!.isEmpty) continue;
            int from = at;
            while (true) {
              final int hit = value.indexOf(key, from);
              if (hit < 0) break;
              final bool startOk =
                  hit == 0 ||
                  !_wordChar.hasMatch(value[hit - 1]) ||
                  !_wordChar.hasMatch(key[0]);
              final int end = hit + key.length;
              final bool endOk =
                  end == value.length ||
                  !_wordChar.hasMatch(value[end]) ||
                  !_wordChar.hasMatch(key[key.length - 1]);
              if (startOk && endOk) {
                if (bestStart < 0 ||
                    hit < bestStart ||
                    (hit == bestStart && key.length > best!.length)) {
                  bestStart = hit;
                  best = key;
                }
                break;
              }
              from = hit + 1;
            }
          }
          if (best == null) break;
          pieces.add((
            bestStart,
            bestStart + best.length,
            queues[best]!.removeAt(0),
          ));
          at = bestStart + best.length;
        }
      }
      perWidth.add(found);
    }

    // One set of runs per text node, from the width that matched most of it;
    // every width then shows the paragraph it matched to the same piece.
    for (int index = 0; index < texts.length; index++) {
      final _TextNode text = texts[index];
      int bestWidth = -1;
      int bestCovered = 0;
      for (int w = 0; w < widths.length; w++) {
        final int covered = perWidth[w][index].fold<int>(
          0,
          (int sum, (int, int, _Item) p) => sum + p.$2 - p.$1,
        );
        if (covered > bestCovered) {
          bestCovered = covered;
          bestWidth = w;
        }
      }
      if (bestWidth < 0) continue;
      for (final (int start, int end, _Item _) in perWidth[bestWidth][index]) {
        final _Segment segment = _Segment(start, end);
        final _Node node = _Node('dvr${_ids++}', 'run')
          ..container = text.control?.node;
        for (int w = 0; w < widths.length; w++) {
          for (final (int s, int e, _Item item) in perWidth[w][index]) {
            if (s == start && e == end) {
              node.items[w] = item;
              item.used = true;
            }
          }
        }
        segment.node = node;
        text.segments.add(segment);
        runs.add(node);
      }
    }
  }

  /// Each control's box at each width, off the semantics host, before the
  /// text is matched.
  void _assignControlBoxes() {
    for (int w = 0; w < widths.length; w++) {
      final Map<String, List<_Control>> captured = <String, List<_Control>>{};
      for (final _Control control in widths[w].controls) {
        captured.putIfAbsent(control.key, () => <_Control>[]).add(control);
      }
      for (final (_Node node, String key, _Token _) in _docControls) {
        final List<_Control>? queue = captured[key];
        if (queue == null || queue.isEmpty) continue;
        final _Control control = queue.removeAt(0);
        node.boxes[w] = control.rect;
        if (control.tall != null) node.tallBoxes[w] = control.tall!;
      }
    }
  }

  /// The text each field starts with (`e` items: what the app's editable
  /// paints) goes into the document's field as its value -- an input's
  /// `value`, a textarea's content -- styled as the app draws it, rather than
  /// staying empty until Flutter takes over. An empty field's `e` item still
  /// gives the box and style typing takes; the hint the app paints in it
  /// becomes the field's placeholder, which goes as the visitor types (drawn
  /// over the field, it stayed on top of what was typed). Text of a field
  /// the document has no input for is drawn with the layer. A password
  /// field is never given a value.
  void _fillFields() {
    for (final (_Node node, String _, _Token token) in _docControls) {
      if (node.kind != 'field') continue;
      final bool textarea = token.name == 'textarea';
      // The snapshot never reads a password; one that came anyway is
      // swallowed, neither a value nor drawn.
      final bool secret = !textarea &&
          (_attr(token.source, 'type') ?? 'text').toLowerCase() == 'password';
      String? value;
      String? hint;
      for (final int w in node.boxes.keys) {
        final List<double> box = node.boxes[w]!;
        bool within(List<double> r) =>
            r[0] >= box[0] - 1 && r[1] >= box[1] - 1 &&
            r[0] + r[2] <= box[0] + box[2] + 1 && r[1] + r[3] <= box[1] + box[3] + 1;
        _Item? editable;
        for (final _Item item in widths[w].items) {
          if (item.used || item.kind != 'e' || !within(item.rect)) continue;
          editable = item;
          break;
        }
        if (editable == null) continue;
        editable.used = true;
        if (secret && editable.text.isNotEmpty) continue;
        final List<double> r = editable.rect;
        node.items[w] = editable;
        node.pads[w] = (math.max(0, r[0] - box[0]), math.max(0, box[0] + box[2] - r[0] - r[2]));
        if (textarea) {
          node.verticalPads[w] = (math.max(0, r[1] - box[1]), math.max(0, box[1] + box[3] - r[1] - r[3]));
        }
        if (editable.text.isNotEmpty) {
          value ??= editable.text;
          continue;
        }
        // Empty: the paragraph the app paints where its text would start
        // is the hint.
        for (final _Item item in widths[w].items) {
          if (item.used || item.kind != 't' || item.norm.isEmpty || !within(item.rect)) continue;
          final List<double> t = item.rect;
          if (t[1] + t[3] <= r[1] || t[1] >= r[1] + r[3]) continue;
          // Where the text starts (or ends, or centres): an icon at the
          // end of the field, or a glyph of an icon font, is not the hint.
          final bool aligned = (t[0] - r[0]).abs() <= 2 ||
              (t[0] + t[2] - r[0] - r[2]).abs() <= 2 ||
              (t[0] + t[2] / 2 - r[0] - r[2] / 2).abs() <= 2;
          if (!aligned || !item.text.runes.any(_readable)) continue;
          item.used = true;
          node.hints[w] = item;
          hint ??= item.text;
          break;
        }
      }
      if (hint != null && _attr(token.source, 'placeholder') == null) {
        token.source = _withAttr(token.source, 'placeholder', hint);
      }
      if (secret || value == null) continue;
      if (textarea) {
        if (_emptyTextareas.contains(token)) {
          token.replacement = '${token.source}${_elementText.convert(value)}';
        }
      } else if (_attr(token.source, 'value') == null) {
        token.source = _withAttr(token.source, 'value', value);
      }
    }
  }

  /// A control the layout never places (no box at any width, nothing of it
  /// painted) is kept for readers, its text hidden from the eye; it is still
  /// a Tab stop, so it is marked to show itself when focused.
  void _markReaderControls() {
    for (final (_Node node, String _, _Token token) in _docControls) {
      if (node.kind == 'field' || node.captured) continue;
      if (runs.any((_Node run) => run.container == node)) continue;
      token.source = _withClass(token.source, 'dvf');
    }
  }

  void _matchControls() {
    // A box with nothing painted in it is a control that is laid out and not
    // on screen: a closed menu's links. Placed, they would sit on top of the
    // page and take its clicks and its Tab stops. A field keeps its box: its
    // border is drawn by a painter the snapshot cannot read.
    for (final (_Node node, String _, _Token _) in _docControls) {
      if (node.boxes.isNotEmpty) node.captured = true;
      // A field is placed at every box it has: it is where a visitor taps
      // to type (Dartvel 3.47.8 to 3.47.9 left every field out of the
      // layout, under the box the app paints for it).
      if (node.kind == 'field') continue;
      bool covered = false;
      for (final int w in node.boxes.keys.toList()) {
        if (_coversScreen(node, w)) {
          covered = true;
          node.boxes.remove(w);
        } else if (!_paintedIn(node, w)) {
          node.boxes.remove(w);
        }
      }
      // Never placed but for its screen-sized box: a reader control, which
      // shows itself when focused.
      if (covered && node.boxes.isEmpty) node.captured = false;
    }
  }

  /// Whether [control], painting no words of its own at width [w], has a box
  /// of half the screen or more: the page shell's scroll button or a modal
  /// barrier, not something a visitor sees and presses. Everything painted
  /// lies inside such a box, so [_paintedIn] counts it as painted; placed,
  /// it sat above the page and took every click (sigmadev.digital at 1366,
  /// "To the bottom", 3.47.10). It stays for readers and shows itself when
  /// the keyboard reaches it.
  bool _coversScreen(_Node control, int w) {
    for (final _Node run in runs) {
      if (run.container == control && run.items[w] != null) return false;
    }
    final List<double> box = control.boxes[w]!;
    final _Width width = widths[w];
    final double screen = width.width * (width.height > 0 ? width.height : width.width);
    return screen > 0 && box[2] * box[3] >= screen / 2;
  }

  /// Whether anything is painted inside [control]'s box at width [w]: one of
  /// its own runs, or a piece of the layer (an icon, an image, a surface).
  bool _paintedIn(_Node control, int w) {
    for (final _Node run in runs) {
      if (run.container == control && run.items[w] != null) return true;
    }
    final List<double> box = control.boxes[w]!;
    for (final _Item item in widths[w].items) {
      final List<double> r = item.rect;
      if (r[0] >= box[0] - 1 && r[1] >= box[1] - 1 &&
          r[0] + r[2] <= box[0] + box[2] + 1 && r[1] + r[3] <= box[1] + box[3] + 1) {
        return true;
      }
    }
    return false;
  }

  void _buildLayer() {
    final Map<String, _Node> byKey = <String, _Node>{};
    for (int w = 0; w < widths.length; w++) {
      final Map<String, int> seen = <String, int>{};
      for (final _Item item in widths[w].items) {
        if (item.used) continue;
        final String kind = switch (item.kind) {
          'b' => 'box',
          'i' => 'image',
          't' || 'e' => 'decor',
          _ => '',
        };
        if (kind.isEmpty) continue;
        if (kind == 'image' && _safeSource(item.json['src']) == null) continue;
        if (kind == 'decor' && item.text.isEmpty) continue;
        final String identity = switch (kind) {
          'box' => 'b|${item.json['bg']}|${item.json['g']}|${item.json['bd']}',
          'image' => 'i',
          _ => 't|${item.text}',
        };
        final int occurrence = seen[identity] = (seen[identity] ?? -1) + 1;
        final String key = '$identity#$occurrence';
        final _Node node = byKey.putIfAbsent(key, () {
          final _Node created = _Node('dvp${_ids++}', kind);
          layer.add(created);
          return created;
        });
        node.items[w] = item;
      }
    }
    // In paint order, so a later piece covers an earlier one even where two
    // share a z.
    layer.sort((_Node a, _Node b) => _firstZ(a).compareTo(_firstZ(b)));
  }

  int _firstZ(_Node node) => node.items.values.first.z;

  void _wrapText(List<_TextNode> texts) {
    for (final _TextNode text in texts) {
      if (text.slotOpen != null) {
        final bool whole =
            text.segments.length == 1 &&
            text.segments.single.start == 0 &&
            text.segments.single.end == text.norm.length;
        if (whole) {
          text.slotOpen!.replacement =
              '<span id="${text.segments.single.node.id}">${text.slotOpen!.source}';
          text.slotClose!.replacement = '${text.slotClose!.source}</span>';
        } else {
          text.slotOpen!.replacement =
              '<span class="dvu">${text.slotOpen!.source}';
          text.slotClose!.replacement = '${text.slotClose!.source}</span>';
        }
        continue;
      }
      final StringBuffer out = StringBuffer();
      int rawAt = 0;
      void plain(int end) {
        if (end <= rawAt) return;
        final String piece = text.raw.substring(rawAt, end);
        if (piece.trim().isEmpty) {
          out.write(_elementText.convert(piece));
        } else {
          // What the app does not paint as text: kept for readers.
          final String lead = piece.substring(
            0,
            piece.length - piece.trimLeft().length,
          );
          final String trail = piece.substring(piece.trimRight().length);
          out
            ..write(_elementText.convert(lead))
            ..write(
              '<span class="dvu">${_elementText.convert(piece.trim())}</span>',
            )
            ..write(_elementText.convert(trail));
        }
        rawAt = end;
      }

      for (final _Segment segment in text.segments) {
        final int rawStart = text.normToRaw[segment.start];
        final int rawEnd = text.normToRaw[segment.end - 1] + 1;
        plain(rawStart);
        out.write(
          '<span id="${segment.node.id}">${_subRuns(segment, text.raw.substring(rawStart, rawEnd))}</span>',
        );
        rawAt = rawEnd;
      }
      plain(text.raw.length);
      text.token.replacement = out.toString();
    }
  }

  /// [raw] with each run of the paragraph that is styled differently from its
  /// first in a span of its own.
  String _subRuns(_Segment segment, String raw) {
    final _Node node = segment.node;
    final _Item reference = node.items.values.first;
    final List<Map<String, Object?>> styles = reference.runs;
    if (styles.length < 2) return _elementText.convert(raw);
    // Which run each character of the paragraph's normalised text is in.
    final List<int> owner = <int>[];
    final StringBuffer joined = StringBuffer();
    bool space = true;
    for (int run = 0; run < styles.length; run++) {
      final String text = styles[run]['t'] as String? ?? '';
      for (int index = 0; index < text.length; index++) {
        final bool white = RegExp(r'\s').hasMatch(text[index]);
        if (white && space) continue;
        joined.write(white ? ' ' : text[index]);
        owner.add(run);
        space = white;
      }
    }
    // The same walk over the raw text, so each raw character has its run.
    final StringBuffer out = StringBuffer();
    int normIndex = 0;
    bool rawSpace = true;
    int? open;
    final String base = _inlineStyle(styles.first);
    for (int index = 0; index < raw.length; index++) {
      final bool white = RegExp(r'\s').hasMatch(raw[index]);
      int run = open ?? 0;
      if (!(white && rawSpace) && normIndex < owner.length) {
        run = owner[normIndex++];
      }
      rawSpace = white;
      final bool differs = run > 0 && _inlineStyle(styles[run]) != base;
      final int? want = differs ? run : null;
      if (want != open) {
        if (open != null) out.write('</span>');
        if (want != null) {
          final _Node sub = _Node('${node.id}-$want', 'sub')
            ..container = node
            ..subIndex = want;
          sub.items.addAll(node.items);
          if (!runs.any((_Node existing) => existing.id == sub.id)) {
            runs.add(sub);
          }
          out.write('<span id="${sub.id}">');
        }
        open = want;
      }
      out.write(_elementText.convert(raw[index]));
    }
    if (open != null) out.write('</span>');
    return out.toString();
  }

  String _layerHtml() {
    if (layer.isEmpty) return '';
    final StringBuffer out = StringBuffer(
      '<div class="dvp" aria-hidden="true">',
    );
    for (final _Node node in layer) {
      if (node.kind == 'image') {
        final _Item first = node.items.values.first;
        final bool belowFold = node.items.entries.every(
          (MapEntry<int, _Item> entry) =>
              entry.value.rect[1] > widths[entry.key].height,
        );
        out.write(
          '<img id="${node.id}" src="${_attribute.convert(_safeSource(first.json['src'])!)}" alt=""'
          ' decoding="async"${belowFold ? ' loading="lazy"' : ''}>',
        );
      } else {
        out.write('<i id="${node.id}"></i>');
      }
    }
    out.write('</div>');
    return out.toString();
  }

  // -- The stylesheet.

  /// The ranges of widths the stylesheet switches at: each captured width,
  /// and each midpoint between two. Each range takes its boxes from the
  /// segment it is in and its styles from its nearer captured width.
  List<({double from, int a, int b, int near})> get _ranges {
    if (widths.length == 1) {
      return <({double from, int a, int b, int near})>[
        (from: 0, a: 0, b: 0, near: 0),
      ];
    }
    final List<({double from, int a, int b, int near})> ranges =
        <({double from, int a, int b, int near})>[];
    for (int index = 0; index + 1 < widths.length; index++) {
      final double mid = (widths[index].width + widths[index + 1].width) / 2;
      ranges
        ..add((
          from: index == 0 ? 0 : widths[index].width,
          a: index,
          b: index + 1,
          near: index,
        ))
        ..add((from: mid, a: index, b: index + 1, near: index + 1));
    }
    return ranges;
  }

  (String, String) _css() {
    final StringBuffer out = StringBuffer();
    // Usable fonts first, outside every gate: a face is only fetched when
    // something on the page is drawn in it.
    final StringBuffer gated = StringBuffer();
    final int controlZ =
        widths.fold<int>(
          0,
          (int top, _Width width) => math.max(top, width.topZ),
        ) +
        1;
    int nextControlZ = controlZ;
    for (final _Node control in controls) {
      control.controlZ = nextControlZ++;
    }
    // Every control is stacked above everything painted, so its text and
    // focus ring are never under a box. What the app pins to the screen and
    // paints after the page's links -- a consent banner, a bottom sheet, an
    // app bar -- has to be above them too, or a link scrolled under it shows
    // through (sigmadev.digital's hero buttons through its consent banner,
    // Dartvel 3.47.9): such a piece, and every pinned control, is lifted
    // above all controls, keeping its own order. A pinned piece painted
    // before any control's content -- a background -- stays where it is.
    _lift = nextControlZ;
    final Set<_Node> controlSet = controls.toSet();
    int? first;
    for (final _Node node in <_Node>[...runs, ...layer]) {
      if (!controlSet.contains(node.container)) continue;
      for (final _Item item in node.items.values) {
        first = first == null ? item.z : math.min(first, item.z);
      }
    }
    _firstControlContentZ = first;

    gated
      ..write('.dv-fallback:has(>.dvl){padding:0;scrollbar-width:none}')
      ..write('.dv-fallback:has(>.dvl)::-webkit-scrollbar{display:none}')
      ..write('.dvl{position:relative;min-height:100%}')
      ..write(
        '.dvl *:is(h1,h2,h3,h4,h5,h6,p,ul,ol,li,pre,code,figure,figcaption,nav,main,footer,header,'
        'section,strong,em,label,div,blockquote,a){margin:0!important;padding:0;border:0;'
        'background:none;list-style:none;text-decoration:none;color:inherit}',
      )
      ..write('.dvl .dvp{display:block;pointer-events:none}')
      ..write(
        '.dvl .dvp>*{position:absolute;left:-99999px;display:block;box-sizing:border-box;margin:0}',
      )
      ..write(
        '.dvl [id^=dvr]{position:absolute;left:-99999px;display:block;margin:0;box-sizing:border-box;'
        'overflow-wrap:break-word;text-decoration:none}',
      )
      ..write('.dvl [id^=dvr] [id^=dvr]{position:static;display:inline}')
      ..write(
        '.dvl input,.dvl textarea{background:transparent;border:0;color:inherit;font:inherit;'
        'box-sizing:border-box}',
      );
    // Glyphs cut out of a gradient are drawn again when selected, in the
    // selection's own colour, so a selection never hides them.
    final bool gradientText = widths.any((_Width width) => width.items.any(
          (_Item item) => item.runs.any((Map<String, Object?> run) => run['g'] is String),
        ));
    if (gradientText) {
      gated.write('.dvl [id^=dvr]::selection{-webkit-text-fill-color:currentcolor}');
    }
    // A field's placeholder in the colour the app paints its hint.
    final StringBuffer darkHints = StringBuffer();
    for (final _Node node in controls) {
      if (node.hints.isEmpty) continue;
      final _Item hint = node.hints.values.first;
      final String? colour = _colour(hint.runs.isEmpty ? null : hint.runs.first['c']);
      if (colour != null) gated.write('#${node.id}::placeholder{color:$colour;opacity:1}');
      final _Item? dark = hint.dark;
      final String? darkColour = dark == null ? null : _colour(dark.runs.isEmpty ? null : dark.runs.first['c']);
      if (darkColour != null && darkColour != colour) {
        darkHints.write('#${node.id}::placeholder{color:$darkColour}');
      }
    }
    if (darkHints.isNotEmpty) gated.write('@media (prefers-color-scheme:dark){$darkHints}');
    for (final _Node node in layer) {
      if (node.kind != 'decor') continue;
      gated.write(
        '#${node.id}::before{content:"${_cssString(node.items.values.first.text)}"}',
      );
    }

    final List<({double from, int a, int b, int near})> ranges = _ranges;
    final Map<String, String> lastGeometry = <String, String>{};
    final Map<String, String> lastStyle = <String, String>{};
    final Map<String, String> lastDark = <String, String>{};
    final List<_Node> all = <_Node>[...layer, ...controls, ...runs];
    final Set<_Node> above = <_Node>{
      for (final _Node node in all)
        if (_aboveFold(node)) node,
    };
    final Map<String, List<String?>> geometries = <String, List<String?>>{
      for (final _Node node in all)
        if (node.kind != 'sub' && !node.inline) node.id: _geometries(node, ranges),
    };
    void placeAll(
      Iterable<_Node> nodes,
      StringBuffer into, {
      required bool withHeight,
    }) {
      for (int rangeIndex = 0; rangeIndex < ranges.length; rangeIndex++) {
        final ({double from, int a, int b, int near}) range =
            ranges[rangeIndex];
        final StringBuffer block = StringBuffer();
        final StringBuffer dark = StringBuffer();
        // The scroll height.
        final String height =
            'height:${_heightAware(_value(range, (int w) => <double>[_contentHeight(w)], 0), _contentSlope(range.near), range.near, _contentHeight, a: range.a, b: range.b)}';
        if (withHeight && lastGeometry['.dvl'] != height) {
          block.write('.dvl{$height}');
          lastGeometry['.dvl'] = height;
        }
        final Map<String, List<String>> styleGroups = <String, List<String>>{};
        final Map<String, List<String>> darkGroups = <String, List<String>>{};
        for (final _Node node in nodes) {
          if (node.kind != 'sub' && !node.inline) {
            final String? geometry = geometries[node.id]![rangeIndex];
            if (geometry != null) block.write('#${node.id}{$geometry}');
          }
          final _Item? item = _nearItem(node, range);
          if (item == null) continue;
          final String style = _style(node, item);
          bool styleWritten = false;
          if (style.isNotEmpty && lastStyle[node.id] != style) {
            styleGroups.putIfAbsent(style, () => <String>[]).add('#${node.id}');
            lastStyle[node.id] = style;
            styleWritten = true;
          }
          final String darkStyle = item.dark == null
              ? ''
              : _darkStyle(node, item, item.dark!);
          if (darkStyle.isNotEmpty &&
              (styleWritten || lastDark[node.id] != darkStyle)) {
            darkGroups
                .putIfAbsent(darkStyle, () => <String>[])
                .add('#${node.id}');
            lastDark[node.id] = darkStyle;
          }
        }
        styleGroups.forEach(
          (String style, List<String> ids) =>
              block.write('${ids.join(',')}{$style}'),
        );
        darkGroups.forEach(
          (String style, List<String> ids) =>
              dark.write('${ids.join(',')}{$style}'),
        );
        if (dark.isNotEmpty) {
          block.write('@media (prefers-color-scheme:dark){$dark}');
        }
        if (block.isEmpty) continue;
        if (range.from <= 0) {
          into.write(block);
        } else {
          into.write('@media (min-width:${_num(range.from)}px){$block}');
        }
      }
    }

    placeAll(all.where(above.contains), gated, withHeight: true);
    final StringBuffer later = StringBuffer();
    placeAll(
      all.where((_Node node) => !above.contains(node)),
      later,
      withHeight: false,
    );

    out.write(_fontFaces());
    out.write('.dvl .dvp{display:none}');
    out.write(
      '@media screen and (scripting:enabled){html:not([data-dv-app]){$gated'
      '.dvl .dvu{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);'
      'white-space:nowrap}'
      // A link or field kept only for readers (a closed menu's) is still a
      // Tab stop; when the keyboard reaches it, it shows itself where the
      // reader can see it rather than taking an invisible stop.
      '.dvl .dvu:focus-within,.dvl .dvf:focus'
      '{position:fixed!important;left:8px!important;top:8px!important;width:auto!important;'
      'height:auto!important;display:block!important;'
      'overflow:visible;clip-path:none;white-space:normal;z-index:2147483647;padding:8px 12px;'
      'background:Canvas;color:CanvasText;outline:2px solid Highlight;border-radius:4px}'
      '.dvl .dvf:focus .dvu{position:static;width:auto;'
      'height:auto;overflow:visible;clip-path:none;white-space:normal}}}',
    );
    final String rest = later.isEmpty
        ? ''
        : '@media screen and (scripting:enabled){html:not([data-dv-app]){$later}}';
    return (out.toString(), rest);
  }

  /// Whether [node] is on the first screens at some width: pinned, or
  /// starting within two screen heights of the top.
  bool _aboveFold(_Node node) {
    final _Node subject = node.kind == 'sub' ? node.container! : node;
    for (int w = 0; w < widths.length; w++) {
      final List<double>? box = subject.boxes[w] ?? subject.items[w]?.rect;
      if (box == null) continue;
      final _Item? item = subject.items[w];
      if (item != null && !item.scrolls) return true;
      if (box[1] < widths[w].height * 2) return true;
    }
    return false;
  }

  /// How much the scroll height grows per pixel of screen height at [w].
  double _contentSlope(int w) {
    final double? tall = widths[w].tallHeight;
    if (tall == null) return 0;
    double bottom = tall;
    for (final _Item item in widths[w].items) {
      if (!item.scrolls) continue;
      // Not found at the second height: taken to stay where it is.
      final List<double> rect = item.tall?.rect ?? item.rect;
      bottom = math.max(bottom, rect[1] + rect[3]);
    }
    return (bottom - _contentHeight(w)) / (tall - widths[w].height);
  }

  /// How each of a node's box values grows per pixel of screen height at
  /// [w], from the capture at a second height; null when it does not.
  List<double>? _heightSlope(_Node node, int w) {
    final double? tall = widths[w].tallHeight;
    if (tall == null) return null;
    final double span = tall - widths[w].height;
    List<double>? base;
    List<double>? other;
    if (node.kind == 'control' || node.kind == 'field') {
      base = node.boxes[w];
      other = node.tallBoxes[w];
    } else {
      final _Item? item = node.items[w];
      base = item?.rect;
      other = item?.tall?.rect;
      final _Node? container = node.container;
      final List<double>? outer = container?.boxes[w];
      if (outer != null && base != null && other != null) {
        final List<double>? outerTall = container!.tallBoxes[w];
        if (outerTall == null) return null;
        base = <double>[base[0] - outer[0], base[1] - outer[1], base[2], base[3]];
        other = <double>[other[0] - outerTall[0], other[1] - outerTall[1], other[2], other[3]];
      }
    }
    if (base == null || other == null) return null;
    final List<double> slope = <double>[
      for (int index = 0; index < 4; index++) (other[index] - base[index]) / span,
    ];
    return slope.every((double value) => value.abs() < 0.001) ? null : slope;
  }

  /// A length that grows by [slope] per pixel of screen height: [plain] when
  /// it does not, otherwise each captured value taken back to a screen of no
  /// height (so the heights two widths were captured at are not read as a
  /// change with width), moved linearly between widths [a] and [b] when both
  /// are given, plus the screen's height in `dvh`.
  String _heightAware(String plain, double slope, int near, double Function(int w) at, {int? a, int? b}) {
    if (slope.abs() < 0.001) return plain;
    double level(int w) => at(w) - slope * widths[w].height;
    double px, vw = 0;
    if (a != null && b != null && a != b) {
      final double wA = widths[a].width, wB = widths[b].width;
      vw = (level(b) - level(a)) / (wB - wA) * 100;
      px = level(a) - vw / 100 * wA;
    } else {
      px = level(near);
    }
    return _lengths(px, vw, slope * 100);
  }

  double _contentHeight(int w) {
    double bottom = widths[w].height;
    for (final _Item item in widths[w].items) {
      if (item.scrolls) bottom = math.max(bottom, item.rect[1] + item.rect[3]);
    }
    return bottom;
  }

  _Item? _nearItem(_Node node, ({double from, int a, int b, int near}) range) =>
      node.items[range.near];

  /// A node's box at width [w], relative to what it is positioned in, and
  /// whether it is pinned.
  (List<double>, bool)? _boxAt(_Node node, int w) {
    if (node.kind == 'control' || node.kind == 'field') {
      final List<double>? box = node.boxes[w];
      if (box == null) return null;
      return (box, !_controlScrolls(node, w));
    }
    final _Item? item = node.items[w];
    if (item == null) return null;
    final List<double> rect = item.rect;
    final _Node? container = node.container;
    final List<double>? outer = container == null ? null : container.boxes[w];
    if (outer != null) {
      return (
        <double>[rect[0] - outer[0], rect[1] - outer[1], rect[2], rect[3]],
        false,
      );
    }
    return (rect, !item.scrolls);
  }

  bool _controlScrolls(_Node control, int w) {
    for (final _Node run in runs) {
      if (run.container == control && run.items[w] != null) {
        return run.items[w]!.scrolls;
      }
    }
    final List<double> box = control.boxes[w]!;
    for (final _Item item in widths[w].items) {
      if (item.rect[0] >= box[0] - 1 &&
          item.rect[1] >= box[1] - 1 &&
          item.rect[0] + item.rect[2] <= box[0] + box[2] + 1 &&
          item.rect[1] + item.rect[3] <= box[1] + box[3] + 1) {
        return item.scrolls;
      }
    }
    return true;
  }

  /// A node's placement in [range]: null when it is not on screen there.
  ({String box, String display, String position, int? z})? _placement(
    _Node node,
    ({double from, int a, int b, int near}) range,
  ) {
    final (List<double>, bool)? near = _boxAt(node, range.near);
    final bool control = node.kind == 'control' || node.kind == 'field';
    if (near == null) {
      // A link not placed at this width whose text is painted: in the flow,
      // so its text is placed on its own.
      if (control && runs.any((_Node run) => run.container == node && run.items[range.near] != null)) {
        return (box: '', display: 'inline', position: 'static', z: null);
      }
      return null;
    }
    final (List<double>, bool)? a = _boxAt(node, range.a);
    final (List<double>, bool)? b = _boxAt(node, range.b);
    // Moves linearly between the two widths when it is on screen, and placed
    // the same way, at both.
    final bool linear =
        a != null &&
        b != null &&
        a.$2 == b.$2 &&
        range.a != range.b &&
        _sameContainer(node, range.a, range.b);
    String v(int index) => linear
        ? _linear(
            widths[range.a].width,
            a.$1[index],
            widths[range.b].width,
            b.$1[index],
          )
        : '${_num(near.$1[index])}px';
    final List<double>? slope = _heightSlope(node, range.near);
    String placed(int index) => _heightAware(
      v(index),
      slope == null ? 0 : slope[index],
      range.near,
      (int w) => (w == range.a ? a : w == range.b ? b : near)!.$1[index],
      a: linear ? range.a : null,
      b: linear ? range.b : null,
    );
    final bool pinned = near.$2;
    final _Item? item = node.items[range.near];
    final bool clamp =
        item != null &&
        item.kind == 't' &&
        (item.json['ml'] as num? ?? 0) > 1 &&
        item.json['ell'] == true;
    final bool fixed = control
        ? pinned
        : pinned && node.container?.boxes[range.near] == null;
    final int? z = control ? node.controlZ : item?.z;
    final int? first = _firstControlContentZ;
    // Pinned over the page's links: see _css.
    final bool lifted = fixed && z != null && first != null && (control || z > first);
    return (
      box: 'left:${placed(0)};top:${placed(1)};width:${placed(2)};height:${placed(3)}',
      display: clamp ? '-webkit-box' : 'block',
      position: fixed ? 'fixed' : 'absolute',
      z: lifted ? z + _lift : z,
    );
  }

  /// [node]'s declaration in each of [ranges], or null where nothing
  /// changes from the range before (the ranges are cumulative). Display is
  /// written when the node is off screen in some range or clamped, position
  /// when it is pinned in some range, so a later range always undoes an
  /// earlier one; the z-index when it changes.
  List<String?> _geometries(
    _Node node,
    List<({double from, int a, int b, int near})> ranges,
  ) {
    final List<({String box, String display, String position, int? z})?>
    placed = <({String box, String display, String position, int? z})?>[
      for (final ({double from, int a, int b, int near}) range in ranges)
        _placement(node, range),
    ];
    // A control the capture found no box for at any width is left alone.
    if ((node.kind == 'control' || node.kind == 'field') && !node.captured) {
      return List<String?>.filled(ranges.length, null);
    }
    final bool sayDisplay = placed.any(
      (p) => p == null || p.display != 'block',
    );
    final bool sayPosition =
        placed.any((p) => p != null && p.position != 'absolute') ||
        (node.kind == 'control' || node.kind == 'field');
    final List<String?> out = <String?>[];
    String? previous;
    int? lastZ;
    for (final p in placed) {
      final String key = p == null
          ? 'none'
          : '${p.box}|${p.display}|${p.position}|${p.z}';
      if (key == previous) {
        out.add(null);
        continue;
      }
      previous = key;
      if (p == null) {
        out.add('display:none');
        continue;
      }
      out.add(
        <String>[
          if (p.box.isNotEmpty) p.box,
          if (sayDisplay) 'display:${p.display}',
          if (sayPosition) 'position:${p.position}',
          if (p.z != null && p.z != lastZ) 'z-index:${p.z}',
        ].join(';'),
      );
      lastZ = p.z ?? lastZ;
    }
    return out;
  }

  bool _sameContainer(_Node node, int a, int b) {
    final _Node? container = node.container;
    if (container == null) return true;
    return (container.boxes[a] == null) == (container.boxes[b] == null);
  }

  String _value(
    ({double from, int a, int b, int near}) range,
    List<double> Function(int w) at,
    int index,
  ) {
    if (range.a == range.b) return '${_num(at(range.near)[index])}px';
    return _linear(
      widths[range.a].width,
      at(range.a)[index],
      widths[range.b].width,
      at(range.b)[index],
    );
  }

  // -- Styles.

  String _style(_Node node, _Item item) {
    // In a sentence's line: styled as a run inside it, its line the sentence's.
    if (node.inline) {
      return node.kind == 'run' && item.runs.isNotEmpty ? _inlineStyle(item.runs.first) : '';
    }
    switch (node.kind) {
      case 'run':
        return _textStyle(
          item,
          item.runs.isEmpty ? const <String, Object?>{} : item.runs.first,
        );
      case 'sub':
        final List<Map<String, Object?>> styles = item.runs;
        if (node.subIndex >= styles.length) return '';
        return _inlineStyle(styles[node.subIndex]);
      case 'field':
        final Map<String, Object?> run =
            item.runs.isEmpty ? const <String, Object?>{} : item.runs.first;
        (double, double)? pad;
        (double, double)? vertical;
        node.items.forEach((int w, _Item own) {
          if (identical(own, item)) {
            pad = node.pads[w];
            vertical = node.verticalPads[w];
          }
        });
        return <String>[
          'font:${_font(run, item.json['lh'])}',
          ..._inlineExtras(run),
          'text-align:${_cssWord(item.json['al']) ?? 'left'}',
          if (pad != null)
            'padding:${_num(vertical?.$1 ?? 0)}${vertical == null ? '' : 'px'} '
                '${_num(pad!.$2)}px ${_num(vertical?.$2 ?? 0)}${vertical == null ? '' : 'px'} ${_num(pad!.$1)}px',
          if (item.json['nw'] != true) 'white-space:pre-wrap;resize:none;overflow:auto',
        ].join(';');
      case 'decor':
        return _textStyle(
              item,
              item.runs.isEmpty ? const <String, Object?>{} : item.runs.first,
            ) +
            ';user-select:none';
      case 'box':
        return _boxStyle(item);
      case 'image':
        final List<String> out = <String>[
          'object-fit:${_cssWord(item.json['fit']) ?? 'contain'}',
          if (item.json['pos'] is String)
            'object-position:${_cssWords(item.json['pos'] as String)}',
          if (item.json['rad'] is List)
            'border-radius:${_radii(item.json['rad'])}',
          if (item.json['op'] is num)
            'opacity:${_num((item.json['op']! as num).toDouble())}',
          ..._clip(item),
        ];
        return out.join(';');
      default:
        return '';
    }
  }

  String _darkStyle(_Node node, _Item light, _Item dark) {
    switch (node.kind) {
      case 'run':
      case 'decor':
      case 'field':
        final String colour =
            _colour(dark.runs.isEmpty ? null : dark.runs.first['c']) ?? '';
        final String lightColour =
            _colour(light.runs.isEmpty ? null : light.runs.first['c']) ?? '';
        return colour.isEmpty || colour == lightColour ? '' : 'color:$colour';
      case 'sub':
        if (node.subIndex >= dark.runs.length) return '';
        final String? colour = _colour(dark.runs[node.subIndex]['c']);
        final Object? gradient = dark.runs[node.subIndex]['g'];
        final Object? lightGradient = node.subIndex < light.runs.length
            ? light.runs[node.subIndex]['g']
            : null;
        return <String>[
          if (colour != null) 'color:$colour',
          if (gradient is String && gradient != lightGradient)
            'background-image:${_cssValue(gradient)}',
        ].join(';');
      case 'box':
        final String lightStyle = _boxStyle(light);
        final String darkStyle = _boxStyle(dark);
        return lightStyle == darkStyle ? '' : darkStyle;
      case 'image':
        final String? source = _safeSource(dark.json['src']);
        return source == null || source == _safeSource(light.json['src'])
            ? ''
            : 'content:url("${_cssString(source)}")';
      default:
        return '';
    }
  }

  String _textStyle(_Item item, Map<String, Object?> run) {
    final List<String> out = <String>[
      'font:${_font(run, item.json['lh'])}',
      ..._inlineExtras(run),
      'text-align:${_cssWord(item.json['al']) ?? 'left'}',
      if (item.json['dir'] == 'rtl') 'direction:rtl',
      'white-space:${item.json['nw'] == true ? 'pre' : 'pre-wrap'}',
      if (item.json['ell'] == true && (item.json['ml'] as num? ?? 1) <= 1)
        'overflow:hidden;text-overflow:ellipsis',
      if (item.json['ell'] == true && (item.json['ml'] as num? ?? 1) > 1)
        '-webkit-line-clamp:${(item.json['ml']! as num).toInt()};-webkit-box-orient:vertical;overflow:hidden',
      if (item.json['op'] is num)
        'opacity:${_num((item.json['op']! as num).toDouble())}',
      ..._clip(item),
    ];
    return out.join(';');
  }

  /// What a run inside a paragraph sets: everything but the line.
  String _inlineStyle(Map<String, Object?> run) {
    final String family = _family(run);
    return <String>[
      'font-family:$family',
      'font-size:${_num(_double(run['fs'], 14))}px',
      'font-weight:${(run['fw'] as num? ?? 400).toInt()}',
      'font-style:${run['it'] == true ? 'italic' : 'normal'}',
      ..._inlineExtras(run),
    ].join(';');
  }

  List<String> _inlineExtras(Map<String, Object?> run) => <String>[
    'color:${_colour(run['c']) ?? '#000000'}',
    if (run['ls'] is num) 'letter-spacing:${_num(_double(run['ls'], 0))}px',
    if (run['ws'] is num) 'word-spacing:${_num(_double(run['ws'], 0))}px',
    if (run['d'] is String)
      'text-decoration:${_cssWords(run['d'] as String)}${_colour(run['dc']) == null ? '' : ' ${_colour(run['dc'])}'}',
    if (run['sh'] is String) 'text-shadow:${_cssValue(run['sh'] as String)}',
    // Filled with a gradient (DVGradientSpan): still the text itself, its
    // glyphs cut out of the gradient, which runs along its line pieces laid
    // end to end as the app paints it.
    if (run['g'] is String) ...<String>[
      'background-image:${_cssValue(run['g'] as String)}',
      '-webkit-background-clip:text',
      'background-clip:text',
      '-webkit-text-fill-color:transparent',
    ],
  ];

  String _font(Map<String, Object?> run, Object? lineHeight) {
    final String size = _num(_double(run['fs'], 14));
    final String line = lineHeight is num
        ? '${_num(lineHeight.toDouble())}px'
        : 'normal';
    return '${run['it'] == true ? 'italic ' : ''}${(run['fw'] as num? ?? 400).toInt()} ${size}px/$line ${_family(run)}';
  }

  String _family(Map<String, Object?> run) {
    final String family = run['f'] is String && (run['f'] as String).isNotEmpty
        ? run['f'] as String
        : dvLayoutDefaultFamily;
    families.add(family);
    // Only the fallbacks the app bundles: Flutter on the web draws with
    // those and its own fallback fonts, never the visitor's system fonts.
    // The theme's list is the capture host's platform default (Material's
    // Linux list on a Linux build box: Ubuntu, Cantarell, DejaVu Sans...);
    // named here, each missing one cost a font lookup before the first
    // paint, and one present drew in a font the app never shows.
    final List<String> fallback = <String>[
      for (final Object? name
          in (run['ff'] as List<Object?>? ?? const <Object?>[]))
        if (name is String && name.isNotEmpty && fonts.containsKey(name)) name,
    ];
    families.addAll(fallback);
    return <String>[
      '"${_cssString(family)}"',
      for (final String name in fallback) '"${_cssString(name)}"',
      'sans-serif',
    ].join(',');
  }

  String _boxStyle(_Item item) {
    final Map<String, Object?> json = item.json;
    final List<String> out = <String>[
      if (_colour(json['bg']) != null)
        'background-color:${_colour(json['bg'])}',
      if (json['g'] is String)
        'background-image:${_cssValue(json['g'] as String)}',
      if (json['rad'] is List) 'border-radius:${_radii(json['rad'])}',
      if (json['bd'] is List) ..._border(json['bd']! as List<Object?>),
      if (json['sh'] is String) 'box-shadow:${_cssValue(json['sh'] as String)}',
      if (json['op'] is num) 'opacity:${_num((json['op']! as num).toDouble())}',
      ..._clip(item),
    ];
    return out.join(';');
  }

  List<String> _border(List<Object?> border) {
    if (border.length < 2 || border[0] is! num) return const <String>[];
    final String colour = _colour(border[1]) ?? '#000000';
    if (border.length > 2 && border[2] is List) {
      final List<Object?> sides = border[2]! as List<Object?>;
      return <String>[
        'border-style:solid',
        'border-color:$colour',
        'border-width:${sides.map((Object? side) => '${_num(_double(side, 0))}px').join(' ')}',
      ];
    }
    return <String>[
      'border:${_num((border[0]! as num).toDouble())}px solid $colour',
    ];
  }

  List<String> _clip(_Item item) {
    final Object? clip = item.json['cl'];
    if (clip is! List || clip.length < 4) return const <String>[];
    final List<double> rect = item.rect;
    final double top = math.max(0, _double(clip[1], 0) - rect[1]);
    final double right = math.max(0, rect[0] + rect[2] - _double(clip[2], 0));
    final double bottom = math.max(0, rect[1] + rect[3] - _double(clip[3], 0));
    final double left = math.max(0, _double(clip[0], 0) - rect[0]);
    return <String>[
      'clip-path:inset(${_num(top)}px ${_num(right)}px ${_num(bottom)}px ${_num(left)}px)',
    ];
  }

  String _fontFaces() {
    final StringBuffer out = StringBuffer();
    for (final String family in families) {
      final List<DVLayoutFont>? files = fonts[family];
      if (files == null) continue;
      for (final DVLayoutFont font in files) {
        final String? url = _safeSource(font.url);
        if (url == null) continue;
        out.write(
          '@font-face{font-family:"${_cssString(family)}";src:url(${_cssUrl(url)});'
          'font-weight:${font.weight ?? (files.length == 1 ? '1 1000' : 400)};'
          'font-style:${font.style == 'italic' ? 'italic' : 'normal'};font-display:swap}',
        );
      }
    }
    return out.toString();
  }
}

// ---------------------------------------------------------------------------
// Values.

/// `vA` at `wA` to `vB` at `wB` as `calc(Apx + Bvw)`.
String _linear(double wA, double vA, double wB, double vB) {
  final double slope = (vB - vA) / (wB - wA);
  final double intercept = vA - slope * wA;
  final double viewport = (slope * 100 * 10000).roundToDouble() / 10000;
  if (viewport == 0) return '${_num(vA)}px';
  return 'calc(${_num(intercept)}px + ${_num(viewport)}vw)';
}

/// `px + vw + vh` as CSS, the screen's height in `dvh` (the height it has
/// now, toolbars and all, which is the height the app lays out in).
String _lengths(double px, double vw, double vh) {
  double round(double value) => (value * 10000).roundToDouble() / 10000;
  final double width = round(vw), height = round(vh);
  final List<String> terms = <String>[
    if (_num(px) != '0' || (width == 0 && height == 0)) '${_num(px)}px',
    if (width != 0) '${_num(width)}vw',
    if (height != 0) '${_num(height)}dvh',
  ];
  if (terms.length == 1) return terms.single;
  return 'calc(${terms.join(' + ')})';
}

String _num(double value) {
  final double rounded = (value * 100).roundToDouble() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.round().toString();
  return rounded.toString();
}

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

String _radii(Object? value) {
  final List<Object?> radii = value is List ? value : const <Object?>[];
  return radii.take(4).map((Object? r) => '${_num(_double(r, 0))}px').join(' ');
}

final RegExp _colourPattern = RegExp(
  r'^(#[0-9a-fA-F]{3,8}|rgba?\([0-9., ]+\))$',
);

String? _colour(Object? value) =>
    value is String && _colourPattern.hasMatch(value) ? value : null;

String? _cssWord(Object? value) =>
    value is String && RegExp(r'^[a-z-]+$').hasMatch(value) ? value : null;

String _cssWords(String value) =>
    value.replaceAll(RegExp(r'[^a-z0-9%. -]'), '');

/// A value made of numbers, units, colours and gradient words only.
String _cssValue(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9#%.,() -]'), '');

/// [text] inside a CSS string: quotes, backslashes, line breaks, `<` and
/// anything outside ASCII escaped, so nothing in it ends the string or the
/// style element.
String _cssString(String text) {
  final StringBuffer out = StringBuffer();
  for (final int rune in text.runes) {
    if (rune == 0x22 ||
        rune == 0x5C ||
        rune == 0x3C ||
        rune == 0x3E ||
        rune < 0x20 ||
        rune > 0x7E) {
      out.write('\\${rune.toRadixString(16)} ');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

String _cssUrl(String url) => url.replaceAllMapped(
  RegExp(r'''[\s()'"\\<>]'''),
  (Match c) => Uri.encodeComponent(c.group(0)!),
);

/// A source a page may load: http(s), or a path relative to the site.
String? _safeSource(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final String source = value.trim();
  final Uri? uri = Uri.tryParse(source);
  if (uri == null) return null;
  if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
    return null;
  }
  return source;
}

/// A character that reads as text: not a space, and not in a private use
/// area, where icon fonts put their glyphs.
bool _readable(int rune) =>
    !(rune >= 0xE000 && rune <= 0xF8FF) &&
    !(rune >= 0xF0000) &&
    String.fromCharCode(rune).trim().isNotEmpty;
