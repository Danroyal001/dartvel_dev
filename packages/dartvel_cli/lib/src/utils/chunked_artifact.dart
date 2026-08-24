/// Splitting large build artifacts across files small enough to commit, and
/// putting them back together.
///
/// A Flutter engine or an embedder library does not fit in a git repository:
/// GitHub hard-blocks any file over 100 MB, and Git LFS gives 1 GB free, which
/// a couple of engine builds exhaust. Chunking sidesteps both.
///
/// The entire risk is in the reassembly. Concatenating files is easy to get
/// almost right, and every way of getting it almost right produces a binary
/// rather than an error: a missing tail chunk gives a short library, a
/// mis-ordered chunk gives a scrambled one of exactly the right length. Both
/// fail later, somewhere that does not mention chunks. So every part carries a
/// hash, the whole artifact carries a hash, and both are checked.
library;

import 'dart:convert';
import 'dart:io';
// BytesBuilder directly, not through dart:io. Reaching it indirectly is
// deprecated, and CI analyses with --fatal-warnings.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 90 MB: comfortably under GitHub's 100 MB hard block, with room for the
/// repository's own overhead per object.
const int defaultChunkSize = 90 * 1024 * 1024;

/// Raised when an artifact cannot be reassembled exactly.
///
/// Never swallowed and never downgraded to a warning: the alternative to
/// failing here is linking a corrupt library.
class ArtifactException implements Exception {
  final String message;
  const ArtifactException(this.message);

  @override
  String toString() => 'ArtifactException: $message';
}

/// One chunk of a split artifact.
class ArtifactPart {
  /// File name, zero-padded so lexical order is part order.
  final String name;
  final int bytes;
  final String sha256;

  const ArtifactPart({
    required this.name,
    required this.bytes,
    required this.sha256,
  });

  Map<String, Object?> toMap() =>
      <String, Object?>{'name': name, 'bytes': bytes, 'sha256': sha256};

  static ArtifactPart fromMap(Map<String, Object?> map) => ArtifactPart(
        name: map['name']! as String,
        bytes: map['bytes']! as int,
        sha256: map['sha256']! as String,
      );
}

/// What is needed to rebuild one artifact, and to know the rebuild was exact.
class ArtifactManifest {
  /// The file name to restore, without any directory.
  final String name;
  final int totalBytes;

  /// Hash of the whole artifact, checked after joining.
  ///
  /// Not redundant with the per-part hashes: they prove each chunk is intact,
  /// this proves they are the chunks of *this* artifact. A stale manifest
  /// committed beside fresh chunks passes every part check.
  final String sha256;

  final List<ArtifactPart> parts;

  const ArtifactManifest({
    required this.name,
    required this.totalBytes,
    required this.sha256,
    required this.parts,
  });

  String toJson() => const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          'name': name,
          'totalBytes': totalBytes,
          'sha256': sha256,
          'parts': parts.map((ArtifactPart p) => p.toMap()).toList(),
        },
      );

  static ArtifactManifest fromJson(String json) {
    final map = jsonDecode(json) as Map<String, Object?>;
    return ArtifactManifest(
      name: map['name']! as String,
      totalBytes: map['totalBytes']! as int,
      sha256: map['sha256']! as String,
      parts: (map['parts']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(ArtifactPart.fromMap)
          .toList(growable: false),
    );
  }
}

/// Splits [source] into [into], returning the manifest that rebuilds it.
ArtifactManifest splitArtifact(
  File source, {
  required Directory into,
  int chunkSize = defaultChunkSize,
}) {
  if (chunkSize <= 0) {
    throw ArtifactException('chunk size must be positive, got $chunkSize');
  }
  if (!source.existsSync()) {
    throw ArtifactException('no such artifact: ${source.path}');
  }
  into.createSync(recursive: true);

  final bytes = source.readAsBytesSync();
  final baseName = source.uri.pathSegments.last;
  final parts = <ArtifactPart>[];

  // Zero-padded to a fixed width so lexical order is part order. Without this
  // an artifact of more than ten chunks reassembles scrambled — same length,
  // wrong contents, and nothing reports it.
  final count = (bytes.length / chunkSize).ceil().clamp(1, 1 << 30);
  final width = '$count'.length < 3 ? 3 : '$count'.length;

  for (var index = 0; index < count; index++) {
    final start = index * chunkSize;
    final end = (start + chunkSize).clamp(0, bytes.length);
    final chunk = bytes.sublist(start, end);
    final name = '$baseName.part${'$index'.padLeft(width, '0')}';
    File('${into.path}/$name').writeAsBytesSync(chunk);
    parts.add(ArtifactPart(
      name: name,
      bytes: chunk.length,
      sha256: sha256.convert(chunk).toString(),
    ));
  }

  return ArtifactManifest(
    name: baseName,
    totalBytes: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    parts: parts,
  );
}

/// Rebuilds the artifact [manifest] describes from [from] into [into].
///
/// Throws [ArtifactException] rather than writing anything questionable.
void joinArtifact(
  ArtifactManifest manifest, {
  required Directory from,
  required File into,
}) {
  final builder = BytesBuilder(copy: false);

  for (final part in manifest.parts) {
    final file = File('${from.path}/${part.name}');
    if (!file.existsSync()) {
      throw ArtifactException(
        'missing chunk ${part.name} of ${manifest.name}. Joining without it '
        'would produce a file ${part.bytes} bytes short, which is still a '
        'file and fails somewhere that does not mention chunks.',
      );
    }
    final chunk = file.readAsBytesSync();
    final actual = sha256.convert(chunk).toString();
    if (actual != part.sha256) {
      throw ArtifactException(
        'chunk ${part.name} of ${manifest.name} does not match the manifest '
        '(expected ${part.sha256}, got $actual). Its length may well be right; '
        'only the hash can tell.',
      );
    }
    builder.add(chunk);
  }

  final joined = builder.takeBytes();
  final actual = sha256.convert(joined).toString();
  if (actual != manifest.sha256) {
    throw ArtifactException(
      'rebuilt ${manifest.name} does not match the manifest (expected '
      '${manifest.sha256}, got $actual). Every chunk verified, so these are '
      'intact chunks of a different artifact — usually a manifest committed '
      'out of step with the chunks beside it.',
    );
  }
  if (joined.length != manifest.totalBytes) {
    throw ArtifactException(
      'rebuilt ${manifest.name} is ${joined.length} bytes, manifest says '
      '${manifest.totalBytes}',
    );
  }

  into.parent.createSync(recursive: true);
  into.writeAsBytesSync(joined);
}
