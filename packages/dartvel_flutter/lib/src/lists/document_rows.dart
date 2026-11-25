/// Unbuilt lazy rows, read from the server-rendered document instead of
/// built (see document_rows.dart in dartvel_core).
///
/// A long DVBox collection builds only the rows near the screen. A row that
/// is not built has no semantics node, so a screen reader reading line by
/// line stopped at the last row built. Building the rest while the page was
/// idle reached them at about 20 ms of main thread a row (Dartvel 3.47.9,
/// shipped off by default for that).
///
/// The document the server sends for each route already holds every row, and
/// the build marks where each lazy collection's rows start and end. So on the
/// web, once the page is idle, an unbuilt row stands in for itself with what
/// the document says it holds: a semantics node per link, heading and
/// paragraph, at no cost beyond a box and a label each -- nothing of the
/// row's own widgets is built, laid out or painted. A screen reader reads it,
/// a link in it opens what it names; when the row comes near the screen it
/// is built as before and replaces its stand-in.
///
/// While the build captures a page ([DVLazyLists.buildWhole]) the marks are
/// put into the semantics tree as identifiers (`dartvel:rows`,
/// `dartvel:row`), which the build writes into the document as comments.
///
/// Not in the barrel: there is nothing for an application to call.
library;

import 'package:dartvel_core/dartvel.dart' show DVDocumentCollection, DVDocumentRow, DVDocumentRowPart;
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart' show DV, DVRouteTarget;
import '../routing/client_hosts.dart' show dvIsOtherOrigin;
import '../routing/nav_link.dart' show DVLinkOpener;
import 'lazy_lists.dart';

/// The semantics identifier marking a lazy collection while the build
/// captures the page.
const String dvRowsIdentifier = 'dartvel:rows';

/// The semantics identifier marking one row of it.
const String dvRowIdentifier = 'dartvel:row';

/// A lazy DVBox collection: a long column or grid of rows built near the
/// screen, or a scrollable list. Marks where the document's collection is.
class DVLazyCollection extends StatelessWidget {
  const DVLazyCollection({super.key, required this.childCount, required this.child});

  /// How many children the collection has: how many rows the document's
  /// collection must have for its rows to be this collection's.
  final int childCount;

  final Widget child;

  @override
  Widget build(BuildContext context) => DVLazyLists.buildWhole
      ? Semantics(container: true, explicitChildNodes: true, identifier: dvRowsIdentifier, child: child)
      : child;
}

/// [child], the row at its index in a lazy collection, marked while the
/// build captures the page; as it is otherwise.
Widget dvMarkRow(Widget child) => DVLazyLists.buildWhole
    ? Semantics(container: true, explicitChildNodes: true, identifier: dvRowIdentifier, child: child)
    : child;

/// One row, or a run of cells, of a lazy collection: which children of the
/// collection it holds. Marks the row so its document row can be found.
class DVLazyRow extends StatelessWidget {
  const DVLazyRow({super.key, required this.firstChild, this.childCount = 1, required this.child});

  /// The index of the first child of the collection it holds, and how many
  /// (a row of a grid holds several).
  final int firstChild;
  final int childCount;

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// What is waiting for a stand-in, so the page is not walked when nothing is.
abstract final class DVDocumentRows {
  /// Whether unbuilt rows stand in from the document: on the web.
  static bool enabled = kIsWeb;

  /// Rows and lists not built and not standing in yet.
  static final Set<Object> waiting = <Object>{};

  /// Told when a row read elsewhere is built: the list it is read after
  /// drops it from what stands in.
  static final ChangeNotifier built = ChangeNotifier();
}

/// A row that is not built and can stand in for itself with what the
/// document says it holds (DVNearScreen).
abstract class DVStandInRow {
  /// Whether it is built: then the collections inside it are in the app.
  bool get built;

  /// Whether it is built, or already standing in.
  bool get settled;

  /// Stands in with [parts], in its place, until it is built.
  void standIn(List<DVDocumentRowPart> parts);

  /// Its words are read elsewhere: after the rows of the scrollable list it
  /// is in, which drops what is far from the screen out of the semantics
  /// tree.
  void standElsewhere();
}

/// A scrollable lazy list (DVLazyListView). It builds only what is near the
/// screen and leaves out of the semantics tree what lies far past it, so
/// what is not built in it -- its own rows, and rows of collections inside
/// the rows it has built -- stands in after the rows it has.
abstract class DVStandInList {
  /// Whether it has its document rows already.
  bool get settled;

  /// Its rows, as the document has them, one per child.
  void standInRows(List<DVDocumentRow> rows);
}

/// Gives the unbuilt rows of the lazy collections under [root] what the
/// document says they hold. [collections] are the document's top-level ones
/// (`dvDocumentRows`). Up to [limit] rows (a list counts as one) are given
/// their stand-ins; returns how many were.
///
/// The app's collections are matched to the document's by their order and
/// their number of children, level by level: the collections in a built row
/// with those of the same row in the document. A collection inside a row
/// that is not built does not exist in the app, and its words are the row's.
/// Where a level has a different number of collections than the document,
/// nothing on it is matched: a row given another row's words is worse than
/// none.
int dvApplyDocumentRows(
  Element root,
  List<DVDocumentCollection> collections, {
  int limit = 1 << 30,
}) {
  final _Matcher matcher = _Matcher(limit);
  matcher.match(_collectionsUnder(root), collections, null);
  return matcher.given;
}

/// What stands in after the rows a scrollable list has built: for each row
/// of [rows] it has not built, what the row says; for each it has, what the
/// unbuilt rows of the collections inside it say. In document order.
List<DVDocumentRowPart> dvListStandIns(Element list, List<DVDocumentRow> rows) {
  final List<DVDocumentRowPart> parts = <DVDocumentRowPart>[];
  final Map<int, Element> built = <int, Element>{
    for (final Element row in _rowsUnder(list).$1) (row.widget as DVLazyRow).firstChild: row,
  };
  final _Matcher matcher = _Matcher(1 << 30);
  for (int index = 0; index < rows.length; index++) {
    final Element? row = built[index];
    if (row == null) {
      parts.addAll(rows[index].parts);
    } else {
      matcher.match(_collectionsUnder(row), rows[index].collections, parts);
    }
  }
  return parts;
}

// The collections under [from], stopping at each.
List<Element> _collectionsUnder(Element from) {
  final List<Element> found = <Element>[];
  void visit(Element element) {
    final Widget widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (widget is DVLazyCollection) {
      found.add(element);
      return;
    }
    element.visitChildElements(visit);
  }

  from.visitChildElements(visit);
  return found;
}

// The rows of the collection at [from], stopping at each, and a scrollable
// list's state when it is one.
(List<Element>, DVStandInList?, Element?) _rowsUnder(Element from) {
  final List<Element> rows = <Element>[];
  DVStandInList? list;
  Element? listElement;
  void visit(Element element) {
    final Widget widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (widget is DVLazyRow) {
      rows.add(element);
      return;
    }
    if (widget is DVLazyCollection) return;
    if (list == null && element is StatefulElement && element.state is DVStandInList) {
      list = element.state as DVStandInList;
      listElement = element;
    }
    element.visitChildElements(visit);
  }

  from.visitChildElements(visit);
  return (rows, list, listElement);
}

// The row's own state, when it is one that can be unbuilt.
DVStandInRow? _standInOf(Element row) {
  DVStandInRow? found;
  void visit(Element element) {
    if (found != null || element.widget is DVLazyCollection) return;
    if (element is StatefulElement && element.state is DVStandInRow) {
      found = element.state as DVStandInRow;
      return;
    }
    element.visitChildElements(visit);
  }

  row.visitChildElements(visit);
  return found;
}

class _Matcher {
  _Matcher(this.limit);

  final int limit;
  int given = 0;

  /// Matches [app]'s collections with [document]'s. With [hoist], inside a
  /// scrollable list: what is not built goes into it rather than in place.
  void match(List<Element> app, List<DVDocumentCollection> document, List<DVDocumentRowPart>? hoist) {
    if (app.length != document.length) return;
    for (int index = 0; index < app.length && given < limit; index++) {
      final DVLazyCollection collection = app[index].widget as DVLazyCollection;
      final List<DVDocumentRow> rows = document[index].rows;
      if (rows.length != collection.childCount) continue;
      final (List<Element> built, DVStandInList? list, Element? listElement) = _rowsUnder(app[index]);
      if (list != null) {
        if (hoist != null) {
          // A scrollable list inside another: read after the outer one's.
          hoist.addAll(dvListStandIns(listElement!, rows));
        } else if (!list.settled) {
          list.standInRows(rows);
          given++;
        }
        continue;
      }
      for (final Element element in built) {
        if (given >= limit) return;
        final DVLazyRow row = element.widget as DVLazyRow;
        final int end = row.firstChild + row.childCount;
        if (row.firstChild < 0 || end > rows.length) continue;
        final DVStandInRow? standIn = _standInOf(element);
        if (standIn != null && !standIn.built) {
          final List<DVDocumentRowPart> parts = <DVDocumentRowPart>[
            for (int child = row.firstChild; child < end; child++) ...rows[child].parts,
          ];
          if (hoist != null) {
            hoist.addAll(parts);
            if (!standIn.settled) standIn.standElsewhere();
          } else if (!standIn.settled) {
            standIn.standIn(parts);
            given++;
          }
          continue;
        }
        match(_collectionsUnder(element), <DVDocumentCollection>[
          for (int child = row.firstChild; child < end; child++) ...rows[child].collections,
        ], hoist);
      }
    }
  }
}

/// Opens [href], a link a stand-in row read from the document, as the link
/// in the row would.
void dvFollowDocumentLink(String href) {
  if (dvIsOtherOrigin(href)) {
    // On the web a screen reader activates the anchor itself, and the
    // browser follows it.
    if (DVLinkOpener.browserFollowsAnchors) return;
    DVLinkOpener.open(href);
    return;
  }
  DV.Navigation.navigate(DVRouteTarget(href));
}

/// [parts] as semantics nodes in a box [height] tall: one per part, each a
/// share of the height, nothing painted.
Widget dvStandIn(List<DVDocumentRowPart> parts, double height) {
  if (parts.isEmpty) return SizedBox(height: height);
  final double each = height / parts.length;
  return SizedBox(
    height: height,
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          for (final DVDocumentRowPart part in parts)
            SizedBox(
              height: each,
              child: Semantics(
                container: true,
                label: part.text,
                link: part.href != null,
                linkUrl: part.href == null ? null : Uri.tryParse(part.href!),
                header: part.headingLevel != null,
                headingLevel: part.headingLevel,
                onTap: part.href == null ? null : () => dvFollowDocumentLink(part.href!),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    ),
  );
}

/// The rows a scrollable lazy list ([DVLazyListView]) has not built, as
/// stand-ins read after the rows it has: it builds only what is near the
/// screen, so they cannot sit in their places, and are read after them.
Widget dvListStandInsBox(List<DVDocumentRowPart> parts) => Semantics(
      container: true,
      explicitChildNodes: true,
      sortKey: const OrdinalSortKey(1),
      child: IgnorePointer(child: dvStandIn(parts, 1.0 * parts.length)),
    );
