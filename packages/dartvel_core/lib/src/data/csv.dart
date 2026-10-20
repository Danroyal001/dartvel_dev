/// Reading CSV the way the generated exporter writes it.
///
/// The generated importer split the file on every line break and every comma,
/// while the exporter quotes a value holding a comma, a quote or a line break.
/// So anything the app had exported with a comma in a note or a paragraph in
/// a description could not be imported back. One reader here, that follows
/// the quoting (RFC 4180), and the generated code calls it.
library dartvel.data.csv;

/// [content] as rows of fields.
///
/// A quoted field keeps its commas, its line breaks and its spaces, and `""`
/// inside it is one quote. An unquoted field is trimmed, as before. Blank
/// lines are skipped rather than read as empty records, and a leading
/// byte-order mark is dropped so it never sticks to the first header.
List<List<String>> dvParseCsv(String content) => <List<String>>[
      for (final _CsvRecord record in _records(content)) record.fields,
    ];

/// [content] cut into its records, each as the text it was written as, so a
/// quoted line break stays inside the record it belongs to. [startLines]
/// receives each record's 1-based source line.
List<String> dvSplitCsvRecords(String content, {List<int>? startLines}) {
  final List<String> records = <String>[];
  for (final _CsvRecord record in _records(content)) {
    records.add(record.text);
    startLines?.add(record.line);
  }
  return records;
}

class _CsvRecord {
  _CsvRecord(this.fields, this.text, this.line);
  final List<String> fields;
  final String text;
  final int line;
}

Iterable<_CsvRecord> _records(String content) sync* {
  final String input = content.startsWith('﻿') ? content.substring(1) : content;
  final List<String> fields = <String>[];
  final StringBuffer field = StringBuffer();
  bool quoted = false; // inside quotes now
  bool wasQuoted = false; // this field was quoted
  int recordStart = 0;
  int line = 1;
  int recordLine = 1;

  String finishField() {
    final String value = wasQuoted ? field.toString() : field.toString().trim();
    field.clear();
    wasQuoted = false;
    return value;
  }

  _CsvRecord? finishRecord(int end) {
    fields.add(finishField());
    final String text = input.substring(recordStart, end);
    final bool blank = fields.length == 1 && fields.first.isEmpty && text.trim().isEmpty;
    final _CsvRecord? record = blank ? null : _CsvRecord(List<String>.of(fields), text, recordLine);
    fields.clear();
    return record;
  }

  int index = 0;
  while (index < input.length) {
    final String char = input[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index += 2;
          continue;
        }
        quoted = false;
      } else {
        if (char == '\n') line += 1;
        field.write(char);
      }
      index += 1;
      continue;
    }
    if (char == '"' && field.toString().trim().isEmpty) {
      field.clear();
      quoted = true;
      wasQuoted = true;
    } else if (char == ',') {
      fields.add(finishField());
    } else if (char == '\r' || char == '\n') {
      final _CsvRecord? record = finishRecord(index);
      if (record != null) yield record;
      if (char == '\r' && index + 1 < input.length && input[index + 1] == '\n') index += 1;
      line += 1;
      recordStart = index + 1;
      recordLine = line;
    } else if (!wasQuoted) {
      field.write(char);
    }
    index += 1;
  }
  if (recordStart < input.length || fields.isNotEmpty || field.isNotEmpty || wasQuoted) {
    final _CsvRecord? record = finishRecord(input.length);
    if (record != null) yield record;
  }
}
