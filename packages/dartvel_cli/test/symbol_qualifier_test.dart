// Qualifying references to symbols that stayed behind in the source file.
//
// Lowered bodies run in the generated library, where those names do not exist,
// so each one has to be reached through the source file's import prefix. The
// qualifier rewrites text, and text rewriting is where this goes wrong: a name
// inside a string is not a reference, and a name in an interpolation needs
// braces once it becomes a member access.
import 'package:dartvel_cli/src/generators/symbol_qualifier.dart';
import 'package:test/test.dart';

String q(String source) =>
    dvQualifySourceSymbols(source, 'w0', const <String>{'suffix', 'build'});

void main() {
  group('plain code', () {
    test('a bare reference is qualified', () {
      expect(q('return suffix;'), 'return w0.suffix;');
    });

    test('a member with the same name is not', () {
      // `x.suffix` is a property of x, not the top-level symbol.
      expect(q('return x.suffix;'), 'return x.suffix;');
    });

    test('a longer identifier containing the name is not', () {
      expect(q('return suffixes;'), 'return suffixes;');
      expect(q('return mysuffix;'), 'return mysuffix;');
    });
  });

  group('strings', () {
    test('a name inside a string literal is left alone', () {
      // This is the silent one: the result still compiles and just renders
      // the wrong words.
      expect(q("return 'suffix';"), "return 'suffix';");
    });

    test('a double-quoted string too', () {
      expect(q('return "suffix";'), 'return "suffix";');
    });

    test('an escaped quote does not end the string early', () {
      expect(q("return 'it\\'s suffix';"), "return 'it\\'s suffix';");
    });

    test('a raw string has no interpolation to qualify', () {
      expect(q("return r'\$suffix';"), "return r'\$suffix';");
    });

    test('a triple-quoted string is skipped whole', () {
      expect(q("return '''suffix''';"), "return '''suffix''';");
    });
  });

  group('interpolation', () {
    test('a simple interpolation gains braces when it becomes a member', () {
      // Without braces Dart reads `$w0` and treats `.suffix` as literal text.
      expect(q("return '\$suffix';"), "return '\${w0.suffix}';");
    });

    test('a braced interpolation is qualified in place', () {
      expect(q("return '\${suffix}';"), "return '\${w0.suffix}';");
    });

    test('two adjacent interpolations both survive', () {
      expect(q("return '\$suffix\$build';"), "return '\${w0.suffix}\${w0.build}';");
    });

    test('an expression inside an interpolation is qualified', () {
      expect(q("return '\${build()}';"), "return '\${w0.build()}';");
    });

    test('a string inside an interpolation is still a string', () {
      expect(q("return '\${f('suffix')}';"), "return '\${f('suffix')}';");
    });

    test('an unknown name in an interpolation is untouched', () {
      expect(q("return '\$label';"), "return '\$label';");
    });
  });

  group('comments', () {
    test('a name in a line comment is not a reference', () {
      expect(q('// suffix\nreturn 1;'), '// suffix\nreturn 1;');
    });

    test('a name in a block comment is not either', () {
      expect(q('/* suffix */ return 1;'), '/* suffix */ return 1;');
    });
  });

  test('no symbols means no rewriting', () {
    expect(dvQualifySourceSymbols('return suffix;', 'w0', const <String>{}),
        'return suffix;');
  });
}
