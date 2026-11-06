// Oracle for the Rust port of lib/src/scanner (see ../README.md).
//
// Dumps the token stream the upstream Dart scanner produces for every `.dart`
// file under one or more corpus roots, in the text format that
// `cargo run --release --bin scanner_dump` writes for the Rust port. The two
// outputs are compared byte for byte.
//
// Usage:
//   dart --packages=pkg/_fe_analyzer_shared/rust/oracle/package_config.json \
//     pkg/_fe_analyzer_shared/rust/oracle/scanner_dump.dart \
//     [--scanner=utf8|string] [--bench=N] --out <dir> <root>...
//
// `--scanner=utf8` (the default) runs `scan(bytes)`, the Utf8BytesScanner the
// front end uses; `--scanner=string` runs `scanString(source)`, the
// StringScanner. Both include comments and use the default configuration.
//
// Only `dart:` libraries and this package's own libraries are imported.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:_fe_analyzer_shared/src/scanner/error_token.dart';
import 'package:_fe_analyzer_shared/src/scanner/scanner.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';

void main(List<String> args) {
  String scannerKind = 'utf8';
  String? out;
  int bench = 0;
  List<String> roots = [];
  for (int i = 0; i < args.length; i++) {
    String arg = args[i];
    if (arg.startsWith('--scanner=')) {
      scannerKind = arg.substring('--scanner='.length);
    } else if (arg.startsWith('--bench=')) {
      bench = int.parse(arg.substring('--bench='.length));
    } else if (arg == '--out') {
      out = args[++i];
    } else {
      roots.add(arg);
    }
  }
  if (scannerKind != 'utf8' && scannerKind != 'string') {
    stderr.writeln('unknown --scanner=$scannerKind');
    exit(64);
  }
  if (roots.isEmpty || (out == null && bench == 0)) {
    stderr.writeln(
      'usage: scanner_dump.dart [--scanner=utf8|string] [--bench=N] '
      '--out <dir> <root>...',
    );
    exit(64);
  }

  List<(String, String)> inputs = corpusFiles(roots);

  if (bench > 0) {
    runBench(scannerKind, inputs, bench);
    return;
  }

  for (var (String path, String relative) in inputs) {
    Uint8List bytes = new File(path).readAsBytesSync();
    String dump = dumpFile(scannerKind, bytes);
    File target = new File('$out/$relative.tokens');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(utf8.encode(dump));
  }
}

/// Every `.dart` file under [roots] as (path, label/relative path), sorted
/// by relative path within each root. The label is the root's basename, and
/// a repeated basename gets `~2`, `~3`, ...
List<(String, String)> corpusFiles(List<String> roots) {
  Map<String, int> seen = {};
  List<(String, String)> result = [];
  for (String root in roots) {
    Directory dir = new Directory(root);
    String base = dir.absolute.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last;
    int count = (seen[base] ?? 0) + 1;
    seen[base] = count;
    String label = count == 1 ? base : '$base~$count';
    String prefix = dir.absolute.path;
    if (!prefix.endsWith('/')) prefix = '$prefix/';
    List<(String, String)> files = [];
    for (FileSystemEntity entity in dir.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.dart')) {
        String abs = entity.absolute.path;
        files.add((abs, '$label/${abs.substring(prefix.length)}'));
      }
    }
    files.sort((a, b) => compareBytes(a.$2, b.$2));
    result.addAll(files);
  }
  return result;
}

int compareBytes(String a, String b) {
  List<int> x = utf8.encode(a), y = utf8.encode(b);
  for (int i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return x.length - y.length;
}

ScannerResult runScanner(String scannerKind, Uint8List bytes) {
  if (scannerKind == 'utf8') {
    return scan(bytes, includeComments: true);
  } else {
    return scanString(
      utf8.decode(bytes, allowMalformed: true),
      includeComments: true,
    );
  }
}

void runBench(String scannerKind, List<(String, String)> inputs, int rounds) {
  List<Uint8List> data = [
    for (var (String path, _) in inputs) new File(path).readAsBytesSync(),
  ];
  int totalBytes = data.fold(0, (sum, b) => sum + b.length);
  List<String>? strings = scannerKind == 'string'
      ? [for (Uint8List b in data) utf8.decode(b, allowMalformed: true)]
      : null;
  Stopwatch watch = new Stopwatch();
  int tokens = 0;
  List<int> times = [];
  for (int round = 0; round < rounds; round++) {
    tokens = 0;
    watch
      ..reset()
      ..start();
    for (int i = 0; i < data.length; i++) {
      ScannerResult result = strings != null
          ? scanString(strings[i], includeComments: true)
          : scan(data[i], includeComments: true);
      Token token = result.tokens;
      while (!token.isEof) {
        tokens++;
        token = token.next!;
      }
    }
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  stdout.writeln(
    'dart scanner=$scannerKind files=${data.length} bytes=$totalBytes '
    'tokens=$tokens rounds=$rounds '
    'min_us=${times.first} median_us=${times[times.length ~/ 2]}',
  );
}

String dumpFile(String scannerKind, Uint8List bytes) {
  ScannerResult result = runScanner(scannerKind, bytes);
  StringBuffer sb = new StringBuffer();
  sb.write('scanner=$scannerKind hasErrors=${result.hasErrors}\n');
  Token token = result.tokens;
  int index = 0;
  while (true) {
    CommentToken? comment = token.precedingComments;
    while (comment != null) {
      sb.write('  ');
      writeToken(sb, comment);
      comment = comment.next as CommentToken?;
    }
    sb.write('$index ');
    writeToken(sb, token);
    if (token.isEof) break;
    token = token.next!;
    index++;
  }
  sb.write('lineStarts');
  for (int start in result.lineStarts) {
    sb.write(' $start');
  }
  sb.write('\n');
  return sb.toString();
}

void writeToken(StringBuffer sb, Token token) {
  sb.write('${token.type.name} ${token.runtimeType} @${token.offset}');
  sb.write(' len=${token.length}');
  if (token is ErrorToken) {
    sb.write(' err=${token.errorCode.name}');
    if (token.character != null) sb.write(' char=${token.character}');
    if (token.start != null) sb.write(' start="${escape(token.start!)}"');
    if (token.endOffset != null) sb.write(' endOffset=${token.endOffset}');
    BeginToken? begin = token.begin;
    if (begin != null) {
      sb.write(' begin=${begin.type.name}@${begin.offset}');
    }
    if (token is UnsupportedOperator) {
      sb.write(' operator=${token.token.type.name}@${token.token.offset}');
    }
  } else {
    sb.write(' lex="${escape(token.lexeme)}"');
  }
  if (token is LanguageVersionToken) {
    sb.write(' version=${token.major}.${token.minor}');
  }
  if (token is BeginToken) {
    Token? end = token.endGroup;
    sb.write(
      end == null ? ' end=null' : ' end=${end.type.name}@${end.offset}',
    );
  }
  if (token.isSynthetic) sb.write(' synthetic');
  sb.write('\n');
}

/// Printable ASCII other than `\` and `"` as is; every other UTF-16 code
/// unit as `\uXXXX`. The dump is pure ASCII, so no encoding question arises.
String escape(String s) {
  StringBuffer sb = new StringBuffer();
  for (int i = 0; i < s.length; i++) {
    int c = s.codeUnitAt(i);
    if (c >= 0x20 && c < 0x7f && c != 0x5c && c != 0x22) {
      sb.writeCharCode(c);
    } else {
      sb.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
    }
  }
  return sb.toString();
}

