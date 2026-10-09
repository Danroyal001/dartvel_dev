import 'dart:convert';
import 'dart:io';

import 'log_file.dart';
import 'logging.dart';

/// Records as JSON lines in [directory], capped at [maxBytes] per file and
/// [files] files, so the log never holds more than their product.
///
/// `dartvel.log` is the file being written; when the next line would take it
/// past [maxBytes] it becomes `dartvel.1.log`, the one before that
/// `dartvel.2.log`, and the oldest is removed. Files untouched for longer
/// than [retention] are removed when the log opens: an application opened
/// once a month should not carry last year's records, and a person who
/// stopped using it has a reasonable expectation that what it wrote ages out.
///
/// Each line is written straight to the operating system rather than through
/// a buffer in this process, so a record written just before a crash is on
/// disk after it -- which is the case the file exists for. A failure to
/// write is counted in [failures] and never thrown: a full disk must not be
/// the reason the code that logged fails.
class DVRotatingLogFile implements DVLogFile {
  DVRotatingLogFile(
    this.directory, {
    this.maxBytes = defaultMaxBytes,
    this.files = defaultFiles,
    this.retention = defaultRetention,
    DateTime Function()? clock,
  })  : assert(maxBytes >= minimumMaxBytes, 'a file smaller than one record'),
        assert(files >= 1, 'a log with no file keeps nothing'),
        _clock = clock ?? DateTime.now {
    _ageOut();
  }

  static const int defaultMaxBytes = 1024 * 1024;
  static const int defaultFiles = 2;
  static const Duration defaultRetention = Duration(days: 7);

  /// The smallest file that still holds a record with its time and level.
  static const int minimumMaxBytes = 128;

  static const String _current = 'dartvel.log';
  static const String _truncated = '[truncated]';

  final String directory;
  final int maxBytes;
  final int files;
  final Duration retention;
  final DateTime Function() _clock;

  RandomAccessFile? _open;
  int _size = 0;
  int _failures = 0;

  /// Writes that did not reach the disk.
  int get failures => _failures;

  File _file(int generation) => File(generation == 0
      ? '$directory/$_current'
      : '$directory/dartvel.$generation.log');

  void _ageOut() {
    try {
      final DateTime oldest = _clock().subtract(retention);
      for (int generation = 0; generation < files; generation++) {
        final File file = _file(generation);
        if (file.existsSync() && file.lastModifiedSync().isBefore(oldest)) {
          file.deleteSync();
        }
      }
      // Generations past the current count, left by a build that kept more
      // files: they would never be rotated away otherwise.
      for (int generation = files; generation < files + 16; generation++) {
        final File file = _file(generation);
        if (file.existsSync()) file.deleteSync();
      }
    } on FileSystemException {
      _failures++;
    }
  }

  @override
  void write(DVLogRecord record) {
    try {
      final List<int> line = _encode(record);
      RandomAccessFile file = _open ?? _openCurrent();
      if (_size > 0 && _size + line.length > maxBytes) {
        _rotate();
        file = _openCurrent();
      }
      file.writeFromSync(line);
      _size += line.length;
    } on FileSystemException {
      _failures++;
      _closeQuietly();
    }
  }

  /// The record as one line that fits in a file, cutting its longest parts
  /// when it does not: a record is worth more cut short than dropped, and a
  /// stack trace pasted into a message is how one gets that long.
  List<int> _encode(DVLogRecord record) {
    List<int> line = utf8.encode('${record.toJsonLine()}\n');
    if (line.length <= maxBytes) return line;
    final Map<String, Object?> json = record.toJson()
      ..remove('context')
      ..remove('stack');
    final String message = record.message;
    final int room = maxBytes -
        utf8.encode('${jsonEncode(json..['message'] = '')}\n').length -
        _truncated.length -
        16;
    // Cut by bytes on a character boundary, leaving space for escaping.
    final List<int> encoded = utf8.encode(message);
    final int keep = room <= 0 ? 0 : (room ~/ 2).clamp(0, encoded.length);
    final String cut = utf8.decode(encoded.sublist(0, keep), allowMalformed: true)
        .replaceAll('�', '');
    json['message'] = '$cut$_truncated';
    final Object? error = json['error'];
    if (error is String && error.length > 200) {
      json['error'] = '${error.substring(0, 200)}$_truncated';
    }
    line = utf8.encode('${jsonEncode(json)}\n');
    return line;
  }

  RandomAccessFile _openCurrent() {
    Directory(directory).createSync(recursive: true);
    final File current = _file(0);
    final RandomAccessFile opened = current.openSync(mode: FileMode.append);
    _open = opened;
    _size = opened.lengthSync();
    // A line cut short by the crash that was writing it is ended here, so
    // the first record of this run does not join it and go with it.
    if (_size > 0) {
      opened.setPositionSync(_size - 1);
      final int last = opened.readByteSync();
      opened.setPositionSync(_size);
      if (last != 0x0A) {
        opened.writeByteSync(0x0A);
        _size++;
      }
    }
    return opened;
  }

  void _rotate() {
    _closeQuietly();
    final File oldest = _file(files - 1);
    if (oldest.existsSync()) oldest.deleteSync();
    for (int generation = files - 2; generation >= 0; generation--) {
      final File file = _file(generation);
      if (file.existsSync()) file.renameSync(_file(generation + 1).path);
    }
    // With a single file there is nowhere to rotate to; the rename above
    // has no target and the file is started again.
    if (files == 1 && _file(0).existsSync()) _file(0).deleteSync();
  }

  void _closeQuietly() {
    try {
      _open?.closeSync();
    } on FileSystemException {
      // Already gone; nothing to release.
    }
    _open = null;
    _size = 0;
  }

  @override
  String export() {
    final StringBuffer out = StringBuffer();
    for (int generation = files - 1; generation >= 0; generation--) {
      final File file = _file(generation);
      try {
        if (!file.existsSync()) continue;
        final String text =
            utf8.decode(file.readAsBytesSync(), allowMalformed: true);
        for (final String line in const LineSplitter().convert(text)) {
          if (_whole(line)) out.writeln(line);
        }
      } on FileSystemException {
        _failures++;
      }
    }
    return out.toString();
  }

  static bool _whole(String line) {
    if (line.isEmpty) return false;
    try {
      final Object? json = jsonDecode(line);
      if (json is! Map<String, Object?>) return false;
      DVLogRecord.fromJson(json);
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  void clear() {
    _closeQuietly();
    for (int generation = 0; generation < files; generation++) {
      try {
        final File file = _file(generation);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        _failures++;
      }
    }
  }

  @override
  void close() => _closeQuietly();
}
