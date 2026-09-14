/// The content digest of a module package.
///
/// What the publisher signs and what the parent's lockfile pins. It is always
/// recomputed from the bytes on disk and never read from anything the module
/// ships, and it covers every file the parent could run: a file outside the
/// digest is a file the publisher can change without any pin noticing.
///
/// Left out, and only at the package root: `.dart_tool/`, `.git/` and
/// `build/`, which a parent regenerates locally and which no `package:` import
/// can reach; `pubspec.lock`, which a dependency's resolution ignores; and the
/// signature file itself, which cannot sign its own bytes. The same names
/// anywhere below the root are ordinary files and are digested.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The signature a publisher attaches, at the package root.
const String dvModuleSignatureFile = 'dartvel.module.sig';

const Set<String> _rootExcludedDirectories = <String>{
  '.dart_tool',
  '.git',
  'build',
};
const Set<String> _rootExcludedFiles = <String>{
  'pubspec.lock',
  dvModuleSignatureFile,
};

/// Why a package could not be digested.
class DVModuleDigestException implements Exception {
  const DVModuleDigestException(this.message);

  final String message;

  @override
  String toString() => message;
}

final RegExp _digest = RegExp(r'^[0-9a-f]{64}$');

/// Whether [value] is a digest as this writes one: exactly 64 lowercase hex
/// characters.
///
/// Strict on purpose. Accepting a prefix or another case is how a comparison
/// ends up checking fewer bits than it says it does.
bool dvIsModuleDigest(String value) => _digest.hasMatch(value);

/// The sha256 digest of the package at [root], as 64 lowercase hex characters.
///
/// Throws [DVModuleDigestException] for a symbolic link or anything that is
/// neither a file nor a directory: what a link points at is not part of the
/// package and can change after it is pinned.
String dvModulePackageDigest(String root) {
  final Directory directory = Directory(root);
  if (!directory.existsSync()) {
    throw DVModuleDigestException('There is no package at $root to digest.');
  }

  final List<(List<int>, String)> files = <(List<int>, String)>[];
  void walk(String dir, String rel) {
    for (final FileSystemEntity entity in Directory(
      dir,
    ).listSync(followLinks: false)) {
      final String name = p.basename(entity.path);
      final String childRel = rel.isEmpty ? name : '$rel/$name';
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        entity.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) {
        throw DVModuleDigestException(
          '$childRel is a symbolic link. A module package is digested as the '
          'bytes it contains, and what a link points at is not one of them.',
        );
      }
      if (type == FileSystemEntityType.directory) {
        if (rel.isEmpty && _rootExcludedDirectories.contains(name)) continue;
        walk(entity.path, childRel);
      } else if (type == FileSystemEntityType.file) {
        if (rel.isEmpty && _rootExcludedFiles.contains(name)) continue;
        files.add((utf8.encode(childRel), entity.path));
      } else {
        throw DVModuleDigestException(
          '$childRel is neither a file nor a directory, so it cannot be '
          'digested.',
        );
      }
    }
  }

  walk(directory.path, '');
  files.sort(
    ((List<int>, String) a, (List<int>, String) b) => _compareBytes(a.$1, b.$1),
  );

  final _DigestSink out = _DigestSink();
  final ByteConversionSink sink = sha256.startChunkedConversion(out);
  sink.add(utf8.encode('dartvel-module-digest-v1\n'));
  for (final (List<int> path, String file) in files) {
    // Lengths first, so no boundary between a path and its contents can be
    // moved without changing the digest.
    final Uint8List contents = File(file).readAsBytesSync();
    sink
      ..add(_u64(path.length))
      ..add(path)
      ..add(_u64(contents.length))
      ..add(sha256.convert(contents).bytes);
  }
  sink.close();
  return out.value!.toString();
}

int _compareBytes(List<int> a, List<int> b) {
  final int shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

Uint8List _u64(int value) =>
    (ByteData(8)..setUint64(0, value)).buffer.asUint8List();

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
