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

/// A synchronous key-value store: `window.localStorage` on the web.
///
/// Synchronous because a crash handler cannot await, and that is the only
/// property a crash store needs from where it keeps things.
abstract class DVCrashKeyValue {
  String? read(String key);
  void write(String key, String value);
  void delete(String key);

  /// Every key currently held, including keys that are not the store's.
  Iterable<String> get keys;
}

/// Crash records in a [DVCrashKeyValue], for a target with no file system.
///
/// Every key is under [prefix], so the store shares a browser's storage with
/// the rest of the application without reading its keys as records. The
/// per-release count is persisted beside the records for the reason the file
/// store persists it: a crash loop on the web is a reload loop.
class DVKeyValueCrashStore implements DVCrashStore {
  DVKeyValueCrashStore(this.storage, {this.prefix = 'dartvel.crash.'});

  final DVCrashKeyValue storage;
  final String prefix;

  String get _records => '${prefix}record.';
  String _record(String id) => '$_records$id';
  String _sentNote(String id) => '${prefix}sent.$id';
  String get _counts => '${prefix}counts';

  @override
  void writeSync(DVCrashReport report) =>
      storage.write(_record(report.id), jsonEncode(report.toJson()));

  @override
  List<DVCrashStoreEntry> pending() {
    final List<String> ids = <String>[
      for (final String key in storage.keys)
        if (key.startsWith(_records)) key.substring(_records.length),
    ]..sort();
    return <DVCrashStoreEntry>[
      for (final String id in ids)
        DVCrashStoreEntry(
          id: id,
          report: dvReadCrashRecord(storage.read(_record(id)) ?? ''),
        ),
    ];
  }

  @override
  void markSent(String id) => storage.write(_sentNote(id), '1');

  @override
  bool isSent(String id) => storage.read(_sentNote(id)) != null;

  @override
  void remove(String id) {
    storage.delete(_record(id));
    storage.delete(_sentNote(id));
  }

  @override
  int countCrash(String release) {
    Map<String, Object?> counts = <String, Object?>{};
    try {
      final Object? json = jsonDecode(storage.read(_counts) ?? '{}');
      if (json is Map<String, Object?>) counts = json;
    } on FormatException {
      // Cut short: the count restarts rather than refusing this crash.
    }
    final Object? previous = counts[release];
    final int next = (previous is int ? previous : 0) + 1;
    counts[release] = next;
    storage.write(_counts, jsonEncode(counts));
    return next;
  }
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
