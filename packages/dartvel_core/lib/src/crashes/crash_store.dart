/// Where a crash is kept between the run that had it and the run that sends
/// it.
library;

import 'dart:convert';

import 'crash_report.dart';

export 'crash_store_unsupported.dart'
    if (dart.library.io) 'crash_store_io.dart';

/// One record found at launch: a report, or a record that is not a whole one.
class DVCrashStoreEntry {
  final String id;

  /// Null when the record could not be read — cut short by the crash that was
  /// writing it.
  final DVCrashReport? report;

  const DVCrashStoreEntry({required this.id, this.report});

  bool get truncated => report == null;
}

/// The handler's side and the launch's side of crash persistence.
///
/// [writeSync] is synchronous on purpose, and it is the whole of what a crash
/// handler does. A handler runs in a process that is already going down; a
/// write that awaits anything finishes after the process does.
abstract class DVCrashStore {
  /// Writes [report] before returning.
  void writeSync(DVCrashReport report);

  /// Every record left by earlier runs, oldest first.
  List<DVCrashStoreEntry> pending();

  /// Notes that [id] reached the sink, before the record is removed. A
  /// process that dies between the two finds the note at the next launch and
  /// removes the record without sending it again.
  void markSent(String id);

  bool isSent(String id);

  /// Removes the record and its sent note.
  void remove(String id);

  /// Counts one more crash on this device for [release] and returns the
  /// count. Persisted with the records, because a crash loop is a sequence of
  /// restarts, and a limit that restarts with them limits nothing.
  int countCrash(String release);
}

/// A store in memory: for tests, and for a target with nowhere to write.
class DVMemoryCrashStore implements DVCrashStore {
  /// The stored records, as the bytes a file store would hold.
  final Map<String, String> raw = <String, String>{};
  final Set<String> _sent = <String>{};
  final Map<String, int> _counts = <String, int>{};

  @override
  void writeSync(DVCrashReport report) {
    raw[report.id] = jsonEncode(report.toJson());
  }

  @override
  List<DVCrashStoreEntry> pending() => <DVCrashStoreEntry>[
        for (final MapEntry<String, String> entry in raw.entries)
          DVCrashStoreEntry(id: entry.key, report: _read(entry.value)),
      ];

  /// Cuts [id]'s record in half, the way a crash mid-write would.
  void truncate(String id) {
    final String? record = raw[id];
    if (record != null) raw[id] = record.substring(0, record.length ~/ 2);
  }

  @override
  void markSent(String id) => _sent.add(id);

  @override
  bool isSent(String id) => _sent.contains(id);

  @override
  void remove(String id) {
    raw.remove(id);
    _sent.remove(id);
  }

  @override
  int countCrash(String release) =>
      _counts[release] = (_counts[release] ?? 0) + 1;
}

/// Reads one stored record, or null when it is not a whole one.
DVCrashReport? dvReadCrashRecord(String record) {
  try {
    final Object? json = jsonDecode(record);
    if (json is! Map<String, Object?>) return null;
    return DVCrashReport.fromJson(json);
  } on FormatException {
    return null;
  }
}

DVCrashReport? _read(String record) => dvReadCrashRecord(record);
