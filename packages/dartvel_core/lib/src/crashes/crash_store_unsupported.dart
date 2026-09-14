import 'crash_report.dart';
import 'crash_store.dart';

/// A file store, on a target with no file system to put it on.
///
/// Constructing one throws rather than returning a store that silently keeps
/// nothing: a crash reporter that loses every report across a restart looks
/// exactly like one that works until the day somebody needs a report.
class DVFileCrashStore implements DVCrashStore {
  DVFileCrashStore(this.directory) {
    throw UnsupportedError(
        'DVFileCrashStore needs dart:io; use DVMemoryCrashStore or a '
        'platform store on this target');
  }

  final String directory;

  @override
  void writeSync(DVCrashReport report) => throw UnsupportedError('no files');

  @override
  List<DVCrashStoreEntry> pending() => throw UnsupportedError('no files');

  @override
  void markSent(String id) => throw UnsupportedError('no files');

  @override
  bool isSent(String id) => throw UnsupportedError('no files');

  @override
  void remove(String id) => throw UnsupportedError('no files');

  @override
  int countCrash(String release) => throw UnsupportedError('no files');
}
