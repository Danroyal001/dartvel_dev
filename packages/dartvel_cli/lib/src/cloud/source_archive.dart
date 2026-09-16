/// The project as a cloud build receives it: a zip of the source, without
/// build output, tool caches or `.env` files.
///
/// In a git repository the file list is git's own -- tracked files plus
/// untracked ones that are not ignored -- so what is sent is what a clean
/// checkout with local edits would hold, and a `.gitignore` is honoured
/// without a second reading of it here. Outside one, the directory is walked.
/// Either way [dvCloudSourceExcluded] has the last word, because a tracked
/// `.env` is still an `.env`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/cloud.dart';
import 'package:path/path.dart' as p;

class DVSourceArchive {
  const DVSourceArchive(this.file, this.fileCount);

  final File file;
  final int fileCount;
}

/// The source at [root] zipped into a temporary file the caller deletes.
/// [app] is the application's directory inside it.
Future<DVSourceArchive> dvPackSource(String root, {String app = '.'}) async {
  final List<String> paths = (await _gitFiles(root) ?? _walk(root))
      .where((String path) => !dvCloudSourceExcluded(path, app: app))
      .where((String path) => FileSystemEntity.typeSync(p.join(root, path), followLinks: false) ==
          FileSystemEntityType.file)
      .toList()
    ..sort();
  final Directory temp = Directory.systemTemp.createTempSync('dartvel_cloud_source_');
  final File zip = File(p.join(temp.path, 'source.zip'));
  final RandomAccessFile out = zip.openSync(mode: FileMode.write);
  final BytesBuilder central = BytesBuilder(copy: false);
  int offset = 0;
  try {
    for (final String path in paths) {
      final Uint8List data = File(p.join(root, path)).readAsBytesSync();
      final List<int> deflated = ZLibEncoder(raw: true, level: 6).convert(data);
      final bool store = deflated.length >= data.length;
      final List<int> body = store ? data : deflated;
      final List<int> name = utf8.encode(path);
      final int crc = _crc32(data);
      final BytesBuilder local = BytesBuilder(copy: false)
        ..add(_u32(0x04034b50))
        ..add(_u16(20))
        ..add(_u16(0x0800)) // names are UTF-8
        ..add(_u16(store ? 0 : 8))
        ..add(_u16(0))
        ..add(_u16(0x21))
        ..add(_u32(crc))
        ..add(_u32(body.length))
        ..add(_u32(data.length))
        ..add(_u16(name.length))
        ..add(_u16(0))
        ..add(name);
      final Uint8List header = local.takeBytes();
      out
        ..writeFromSync(header)
        ..writeFromSync(body);
      central
        ..add(_u32(0x02014b50))
        ..add(_u16(0x031e))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(store ? 0 : 8))
        ..add(_u16(0))
        ..add(_u16(0x21))
        ..add(_u32(crc))
        ..add(_u32(body.length))
        ..add(_u32(data.length))
        ..add(_u16(name.length))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(_executable(root, path) ? (0x81ed << 16) : (0x81a4 << 16)))
        ..add(_u32(offset))
        ..add(name);
      offset += header.length + body.length;
      if (offset > 0xffffffff) {
        throw const FileSystemException('The project is larger than 4 GB, which a zip without zip64 cannot hold.');
      }
    }
    final Uint8List directory = central.takeBytes();
    out
      ..writeFromSync(directory)
      ..writeFromSync(<int>[
        ..._u32(0x06054b50),
        ..._u16(0),
        ..._u16(0),
        ..._u16(paths.length),
        ..._u16(paths.length),
        ..._u32(directory.length),
        ..._u32(offset),
        ..._u16(0),
      ]);
  } finally {
    out.closeSync();
  }
  return DVSourceArchive(zip, paths.length);
}

Future<List<String>?> _gitFiles(String root) async {
  try {
    final ProcessResult inside = await Process.run(
        'git', <String>['rev-parse', '--is-inside-work-tree'],
        workingDirectory: root);
    if (inside.exitCode != 0) return null;
    final ProcessResult r = await Process.run(
      'git',
      <String>['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '.'],
      workingDirectory: root,
    );
    if (r.exitCode != 0) return null;
    return '${r.stdout}'
        .split('\u0000')
        .where((String s) => s.isNotEmpty)
        .toSet()
        .toList();
  } on ProcessException {
    return null;
  }
}

List<String> _walk(String root) => <String>[
      for (final FileSystemEntity entity
          in Directory(root).listSync(recursive: true, followLinks: false))
        if (entity is File) p.posix.joinAll(p.split(p.relative(entity.path, from: root))),
    ];

bool _executable(String root, String path) {
  if (Platform.isWindows) return false;
  return FileStat.statSync(p.join(root, path)).mode & 0x49 != 0;
}

List<int> _u16(int v) => <int>[v & 0xff, (v >> 8) & 0xff];
List<int> _u32(int v) =>
    <int>[v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

final List<int> _crcTable = List<int>.generate(256, (int n) {
  int c = n;
  for (int k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  int crc = 0xffffffff;
  for (final int byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}
