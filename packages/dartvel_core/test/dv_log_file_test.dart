// The log a device keeps: capped, rotated, aged out, and readable back.
//
// The cap is the property that matters most and fails most quietly. A log
// file that grows past it is not noticed until a phone is out of space, and
// by then the logs are the reason, which is the opposite of what they were
// kept for.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('dv-log-file-'));
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  DVLogRecord record(String message, {DateTime? time}) => DVLogRecord(
        level: DVLogLevel.info,
        message: message,
        tag: 'test',
        time: time ?? DateTime.utc(2026, 10, 9, 12),
      );

  int bytesOnDisk() => directory
      .listSync()
      .whereType<File>()
      .fold<int>(0, (int total, File file) => total + file.lengthSync());

  test('writes one JSON record per line and reads them back in order', () {
    final DVRotatingLogFile file = DVRotatingLogFile(directory.path);
    file.write(record('first'));
    file.write(record('second'));
    file.close();

    final List<String> lines = const LineSplitter().convert(file.export());
    expect(lines.map((String line) => jsonDecode(line)['message']),
        <String>['first', 'second']);
  });

  test('never holds more than its cap, however much is written', () {
    final DVRotatingLogFile file =
        DVRotatingLogFile(directory.path, maxBytes: 2048, files: 3);
    for (int index = 0; index < 500; index++) {
      file.write(record('line $index ${'x' * 40}'));
      expect(bytesOnDisk(), lessThanOrEqualTo(2048 * 3),
          reason: 'over the cap after record $index');
    }
    file.close();

    final List<String> messages = const LineSplitter()
        .convert(file.export())
        .map((String line) => jsonDecode(line)['message'] as String)
        .toList();
    expect(messages.last, startsWith('line 499 '),
        reason: 'the newest records are the ones kept');
    expect(messages.first, isNot(startsWith('line 0 ')),
        reason: 'the oldest records are the ones dropped');
    final List<int> order = <int>[
      for (final String message in messages) int.parse(message.split(' ')[1]),
    ];
    expect(order, orderedEquals(List<int>.of(order)..sort()),
        reason: 'export reads the rotated files oldest first');
  });

  test('a record larger than the whole file is cut to fit, not dropped', () {
    final DVRotatingLogFile file =
        DVRotatingLogFile(directory.path, maxBytes: 1024, files: 2);
    file.write(record('y' * 5000));
    file.close();

    expect(bytesOnDisk(), lessThanOrEqualTo(1024 * 2));
    final Map<String, Object?> written =
        jsonDecode(file.export().trim()) as Map<String, Object?>;
    expect((written['message']! as String).startsWith('yyyy'), isTrue);
    expect(written['message'], endsWith('[truncated]'));
  });

  test('files older than the retention are removed when the log opens', () {
    final DateTime now = DateTime(2026, 10, 9);
    final DVRotatingLogFile first =
        DVRotatingLogFile(directory.path, maxBytes: 200, files: 3);
    for (int index = 0; index < 10; index++) {
      first.write(record('old $index'));
    }
    first.close();
    for (final File file in directory.listSync().whereType<File>()) {
      file.setLastModifiedSync(now.subtract(const Duration(days: 30)));
    }

    final DVRotatingLogFile reopened = DVRotatingLogFile(directory.path,
        maxBytes: 200,
        files: 3,
        retention: const Duration(days: 7),
        clock: () => now);
    reopened.write(record('new'));
    reopened.close();

    final List<String> lines = const LineSplitter().convert(reopened.export());
    expect(lines.map((String line) => jsonDecode(line)['message']),
        <String>['new']);
  });

  test('a line cut short by a crash is left out of the export', () {
    final DVRotatingLogFile file = DVRotatingLogFile(directory.path);
    file.write(record('whole'));
    file.close();
    File('${directory.path}/dartvel.log')
        .writeAsStringSync('{"time":"2026-10-09T12:', mode: FileMode.append);

    final DVRotatingLogFile reopened = DVRotatingLogFile(directory.path);
    reopened.write(record('after'));
    reopened.close();

    final List<String> lines = const LineSplitter().convert(reopened.export());
    expect(lines.map((String line) => jsonDecode(line)['message']),
        <String>['whole', 'after']);
  });

  test('clear removes every file and the log keeps working', () {
    final DVRotatingLogFile file =
        DVRotatingLogFile(directory.path, maxBytes: 200, files: 3);
    for (int index = 0; index < 20; index++) {
      file.write(record('line $index'));
    }
    file.clear();
    expect(file.export(), isEmpty);

    file.write(record('after clear'));
    file.close();
    expect(file.export(), contains('after clear'));
  });

  test('a directory that cannot be written is not an exception', () {
    final File blocker = File('${directory.path}/not-a-directory')
      ..writeAsStringSync('');
    final DVRotatingLogFile file = DVRotatingLogFile(blocker.path);

    file.write(record('lost'));

    expect(file.failures, greaterThan(0));
    expect(file.export(), isEmpty);
  });

  test('DV.log.export reads the installed file', () async {
    DV.ObservabilityAndLogging.resetLogging();
    final DVRotatingLogFile file = DVRotatingLogFile(directory.path);
    DV.ObservabilityAndLogging.useLogFile(file);
    addTearDown(DV.ObservabilityAndLogging.resetLogging);

    DV.log('kept on the device', tag: 'boot');

    expect(await DV.log.export(), contains('kept on the device'));
    await DV.log.clear();
    expect(await DV.log.export(), isNot(contains('kept on the device')));
  });
}
