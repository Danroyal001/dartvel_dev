import 'package:dv_dialect/dv_dialect.dart';
import 'package:test/test.dart';

/// Converting to the dialect and back must give back the exact text.
void roundTrips(String dart) {
  final dialect = toDialect(dart);
  expect(toDart(dialect).source, dart, reason: 'via:\n$dialect');
}

void main() {
  group('toDialect removes what insertion puts back', () {
    test('a semicolon ending a line', () {
      expect(
        toDialect('void main() {\n  final a = 1;\n  print(a);\n}\n'),
        'void main() {\n  final a = 1\n  print(a)\n}\n',
      );
    });

    test('a semicolon before the closing brace of a block', () {
      expect(
        toDialect('int f() {\n  return 1;\n}\n'),
        'int f() {\n  return 1\n}\n',
      );
    });

    test('top-level directives and declarations', () {
      expect(
        toDialect("import 'a.dart';\nint x = 1;\n"),
        "import 'a.dart'\nint x = 1\n",
      );
    });

    test(
      'a semicolon followed by another statement on the same line stays',
      () {
        expect(
          toDialect('void f() {\n  a(); b();\n}\n'),
          'void f() {\n  a(); b()\n}\n',
        );
      },
    );

    test('a closure assigned on its own lines keeps the statement shape', () {
      const source =
          'void f() {\n  final g = () {\n    h();\n  };\n  g();\n}\n';
      expect(
        toDialect(source),
        'void f() {\n  final g = () {\n    h()\n  }\n  g()\n}\n',
      );
    });

    test('a comment after the semicolon stays where it was', () {
      expect(
        toDialect('void f() {\n  a(); // why\n}\n'),
        'void f() {\n  a() // why\n}\n',
      );
    });
  });

  group('toDialect leaves alone what is not a statement end', () {
    for (final (name, source) in [
      (
        'a for header split over lines',
        'void f() {\n  for (var i = 0;\n      i < 3;\n      i++) {}\n}\n',
      ),
      (
        'arguments split over lines',
        'void f() {\n  g(\n    1,\n    2,\n  );\n}\n',
      ),
      (
        'a method chain on the next line',
        'void f() {\n  a\n      .b()\n      .c();\n}\n',
      ),
      (
        'an operator starting the next line',
        'int f() {\n  return 1\n      + 2;\n}\n',
      ),
      (
        'adjacent string literals',
        "void f() {\n  print('a'\n      'b');\n  final s = 'c'\n      'd';\n}\n",
      ),
      ('an if header on its own line', 'void f() {\n  if (x)\n    g();\n}\n'),
      (
        'an annotation on its own line',
        'class A {\n  @override\n  String toString() => \'A\';\n}\n',
      ),
      ('an annotation with arguments', "@Deprecated('no')\nvoid f() {}\n"),
      (
        'a map literal over lines',
        "void f() {\n  final m = {\n    'a': 1,\n    'b': 2\n  };\n}\n",
      ),
      ('an enum value list', 'enum E {\n  a,\n  b\n}\n'),
      ('an enhanced enum', 'enum E {\n  a,\n  b;\n\n  int get x => 1;\n}\n'),
      (
        'a block closing with no semicolon',
        'void f() {\n  if (x) {\n    g();\n  }\n  h();\n}\n',
      ),
      ('a do-while', 'void f() {\n  do {\n    g();\n  } while (x);\n}\n'),
      (
        'a switch expression',
        "String f(int x) {\n  return switch (x) {\n    1 => 'a',\n    _ => 'b'\n  };\n}\n",
      ),
      (
        'a constructor initializer list',
        'class A {\n  A(this.x)\n      : y = 1;\n  final int x;\n  final int y;\n}\n',
      ),
      ('a statement ending in a type argument', 'typedef L = List<int>;\n'),
      // Found by the corpus run over packages/: the parser's error recovery
      // on dialect input rewrote this token stream, so the scan has to come
      // from the scanner, not the parser.
      (
        'identifiers with \$ in them, as jnigen writes',
        r'void f() {'
            '\n'
            r'  late final jni$_.RawReceivePort $p;'
            '\n'
            r'  $p = jni$_.RawReceivePort(($m) {});'
            '\n'
            '}\n',
      ),
      (
        'a show list wrapped onto the next lines',
        "export 'a.dart'\n    show\n        A,\n        b;\n",
      ),
      (
        'a conditional import',
        "import 'a.dart'\n    if (dart.library.io) 'b.dart';\n",
      ),
      (
        'a type on its own line, its name on the next',
        'class S {\n  late int\n  _next; // why\n  final Widget\n  child;\n}\n',
      ),
      (
        'a record type on its own line, the name on the next',
        '(bool, int)\n_f() => (true, 1);\n\nvoid g() {\n'
            '  final ({bool a, int b})\n  d = (a: true, b: 1);\n}\n',
      ),
      (
        'mixin on wrapped onto its own line',
        'mixin M\n    on\n        B,\n        C {}\n',
      ),
      (
        'a switch statement right after a case label',
        'int f(int a, int b) {\n  switch (a) {\n    case 1:\n'
            '      switch (b) {\n        case 2:\n          return 3;\n      }\n'
            '    case 4:\n      return 5;\n  }\n  return 0;\n}\n',
      ),
      (
        'a constructor body after an initializer ending in a grouped '
            'expression',
        'class A {\n  A(double a)\n      : x = 2 *\n            (a / 3) {\n'
            '    g();\n  }\n  final double x;\n}\n',
      ),
      (
        'a block after a case label is a block, not a map',
        'void f(int x) {\n  switch (x) {\n    case 1: {\n      g();\n    }\n'
            '    case Point(x: 0, y: 0): {\n      g();\n    }\n'
            '    default: {\n      g();\n    }\n  }\n}\n',
      ),
      (
        'an operator declaration body is a block, not a closure',
        'class A {\n  @override\n  bool operator ==(Object other) {\n'
            '    return true;\n  }\n\n  int operator +(int b) {\n'
            '    return b;\n  }\n}\n\nint x = 1;\n',
      ),
      (
        'implements wrapped onto its own line',
        'class A\n    implements\n        B,\n        C {}\n',
      ),
      (
        'a function-typed field wrapped before its name',
        'class A {\n  final void Function(int a, int b)\n  _f;\n  A(this._f);\n}\n',
      ),
      (
        'return wrapped before a long expression',
        'int f() {\n  return\n      g(1);\n}\n',
      ),
      (
        'an annotation with type arguments',
        "@Native<Void Function()>(symbol: 'x')\nexternal void f();\n",
      ),
      (
        'a generator body is a block, not a set literal',
        'Iterable<int> f() sync* {\n  yield 1;\n}\n\n'
            'Stream<int> g() async* {\n  yield 2;\n}\n\nint x = 1;\n',
      ),
    ]) {
      test(name, () => roundTrips(source));
    }
  });

  group('toDart', () {
    test('inserts at the end of every statement line', () {
      expect(
        toDart('void main() {\n  final a = 1\n  print(a)\n}\n').source,
        'void main() {\n  final a = 1;\n  print(a);\n}\n',
      );
    });

    test('a line starting with ( or [ is a new statement, with a warning', () {
      final result = toDart('void f() {\n  a()\n  (b)\n}\n');
      expect(result.source, 'void f() {\n  a();\n  (b);\n}\n');
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single.line, 3);
    });

    test('a { on its own line attaches to the line before', () {
      expect(
        toDart('void f()\n{\n  g()\n}\n').source,
        'void f()\n{\n  g();\n}\n',
      );
    });
  });

  group('refusals', () {
    test('toDialect takes only standard Dart that parses', () {
      expect(() => toDialect('void f( {'), throwsFormatException);
    });
  });
}
