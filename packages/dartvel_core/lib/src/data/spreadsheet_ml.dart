/// Reading the Excel file the generated exporter writes.
///
/// A data model's exportExcel writes SpreadsheetML (XML Spreadsheet 2003),
/// which Excel, LibreOffice and Numbers open without a converter, while its
/// importExcel read only tab-separated text. So a workbook the application
/// had exported could not be imported back. This reads the first worksheet of
/// such a workbook into rows of text, and the generated importer calls it.
library dartvel.data.spreadsheet_ml;

final RegExp _worksheet = RegExp(
  r'<Worksheet\b[^>]*>([\s\S]*?)</Worksheet>',
);
final RegExp _row = RegExp(r'<Row\b[^>]*?(?:/>|>([\s\S]*?)</Row>)');
final RegExp _cell = RegExp(r'<Cell\b([^>]*?)(?:/>|>([\s\S]*?)</Cell>)');
final RegExp _index = RegExp(r'''ss:Index\s*=\s*["'](\d+)["']''');
final RegExp _data = RegExp(r'<Data\b[^>]*?(?:/>|>([\s\S]*?)</Data>)');
final RegExp _tag = RegExp(r'<[^>]+>');
final RegExp _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');

/// The first worksheet of the SpreadsheetML workbook [content], as rows of
/// cell text.
///
/// A cell carrying `ss:Index` lands in that column, with the cells it skipped
/// read as empty, because Excel writes the index after a gap rather than an
/// empty cell. Formatting inside a cell's data is dropped and entities are
/// decoded. Every cell is text; the data model's parser turns it into the
/// field's type, as it does a CSV value.
///
/// Throws a [FormatException] when [content] has no worksheet, so a file that
/// is not a workbook is not read as one with no rows.
List<List<String>> dvParseSpreadsheetMl(String content) {
  final RegExpMatch? sheet = _worksheet.firstMatch(content);
  if (sheet == null) {
    throw const FormatException(
      'Not a SpreadsheetML workbook: no <Worksheet> element.',
    );
  }
  final List<List<String>> rows = <List<String>>[];
  for (final RegExpMatch row in _row.allMatches(sheet.group(1)!)) {
    final List<String> cells = <String>[];
    for (final RegExpMatch cell in _cell.allMatches(row.group(1) ?? '')) {
      final RegExpMatch? index = _index.firstMatch(cell.group(1)!);
      if (index != null) {
        final int column = int.parse(index.group(1)!);
        while (cells.length < column - 1) {
          cells.add('');
        }
      }
      final RegExpMatch? data = _data.firstMatch(cell.group(2) ?? '');
      cells.add(_decode((data?.group(1) ?? '').replaceAll(_tag, '')));
    }
    rows.add(cells);
  }
  return rows;
}

String _decode(String text) => text.replaceAllMapped(_entity, (Match match) {
      final String name = match.group(1)!;
      return switch (name) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        _ when name.startsWith('#x') =>
          String.fromCharCode(int.parse(name.substring(2), radix: 16)),
        _ => String.fromCharCode(int.parse(name.substring(1))),
      };
    });
