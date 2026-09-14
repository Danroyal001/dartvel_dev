import 'dart:convert';
import 'dart:io';

import 'crash_report.dart';
import 'crash_store.dart';

/// Crash records as files in [directory]: one per report, written with a
/// flush before the handler returns.
///
/// Written in place rather than to a temporary name and renamed. A crash
/// during the write then leaves a record that is visibly cut short, which the
/// next launch drops and names (`DV-CRASH-005`) — where a rename would leave
/// nothing, and the crash would be missing without anything saying so.
class DVFileCrashStore implements DVCrashStore {
  DVFileCrashStore(this.directory);

  final String directory;

  File _record(String id) => File('$directory/$id.crash');
  File _sentNote(String id) => File('$directory/$id.sent');
  File get _counts => File('$directory/counts.json');

  void _ensureDirectory() => Directory(directory).createSync(recursive: true);

  @override
  void writeSync(DVCrashReport report) {
    _ensureDirectory();
    _record(report.id)
        .writeAsStringSync(jsonEncode(report.toJson()), flush: true);
  }

  @override
  List<DVCrashStoreEntry> pending() {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) return const <DVCrashStoreEntry>[];
    final List<File> records = <File>[
      for (final FileSystemEntity entity in dir.listSync())
        if (entity is File && entity.path.endsWith('.crash')) entity,
    ]..sort((File a, File b) => a.path.compareTo(b.path));
    return <DVCrashStoreEntry>[
      for (final File file in records)
        DVCrashStoreEntry(
          id: file.uri.pathSegments.last.replaceAll('.crash', ''),
          report: _readFile(file),
        ),
    ];
  }

  DVCrashReport? _readFile(File file) {
    try {
      return dvReadCrashRecord(file.readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  @override
  void markSent(String id) {
    _ensureDirectory();
    _sentNote(id).writeAsStringSync('', flush: true);
  }

  @override
  bool isSent(String id) => _sentNote(id).existsSync();

  @override
  void remove(String id) {
    for (final File file in <File>[_record(id), _sentNote(id)]) {
      if (file.existsSync()) file.deleteSync();
    }
  }

  @override
  int countCrash(String release) {
    _ensureDirectory();
    Map<String, Object?> counts = <String, Object?>{};
    if (_counts.existsSync()) {
      try {
        final Object? json = jsonDecode(_counts.readAsStringSync());
        if (json is Map<String, Object?>) counts = json;
      } on FormatException {
        // A counts file cut short restarts the count rather than refusing to
        // record the crash that is happening now.
      }
    }
    final int next = ((counts[release] as int?) ?? 0) + 1;
    counts[release] = next;
    _counts.writeAsStringSync(jsonEncode(counts), flush: true);
    return next;
  }
}
