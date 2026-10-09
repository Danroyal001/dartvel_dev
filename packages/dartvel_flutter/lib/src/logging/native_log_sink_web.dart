/// The browser console, as a destination for DV.log records.
///
/// Each record is one console call at its level -- `debug`, `info`, `warn`,
/// `error` -- with the line first and the fields as an object after it, so
/// the developer tools show them expandable and filterable rather than
/// flattened into text.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:dartvel_core/dartvel.dart' show DVLogLevel, DVLogRecord, DVLogSink;


@JS('console.debug')
external void _consoleDebug(JSString line, JSAny? fields);
@JS('console.info')
external void _consoleInfo(JSString line, JSAny? fields);
@JS('console.warn')
external void _consoleWarn(JSString line, JSAny? fields);
@JS('console.error')
external void _consoleError(JSString line, JSAny? fields);

@JS('JSON.parse')
external JSAny? _jsonParse(JSString text);

DVLogSink? dvPlatformLogSink({required String appId}) => DVConsoleLogSink();

/// Writes each record to the browser console.
class DVConsoleLogSink implements DVLogSink {
  @override
  void write(DVLogRecord record) {
    try {
      final String line = <String>[
        '${record.level.name.toUpperCase()} '
            '${record.tag == null ? '' : '${record.tag}: '}${record.message}',
        if (record.error != null) record.error!,
        if (record.stackTrace != null) record.stackTrace!,
      ].join('\n');
      final Map<String, Object?> fields = <String, Object?>{
        ...record.context,
        if (record.traceId != null) 'trace': record.traceId,
      };
      final JSAny? jsFields =
          fields.isEmpty ? null : _jsonParse(jsonEncode(fields).toJS);
      switch (record.level) {
        case DVLogLevel.trace || DVLogLevel.debug:
          _consoleDebug(line.toJS, jsFields);
        case DVLogLevel.info:
          _consoleInfo(line.toJS, jsFields);
        case DVLogLevel.warn:
          _consoleWarn(line.toJS, jsFields);
        case DVLogLevel.error || DVLogLevel.fatal:
          _consoleError(line.toJS, jsFields);
      }
    } on Object {
      // A console that cannot be written to is not the application's problem.
    }
  }
}

