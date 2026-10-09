import 'log_file.dart';
import 'logging.dart';

/// A rotating log file, on a target with no file system to put it on.
///
/// Constructing one throws rather than returning a log that silently keeps
/// nothing: the browser keeps its records in the in-process buffer and the
/// console, and says so, rather than pretending to have a file.
class DVRotatingLogFile implements DVLogFile {
  DVRotatingLogFile(
    this.directory, {
    this.maxBytes = DVRotatingLogFile.defaultMaxBytes,
    this.files = DVRotatingLogFile.defaultFiles,
    this.retention = DVRotatingLogFile.defaultRetention,
    DateTime Function()? clock,
  }) {
    throw UnsupportedError(
        'DVRotatingLogFile needs dart:io; on this target records are kept in '
        'the in-process buffer');
  }

  static const int defaultMaxBytes = 1024 * 1024;
  static const int defaultFiles = 2;
  static const Duration defaultRetention = Duration(days: 7);

  final String directory;
  final int maxBytes;
  final int files;
  final Duration retention;

  int get failures => 0;

  @override
  void write(DVLogRecord record) => throw UnsupportedError('no files');

  @override
  String export() => throw UnsupportedError('no files');

  @override
  void clear() => throw UnsupportedError('no files');

  @override
  void close() {}
}
