// The part of `package:test` that upstream's
// test/transformations/type_flow/types_test.dart uses (not a mirrored file;
// see ../README.md): `test`, `expect`, `equals`, `isTrue` and `isFalse`.
// build_types_inputs.dart copies the test unchanged but for its
// `package:test` import, which it points here, so the test's own body runs.
//
// Instead of stopping at the first failure, every `expect` prints one line:
//
//   <ok|FAIL> | <test name> | <reason> | <actual> | <expected>
//
// with `actual` and `expected` as `toString` gives them. The Rust port of
// the test (tests/types_test.rs) prints the same lines from the port.
String _testName = '';

void test(String name, void Function() body) {
  _testName = name;
  body();
}

class Matcher {
  final String description;
  final bool Function(Object? actual) matches;

  Matcher(this.description, this.matches);
}

Matcher equals(Object? expected) =>
    Matcher('$expected', (Object? actual) => actual == expected);

final Matcher isTrue = Matcher('true', (Object? actual) => actual == true);

final Matcher isFalse = Matcher('false', (Object? actual) => actual == false);

void expect(Object? actual, Matcher matcher, {String? reason}) {
  final String verdict = matcher.matches(actual) ? 'ok' : 'FAIL';
  print(
    '$verdict | $_testName | ${reason ?? ''} | $actual | '
    '${matcher.description}',
  );
}
