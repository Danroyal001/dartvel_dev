// `dartvel update` — replacing the running binary with the published one.
//
// The dangerous parts are not the download. They are: picking the wrong asset
// for the host, which installs a binary that cannot run; skipping the checksum,
// which installs whatever answered the request; and replacing the executable
// badly, which leaves the user with no working CLI and no way to reinstall one.
//
// So the decisions are pure functions with their own tests, and only the file
// moving touches disk.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/update/self_update.dart';
import 'package:test/test.dart';

const String _manifest = '''
{
  "version": "0.4.0",
  "assets": {
    "dartvel-linux-amd64": {
      "url": "https://example.test/dartvel-linux-amd64",
      "sha256": "aaaa"
    },
    "dartvel-linux-arm64": {
      "url": "https://example.test/dartvel-linux-arm64",
      "sha256": "bbbb"
    },
    "dartvel-darwin-arm64": {
      "url": "https://example.test/dartvel-darwin-arm64",
      "sha256": "cccc"
    },
    "dartvel-windows-amd64.exe": {
      "url": "https://example.test/dartvel-windows-amd64.exe",
      "sha256": "dddd"
    }
  }
}
''';

void main() {
  group('choosing the asset', () {
    test('linux x64', () {
      expect(dvAssetName(os: 'linux', arch: 'x64'), 'dartvel-linux-amd64');
    });

    test('the arm names differ per vendor, and both map to arm64', () {
      // uname says aarch64, Dart says arm64, the release says arm64. Getting
      // this wrong downloads an x86 binary onto an ARM machine, which installs
      // cleanly and then cannot exec.
      expect(dvAssetName(os: 'linux', arch: 'aarch64'), 'dartvel-linux-arm64');
      expect(dvAssetName(os: 'linux', arch: 'arm64'), 'dartvel-linux-arm64');
    });

    test('macOS is darwin in the asset name', () {
      expect(dvAssetName(os: 'macos', arch: 'arm64'), 'dartvel-darwin-arm64');
      expect(dvAssetName(os: 'darwin', arch: 'x64'), 'dartvel-darwin-amd64');
    });

    test('windows keeps its extension', () {
      // Without .exe the downloaded file is not executable on Windows and the
      // failure appears later, as "not recognized as a command".
      expect(
        dvAssetName(os: 'windows', arch: 'x64'),
        'dartvel-windows-amd64.exe',
      );
    });

    test('an unsupported host is named, not guessed at', () {
      expect(() => dvAssetName(os: 'plan9', arch: 'x64'), throwsArgumentError);
      expect(
        () => dvAssetName(os: 'linux', arch: 'riscv64'),
        throwsArgumentError,
      );
    });
  });

  group('reading the manifest', () {
    test('it finds the entry for this host', () {
      final DVUpdateTarget target = dvUpdateTargetFrom(
        jsonDecode(_manifest) as Map<String, Object?>,
        assetName: 'dartvel-linux-amd64',
      );

      expect(target.version, '0.4.0');
      expect(target.url, 'https://example.test/dartvel-linux-amd64');
      expect(target.sha256, 'aaaa');
    });

    test('a manifest without this host says so', () {
      // Better than downloading nothing and reporting success.
      expect(
        () => dvUpdateTargetFrom(
          jsonDecode(_manifest) as Map<String, Object?>,
          assetName: 'dartvel-linux-riscv64',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a manifest with no checksum is refused', () {
      // Installing an unverified binary over the running one is the one thing
      // this must never do.
      const String noSum =
          '{"version":"0.4.0","assets":{"dartvel-linux-amd64":'
          '{"url":"https://example.test/x"}}}';

      expect(
        () => dvUpdateTargetFrom(
          jsonDecode(noSum) as Map<String, Object?>,
          assetName: 'dartvel-linux-amd64',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('deciding whether to update', () {
    test('a newer published version is an update', () {
      expect(dvIsNewer(published: '0.4.0', running: '0.3.0'), isTrue);
    });

    test('the same version is not', () {
      expect(dvIsNewer(published: '0.3.0', running: '0.3.0'), isFalse);
    });

    test('an older published version is not, so a rollback is deliberate', () {
      expect(dvIsNewer(published: '0.2.9', running: '0.3.0'), isFalse);
    });

    test('versions compare numerically, not as strings', () {
      // '0.10.0' < '0.9.0' as a string, which would strand everyone on 0.9
      // exactly when the tenth release shipped.
      expect(dvIsNewer(published: '0.10.0', running: '0.9.0'), isTrue);
      expect(dvIsNewer(published: '1.0.0', running: '0.99.0'), isTrue);
    });

    test('a v prefix on either side is tolerated', () {
      expect(dvIsNewer(published: 'v0.4.0', running: '0.3.0'), isTrue);
    });

    test('a prerelease is not newer than its own release', () {
      expect(dvIsNewer(published: '0.4.0-beta.1', running: '0.4.0'), isFalse);
    });

    test('an unparseable version is not an update', () {
      // Refusing is right: replacing a working binary on the strength of a
      // version string nobody can read is worse than staying put.
      expect(dvIsNewer(published: 'nightly', running: '0.3.0'), isFalse);
    });
  });

  group('verifying what was downloaded', () {
    test('the right bytes pass', () {
      final List<int> bytes = utf8.encode('dartvel');
      expect(dvVerifyDownload(bytes, dvSha256Hex(bytes)), isTrue);
    });

    test('the wrong bytes fail', () {
      expect(dvVerifyDownload(utf8.encode('dartvel'), 'deadbeef'), isFalse);
    });

    test('case does not decide it', () {
      final List<int> bytes = utf8.encode('dartvel');
      expect(
        dvVerifyDownload(bytes, dvSha256Hex(bytes).toUpperCase()),
        isTrue,
      );
    });

    test('an empty download never passes', () {
      // A truncated or refused request that still wrote a file.
      expect(dvVerifyDownload(const <int>[], dvSha256Hex(const <int>[])),
          isFalse);
    });
  });

  group('replacing the binary', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('dv_update_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('the new binary lands and is executable', () async {
      final File current = File('${dir.path}/dartvel')
        ..writeAsStringSync('old');

      await dvReplaceExecutable(
        current: current,
        bytes: utf8.encode('new'),
      );

      expect(current.readAsStringSync(), 'new');
      if (!Platform.isWindows) {
        final int mode = current.statSync().mode;
        expect(mode & 0x40, isNot(0), reason: 'owner execute bit');
      }
    });

    test('the old binary is kept until the new one is in place', () async {
      // Writing over the running executable directly can leave nothing at all
      // if the write fails halfway. The old one is moved aside first so there
      // is always something to fall back to.
      final File current = File('${dir.path}/dartvel')
        ..writeAsStringSync('old');

      await dvReplaceExecutable(
        current: current,
        bytes: utf8.encode('new'),
      );

      expect(File('${current.path}.old').existsSync(), isTrue);
      expect(File('${current.path}.old').readAsStringSync(), 'old');
    });

    test('a second update replaces the backup rather than failing', () async {
      final File current = File('${dir.path}/dartvel')
        ..writeAsStringSync('one');
      await dvReplaceExecutable(current: current, bytes: utf8.encode('two'));
      await dvReplaceExecutable(current: current, bytes: utf8.encode('three'));

      expect(current.readAsStringSync(), 'three');
      expect(File('${current.path}.old').readAsStringSync(), 'two');
    });
  });
}
