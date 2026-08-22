// `esc` puts arbitrary text inside a single-quoted Dart string literal in
// generated source. Getting it wrong does not produce a wrong value — it
// produces a file that will not compile, and every symbol the file was
// supposed to declare disappears with it.
//
// Windows proved it. A generated path `D:\a\dartvel\...` reached
// functions.g.dart unescaped and the compiler stopped at
// "An escape sequence starting with '\u' must be followed by 4 hexadecimal
// digits", after which User, getHelloApi and every other generated symbol was
// undefined. The build had nothing to do with paths.
//
// These tests round-trip rather than assert on the escaped text: they write a
// program that prints the literal, run it, and compare with what went in.
// Asserting the escaping *looks* right is how the bug survived — the shape
// looked fine.
import 'dart:io';

import 'package:dartvel_cli/src/utils/helpers.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUpAll(() => temp = Directory.systemTemp.createTempSync('dartvel_esc_'));
  tearDownAll(() => temp.deleteSync(recursive: true));

  String jsonish(String s) => s.replaceAll(r'\', r'\\');

  /// Emits `esc(value)` inside a single-quoted literal, runs it, and returns
  /// what the program actually printed.
  String roundTrip(String value) {
    final file = File('${temp.path}/probe.dart');
    file.writeAsStringSync(
      "import 'dart:io';\n"
      "void main() { stdout.write('${esc(value)}'); }\n",
    );
    final result = Process.runSync(
      Platform.resolvedExecutable,
      <String>[file.path],
    );
    if (result.exitCode != 0) {
      fail('generated source did not compile for ${jsonish(value)}:\n'
          '${result.stderr}');
    }
    return result.stdout as String;
  }

  group('esc', () {
    test('a Windows path survives', () {
      // The exact Windows failure: \U is not a valid escape.
      expect(roundTrip(r'C:\Users\dev'), r'C:\Users\dev');
    });

    test('a Windows path with a drive and many segments survives', () {
      expect(
        roundTrip(r'D:\a\dartvel\dartvel\examples\dartvel_example\lib'),
        r'D:\a\dartvel\dartvel\examples\dartvel_example\lib',
      );
    });

    test('a trailing backslash does not escape the closing quote', () {
      // The nastiest one: an odd number of backslashes at the end swallows
      // the quote that was supposed to close the literal.
      expect(roundTrip(r'C:\dir\'), r'C:\dir\');
    });

    test('a dollar stays a dollar and does not interpolate', () {
      // Emitting a bare $ makes the generated file reference a variable that
      // does not exist, or worse, one that does.
      expect(roundTrip(r'a$b'), r'a$b');
    });

    test('an interpolation-looking sequence stays literal', () {
      expect(roundTrip(r'${totalCost}'), r'${totalCost}');
    });

    test('a single quote does not end the string', () {
      expect(roundTrip("it's"), "it's");
    });

    test('an escaped quote in the input stays escaped text', () {
      expect(roundTrip(r"it\'s"), r"it\'s");
    });

    test('newlines and tabs survive as their characters', () {
      expect(roundTrip('a\nb\tc'), 'a\nb\tc');
    });

    test('ordinary text is unchanged', () {
      expect(esc('plain'), 'plain');
      expect(roundTrip('plain'), 'plain');
    });

    test('an empty string round-trips', () {
      expect(roundTrip(''), '');
    });
  });
}
