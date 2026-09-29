/// The documentation document: what `dartvel docs` writes for the
/// application to draw.
///
/// `dartvel docs` used to write nine pages of hand-authored HTML with a
/// stylesheet in it, and the application's own theme never touched any of
/// them. Those pages are the site now: `dartvel docs` compiles `DVDocsApp`
/// and writes this beside it, and the app renders every page from it. So this
/// is a description of a page, in terms a widget can be built from, and it
/// carries no markup -- a doc comment is a sentence somebody wrote, and a
/// sentence is data.
///
/// Everything here crosses a process boundary, so every value has to survive
/// `toJson`, a file, and `fromJson` unchanged. What that costs is a decision
/// to say, in a type, what a link is: a [DVDocsTarget] names a page in the
/// document and an anchor in it, or a place outside. A string would be
/// shorter, and a string is a path that drifts the moment a page moves.
library;

/// The file the document is written as, and the one the app reads.
const String dvDocsPayloadFile = 'docs.json';

/// The project graph, published beside the document.
///
/// Not part of the document: it is the same body of data `dartvel inspect`
/// and `dartvel mcp` answer from, published as the raw file it is, so a
/// reader can diff it against a commit.
const String dvDocsGraphFile = 'graph.json';

/// Something the documentation build found wrong with what it was asked to
/// render. Both codes are drift -- see `DV-DOCS` in the diagnostics registry.
/// A generated site cannot be out of date with the code; what it can be is
/// pointed at something that is gone.
class DVDocsFinding {
  const DVDocsFinding({
    required this.code,
    required this.message,
    required this.source,
  });

  /// `DV-DOCS-001` or `DV-DOCS-002`.
  final String code;

  final String message;

  /// Where to look, as `path:line` relative to the project.
  final String source;

  factory DVDocsFinding.fromJson(Map<String, Object?> json) => DVDocsFinding(
        code: json['code']! as String,
        message: json['message']! as String,
        source: json['source']! as String,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'message': message,
        'source': source,
      };

  @override
  String toString() => '$code  $source  $message';
}

/// Where a link goes: a page of this document and an anchor in it, or
/// somewhere outside it.
///
/// Anchors are the block and row ids below, not element ids, because there
/// are no elements. A link is a pair of names the application resolves, and
/// one that names nothing is a link to nowhere rather than a 404 in a page
/// whose whole job is to be right about what exists.
class DVDocsTarget {
  /// A page of the document, and optionally an anchor inside it.
  const DVDocsTarget.page(this.page, {this.anchor}) : href = null;

  /// Somewhere outside: an absolute URL, or a path relative to the site's own
  /// root.
  const DVDocsTarget.external(this.href) : page = null, anchor = null;

  final String? page;
  final String? anchor;
  final String? href;

  factory DVDocsTarget.fromJson(Map<String, Object?> json) =>
      json['href'] != null
          ? DVDocsTarget.external(json['href']! as String)
          : DVDocsTarget.page(
              json['page']! as String,
              anchor: json['anchor'] as String?,
            );

  Map<String, Object?> toJson() => <String, Object?>{
        if (page != null) 'page': page,
        if (anchor != null) 'anchor': anchor,
        if (href != null) 'href': href,
      };

  @override
  bool operator ==(Object other) =>
      other is DVDocsTarget &&
      other.page == page &&
      other.anchor == anchor &&
      other.href == href;

  @override
  int get hashCode => Object.hash(page, anchor, href);
}

/// A run of text inside a block, and what it is drawn as.
///
/// The kinds are the whole vocabulary the application draws. A new one is a
/// change on both sides of the payload at once, which is why
/// `docs_site_test.dart` enumerates them: an unknown kind is the one thing
/// that could make this document mean something other than what it says.
class DVDocsSpan {
  const DVDocsSpan(this.kind, this.text, [this.target]);

  /// Prose.
  const DVDocsSpan.text(String text) : this('text', text);

  /// Code, as written: a type, a path, a field, a signature fragment.
  const DVDocsSpan.code(String text) : this('code', text);

  const DVDocsSpan.strong(String text) : this('strong', text);

  /// A chip, for the one thing the site labels rather than states.
  const DVDocsSpan.badge(String text) : this('badge', text);

  /// An action no policy method answers. Said rather than left blank: a blank
  /// cell reads as a value the build could not find.
  const DVDocsSpan.denied([String text = 'denied']) : this('denied', text);

  /// A reference to a node that is not in the project. Marked, unlinked.
  const DVDocsSpan.gone(String text) : this('gone', text);

  /// A source path, or the absence of one.
  const DVDocsSpan.note(String text) : this('note', text);

  /// Something the build found wrong.
  const DVDocsSpan.finding(String text) : this('finding', text);

  const DVDocsSpan.link(String text, DVDocsTarget target)
      : this('link', text, target);

  /// `text`, `code`, `strong`, `link`, `badge`, `denied`, `gone`, `note` or
  /// `finding`.
  final String kind;

  /// The characters, verbatim. Nothing here is escaped on the way out, because
  /// there is nothing that would read them as anything but characters.
  final String text;

  /// Set for [link] and nowhere else.
  final DVDocsTarget? target;

  factory DVDocsSpan.fromJson(Map<String, Object?> json) => DVDocsSpan(
        json['kind']! as String,
        json['text']! as String,
        json['target'] == null
            ? null
            : DVDocsTarget.fromJson(
                _as(json['target']),
              ),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'text': text,
        if (target != null) 'target': target!.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is DVDocsSpan &&
      other.kind == kind &&
      other.text == text &&
      other.target == target;

  @override
  int get hashCode => Object.hash(kind, text, target);
}

/// One item of a list, and the id the test -- and a reader scanning for the
/// request lifecycle -- finds it by.
class DVDocsListItem {
  const DVDocsListItem(this.spans, [this.id]);

  final List<DVDocsSpan> spans;
  final String? id;

  factory DVDocsListItem.fromJson(Map<String, Object?> json) => DVDocsListItem(
        _spans(json['spans']),
        json['id'] as String?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        if (id != null) 'id': id,
        'spans': _jsonSpans(spans),
      };
}

/// A column of a table, and the action or field it holds.
class DVDocsColumn {
  const DVDocsColumn(this.label, [this.id]);

  final String label;
  final String? id;

  factory DVDocsColumn.fromJson(Map<String, Object?> json) => DVDocsColumn(
        json['label']! as String,
        json['id'] as String?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'label': label,
        if (id != null) 'id': id,
      };
}

/// A row of a table, addressable by [id] so a decision record naming a
/// field links to that field and not to the table it sits in.
class DVDocsRow {
  const DVDocsRow(this.cells, [this.id]);

  final List<List<DVDocsSpan>> cells;
  final String? id;

  factory DVDocsRow.fromJson(Map<String, Object?> json) => DVDocsRow(
        <List<DVDocsSpan>>[
          for (final Object? cell in json['cells']! as List<Object?>)
            _spans(cell),
        ],
        json['id'] as String?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        if (id != null) 'id': id,
        'cells': <List<Map<String, Object?>>>[
          for (final List<DVDocsSpan> cell in cells) _jsonSpans(cell),
        ],
      };
}

/// A block of a page. Five of them, and the application draws each one; a
/// sixth is a change to both sides of the payload.
sealed class DVDocsBlock {
  const DVDocsBlock();

  static const String paragraphKind = 'paragraph';
  static const String headingKind = 'heading';
  static const String listKind = 'list';
  static const String codeKind = 'code';
  static const String tableKind = 'table';

  /// What this block is called in the document.
  String get kind;

  /// The name a link may point at this block by, or null.
  String? get anchor;

  /// What this block is on the wire. Every kind writes its own shape.
  Map<String, Object?> toJson();

  /// The text of [spans], as one string. For tests, and for a page's own
  /// search index.
  static String plain(List<DVDocsSpan> spans) =>
      spans.map((DVDocsSpan s) => s.text).join();

  factory DVDocsBlock.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        paragraphKind => DVDocsParagraph(_spans(json['spans'])),
        headingKind => DVDocsHeading(
            (json['level']! as num).toInt(),
            _spans(json['spans']),
            anchor: json['anchor'] as String?,
          ),
        listKind => DVDocsList(
            (json['ordered']! as bool?) ?? false,
            <DVDocsListItem>[
              for (final Object? item in json['items']! as List<Object?>)
                DVDocsListItem.fromJson(
                  _as(item),
                ),
            ],
          ),
        codeKind => DVDocsCode(
            json['text']! as String,
            signature: json['signature'] == true,
          ),
        tableKind => DVDocsTable(
            <DVDocsColumn>[
              for (final Object? column in json['columns']! as List<Object?>)
                DVDocsColumn.fromJson(
                  _as(column),
                ),
            ],
            <DVDocsRow>[
              for (final Object? row in json['rows']! as List<Object?>)
                DVDocsRow.fromJson(
                  _as(row),
                ),
            ],
            anchor: json['anchor'] as String?,
          ),
        final Object? other =>
          throw FormatException('unknown documentation block: $other'),
      };
}

class DVDocsParagraph extends DVDocsBlock {
  const DVDocsParagraph(this.spans);

  final List<DVDocsSpan> spans;

  @override
  String get kind => DVDocsBlock.paragraphKind;

  @override
  String? get anchor => null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'spans': _jsonSpans(spans),
      };
}

class DVDocsHeading extends DVDocsBlock {
  const DVDocsHeading(this.level, this.spans, {this.anchor});

  final int level;
  final List<DVDocsSpan> spans;

  @override
  final String? anchor;

  @override
  String get kind => DVDocsBlock.headingKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'level': level,
        if (anchor != null) 'anchor': anchor,
        'spans': _jsonSpans(spans),
      };
}

class DVDocsList extends DVDocsBlock {
  const DVDocsList(this.ordered, this.items);

  final bool ordered;
  final List<DVDocsListItem> items;

  @override
  String get kind => DVDocsBlock.listKind;

  @override
  String? get anchor => null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'ordered': ordered,
        'items': <Map<String, Object?>>[
          for (final DVDocsListItem item in items) item.toJson(),
        ],
      };
}

/// Verbatim source: a signature, an example record, a fenced block from a
/// decision record.
class DVDocsCode extends DVDocsBlock {
  const DVDocsCode(this.text, {this.signature = false});

  final String text;

  /// A function's signature, which the site sets apart from example code.
  final bool signature;

  @override
  String get kind => DVDocsBlock.codeKind;

  @override
  String? get anchor => null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'text': text,
        if (signature) 'signature': true,
      };
}

class DVDocsTable extends DVDocsBlock {
  const DVDocsTable(this.columns, this.rows, {this.anchor});

  final List<DVDocsColumn> columns;
  final List<DVDocsRow> rows;

  @override
  final String? anchor;

  @override
  String get kind => DVDocsBlock.tableKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        if (anchor != null) 'anchor': anchor,
        'columns': <Map<String, Object?>>[
          for (final DVDocsColumn column in columns) column.toJson(),
        ],
        'rows': <Map<String, Object?>>[
          for (final DVDocsRow row in rows) row.toJson(),
        ],
      };
}

/// One page of the site.
class DVDocsPage {
  const DVDocsPage({
    required this.id,
    required this.title,
    required this.blocks,
    this.source,
  });

  /// What a link names this page by, and what the application routes it at.
  ///
  /// `index`, `models`, `routes`, and one page per decision record:
  /// `decision:0001-checkout`.
  final String id;

  final String title;

  /// The file this page was rendered from, for a decision record.
  final String? source;

  final List<DVDocsBlock> blocks;

  /// The path the application serves this page at. Derived from [id] so the
  /// two sides cannot disagree about it: the document never carries a URL.
  String get path => id == 'index'
      ? '/'
      : id.startsWith('decision:')
      ? '/decisions/${id.substring('decision:'.length)}'
      : '/$id';

  /// The blocks from the block anchored [anchor] to the next heading of the
  /// same or a higher level, or null when nothing carries that anchor.
  ///
  /// What a decision record's `` `field:User.email` `` link points at: the
  /// field's own row, and the rest of the model it sits in, so a reader who
  /// follows one lands on the field rather than at the top of the page.
  List<DVDocsBlock>? section(String anchor) {
    final int start = blocks.indexWhere((DVDocsBlock b) => b.anchor == anchor);
    if (start == -1) return null;
    final int level =
        blocks[start] is DVDocsHeading
            ? (blocks[start] as DVDocsHeading).level
            : 2;
    final int end = blocks.indexWhere(
      (DVDocsBlock b) => b is DVDocsHeading && b.level <= level,
      start + 1,
    );
    return blocks.sublist(start, end == -1 ? blocks.length : end);
  }

  /// Everything this page has to say, as text. What the site's own find-in-page
  /// would search.
  String get text => blocks
      .map((DVDocsBlock b) => switch (b) {
            final DVDocsParagraph p => DVDocsBlock.plain(p.spans),
            final DVDocsHeading h => DVDocsBlock.plain(h.spans),
            final DVDocsList l => l.items
                .map((DVDocsListItem i) => DVDocsBlock.plain(i.spans))
                .join(' '),
            final DVDocsCode c => c.text,
            final DVDocsTable t => <String>[
              ...t.columns.map((DVDocsColumn c) => c.label),
              for (final DVDocsRow row in t.rows)
                row.cells.map(DVDocsBlock.plain).join(' '),
            ].join(' '),
          })
      .join('\n');

  factory DVDocsPage.fromJson(Map<String, Object?> json) => DVDocsPage(
        id: json['id']! as String,
        title: json['title']! as String,
        source: json['source'] as String?,
        blocks: <DVDocsBlock>[
          for (final Object? block in json['blocks']! as List<Object?>)
            DVDocsBlock.fromJson(
              _as(block),
            ),
        ],
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        if (source != null) 'source': source,
        'blocks': <Map<String, Object?>>[
          for (final DVDocsBlock block in blocks) block.toJson(),
        ],
      };
}

/// The document: one application's documentation, as data.
class DVDocsDocument {
  const DVDocsDocument({
    required this.application,
    required this.graphVersion,
    required this.navigation,
    required this.pages,
    required this.findings,
  });

  /// The package the site documents, from `pubspec.yaml`.
  final String application;

  /// The graph's own version, shown so a reader can tell which build they are
  /// looking at.
  final int graphVersion;

  /// The pages, in navigation order, as `(id, label)`.
  final List<(String, String)> navigation;

  /// Every page, including the decision records the navigation does not list.
  final List<DVDocsPage> pages;

  /// Sorted by code, then source.
  final List<DVDocsFinding> findings;

  /// The page with [id], or null. A link that names a page this returns null
  /// for is a link to nowhere.
  DVDocsPage? page(String id) {
    for (final DVDocsPage page in pages) {
      if (page.id == id) return page;
    }
    return null;
  }

  /// The page that holds [anchor], and the page it is in, for a link the
  /// site resolved while it rendered.
  ({DVDocsPage page, DVDocsBlock block})? at(String anchor) {
    for (final DVDocsPage page in pages) {
      for (final DVDocsBlock block in page.blocks) {
        if (block.anchor == anchor) return (page: page, block: block);
        if (block is DVDocsTable &&
            block.rows.any((DVDocsRow r) => r.id == anchor)) {
          return (page: page, block: block);
        }
      }
    }
    return null;
  }

  factory DVDocsDocument.fromJson(Map<String, Object?> json) => DVDocsDocument(
        application: json['application']! as String,
        graphVersion: (json['graphVersion']! as num).toInt(),
        navigation: <(String, String)>[
          for (final Object? item in json['navigation']! as List<Object?>)
            (
              _as(item)['id']! as String,
              _as(item)['label']! as String,
            ),
        ],
        pages: <DVDocsPage>[
          for (final Object? page in json['pages']! as List<Object?>)
            DVDocsPage.fromJson(
              _as(page),
            ),
        ],
        findings: <DVDocsFinding>[
          for (final Object? finding in json['findings']! as List<Object?>)
            DVDocsFinding.fromJson(
              _as(finding),
            ),
        ],
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'application': application,
        'graphVersion': graphVersion,
        'navigation': <Map<String, Object?>>[
          for (final (String id, String label) in navigation)
            <String, Object?>{'id': id, 'label': label},
        ],
        'pages': <Map<String, Object?>>[
          for (final DVDocsPage page in pages) page.toJson(),
        ],
        'findings': <Map<String, Object?>>[
          for (final DVDocsFinding finding in findings) finding.toJson(),
        ],
      };
}

List<DVDocsSpan> _spans(Object? json) => <DVDocsSpan>[
      for (final Object? span in json! as List<Object?>)
        DVDocsSpan.fromJson(_as(span)),
    ];

Map<String, Object?> _as(Object? json) =>
    (json! as Map<Object?, Object?>).cast<String, Object?>();

List<Map<String, Object?>> _jsonSpans(List<DVDocsSpan> spans) => <Map<
    String, Object?>>[
  for (final DVDocsSpan span in spans) span.toJson(),
];

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

/// The pages the site has, in navigation order: `(id, label)`.
///
/// The identifiers are what a link names and what the application routes, so
/// they are one list rather than a navigation and a router that each hold
/// their own copy of the same eight names.
const List<(String, String)> dvDocsNavigation = <(String, String)>[
  ('index', 'Overview'),
  ('models', 'Models'),
  ('functions', 'Functions'),
  ('routes', 'Routes'),
  ('jobs', 'Jobs and cron'),
  ('policies', 'Policies'),
  ('modules', 'Modules'),
  ('diagnostics', 'Diagnostics'),
];
