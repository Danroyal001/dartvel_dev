/// The symbols bundle: what a release build leaves behind that a crash from
/// that release can be read with.
///
/// A release build of an Android app throws away its own legibility twice.
/// R8 renames every Java and Kotlin class and method (the `mapping.txt` it
/// writes is the only way back), and Flutter's `--obfuscate --split-debug-info`
/// strips Dart's symbol names out of the snapshot (the `.symbols` files it
/// writes beside the build are the only way back for those). Both are
/// specific to one build: a mapping from last week's release turns this
/// week's stack into a plausible wrong one. So the bundle is keyed by
/// release, carries a manifest of exactly which files it holds, and the
/// crash backend refuses to read a stack with symbols from another release.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// What a symbol file is for.
enum DVSymbolKind {
  /// R8 / ProGuard `mapping.txt`: Java and Kotlin names and line numbers.
  r8Mapping,

  /// Flutter's `--split-debug-info` output: an ELF holding Dart's symbol
  /// names and DWARF line tables, one per architecture.
  dartSymbols,

  /// `native-debug-symbols.zip` from Gradle: the unstripped `.so` files, for
  /// native (C, C++, Rust) frames.
  nativeDebug,
}

/// One file in a bundle.
final class DVSymbolFile {
  const DVSymbolFile({
    required this.name,
    required this.kind,
    required this.sha256,
    required this.bytes,
    this.arch,
    this.buildId,
  });

  /// A single path segment; see [dvSymbolFileNameOk].
  final String name;
  final DVSymbolKind kind;

  /// Lowercase hex SHA-256 of the file, what the upload is checked against.
  final String sha256;
  final int bytes;

  /// The ABI a [DVSymbolKind.dartSymbols] file was built for.
  final String? arch;

  /// The ELF build id of a Dart symbols file: what a stack trace names in its
  /// `build_id` header, so the right file is chosen when several
  /// architectures are in one bundle.
  final String? buildId;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'kind': kind.name,
        'sha256': sha256,
        'bytes': bytes,
        if (arch != null) 'arch': arch,
        if (buildId != null) 'buildId': buildId,
      };

  static DVSymbolFile fromJson(Map<String, Object?> json) {
    final Object? name = json['name'];
    if (name is! String || !dvSymbolFileNameOk(name)) {
      throw const FormatException('a symbol file name is one plain segment');
    }
    final Object? kind = json['kind'];
    final DVSymbolKind? known = DVSymbolKind.values
        .where((DVSymbolKind k) => k.name == kind)
        .firstOrNull;
    if (known == null) throw FormatException('unknown symbol kind $kind');
    final Object? hash = json['sha256'];
    final Object? size = json['bytes'];
    if (hash is! String || size is! int) {
      throw const FormatException('a symbol file has a sha256 and a size');
    }
    return DVSymbolFile(
      name: name,
      kind: known,
      sha256: hash,
      bytes: size,
      arch: json['arch'] as String?,
      buildId: json['buildId'] as String?,
    );
  }
}

/// A release's bundle: the manifest `manifest.json` holds.
final class DVSymbolsManifest {
  const DVSymbolsManifest({
    required this.release,
    required this.createdAt,
    required this.files,
  });

  /// The on-disk format. A manifest in another format is not guessed at.
  static const int format = 1;

  /// The name of the manifest within a bundle.
  static const String fileName = 'manifest.json';

  /// The release the files were built for, as the crash reports name it
  /// (`DVCrashContext.release`).
  final String release;
  final DateTime createdAt;
  final List<DVSymbolFile> files;

  Iterable<DVSymbolFile> ofKind(DVSymbolKind kind) =>
      files.where((DVSymbolFile f) => f.kind == kind);

  DVSymbolFile? firstOfKind(DVSymbolKind kind) => ofKind(kind).firstOrNull;

  Map<String, Object?> toJson() => <String, Object?>{
        'v': format,
        'release': release,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'files': <Object?>[for (final DVSymbolFile f in files) f.toJson()],
      };

  static DVSymbolsManifest fromJson(Map<String, Object?> json) {
    if (json['v'] != format) {
      throw FormatException('symbols manifest format ${json['v']}');
    }
    final Object? release = json['release'];
    if (release is! String || !dvSymbolReleaseOk(release)) {
      throw const FormatException('a symbols manifest names a release');
    }
    final Object? files = json['files'];
    if (files is! List) throw const FormatException('a manifest lists files');
    return DVSymbolsManifest(
      release: release,
      createdAt: DateTime.parse(json['createdAt']! as String),
      files: <DVSymbolFile>[
        for (final Object? f in files)
          DVSymbolFile.fromJson((f! as Map).cast<String, Object?>()),
      ],
    );
  }
}

/// Whether [name] is safe to use as a file name inside a release directory:
/// one plain segment, no separators, not hidden, bounded.
bool dvSymbolFileNameOk(String name) =>
    name.isNotEmpty &&
    name.length <= 200 &&
    !name.startsWith('.') &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(name);

/// Whether [release] is safe to use as a directory name. Releases are version
/// strings (`1.4.0+12`); anything that could leave the symbols directory is
/// refused.
bool dvSymbolReleaseOk(String release) =>
    release.isNotEmpty &&
    release.length <= 128 &&
    !release.startsWith('.') &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(release);

/// Lowercase hex SHA-256 of [bytes].
String dvSymbolSha256(List<int> bytes) => sha256.convert(bytes).toString();

/// Where a backend keeps symbols, per release.
abstract class DVSymbolRepository {
  /// Stores [bytes] as [name] in [release]'s directory.
  Future<void> putFile(String release, String name, List<int> bytes);

  /// The stored file, or null.
  Future<List<int>?> readFile(String release, String name);

  /// Records [manifest] as complete for its release.
  Future<void> putManifest(DVSymbolsManifest manifest);

  /// The release's manifest, or null when none was uploaded.
  Future<DVSymbolsManifest?> manifest(String release);

  Future<bool> hasRelease(String release);
}

/// Symbols in memory, for tests.
class DVMemorySymbolRepository implements DVSymbolRepository {
  final Map<String, Map<String, List<int>>> _files =
      <String, Map<String, List<int>>>{};
  final Map<String, DVSymbolsManifest> _manifests =
      <String, DVSymbolsManifest>{};

  @override
  Future<void> putFile(String release, String name, List<int> bytes) async {
    _files.putIfAbsent(release, () => <String, List<int>>{})[name] =
        List<int>.of(bytes);
  }

  @override
  Future<List<int>?> readFile(String release, String name) async =>
      _files[release]?[name];

  @override
  Future<void> putManifest(DVSymbolsManifest manifest) async {
    _manifests[manifest.release] = manifest;
    await putFile(manifest.release, DVSymbolsManifest.fileName,
        utf8.encode(jsonEncode(manifest.toJson())));
  }

  @override
  Future<DVSymbolsManifest?> manifest(String release) async =>
      _manifests[release];

  @override
  Future<bool> hasRelease(String release) async =>
      _manifests.containsKey(release);
}
