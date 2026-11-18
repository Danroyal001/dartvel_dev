// The upstream side of the damage oracle (not a mirrored file; see
// ../README.md): applies each mutation in a list to a kernel file, reads the
// result with this package's BinaryBuilder and writes it with its
// BinaryPrinter, as oracle/roundtrip.dart does, and prints one line per
// mutation: `ok <length> <fnv-1a 64 of the output>` or `error <what was
// thrown, as its toString() prints it>`, newlines as `\n`.
// src/bin/kernel_damage.rs does the same in Rust.
//
// Usage: dart damage.dart <input.dill> <mutations>
//
// A mutations file has one mutation per line: `T <length>` (the first
// <length> bytes) or `F <offset> <xor mask>` (one byte flipped).
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

/// FNV-1a, 64 bits, as two 32-bit halves (Dart's int is 64-bit signed; the
/// multiplication is done in halves so that it wraps as unsigned).
String fnv1a64(Uint8List bytes) {
  int high = 0xcbf29ce4;
  int low = 0x84222325;
  for (final int byte in bytes) {
    low ^= byte;
    // (high:low) * 0x100000001b3 = (high:low) * 0x1b3 + (low << 40)
    final int lowProduct = low * 0x1b3;
    final int newLow = lowProduct & 0xffffffff;
    final int carry = lowProduct >> 32;
    final int newHigh = (high * 0x1b3 + carry + ((low << 8) & 0xffffffff)) &
        0xffffffff;
    high = newHigh;
    low = newLow;
  }
  return high.toRadixString(16).padLeft(8, '0') +
      low.toRadixString(16).padLeft(8, '0');
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('usage: damage.dart <input.dill> <mutations>');
    exit(64);
  }
  final Uint8List base = new File(arguments[0]).readAsBytesSync();
  final StringBuffer out = new StringBuffer();
  for (final String line in new File(arguments[1]).readAsLinesSync()) {
    if (line.isEmpty) continue;
    final List<String> parts = line.split(' ');
    Uint8List input;
    if (parts[0] == 'T') {
      input = Uint8List.fromList(base.sublist(0, int.parse(parts[1])));
    } else {
      input = Uint8List.fromList(base);
      input[int.parse(parts[1])] ^= int.parse(parts[2]);
    }
    try {
      final Uint8List output = roundTrip(input);
      out.writeln('ok ${output.length} ${fnv1a64(output)}');
    } catch (e) {
      out.writeln('error ${'$e'.replaceAll('\n', r'\n')}');
    }
  }
  stdout.write(out);
}
