/// The blocks of a documentation page, drawn.
///
/// One widget per block kind, and a span tree for everything inside a block.
/// The document is the whole vocabulary: a build wrote it, and anything the
/// site does not recognise is drawn as the characters it is, because a page
/// that drops what it did not understand is a page that is quietly wrong.
library dartvel_flutter.docs.blocks;

import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart'
    show
        DVDocsBlock,
        DVDocsCode,
        DVDocsColumn,
        DVDocsHeading,
        DVDocsList,
        DVDocsPage,
        DVDocsParagraph,
        DVDocsRow,
        DVDocsSpan,
        DVDocsTable,
        DVDocsTarget;
import 'package:flutter/material.dart';

import 'docs_style.dart';

/// How a link span is drawn, or null for a target nothing is at.
///
/// The document says where a link points; whether anything is there is the
/// site's knowledge, not the document's. A link to a page the build no longer
/// wrote is a link to nowhere, and the answer to that is its own text rather
/// than a 404 in the middle of a paragraph.
typedef DVDocsLinkSpan =
    InlineSpan? Function(BuildContext context, String text, DVDocsTarget target);

/// The things on a page a link can name, and where they are.
///
/// A link in a decision record carries a block id or a row id, so arriving at
/// one has to find the thing it named rather than sit at the top of a page the
/// reader then has to search. Keys are made once per page and held: a name the
/// page does not have resolves to nothing, which is the honest answer for an
/// address a build wrote before the code moved.
class DVDocsAnchors {
  DVDocsAnchors(this.page);

  final DVDocsPage page;

  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  /// The key for [name] on this page, or null when the page has nothing called
  /// that.
  GlobalKey? keyFor(String? name) {
    if (name == null || name.isEmpty) return null;
    final Map<String, GlobalKey> keys = _collect(page);
    return keys[name];
  }

  Map<String, GlobalKey> _collect(DVDocsPage page) {
    if (_page == page) return _keys;
    _keys.clear();
    _page = page;
    for (final DVDocsBlock block in page.blocks) {
      _add(block.anchor);
      // Rows are addressable on their own, so a decision record naming a field
      // lands on that field and not on the table it sits in.
      if (block is DVDocsTable) {
        for (final DVDocsRow row in block.rows) {
          _add(row.id);
        }
      }
    }
    return _keys;
  }

  DVDocsPage? _page;

  void _add(String? name) {
    if (name == null || name.isEmpty || _keys.containsKey(name)) return;
    _keys[name] = GlobalKey(debugLabel: 'docs/$name');
  }

  /// Scrolls [name] into view, if this page has it.
  ///
  /// Called after the frame the page was laid out in: a key is not a place
  /// until its widget is built, and an address naming a block this page does
  /// not have resolves to nothing -- which is what a browser does with an
  /// anchor it cannot find.
  void reveal(String? name, {double alignment = 0}) {
    final GlobalKey? key = keyFor(name);
    final BuildContext? target = key?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      // No animation. The address already says where this is going, and a
      // reader who asked to be put at a row is there now rather than a third
      // of a second later.
      duration: Duration.zero,
      alignment: alignment,
    );
  }
}

/// A run of spans, as one paragraph's worth of text.
///
/// A [TextSpan] tree rather than a row of widgets, because prose is inline: a
/// code span between two words has to sit on the line between them, and a
/// column of them would reflow the sentence into a list. What cannot be a span
/// -- a padded code chip, an outlined badge, a real link -- is a
/// [WidgetSpan], which is still inline and still one line of text.
class DVDocsSpans extends StatelessWidget {
  const DVDocsSpans({
    super.key,
    required this.spans,
    required this.style,
    this.link,
  });

  final List<DVDocsSpan> spans;

  /// The style the block this run sits in draws its prose with.
  final TextStyle style;

  /// Draws a link span. Null renders every link as its own text.
  final DVDocsLinkSpan? link;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: style,
      children: <InlineSpan>[
        for (final DVDocsSpan span in spans) _span(context, span),
      ],
    ),
  );

  InlineSpan _span(BuildContext context, DVDocsSpan span) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    return switch (span.kind) {
      'code' => _chip(
        context,
        docs.code,
        text: span.text,
        surface: docs.theme.codeSurface,
        bordered: false,
      ),
      'strong' => TextSpan(
        text: span.text,
        style: style.copyWith(fontWeight: .w600),
      ),
      'badge' => _chip(
        context,
        docs.badge,
        text: span.text,
        surface: null,
        bordered: true,
      ),
      // An action no policy method answers. Muted rather than blank, and said
      // rather than implied: a blank cell reads as a value the build could
      // not find.
      'denied' => TextSpan(
        text: span.text,
        style: style.copyWith(color: docs.theme.muted),
      ),
      // A reference to something that is not in the project, and what the
      // build found wrong. Both are the one thing on a page that has to be
      // flagged rather than read past.
      'gone' || 'finding' => TextSpan(
        text: span.text,
        style: style.copyWith(color: docs.theme.warn),
      ),
      // A source path, or the absence of one.
      'note' => TextSpan(text: span.text, style: docs.source),
      'link' =>
        link?.call(context, span.text, span.target!) ??
            TextSpan(text: span.text, style: style),
      // Anything else is the characters it is. The kinds are enumerated by the
      // build and its tests, and an unrecognised one is a payload from a newer
      // `dartvel docs` than this app: showing it beats losing it.
      _ => TextSpan(text: span.text, style: style),
    };
  }

  WidgetSpan _chip(
    BuildContext context,
    TextStyle chipStyle, {
    required String text,
    required Color? surface,
    required bool bordered,
  }) {
    final DVDocsTheme theme = DVDocsTheme.of(context);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: .circular(bordered ? 999 : 4),
          border: bordered ? Border.all(color: theme.ink) : null,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: bordered ? 7 : 4),
          child: Text(text, style: chipStyle),
        ),
      ),
    );
  }
}

/// One block of a page.
class DVDocsBlockView extends StatelessWidget {
  const DVDocsBlockView({
    super.key,
    required this.block,
    required this.anchors,
    this.link,
  });

  final DVDocsBlock block;

  /// The keys for the names on this page, for a block that has one.
  final DVDocsAnchors anchors;

  final DVDocsLinkSpan? link;

  @override
  Widget build(BuildContext context) => switch (block) {
    final DVDocsParagraph paragraph => _paragraph(context, paragraph),
    final DVDocsHeading heading => _heading(context, heading),
    final DVDocsList list => _list(context, list),
    final DVDocsCode code => _code(context, code),
    final DVDocsTable table => _table(context, table),
  };

  Widget _paragraph(BuildContext context, DVDocsParagraph paragraph) =>
      Padding(
        padding: const .only(bottom: 16),
        child: DVDocsSpans(
          spans: paragraph.spans,
          style: DVDocsStyle.of(context).body,
          link: link,
        ),
      );

  /// A rule above every heading below the page's own.
  ///
  /// The stylesheet had it on `section`, which is what a hand-written page was
  /// made of; here it is the thing it meant -- a line before the reader is
  /// about to be shown a new part of the page.
  Widget _heading(BuildContext context, DVDocsHeading heading) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    final bool ruled = heading.level >= 2;
    return Padding(
      key: anchors.keyFor(heading.anchor),
      padding: EdgeInsets.only(top: ruled ? 28 : 8, bottom: 12),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          if (ruled)
            Container(height: 1, color: docs.theme.rule)
          else
            const SizedBox.shrink(),
          if (ruled) const SizedBox(height: 28),
          Semantics(
            header: true,
            child: DVDocsSpans(
              spans: heading.spans,
              style: docs.heading(heading.level),
              link: link,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, DVDocsList list) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    return Padding(
      padding: const .only(bottom: 16, left: 4),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          for (int i = 0; i < list.items.length; i++)
            Padding(
              key: anchors.keyFor(list.items[i].id),
              padding: const .only(bottom: 4),
              child: Row(
                crossAxisAlignment: .start,
                children: <Widget>[
                  SizedBox(
                    width: 26,
                    child: Text(
                      list.ordered ? '${i + 1}.' : '•',
                      style: docs.body.copyWith(color: docs.theme.muted),
                    ),
                  ),
                  Expanded(
                    child: DVDocsSpans(
                      spans: list.items[i].spans,
                      style: docs.body,
                      link: link,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Source, as it was written.
  ///
  /// Horizontally scrollable rather than wrapped, because a signature wrapped
  /// across two lines is no longer the signature anybody can copy.
  Widget _code(BuildContext context, DVDocsCode code) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    return Padding(
      padding: const .only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: docs.theme.codeSurface,
          borderRadius: .circular(4),
        ),
        child: SingleChildScrollView(
          scrollDirection: .horizontal,
          padding: const .all(12),
          child: Text(
            code.text,
            // A signature is the API and is drawn as the page's own ink;
            // example code is illustrative and recedes behind it.
            style: code.signature
                ? docs.code
                : docs.code.copyWith(color: docs.theme.muted),
          ),
        ),
      ),
    );
  }

  /// A table, as rows of sized columns inside a horizontal scroll.
  ///
  /// Not a [Table]: the policy matrix has twelve columns, and a [TableRow] has
  /// nowhere to put the key a row is addressed by. Columns are sized from the
  /// longest cell in them so the layout does not need a second pass over the
  /// text to lay out, and the whole thing scrolls sideways rather than
  /// squeezing twelve actions into a phone.
  Widget _table(BuildContext context, DVDocsTable table) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    final List<double> widths = _columnWidths(table);
    return Padding(
      key: anchors.keyFor(table.anchor),
      padding: const .only(bottom: 16),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          for (int row = -1; row < table.rows.length; row++)
            _tableRow(
              context,
              docs,
              row < 0
                  ? <List<DVDocsSpan>>[
                      for (final DVDocsColumn column in table.columns)
                        <DVDocsSpan>[DVDocsSpan.strong(column.label)],
                    ]
                  : table.rows[row].cells,
              widths,
              anchor: row < 0 ? null : table.rows[row].id,
            ),
        ],
      ),
    );
  }

  Widget _tableRow(
    BuildContext context,
    DVDocsStyle docs,
    List<List<DVDocsSpan>> cells,
    List<double> widths, {
    String? anchor,
  }) {
    return SingleChildScrollView(
      key: anchors.keyFor(anchor),
      scrollDirection: .horizontal,
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          for (int i = 0; i < widths.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const .symmetric(horizontal: 6, vertical: 6),
                child: i < cells.length
                    ? DVDocsSpans(
                        spans: cells[i],
                        style: docs.body,
                        link: link,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  /// How wide each column is, in logical pixels.
  ///
  /// From the longest cell it holds, so a row of one-word values does not get
  /// a table as wide as the matrix above it. A floor, because a column narrower
  /// than [minimum] is a column of half a letter.
  static List<double> _columnWidths(DVDocsTable table) {
    const double minimum = 72;
    const double perCharacter = 7.6;
    const double padding = 28;
    final List<int> longest = <int>[
      for (final DVDocsColumn column in table.columns) column.label.length,
    ];
    for (final DVDocsRow row in table.rows) {
      for (int i = 0; i < row.cells.length && i < longest.length; i++) {
        final int length = DVDocsBlock.plain(row.cells[i]).length;
        if (length > longest[i]) longest[i] = length;
      }
    }
    return <double>[
      for (final int length in longest)
        // Not clamp(): a clamp is a num, and these are the widths a SizedBox
        // takes.
        math.max(minimum, length * perCharacter + padding),
    ];
  }
}
