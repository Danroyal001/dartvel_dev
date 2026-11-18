// The upstream side of the round-trip oracle (not a mirrored file): reads
// each kernel component with this package's BinaryBuilder and writes it
// with its BinaryPrinter, as src/bin/kernel_roundtrip.rs does in Rust.
//
// Usage: dart roundtrip.dart <input.dill> <output.dill> [<input> <output>]...
//        dart roundtrip.dart --bench <runs> <input.dill> <output.dill>
//
// With --bench, the read and write of one component is repeated <runs>
// times in the process and the fastest and median times are printed as
// `min_us=... median_us=...` (the format ../../_fe_analyzer_shared/rust/
// tool/measure.sh reads).
import 'dart:io';
import 'dart:typed_data';

import 'package:kernel/binary/ast_from_binary.dart';
import 'package:kernel/binary/ast_to_binary.dart';
import 'package:kernel/kernel.dart' show Component;

Uint8List roundTrip(Uint8List bytes) {
  final Component component = new Component();
  new BinaryBuilder(bytes).readComponent(component);
  final BytesSink sink = new BytesSink();
  new BinaryPrinter(sink).writeComponentFile(component);
  return sink.builder.takeBytes();
}

void main(List<String> arguments) {
  if (arguments.length == 4 && arguments[0] == '--bench') {
    final int runs = int.parse(arguments[1]);
    final Uint8List bytes = new File(arguments[2]).readAsBytesSync();
    final List<int> times = <int>[];
    Uint8List out = Uint8List(0);
    for (int i = 0; i < runs; i++) {
      final Stopwatch watch = new Stopwatch()..start();
      out = roundTrip(bytes);
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    new File(arguments[3]).writeAsBytesSync(out);
    print('min_us=${times.first} median_us=${times[(times.length - 1) ~/ 2]}');
    return;
  }
  if (arguments.isEmpty || arguments.length.isOdd) {
    stderr.writeln(
      'usage: roundtrip.dart <input.dill> <output.dill> [<input> <output>]...',
    );
    exit(64);
  }
  for (int i = 0; i < arguments.length; i += 2) {
    new File(
      arguments[i + 1],
    ).writeAsBytesSync(roundTrip(new File(arguments[i]).readAsBytesSync()));
  }
}
