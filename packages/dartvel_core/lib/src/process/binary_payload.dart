/// Files carried inside a compiled Dart executable.
///
/// `dart compile exe` writes the runtime, then the program's snapshot, then a
/// 16-byte trailer: where the snapshot starts, and a magic number. The
/// runtime finds its snapshot through that trailer, at the end of its own
/// file, so bytes appended after it stop the program starting.
///
/// A payload goes between the runtime and the snapshot instead. The snapshot
/// moves to the next 64 KiB boundary after the payload (the alignment the
/// runtime maps it at, on 4 KiB, 16 KiB and 64 KiB page sizes alike), the
/// trailer is rewritten to say where it went, and the 16 bytes just before
/// the snapshot say where the payload starts. Reading needs two seeks from
/// the end of the file.
///
/// Both halves of the format are here, so the writer and the reader cannot
/// come to disagree.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

/// The magic number `dart compile exe` ends an executable with.
const int _snapshotMagic = 0xf6f6dcdc;

/// Where the snapshot is moved to.
const int _alignment = 65536;

const String _locatorMagic = 'DVPAYLOC';
const String _payloadMagic = 'DVPAYLD1';

/// Named sections read out of an executable.
final class DVBinaryPayload {
  DVBinaryPayload._(this._file, this._offset, this._sections);

  final String _file;
  final int _offset;
  final Map<String, ({int offset, int length})> _sections;

  /// The section names, in the order they were written.
  List<String> get names => _sections.keys.toList(growable: false);

  /// One section's bytes. Throws [ArgumentError] for a name not carried.
  Uint8List section(String name) {
    final ({int offset, int length})? found = _sections[name];
    if (found == null) {
      throw ArgumentError.value(name, 'name', 'no such section');
    }
    final RandomAccessFile file = File(_file).openSync();
    try {
      file.setPositionSync(_offset + found.offset);
      return file.readSync(found.length);
    } finally {
      file.closeSync();
    }
  }

  /// The payload in the executable at [path], or null when it has none.
  ///
  /// Null also for a file that is not a compiled Dart executable, which is
  /// what `dart run` is: a program run from source carries nothing.
  static DVBinaryPayload? read(String path) {
    final File file = File(path);
    if (!file.existsSync()) return null;
    final RandomAccessFile raf = file.openSync();
    try {
      final int length = raf.lengthSync();
      if (length < 32) return null;
      raf.setPositionSync(length - 16);
      final ByteData trailer = ByteData.sublistView(raf.readSync(16));
      if (trailer.getUint64(8, Endian.little) != _snapshotMagic) return null;
      final int snapshot = trailer.getUint64(0, Endian.little);
      if (snapshot < 16 || snapshot > length - 16) return null;
      raf.setPositionSync(snapshot - 16);
      final Uint8List locator = raf.readSync(16);
      if (ascii.decode(locator.sublist(8), allowInvalid: true) !=
          _locatorMagic) {
        return null;
      }
      final int start =
          ByteData.sublistView(locator).getUint64(0, Endian.little);
      raf.setPositionSync(start);
      final Uint8List head = raf.readSync(12);
      if (head.length < 12 ||
          ascii.decode(head.sublist(0, 8), allowInvalid: true) !=
              _payloadMagic) {
        return null;
      }
      final int headerLength =
          ByteData.sublistView(head).getUint32(8, Endian.little);
      final Object? header = jsonDecode(utf8.decode(raf.readSync(headerLength)));
      final Map<String, ({int offset, int length})> sections =
          <String, ({int offset, int length})>{};
      for (final Object? entry in (header as Map)['sections'] as List) {
        final Map<Object?, Object?> section = entry! as Map;
        sections['${section['name']}'] = (
          offset: section['offset']! as int,
          length: section['length']! as int,
        );
      }
      return DVBinaryPayload._(path, start, sections);
    } on FormatException {
      return null;
    } finally {
      raf.closeSync();
    }
  }

  /// [executable] with [sections] carried inside it.
  ///
  /// Throws [FormatException] for bytes that do not end the way a compiled
  /// Dart executable does: splicing into anything else writes a file that
  /// does not start, and says nothing until somebody runs it.
  static Uint8List splice(
    Uint8List executable,
    Map<String, List<int>> sections,
  ) {
    if (executable.length < 32) {
      throw const FormatException('too short to be a compiled executable');
    }
    final ByteData bytes = ByteData.sublistView(executable);
    if (bytes.getUint64(executable.length - 8, Endian.little) !=
        _snapshotMagic) {
      throw const FormatException(
        'not a compiled Dart executable: it does not end with the snapshot '
        'trailer `dart compile exe` writes',
      );
    }
    final int snapshot = bytes.getUint64(executable.length - 16, Endian.little);
    if (snapshot > executable.length - 16) {
      throw const FormatException('the snapshot trailer points past the file');
    }

    final List<Map<String, Object?>> index = <Map<String, Object?>>[];
    final BytesBuilder body = BytesBuilder(copy: false);
    for (final MapEntry<String, List<int>> section in sections.entries) {
      index.add(<String, Object?>{
        'name': section.key,
        'offset': 0, // placed below, once the header's length is known
        'length': section.value.length,
      });
      body.add(section.value);
    }
    // The offsets depend on the header's length, which depends on the
    // offsets' digits; settle it by writing the header until it stops
    // growing.
    Uint8List header = Uint8List(0);
    for (int attempt = 0; attempt < 4; attempt++) {
      int at = 12 + header.length;
      for (final Map<String, Object?> entry in index) {
        entry['offset'] = at;
        at += entry['length']! as int;
      }
      final Uint8List next =
          utf8.encode(jsonEncode(<String, Object?>{'sections': index}));
      final bool settled = next.length == header.length;
      header = next;
      if (settled) break;
    }

    final int start = snapshot;
    final Uint8List head = Uint8List(12);
    head.setRange(0, 8, ascii.encode(_payloadMagic));
    ByteData.sublistView(head).setUint32(8, header.length, Endian.little);
    final Uint8List content = body.takeBytes();
    final int end = start + 12 + header.length + content.length;
    final int moved = ((end + 16 + _alignment - 1) ~/ _alignment) * _alignment;

    final BytesBuilder out = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(executable, 0, snapshot))
      ..add(head)
      ..add(header)
      ..add(content)
      ..add(Uint8List(moved - 16 - end));
    final ByteData locator = ByteData(16)
      ..setUint64(0, start, Endian.little);
    final Uint8List locatorBytes = locator.buffer.asUint8List();
    locatorBytes.setRange(8, 16, ascii.encode(_locatorMagic));
    out
      ..add(locatorBytes)
      ..add(Uint8List.sublistView(executable, snapshot, executable.length - 16));
    final ByteData trailer = ByteData(16)
      ..setUint64(0, moved, Endian.little)
      ..setUint64(8, _snapshotMagic, Endian.little);
    out.add(trailer.buffer.asUint8List());
    return out.takeBytes();
  }
}

/// [files], keyed by relative path, as one gzip-compressed section.
Uint8List dvPackFiles(Map<String, List<int>> files) {
  final BytesBuilder raw = BytesBuilder(copy: false);
  final List<String> paths = files.keys.toList()..sort();
  for (final String path in paths) {
    final Uint8List name = utf8.encode(path);
    final List<int> data = files[path]!;
    raw
      ..add((ByteData(4)..setUint32(0, name.length, Endian.little))
          .buffer
          .asUint8List())
      ..add(name)
      ..add((ByteData(8)..setUint64(0, data.length, Endian.little))
          .buffer
          .asUint8List())
      ..add(data);
  }
  return Uint8List.fromList(gzip.encode(raw.takeBytes()));
}

/// The files [dvPackFiles] packed.
Map<String, List<int>> dvUnpackFiles(List<int> packed) {
  final Uint8List raw = Uint8List.fromList(gzip.decode(packed));
  final ByteData data = ByteData.sublistView(raw);
  final Map<String, List<int>> files = <String, List<int>>{};
  int at = 0;
  while (at < raw.length) {
    final int nameLength = data.getUint32(at, Endian.little);
    at += 4;
    final String path = utf8.decode(raw.sublist(at, at + nameLength));
    at += nameLength;
    final int length = data.getUint64(at, Endian.little);
    at += 8;
    files[path] = Uint8List.sublistView(raw, at, at + length);
    at += length;
  }
  return files;
}

/// Writes [packed] into a directory under [parent] named by its content, and
/// returns that directory.
///
/// A second start of the same binary finds the directory complete and writes
/// nothing. A new build names a different directory, and the old one is
/// removed once the new one is complete. Written beside its final name and
/// renamed into place, so a start that is killed half way leaves nothing a
/// later start would take as complete.
///
/// Throws [FormatException] for a path that would land outside the directory.
String dvExtractFiles(Uint8List packed, String parent) {
  final String id =
      sha256.convert(packed).toString().substring(0, 16);
  final Directory root = Directory(parent)..createSync(recursive: true);
  final Directory target = Directory('${root.path}${Platform.pathSeparator}$id');
  if (!target.existsSync()) {
    final Map<String, List<int>> files = dvUnpackFiles(packed);
    for (final String path in files.keys) {
      final List<String> parts = path.split('/');
      if (path.startsWith('/') ||
          parts.any((String part) => part == '..' || part.contains(r'\'))) {
        throw FormatException('a packed path leaves its directory', path);
      }
    }
    final Directory partial = Directory('${target.path}.partial-$pid');
    if (partial.existsSync()) partial.deleteSync(recursive: true);
    final String base = partial.absolute.path;
    for (final MapEntry<String, List<int>> entry in files.entries) {
      File(<String>[base, ...entry.key.split('/')]
          .join(Platform.pathSeparator))
        ..createSync(recursive: true)
        ..writeAsBytesSync(entry.value);
    }
    partial.renameSync(target.path);
  }
  for (final FileSystemEntity other in root.listSync()) {
    // Another process's extraction in progress is left to finish.
    if (other is Directory &&
        other.path != target.path &&
        !other.path.contains('.partial-')) {
      other.deleteSync(recursive: true);
    }
  }
  return target.path;
}
