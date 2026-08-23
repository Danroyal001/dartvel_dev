// Large build artifacts — a Flutter engine, an embedder library — do not fit in
// a git repository. GitHub hard-blocks any file over 100 MB, and Git LFS has a
// 1 GB free quota that a couple of engine builds would exhaust.
//
// So they are split into chunks small enough to commit as ordinary files, and
// reassembled where they are used. The whole risk of that scheme is in the
// reassembly: concatenating chunks is trivially easy to get *almost* right, and
// a binary that is missing its last 90 MB is still a file, still executable in
// the sense that a loader will try, and fails somewhere far away from here.
//
// Every one of these tests exists for a way that could happen quietly.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_cli/src/utils/chunked_artifact.dart';
import 'package:test/test.dart';

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('dv_chunk_'));
  tearDown(() => work.deleteSync(recursive: true));

  /// Pseudo-random but deterministic, so a failure is reproducible.
  File sampleFile(String name, int bytes) {
    final random = Random(1234);
    final data = Uint8List.fromList(
        List<int>.generate(bytes, (_) => random.nextInt(256)));
    return File('${work.path}/$name')..writeAsBytesSync(data);
  }

  group('splitting', () {
    test('a file larger than the chunk size becomes several parts', () {
      final source = sampleFile('engine.so', 1000);
      final manifest = splitArtifact(source,
          into: Directory('${work.path}/out'), chunkSize: 300);

      expect(manifest.parts, hasLength(4)); // 300 + 300 + 300 + 100
      expect(manifest.totalBytes, 1000);
      for (final part in manifest.parts) {
        expect(File('${work.path}/out/${part.name}').existsSync(), isTrue);
      }
    });

    test('a file smaller than the chunk size still becomes one part', () {
      // Not a special case in the caller: the reassembly path must be the same
      // whether or not splitting was needed, or the small case is the one that
      // never gets exercised.
      final manifest = splitArtifact(sampleFile('small.bin', 10),
          into: Directory('${work.path}/out'), chunkSize: 300);
      expect(manifest.parts, hasLength(1));
    });

    test('parts are named so they sort in order', () {
      // Reassembly reads them in sorted order. With more than ten parts,
      // "part10" sorts before "part2" and the file is silently scrambled —
      // same length, wrong contents, no error anywhere.
      final manifest = splitArtifact(sampleFile('big.bin', 1100),
          into: Directory('${work.path}/out'), chunkSize: 100);
      expect(manifest.parts, hasLength(11));

      final names = manifest.parts.map((ArtifactPart p) => p.name).toList();
      final sorted = List<String>.from(names)..sort();
      expect(sorted, names,
          reason: 'lexical order must equal part order, or a >10-part artifact '
              'reassembles scrambled');
    });

    test('the default chunk size is under the GitHub file limit', () {
      // 100 MB is a hard block on push, not a warning.
      expect(defaultChunkSize, lessThan(100 * 1024 * 1024));
    });
  });

  group('reassembly', () {
    test('joining reproduces the original byte for byte', () {
      final source = sampleFile('engine.so', 5000);
      final original = source.readAsBytesSync();
      final manifest = splitArtifact(source,
          into: Directory('${work.path}/out'), chunkSize: 512);

      final rebuilt = File('${work.path}/rebuilt.so');
      joinArtifact(manifest,
          from: Directory('${work.path}/out'), into: rebuilt);

      expect(rebuilt.readAsBytesSync(), original);
    });

    test('a missing part fails loudly instead of truncating', () {
      final manifest = splitArtifact(sampleFile('engine.so', 5000),
          into: Directory('${work.path}/out'), chunkSize: 512);
      File('${work.path}/out/${manifest.parts.last.name}').deleteSync();

      expect(
        () => joinArtifact(manifest,
            from: Directory('${work.path}/out'),
            into: File('${work.path}/rebuilt.so')),
        throwsA(isA<ArtifactException>()),
        reason: 'a short binary is still a binary; the loader would report '
            'this somewhere unrecognisable',
      );
    });

    test('a corrupted part fails loudly instead of being linked', () {
      final manifest = splitArtifact(sampleFile('engine.so', 5000),
          into: Directory('${work.path}/out'), chunkSize: 512);
      final part = File('${work.path}/out/${manifest.parts.first.name}');
      final bytes = part.readAsBytesSync();
      bytes[0] = bytes[0] ^ 0xFF; // one flipped byte
      part.writeAsBytesSync(bytes);

      expect(
        () => joinArtifact(manifest,
            from: Directory('${work.path}/out'),
            into: File('${work.path}/rebuilt.so')),
        throwsA(isA<ArtifactException>()),
        reason: 'the part is the right length, so only its hash can catch this',
      );
    });

    test('the whole-file hash is checked, not only the parts', () {
      // Every part can be individually correct while the manifest describes a
      // different artifact — a stale manifest committed beside fresh chunks.
      final manifest = splitArtifact(sampleFile('engine.so', 2000),
          into: Directory('${work.path}/out'), chunkSize: 512);
      final wrong = ArtifactManifest(
        name: manifest.name,
        totalBytes: manifest.totalBytes,
        sha256: '0' * 64,
        parts: manifest.parts,
      );

      expect(
        () => joinArtifact(wrong,
            from: Directory('${work.path}/out'),
            into: File('${work.path}/rebuilt.so')),
        throwsA(isA<ArtifactException>()),
      );
    });
  });

  group('the manifest survives the round trip', () {
    test('it can be written and read back', () {
      final manifest = splitArtifact(sampleFile('engine.so', 3000),
          into: Directory('${work.path}/out'), chunkSize: 512);
      final file = File('${work.path}/out/manifest.json');
      file.writeAsStringSync(manifest.toJson());

      final restored = ArtifactManifest.fromJson(file.readAsStringSync());
      expect(restored.sha256, manifest.sha256);
      expect(restored.totalBytes, manifest.totalBytes);
      expect(restored.parts.map((ArtifactPart p) => p.name),
          manifest.parts.map((ArtifactPart p) => p.name));

      // And it must still reassemble, which is the only thing the manifest is
      // actually for.
      final rebuilt = File('${work.path}/rebuilt.so');
      joinArtifact(restored, from: Directory('${work.path}/out'), into: rebuilt);
      expect(rebuilt.lengthSync(), 3000);
    });
  });
}
