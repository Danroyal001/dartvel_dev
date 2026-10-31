// Corpus builder for the Rust port of lib/src/scanner (see ../README.md).
//
// Writes the inputs of the scanner's own tests as a corpus: every test file
// is copied as is, and the value of every string literal in it that has no
// interpolation is written as a file of its own, because those literals are
// what the tests hand to the scanner.
//
// Usage:
//   dart --packages=pkg/_fe_analyzer_shared/rust/oracle/package_config.json \
//     pkg/_fe_analyzer_shared/rust/oracle/extract_test_inputs.dart \
//     --out <dir> <test file>...
//
// Output: <dir>/<test basename>/source.dart and <dir>/<test basename>/<n>.dart.
// Only `dart:` libraries and this package's own libraries are imported.

import 'dart:convert';
import 'dart:io';

import 'package:_fe_analyzer_shared/src/scanner/scanner.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';

void main(List<String> args) {
  String? out;
  List<String> files = [];
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--out') {
      out = args[++i];
    } else {
      files.add(args[i]);
    }
  }
  if (out == null || files.isEmpty) {
    stderr.writeln('usage: extract_test_inputs.dart --out <dir> <file>...');
    exit(64);
  }
  int total = 0;
  for (String path in files) {
    String name = path.split('/').last.replaceAll('.dart', '');
    Directory dir = new Directory('$out/$name')..createSync(recursive: true);
    String source = new File(path).readAsStringSync();
    new File('${dir.path}/source.dart').writeAsStringSync(source);
    int n = 0;
    Token token = scanString(source).tokens;
    while (!token.isEof) {
      Token next = token.next!;
      if (token.type == TokenType.STRING &&
          !token.previous!.isA(TokenType.STRING_INTERPOLATION_EXPRESSION) &&
          !token.previous!.isA(TokenType.STRING_INTERPOLATION_IDENTIFIER) &&
          !next.isA(TokenType.STRING_INTERPOLATION_EXPRESSION) &&
          !next.isA(TokenType.STRING_INTERPOLATION_IDENTIFIER) &&
          !token.isSynthetic) {
        String? value = literalValue(token.lexeme);
        if (value != null) {
          new File(
            '${dir.path}/${(n++).toString().padLeft(4, '0')}.dart',
          ).writeAsBytesSync(utf8.encode(value));
        }
      }
      token = next;
    }
    total += n;
  }
  stdout.writeln('${files.length} test files, $total literals');
}

/// The value of a complete, uninterpolated string literal, or null when the
/// literal is not one this extractor understands.
String? literalValue(String lexeme) {
  bool raw = lexeme.startsWith('r');
  String rest = raw ? lexeme.substring(1) : lexeme;
  int quoteLength = rest.startsWith("'''") || rest.startsWith('"""') ? 3 : 1;
  if (rest.length < 2 * quoteLength) return null;
  String body = rest.substring(quoteLength, rest.length - quoteLength);
  if (quoteLength == 3) {
    // A multi-line string drops its first line when that line is blank.
    int newline = body.indexOf('\n');
    if (newline >= 0 && body.substring(0, newline).trim().isEmpty) {
      body = body.substring(newline + 1);
    }
  }
  if (raw) return body;
  StringBuffer sb = new StringBuffer();
  for (int i = 0; i < body.length; i++) {
    int c = body.codeUnitAt(i);
    if (c != 0x5c /* \ */ || i + 1 == body.length) {
      sb.writeCharCode(c);
      continue;
    }
    String e = body[++i];
    switch (e) {
      case 'n':
        sb.write('\n');
      case 'r':
        sb.write('\r');
      case 't':
        sb.write('\t');
      case 'b':
        sb.write('\b');
      case 'f':
        sb.write('\f');
      case 'v':
        sb.write('\v');
      case 'x':
        if (i + 2 >= body.length) return null;
        int? v = int.tryParse(body.substring(i + 1, i + 3), radix: 16);
        if (v == null) return null;
        sb.writeCharCode(v);
        i += 2;
      case 'u':
        if (i + 1 < body.length && body[i + 1] == '{') {
          int close = body.indexOf('}', i);
          if (close < 0) return null;
          int? v = int.tryParse(body.substring(i + 2, close), radix: 16);
          if (v == null || v > 0x10ffff) return null;
          sb.writeCharCode(v);
          i = close;
        } else {
          if (i + 4 >= body.length) return null;
          int? v = int.tryParse(body.substring(i + 1, i + 5), radix: 16);
          if (v == null) return null;
          sb.writeCharCode(v);
          i += 4;
        }
      default:
        sb.write(e);
    }
  }
  return sb.toString();
}
