/// How a record reads in a platform's own log: logcat, the Apple unified
/// log, journald, a terminal. Pure functions, so every target's formatting
/// is tested on the machine running the tests.
library;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart' show DVLogLevel, DVLogRecord;

/// `android.util.Log` priorities: VERBOSE 2, DEBUG 3, INFO 4, WARN 5,
/// ERROR 6, ASSERT 7.
int dvAndroidLogPriority(DVLogLevel level) => switch (level) {
      .trace => 2,
      .debug => 3,
      .info => 4,
      .warn => 5,
      .error => 6,
      .fatal => 7,
    };

/// syslog(3) priorities: DEBUG 7, INFO 6, WARNING 4, ERR 3, CRIT 2.
int dvSyslogPriority(DVLogLevel level) => switch (level) {
      .trace || .debug => 7,
      .info => 6,
      .warn => 4,
      .error => 3,
      .fatal => 2,
    };

/// The sd-daemon prefix journald reads a line's priority from.
String dvJournalPrefix(DVLogLevel level) => '<${dvSyslogPriority(level)}>';

final RegExp _needsQuotes = RegExp(r'[\s="]');

String _fieldValue(Object? value) {
  if (value is Map || value is List) return jsonEncode(value);
  final String text = '$value';
  return _needsQuotes.hasMatch(text) || text.isEmpty ? jsonEncode(text) : text;
}

/// `LEVEL tag: message key=value ... trace=<id>` on one line.
String dvNativeLogLine(DVLogRecord record) {
  final StringBuffer line = StringBuffer(record.level.name.toUpperCase())
    ..write(' ');
  if (record.tag != null && record.tag!.isNotEmpty) {
    line.write('${record.tag}: ');
  }
  line.write(record.message);
  record.context.forEach((String key, Object? value) {
    line.write(' $key=${_fieldValue(value)}');
  });
  if (record.traceId != null) line.write(' trace=${record.traceId}');
  return line.toString();
}

/// The line, then the error and the stack on the lines after it, for a log
/// that keeps a multi-line entry together.
String dvNativeLogText(DVLogRecord record) => <String>[
      dvNativeLogLine(record),
      if (record.error != null) record.error!,
      if (record.stackTrace != null && record.stackTrace!.isNotEmpty)
        record.stackTrace!.trimRight(),
    ].join('\n');

/// logcat truncates an entry a little past 4 KB; [text] cut into pieces of
/// at most [maxBytes] UTF-8 bytes, never inside a character.
List<String> dvLogcatChunks(String text, {int maxBytes = 4000}) {
  final List<String> chunks = <String>[];
  final StringBuffer current = StringBuffer();
  int bytes = 0;
  for (final int rune in text.runes) {
    final String character = String.fromCharCode(rune);
    final int size = utf8.encode(character).length;
    if (bytes + size > maxBytes && bytes > 0) {
      chunks.add(current.toString());
      current.clear();
      bytes = 0;
    }
    current.write(character);
    bytes += size;
  }
  if (current.isNotEmpty || chunks.isEmpty) chunks.add(current.toString());
  return chunks;
}

/// A logcat tag: the record's tag, or the last part of the application id;
/// at most 23 characters, the limit older Android releases enforce.
String dvAndroidLogTag(String appId, String? tag) {
  String chosen = (tag != null && tag.isNotEmpty) ? tag : appId.split('.').last;
  if (chosen.isEmpty) chosen = 'dartvel';
  return chosen.length > 23 ? chosen.substring(0, 23) : chosen;
}
