// The vscode build refuses artifacts older than the build that should have
// produced them — a good rule, implemented with a comparison that cannot
// survive filesystem timestamp granularity.
//
// `buildStartedAt` is DateTime.now(), which carries microseconds. A file's
// mtime does not: depending on the filesystem it is truncated to the second,
// or coarser. So a file genuinely written *after* the build started can carry
// an mtime that rounds down below it, and a real artifact gets reported as
// missing.
//
// It fires or not depending on where in the second the build begins, which is
// why it surfaced as an order-dependent test failure after an unrelated
// timing change rather than as an obvious bug.
import 'dart:io';

import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_fresh_');
    Directory('${root.path}/out').createSync(recursive: true);
    Directory('${root.path}/build/web/assets').createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  void writeArtifacts({required DateTime mtime}) {
    final files = <File>[
      File('${root.path}/out/extension.js')..writeAsStringSync('//'),
      File('${root.path}/build/web/flutter_bootstrap.js')..writeAsStringSync('//'),
      File('${root.path}/build/web/assets/AssetManifest.json')..writeAsStringSync('{}'),
    ];
    for (final file in files) {
      file.setLastModifiedSync(mtime);
    }
  }

  group('artifact freshness', () {
    test('accepts artifacts written after the build started', () {
      final since = DateTime.now();
      writeArtifacts(mtime: since.add(const Duration(seconds: 1)));

      final artifacts = validateVSCodeArtifacts(root.path, since: since);
      expect(artifacts.missing, isEmpty);
    });

    test('accepts an artifact whose mtime was truncated to the second', () {
      // The actual failure. The build starts partway through a second, the
      // artifact is written a moment later, and the filesystem records the
      // second it landed in — which is numerically before the build start.
      final since = DateTime(2026, 8, 23, 12, 0, 0, 750);
      final truncated = DateTime(2026, 8, 23, 12, 0, 0, 0);
      writeArtifacts(mtime: truncated);

      final artifacts = validateVSCodeArtifacts(root.path, since: since);
      expect(
        artifacts.missing,
        isEmpty,
        reason: 'an artifact written in the same second the build started is '
            'not stale; the clock is finer than the filesystem',
      );
    });

    test('still rejects an artifact left over from a previous build', () {
      // The rule this exists to enforce must survive the fix: something from
      // minutes ago is genuinely stale and must not be accepted.
      final since = DateTime.now();
      writeArtifacts(mtime: since.subtract(const Duration(minutes: 5)));

      final artifacts = validateVSCodeArtifacts(root.path, since: since);
      expect(artifacts.missing, isNotEmpty,
          reason: 'a stale artifact must still be reported');
    });
  });
}
