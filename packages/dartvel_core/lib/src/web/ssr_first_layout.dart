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
}

class _Element {
  _Element(this.node);
  final _Node node;
}

class _Layout {
  _Layout(this.widths, this.fonts);

  final List<_Width> widths;
  final Map<String, List<DVLayoutFont>> fonts;
  final List<_Node> runs = <_Node>[];
  final List<_Node> controls = <_Node>[];
  final List<_Node> layer = <_Node>[];
  final Set<String> families = <String>{};
  int _ids = 0;

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

    final List<_TextNode> texts = _readDocument(tokens);
    _assignControlBoxes();
    _matchText(texts);
    _matchControls();
    _buildLayer();
    _wrapText(texts);

    final StringBuffer body = StringBuffer();
    for (final _Token token in tokens) {
      body.write(token.replacement ?? token.source);
    }
    final (String first, String rest) = _css();
    // What is below the fold is placed by a second stylesheet after the
    // document, so the first screen paints without waiting for it.
    return '<div class="dvl"><style class="dvl-style">$first</style>'
        '${_layerHtml()}$body${rest.isEmpty ? '' : '<style class="dvl-style">$rest</style>'}</div>';
  }

  // -- Reading the document.

  final List<(_Node node, String key, _Token token)> _docControls =
      <(_Node, String, _Token)>[];

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
        if (item.kind != 't' || item.norm.isEmpty) continue;
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
      bool late(_TextNode text) {
        final _Node? control = text.control?.node;
        return control != null && control.boxes.isNotEmpty && control.boxes[w] == null;
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

  void _matchControls() {
    // A box with nothing painted in it is a control that is laid out and not
    // on screen: a closed menu's links. Placed, they would sit on top of the
    // page and take its clicks and its Tab stops. A field keeps its box: its
    // border is drawn by a painter the snapshot cannot read.
    for (final (_Node node, String _, _Token _) in _docControls) {
      if (node.kind == 'field') continue;
      if (node.boxes.isNotEmpty) node.captured = true;
      for (final int w in node.boxes.keys.toList()) {
        if (!_paintedIn(node, w)) node.boxes.remove(w);
      }
    }
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
          't' => 'decor',
          _ => '',
        };
        if (kind.isEmpty) continue;
        if (kind == 'image' && _safeSource(item.json['src']) == null) continue;
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
        if (node.kind != 'sub') node.id: _geometries(node, ranges),
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
          if (node.kind != 'sub') {
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
      '.dvl .dvu:focus-within,.dvl *:is(a,button,input,textarea,select,[tabindex]):focus:not(:has([id^=dvr]))'
      '{position:fixed!important;left:8px!important;top:8px!important;width:auto!important;'
      'height:auto!important;display:block!important;'
      'overflow:visible;clip-path:none;white-space:normal;z-index:2147483647;padding:8px 12px;'
      'background:Canvas;color:CanvasText;outline:2px solid Highlight;border-radius:4px}'
      '.dvl *:is(a,button,[tabindex]):focus:not(:has([id^=dvr])) .dvu{position:static;width:auto;'
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
      final _Item? other = item.tall;
      if (item.scrolls && other != null) {
        bottom = math.max(bottom, other.rect[1] + other.rect[3]);
      }
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
    return (
      box: 'left:${placed(0)};top:${placed(1)};width:${placed(2)};height:${placed(3)}',
      display: clamp ? '-webkit-box' : 'block',
      position: fixed ? 'fixed' : 'absolute',
      z: control ? node.controlZ : item?.z,
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
    final List<String> fallback = <String>[
      for (final Object? name
          in (run['ff'] as List<Object?>? ?? const <Object?>[]))
        if (name is String && name.isNotEmpty) name,
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
