// Block-bodied pages.
//
// A private @DVPage input had to be a single expression:
//
//     @DVPage() Widget _usersPage(BuildContext c) => DVBox.list([...]);
//
// Anything with a statement in it -- a local, a condition, a loop -- was
// rejected outright, so every page that needed one was written as a
// one-line wrapper around a public helper. That is the shape of nearly all
// Dartvel page code today, and it exists only because the generator could not
// carry a body across.
//
// The generator emits the page's body into a generated widget in another
// file, so lowering a block means moving its statements there and qualifying
// every reference to a symbol that stayed behind.
import 'package:dartvel_cli/src/generators/function_body.dart';
import 'package:test/test.dart';

void main() {
  group('reading a body off the source', () {
    test('an expression body is the text after the arrow', () {
      const String source = 'Widget _page(BuildContext c) => DVBox(x);';
      final int close = source.indexOf(')', source.indexOf('('));

      expect(dvFunctionBodyAfter(source, close)!.expression, 'DVBox(x)');
    });

    test('a block body is its statements, without the braces', () {
      const String source =
          'Widget _page(BuildContext c) {\n  return DVBox(x);\n}';
      final int close = source.indexOf(')', source.indexOf('('));

      final DVFunctionBody body = dvFunctionBodyAfter(source, close)!;
      expect(body.expression, isNull);
      expect(body.statements!.trim(), 'return DVBox(x);');
    });

    test('a nested brace does not end the block early', () {
      // The obvious way to find the end of a block is the next `}`, and it is
      // wrong for every body that contains a map, a closure or an if.
      const String source = 'Widget _page(BuildContext c) {\n'
          '  final m = <String, int>{"a": 1};\n'
          '  if (m.isEmpty) { return DVBox(y); }\n'
          '  return DVBox(x);\n'
          '}';
      final int close = source.indexOf(')', source.indexOf('('));

      final String statements = dvFunctionBodyAfter(source, close)!.statements!;
      expect(statements, contains('return DVBox(x);'));
      expect(statements, contains('if (m.isEmpty)'));
    });

    test('a brace inside a string does not end the block', () {
      // A closing brace in a string literal is not a closing brace, and a
      // scanner that counts them without knowing about strings truncates the
      // body at the first one.
      const String source = 'Widget _page(BuildContext c) {\n'
          r'  final label = "a } in text";' '\n'
          '  return DVText(label);\n'
          '}';
      final int close = source.indexOf(')', source.indexOf('('));

      expect(dvFunctionBodyAfter(source, close)!.statements,
          contains('return DVText(label);'));
    });

    test('an async block keeps its modifier', () {
      const String source =
          'Future<Widget> _page(BuildContext c) async {\n  return x;\n}';
      final int close = source.indexOf(')', source.indexOf('('));

      final DVFunctionBody body = dvFunctionBodyAfter(source, close)!;
      expect(body.modifier, 'async');
      expect(body.statements!.trim(), 'return x;');
    });

    test('an async expression body keeps its modifier too', () {
      const String source =
          'Future<Widget> _page(BuildContext c) async => build(c);';
      final int close = source.indexOf(')', source.indexOf('('));

      final DVFunctionBody body = dvFunctionBodyAfter(source, close)!;
      expect(body.modifier, 'async');
      expect(body.expression, 'build(c)');
    });

    test('a declaration with no body at all is not a body', () {
      const String source = 'Widget _page(BuildContext c);';
      final int close = source.indexOf(')', source.indexOf('('));

      expect(dvFunctionBodyAfter(source, close), isNull);
    });
  });

  group('what the generated widget runs', () {
    test('an expression becomes a return', () {
      expect(
        dvLoweredBody(const DVFunctionBody(expression: 'DVBox(x)')).trim(),
        'return DVBox(x);',
      );
    });

    test('a block is emitted as it was written', () {
      expect(
        dvLoweredBody(
          const DVFunctionBody(statements: '  final a = 1;\n  return DVBox(a);'),
        ),
        contains('final a = 1;'),
      );
    });

    test('a block that falls off the end is still valid Dart', () {
      // A page whose body ends without returning is the author's bug, but the
      // generated file must still compile -- a syntax error in generated code
      // is reported against a file nobody wrote.
      final String lowered =
          dvLoweredBody(const DVFunctionBody(statements: '  doSomething();'));

      expect(lowered, contains('doSomething();'));
    });
  });
}
