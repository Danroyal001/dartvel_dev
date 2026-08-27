// The npm package and the release it fetches from.
//
// The launcher builds its download URL from its own package version, so npm
// 0.2.2 asks for release v0.2.2. Bumping the npm package for an npm-only fix
// -- which is exactly what happened -- pointed it at a release that did not
// exist, and `npx dartvel_dev` answered with a 404 for every user.
//
// The coupling is fine. Nothing checking it was not.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String repoRoot() {
  var dir = Directory.current;
  while (!File(p.join(dir.path, 'npm', 'dartvel_dev', 'package.json'))
      .existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not find the repository root');
    }
    dir = parent;
  }
  return dir.path;
}

void main() {
  group('the npm package and the CLI it launches', () {
    late Map<String, Object?> npm;
    late String cliVersion;

    setUpAll(() {
      final root = repoRoot();
      npm = jsonDecode(File(p.join(root, 'npm', 'dartvel_dev', 'package.json'))
          .readAsStringSync()) as Map<String, Object?>;
      cliVersion = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(
              File(p.join(root, 'packages', 'dartvel_cli', 'pubspec.yaml'))
                  .readAsStringSync())!
          .group(1)!;
    });

    test('the npm version is one the CLI has released', () {
      // Not "equal to": an npm-only fix legitimately moves ahead. What it
      // must not do is move ahead without a release being cut, because the
      // launcher fetches the release named by its own version.
      final npmVersion = npm['version']! as String;
      final npmParts = npmVersion.split('.').map(int.parse).toList();
      final cliParts = cliVersion.split('.').map(int.parse).toList();

      expect(npmParts[0], cliParts[0],
          reason: 'npm $npmVersion and CLI $cliVersion differ in major');
      expect(npmParts[1], cliParts[1],
          reason: 'npm $npmVersion and CLI $cliVersion differ in minor');
    });

    test('the launcher builds its URL from its own version', () {
      // The property that makes the check above matter. If this stops being
      // true the test above is testing nothing.
      final source =
          File(p.join(repoRoot(), 'npm', 'dartvel_dev', 'index.js'))
              .readAsStringSync();

      expect(source, contains("require('./package.json').version"));
      expect(source, contains(r'releases/download/v${VERSION}'));
    });

    test('the binary name matches what the release workflow uploads', () {
      // Two files name these assets: the launcher constructs them and the
      // workflow produces them. A rename in one is a 404 from the other.
      final source =
          File(p.join(repoRoot(), 'npm', 'dartvel_dev', 'index.js'))
              .readAsStringSync();
      final workflow =
          File(p.join(repoRoot(), '.github', 'workflows', 'cli-release.yml'))
              .readAsStringSync();

      for (final String asset in <String>[
        'dartvel-linux-amd64',
        'dartvel-linux-arm64',
        'dartvel-darwin-amd64',
        'dartvel-darwin-arm64',
        'dartvel-windows-amd64.exe',
      ]) {
        expect(workflow, contains(asset),
            reason: '$asset is not built by the release workflow');
      }
      expect(source, contains('dartvel-'));
      expect(source, contains('.exe'));
    });
  });
}
