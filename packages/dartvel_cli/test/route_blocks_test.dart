// Joining the pieces of the generated router's route list.
//
// The list is built from four blocks -- the pages, the model pages, the home
// widgets, and the mounted modules -- any of which may be empty and each of
// which was separately responsible for putting a comma in front of itself.
// That worked until two of them were present at once, and then it emitted a
// comma after a block that already ended in one:
//
//     ),
//     ,
//         GoRoute(
//
// which is `Expected an identifier, but got ','` from the compiler, against a
// file nobody wrote and nobody reads. It shipped for as long as it did
// because no project in the repository had both a model page and a home
// widget, so the two blocks were never both present in CI.
import 'package:dartvel_cli/src/generators/route_blocks.dart';
import 'package:test/test.dart';

/// A block shaped like the generator's: entries that end in a comma.
const String _closed = '''
    GoRoute(
      path: '/a',
    ),''';

/// And one shaped like the page entries, which do not.
const String _open = '''
    GoRoute(
      path: '/b',
    )''';

void main() {
  test('a block after one that already ends in a comma gets no second one',
      () {
    final String out = dvJoinRouteBlocks(<String>[_closed, _closed]);

    expect(out, isNot(contains(RegExp(r',\s*,'))));
  });

  test('a block after one that does not end in a comma gets one', () {
    // The other half. Without it the two entries run together as
    // "),\n    GoRoute(" with nothing between them, which is the same
    // syntax error from the opposite direction.
    final String out = dvJoinRouteBlocks(<String>[_open, _closed]);

    expect(out, contains(RegExp(r'\)\s*,\s*\n\s*GoRoute\(')));
  });

  test('an empty block leaves no trace at all', () {
    // Every one of the four is empty in some project, and an empty block
    // that still contributed its separator is exactly how the lone comma
    // got there.
    expect(dvJoinRouteBlocks(<String>[_closed, '', _closed]),
        dvJoinRouteBlocks(<String>[_closed, _closed]));
    expect(dvJoinRouteBlocks(<String>['', _open, '']),
        dvJoinRouteBlocks(<String>[_open]));
  });

  test('nothing at all is nothing, not a comma', () {
    expect(dvJoinRouteBlocks(<String>['', '', '']), isEmpty);
    expect(dvJoinRouteBlocks(const <String>[]), isEmpty);
  });

  test('four blocks together carry every route and no empty element', () {
    // The combination that was never built: pages, model pages, home widgets
    // and a mounted module in one list.
    final String out =
        dvJoinRouteBlocks(<String>[_open, _closed, _closed, _closed]);

    expect(RegExp('GoRoute').allMatches(out).length, 4);
    expect(out, isNot(contains(RegExp(r',\s*,'))));
    for (final String line in out.split('\n')) {
      expect(line.trim(), isNot(','), reason: 'an empty element in the list');
    }
  });

  test('a block whose comma is followed by a trailing newline still counts',
      () {
    // The blocks are built by joining with newlines and some arrive with
    // whitespace after the last comma. A rule that looked at the final
    // character rather than the final non-space one would add a second.
    final String out = dvJoinRouteBlocks(<String>['$_closed\n  ', _closed]);

    expect(out, isNot(contains(RegExp(r',\s*,'))));
  });
}
