// The reserved-names check guards identifiers, not words.
//
// Its job is to catch code that *uses* a closed name: a `DVModuleManager`
// class, a `MethodChannel(...)` constructed in a binding. It was catching
// sentences instead -- a docs page saying no `MethodChannel` is used, the
// conventions check's own pattern for finding one, a test asserting that
// generated Java contains none. Each of those is the rule being kept, and a
// check that fails on them teaches people to stop running it.
import 'package:test/test.dart';

import '../../tool/ci/reserved_names.dart';

void main() {
  group('what counts as a use', () {
    test('constructing a platform channel', () {
      expect(
        dvReservedNameUses(
          "final channel = MethodChannel('com.example/native');",
        ),
        hasLength(1),
      );
    });

    test('a reserved class name in a declaration', () {
      expect(dvReservedNameUses('class DVModuleManager {}'), hasLength(1));
    });

    test('a type in a generic argument next to a string', () {
      expect(
        dvReservedNameUses(
          'final List<EventChannel> c = <EventChannel>[]; '
          "print('ok');",
        ),
        hasLength(1),
      );
    });

    test('an interpolated expression inside a string is still code', () {
      expect(
        dvReservedNameUses(r"print('${MethodChannel('x')}');"),
        hasLength(1),
      );
    });
  });

  group('what is prose', () {
    test('a line comment', () {
      expect(dvReservedNameUses('// No MethodChannel here.'), isEmpty);
    });

    test('a single-quoted string', () {
      expect(
        dvReservedNameUses(
          "DocsText('No `MethodChannel`, `EventChannel` or "
          "`BasicMessageChannel` is used anywhere.'),",
        ),
        isEmpty,
      );
    });

    test('a double-quoted string', () {
      expect(
        dvReservedNameUses('expect(s, isNot(contains("MethodChannel")));'),
        isEmpty,
      );
    });

    test('a raw string, such as a pattern that finds the name', () {
      expect(
        dvReservedNameUses(
          "RegExp(r'(?<![\\w.])MethodChannel|EventChannel|BasicMessageChannel')",
        ),
        isEmpty,
      );
    });

    test('a string with an escaped quote before the name', () {
      expect(
        dvReservedNameUses(r"source: 'final channel = MethodChannel(\'x\');',"),
        isEmpty,
      );
    });

    test('a triple-quoted string spanning lines', () {
      expect(
        dvReservedNameUses(
          "const docs = '''\n"
          '- Native integrations are FFI. No `MethodChannel`.\n'
          "''';",
        ),
        isEmpty,
      );
    });

    test('a // inside a string does not hide the code after it', () {
      expect(
        dvReservedNameUses(
          "final u = 'https://x'; final c = MethodChannel('y');",
        ),
        hasLength(1),
      );
    });
  });

  test('a use reports its line', () {
    final uses = dvReservedNameUses(
      "const a = '''\nMethodChannel\n''';\n"
      'final b = EventChannel(1);',
    );
    expect(uses.map((u) => u.line), <int>[4]);
    expect(uses.single.name, 'EventChannel');
  });
}
