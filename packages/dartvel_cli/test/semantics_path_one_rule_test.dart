// Where a route's captured semantics tree lives is one rule,
// dvSemanticsPathFor; the build reads it back through the same function
// rather than spelling the file name out again (audit finding 12).
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the build does not compute the capture file name itself', () {
    final String build = File('lib/src/commands/build_command.dart').readAsStringSync();
    expect(build, isNot(contains("'dartvel_semantics'")));
  });
}
