// Oracle for the Rust port of lib/src/parser (see ../README.md).
//
// Parses every `.dart` file under one or more corpus roots with the upstream
// Parser and writes the full listener event trace (every event with its
// arguments, in order, see parser_trace_format.dart) in the text format that
// `cargo run --release --bin parser_dump` writes for the Rust port. The two
// outputs are compared byte for byte.
//
// Usage:
//   dart --packages=pkg/_fe_analyzer_shared/rust/oracle/package_config.json \
//     pkg/_fe_analyzer_shared/rust/oracle/parser_dump.dart \
//     [--bench=N] --out <dir> <root>...
//
// Each file is scanned with `scan(bytes)` (comments included, the scanner
// configuration of the default experimental features) and parsed with
// `new Parser(listener, experimentalFeatures:
// const DefaultExperimentalFeatures()).parseUnit(tokens)`.
//
// Only `dart:` libraries and this package's own libraries are imported.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:_fe_analyzer_shared/src/parser/experimental_features.dart';
import 'package:_fe_analyzer_shared/src/parser/forwarding_listener.dart';
import 'package:_fe_analyzer_shared/src/parser/parser_impl.dart';
import 'package:_fe_analyzer_shared/src/scanner/scanner.dart';

import 'parser_trace_listener.dart';
import 'scanner_dump.dart' show corpusFiles;

const ExperimentalFeatures features = const DefaultExperimentalFeatures();

void main(List<String> args) {
  String? out;
  int bench = 0;
  List<String> roots = [];
  for (int i = 0; i < args.length; i++) {
    String arg = args[i];
    if (arg.startsWith('--bench=')) {
      bench = int.parse(arg.substring('--bench='.length));
    } else if (arg == '--out') {
      out = args[++i];
    } else {
      roots.add(arg);
    }
  }
  if (roots.isEmpty || (out == null && bench == 0)) {
    stderr.writeln('usage: parser_dump.dart [--bench=N] --out <dir> <root>...');
    exit(64);
  }

  List<(String, String)> inputs = corpusFiles(roots);

  if (bench > 0) {
    runBench(inputs, bench);
    return;
  }

  for (var (String path, String relative) in inputs) {
    Uint8List bytes = new File(path).readAsBytesSync();
    String dump = dumpFile(bytes);
    File target = new File('$out/$relative.trace');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(utf8.encode(dump));
  }
}

ScannerResult runScanner(Uint8List bytes) {
  return scan(
    bytes,
    configuration: features.buildScannerConfiguration(),
    includeComments: true,
  );
}

String dumpFile(Uint8List bytes) {
  ScannerResult result = runScanner(bytes);
  TraceListener listener = new TraceListener();
  Parser parser = new Parser(listener, experimentalFeatures: features);
  try {
    parser.parseUnit(result.tokens);
  } catch (e) {
    // The Rust port panics where upstream throws; neither message is
    // compared, only that it happened.
    listener.sb.write('crash\n');
  }
  return listener.sb.toString();
}

/// Scans every file once, then parses the token streams [rounds] times with
/// a listener that does nothing, timing only the parsing. Each round parses
/// a fresh scan, because the parser rewrites the token stream it parses.
void runBench(List<(String, String)> inputs, int rounds) {
  List<Uint8List> data = [
    for (var (String path, _) in inputs) new File(path).readAsBytesSync(),
  ];
  int totalBytes = data.fold(0, (sum, b) => sum + b.length);
  Stopwatch watch = new Stopwatch();
  List<int> times = [];
  for (int round = 0; round < rounds; round++) {
    List<Token> streams = [for (Uint8List b in data) runScanner(b).tokens];
    watch
      ..reset()
      ..start();
    for (Token tokens in streams) {
      new Parser(
        new NullListener(),
        experimentalFeatures: features,
      ).parseUnit(tokens);
    }
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  stdout.writeln(
    'dart parser files=${data.length} bytes=$totalBytes rounds=$rounds '
    'min_us=${times.first} median_us=${times[times.length ~/ 2]}',
  );
}
