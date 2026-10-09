import 'dart:convert';

import 'package:dartvel_core/dartvel.dart'
    show DVLogLevel, DVLogRecord, DVLogger;
import 'package:dartvel_flutter/src/logging/native_log_format.dart';
import 'package:dartvel_flutter/src/logging/native_log_sink.dart';
import 'package:dartvel_flutter/src/logging/native_log_sink_io.dart';
import 'package:flutter_test/flutter_test.dart';

DVLogRecord _record({
  DVLogLevel level = .info,
  String message = 'Checkout completed',
  String? tag,
  Map<String, Object?> context = const <String, Object?>{},
  String? error,
  String? stackTrace,
  String? traceId,
}) =>
    DVLogRecord(
      level: level,
      message: message,
      tag: tag,
      context: context,
      error: error,
      stackTrace: stackTrace,
      traceId: traceId,
      time: DateTime.utc(2026, 10, 9, 12),
    );

void main() {
  group('priorities', () {
    test('Android priorities follow android.util.Log, VERBOSE 2 to ASSERT 7',
        () {
      expect(
        <int>[for (final DVLogLevel level in DVLogLevel.values) dvAndroidLogPriority(level)],
        <int>[2, 3, 4, 5, 6, 7],
      );
    });

    test('syslog priorities: a warning is 4, an error 3, fatal is critical',
        () {
      expect(dvSyslogPriority(.trace), 7);
      expect(dvSyslogPriority(.debug), 7);
      expect(dvSyslogPriority(.info), 6);
      expect(dvSyslogPriority(.warn), 4);
      expect(dvSyslogPriority(.error), 3);
      expect(dvSyslogPriority(.fatal), 2);
    });

    test('the journald prefix is the sd-daemon form of the syslog priority',
        () {
      expect(dvJournalPrefix(.error), '<3>');
      expect(dvJournalPrefix(.info), '<6>');
    });
  });

  group('the line', () {
    test('level, tag, message, then the fields as key=value', () {
      final String line = dvNativeLogLine(_record(
        tag: 'checkout',
        context: <String, Object?>{'orderId': 'ord_1', 'total': 42},
      ));
      expect(line, 'INFO checkout: Checkout completed orderId=ord_1 total=42');
    });

    test('no tag means no empty "tag:" in front of the message', () {
      expect(dvNativeLogLine(_record()), 'INFO Checkout completed');
    });

    test('a value with a space or an equals sign is quoted, so it reads back',
        () {
      final String line = dvNativeLogLine(_record(
        context: <String, Object?>{'note': 'two words', 'query': 'a=b'},
      ));
      expect(line, 'INFO Checkout completed note="two words" query="a=b"');
    });

    test('nested values are JSON rather than a Dart toString', () {
      final String line = dvNativeLogLine(_record(
        context: <String, Object?>{
          'items': <Object?>[1, 2],
          'address': <String, Object?>{'city': 'Uyo'},
        },
      ));
      expect(line, contains('items=[1,2]'));
      expect(line, contains('address={"city":"Uyo"}'));
    });

    test('a redacted value passes through exactly as the logger left it', () {
      final DVLogger logger = DVLogger();
      final List<DVLogRecord> seen = <DVLogRecord>[];
      logger.onRecord = seen.add;
      logger.log('signed in', context: <String, Object?>{'password': 'hunter2'});
      final String line = dvNativeLogLine(seen.single);
      expect(line, isNot(contains('hunter2')));
      expect(line, contains('password=${DVLogger.redactedValue}'));
    });

    test('the trace id rides on the line, so a device line finds its request',
        () {
      expect(
        dvNativeLogLine(_record(traceId: 'abc123')),
        'INFO Checkout completed trace=abc123',
      );
    });

    test('the text keeps the error and stack on the lines after it', () {
      final String text = dvNativeLogText(_record(
        level: .error,
        error: 'StateError: closed',
        stackTrace: '#0 main\n#1 run',
      ));
      expect(
        text,
        'ERROR Checkout completed\nStateError: closed\n#0 main\n#1 run',
      );
    });
  });

  group('logcat', () {
    test('a short text is one chunk', () {
      expect(dvLogcatChunks('hello'), <String>['hello']);
    });

    test('chunks stay under the byte limit and rejoin to the text', () {
      final String text = 'a' * 9000;
      final List<String> chunks = dvLogcatChunks(text);
      expect(chunks.length, 3);
      for (final String chunk in chunks) {
        expect(utf8.encode(chunk).length, lessThanOrEqualTo(4000));
      }
      expect(chunks.join(), text);
    });

    test('a multibyte character is never cut at a chunk boundary', () {
      // 3999 one-byte characters then a four-byte emoji: a byte split at
      // 4000 lands inside the emoji.
      final String text = '${'a' * 3999}😀tail';
      final List<String> chunks = dvLogcatChunks(text);
      expect(chunks.first, 'a' * 3999);
      expect(chunks.join(), text);
      for (final String chunk in chunks) {
        expect(utf8.encode(chunk).length, lessThanOrEqualTo(4000));
        // A cut inside a character would not decode back to itself.
        expect(utf8.decode(utf8.encode(chunk)), chunk);
      }
    });

    test('the tag is the record tag, or the last part of the app id, at most '
        '23 characters', () {
      expect(dvAndroidLogTag('com.example.shop', null), 'shop');
      expect(dvAndroidLogTag('com.example.shop', 'checkout'), 'checkout');
      expect(
        dvAndroidLogTag('shop', 'a-category-name-that-is-far-too-long').length,
        23,
      );
      expect(dvAndroidLogTag('', null), 'dartvel');
    });
  });

  group('the io sink', () {
    test('Linux writes the text to stderr', () {
      final List<String> written = <String>[];
      final DVIoNativeLogSink sink = DVIoNativeLogSink(
        appId: 'shop',
        os: 'linux',
        environment: const <String, String>{},
        writeStderr: written.add,
      );
      sink.write(_record(tag: 'checkout'));
      expect(written, <String>['INFO checkout: Checkout completed']);
    });

    test('under journald every line carries the priority prefix', () {
      final List<String> written = <String>[];
      final DVIoNativeLogSink sink = DVIoNativeLogSink(
        appId: 'shop',
        os: 'linux',
        environment: const <String, String>{'JOURNAL_STREAM': '8:12345'},
        writeStderr: written.add,
      );
      sink.write(_record(
        level: .error,
        error: 'boom',
        stackTrace: '#0 main',
      ));
      expect(written, <String>['<3>ERROR Checkout completed\n<3>boom\n<3>#0 main']);
    });

    test('Android sends each chunk to the native writer with its priority',
        () {
      final List<(int, String, String)> sent = <(int, String, String)>[];
      final DVIoNativeLogSink sink = DVIoNativeLogSink(
        appId: 'com.example.shop',
        os: 'android',
        environment: const <String, String>{},
        writeStderr: (String _) => fail('Android must not write to stderr'),
        writeNative: (int priority, String tag, String text) =>
            sent.add((priority, tag, text)),
      );
      sink.write(_record(level: .warn, message: 'x' * 5000));
      expect(sent.length, 2);
      expect(sent.every(((int, String, String) entry) => entry.$1 == 5), isTrue);
      expect(sent.first.$2, 'shop');
      expect(sent.map(((int, String, String) entry) => entry.$3).join(),
          'WARN ${'x' * 5000}');
    });

    test('a native writer that throws falls back to stderr and never throws',
        () {
      final List<String> written = <String>[];
      final DVIoNativeLogSink sink = DVIoNativeLogSink(
        appId: 'shop',
        os: 'ios',
        environment: const <String, String>{},
        writeStderr: written.add,
        writeNative: (int priority, String tag, String text) =>
            throw ArgumentError('no syslog'),
      );
      sink.write(_record());
      sink.write(_record(message: 'second'));
      expect(written, <String>['INFO Checkout completed', 'INFO second']);
    });

    test('Apple platforms send the syslog priority to the native writer', () {
      final List<int> priorities = <int>[];
      final DVIoNativeLogSink sink = DVIoNativeLogSink(
        appId: 'shop',
        os: 'macos',
        environment: const <String, String>{},
        writeStderr: (String _) {},
        writeNative: (int priority, String tag, String text) =>
            priorities.add(priority),
      );
      sink.write(_record(level: .error));
      expect(priorities, <int>[3]);
    });
  });

  test('nothing is installed under flutter test', () {
    // This process is a flutter test: the sink would print into the test
    // runner's output.
    expect(dvNativeLogSink(appId: 'shop'), isNull);
  });
}
