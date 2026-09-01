/// Splitting a file into chunks a queue worker can import independently.
///
/// The generated chunker split every line and attached none of them to a
/// header. For CSV that is two bugs at once: the first chunk carried the
/// header row as if it were a record, and every chunk after it carried no
/// header at all -- so a worker had no column order and could not build a
/// record. Resumable CSV import could not work, and nothing said so, because
/// the tests asserted the method's signature rather than its behaviour.
///
/// One implementation here, so the generator emits a call rather than a copy.
library dartvel.data.import_chunking;

import 'dart:convert';
import 'dart:math' as math;

/// One chunk: the rows, where they came from, and the header they need.
class DVImportChunkPlan {
  const DVImportChunkPlan({
    required this.startRow,
    required this.rows,
    this.header,
  });

  /// The source line the first row came from, 1-based and counting the
  /// header. That is what a person sees when they open the file to fix the
  /// row an error report named.
  final int startRow;

  final List<String> rows;

  /// The header line, on every chunk rather than only the first. A worker
  /// handed chunk 2 needs the column order as much as the one handed chunk 0.
  final String? header;
}

/// Splits [content] into chunks of at most [chunkSize] rows.
///
/// With [hasHeader], the first non-blank line is the header: it is not
/// imported as a row, and it is attached to every chunk.
List<DVImportChunkPlan> dvChunkImportRows(
  String content, {
  required int chunkSize,
  required bool hasHeader,
}) {
  if (chunkSize < 1) {
    // Zero would loop forever and negative would throw somewhere less obvious
    // than here.
    throw ArgumentError.value(
      chunkSize,
      'chunkSize',
      'chunkSize must be positive',
    );
  }

  // Blank lines are dropped rather than imported as empty records. The
  // trailing \r matters too: left on the end of the last field it silently
  // becomes part of the value, so "Ada\r" is imported and never matches
  // "Ada".
  final List<String> lines = const LineSplitter()
      .convert(content)
      .map((String line) => line.endsWith('\r')
          ? line.substring(0, line.length - 1)
          : line)
      .where((String line) => line.trim().isNotEmpty)
      .toList(growable: false);

  if (lines.isEmpty) return const <DVImportChunkPlan>[];

  final String? header = hasHeader ? lines.first : null;
  final int firstDataIndex = hasHeader ? 1 : 0;
  if (firstDataIndex >= lines.length) {
    // A file with only a header. No chunks rather than one empty chunk: a
    // worker handed nothing to do is a job dispatched for no reason.
    return const <DVImportChunkPlan>[];
  }

  final List<DVImportChunkPlan> chunks = <DVImportChunkPlan>[];
  for (int index = firstDataIndex; index < lines.length; index += chunkSize) {
    final int end = math.min(index + chunkSize, lines.length);
    chunks.add(DVImportChunkPlan(
      // 1-based over the source file, header included, so the number points
      // at the line someone would open the file to.
      startRow: index + 1,
      rows: lines.sublist(index, end),
      header: header,
    ));
  }
  return chunks;
}
