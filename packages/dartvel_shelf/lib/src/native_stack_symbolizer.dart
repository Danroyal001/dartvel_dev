/// Reading an obfuscated Dart stack trace with the `.symbols` file Flutter's
/// `--split-debug-info` wrote beside the build.
///
/// An AOT build made with `--obfuscate --split-debug-info` prints a stack as
/// a header (pid, `build_id`, the loaded base addresses) and one line per
/// frame holding only an offset into the code (`_kDartIsolateSnapshotText
/// +0x3d3da`). The names are in the symbols file's DWARF, which is a program
/// header and a line table, not text: reading it is `package:native_stack_traces`,
/// the same decoder behind `flutter symbolize`.
///
/// This is on the server half rather than in `dartvel_core` because that
/// package also runs in a browser and the decoder reads files through
/// `dart:io`.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart' show DVDartStackDecoder;
import 'package:native_stack_traces/native_stack_traces.dart';

class DVNativeStackSymbolizer implements DVDartStackDecoder {
  const DVNativeStackSymbolizer();

  /// The ELF build id of a symbols file, as lowercase hex, or null when it is
  /// not one this can read. What a bundle's manifest records, so a stack is
  /// matched to the file of the build that printed it.
  static String? buildIdOf(List<int> symbolsFile) {
    try {
      final Dwarf? dwarf = Dwarf.fromBytes(Uint8List.fromList(symbolsFile));
      return dwarf?.buildId()?.toLowerCase();
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> decode(
    String stack, {
    required List<List<int>> symbolFiles,
  }) async {
    for (final List<int> file in symbolFiles) {
      final Dwarf? dwarf;
      try {
        dwarf = Dwarf.fromBytes(Uint8List.fromList(file));
      } on Object {
        continue;
      }
      if (dwarf == null) continue;
      try {
        final List<String> lines = await Stream<String>.fromIterable(
          stack.split('\n'),
        ).transform(DwarfStackTraceDecoder(dwarf)).toList();
        final String decoded = lines.join('\n');
        // A decoder given the wrong file passes every frame through
        // unchanged; that is not a decoding.
        if (decoded.split('\n').any((String line) =>
            line.trimLeft().startsWith('#') && !line.contains(' abs '))) {
          return decoded;
        }
      } on Object {
        continue;
      }
    }
    return null;
  }
}
