// The npm manifests after a version bump.
//
// bump_version rewrote the first `"dartvel_dev": "..."` in each npm manifest,
// meaning dartvel_cli's pin on the launcher. In dartvel_dev's own manifest
// the first match is its bin entry, so 0.5.0 shipped with
// `"dartvel_dev": "0.5.0"` as a bin: `npx dartvel_dev` pointed at a file
// named 0.5.0.
import 'package:test/test.dart';

import '../../tool/bump_version.dart';

const String _launcher = '''
{
  "name": "dartvel_dev",
  "version": "0.5.0",
  "bin": {
    "dartvel": "bin/dartvel.js",
    "dartvel_dev": "bin/dartvel.js"
  }
}
''';

const String _alias = '''
{
  "name": "dartvel_cli",
  "version": "0.5.0",
  "bin": {
    "dartvel": "bin/dartvel.js"
  },
  "dependencies": {
    "dartvel_dev": "0.5.0"
  }
}
''';

void main() {
  test('a bin named dartvel_dev keeps its path', () {
    final String after =
        setNpmManifestVersions(_launcher, version: '0.6.0', launcher: '0.6.0');
    expect(after, contains('"version": "0.6.0"'));
    expect(after, contains('"dartvel_dev": "bin/dartvel.js"'));
  });

  test('the alias pins the launcher it depends on', () {
    final String after =
        setNpmManifestVersions(_alias, version: '0.6.0', launcher: '0.6.1');
    expect(after, contains('"version": "0.6.0"'));
    expect(after, contains('"dartvel_dev": "0.6.1"'));
    expect(after, contains('"dartvel": "bin/dartvel.js"'));
  });
}
