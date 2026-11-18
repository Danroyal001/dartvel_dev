// Oracle for the Rust port of Uri.parse (not a mirrored file; see
// ../README.md).
//
// Reads one input per line from the file given as the first argument and
// writes one result per line to the file given as the second:
// `ok <Uri.parse(input).toString()>` or `error <thrown.toString()>`.
//
// Inputs and results are Dart strings in a line-safe escape format: a code
// unit from U+0020 to U+007E other than `\` stands for itself, any other
// code unit (lone surrogates included) is `\` and four lower-case hex digits.
import 'dart:io';

String decode(String line) {
  var codeUnits = <int>[];
  for (var i = 0; i < line.length; i++) {
    var char = line.codeUnitAt(i);
    if (char == 0x5C) {
      codeUnits.add(int.parse(line.substring(i + 1, i + 5), radix: 16));
      i += 4;
    } else {
      codeUnits.add(char);
    }
  }
  return String.fromCharCodes(codeUnits);
}

String encode(String text) {
  var buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    var char = text.codeUnitAt(i);
    if (char >= 0x20 && char < 0x7F && char != 0x5C) {
      buffer.writeCharCode(char);
    } else {
      buffer.write('\\');
      buffer.write(char.toRadixString(16).padLeft(4, '0'));
    }
  }
  return buffer.toString();
}

Future<void> main(List<String> arguments) async {
  var lines = File(arguments[0]).readAsStringSync().split('\n');
  // The input file ends every line with `\n`, so the last element is empty.
  lines.removeLast();
  var output = File(arguments[1]).openWrite();
  for (var line in lines) {
    String result;
    try {
      result = 'ok ${encode(Uri.parse(decode(line)).toString())}';
    } catch (error) {
      result = 'error ${encode(error.toString())}';
    }
    output.writeln(result);
  }
  await output.close();
}
