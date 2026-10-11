// The versioned symbols bundle: what a release build leaves behind that a
// crash from that release can be read with, and the manifest that says which
// files are which. Wrong in silence: a mapping from another release reads as
// a plausible stack, and a file name with a `..` in it writes outside the
// symbols directory of a server that accepted it.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVSymbolsManifest sample() => DVSymbolsManifest(
      release: '1.4.0+12',
      createdAt: DateTime.utc(2026, 10, 11, 12),
      files: const <DVSymbolFile>[
        DVSymbolFile(
          name: 'mapping.txt',
          kind: DVSymbolKind.r8Mapping,
          sha256: 'aa',
          bytes: 100,
        ),
        DVSymbolFile(
          name: 'app.android-arm64.symbols',
          kind: DVSymbolKind.dartSymbols,
          sha256: 'bb',
          bytes: 200,
          arch: 'arm64',
          buildId: '0123abcd',
        ),
        DVSymbolFile(
          name: 'native-debug-symbols.zip',
          kind: DVSymbolKind.nativeDebug,
          sha256: 'cc',
          bytes: 300,
        ),
      ],
    );

void main() {
  directoryTests();
  group('manifest', () {
    test('round-trips through JSON', () {
      final DVSymbolsManifest read = DVSymbolsManifest.fromJson(
          jsonDecode(jsonEncode(sample().toJson())) as Map<String, Object?>);
      expect(read.release, '1.4.0+12');
      expect(read.files, hasLength(3));
      expect(read.files[1].buildId, '0123abcd');
      expect(read.files[1].arch, 'arm64');
      expect(read.files[0].kind, DVSymbolKind.r8Mapping);
      expect(read.createdAt, DateTime.utc(2026, 10, 11, 12));
    });

    test('knows the file of a kind', () {
      expect(sample().firstOfKind(DVSymbolKind.r8Mapping)!.name, 'mapping.txt');
      expect(sample().ofKind(DVSymbolKind.dartSymbols), hasLength(1));
      expect(DVSymbolsManifest(release: 'r', createdAt: DateTime.utc(2026), files: const <DVSymbolFile>[])
          .firstOfKind(DVSymbolKind.r8Mapping), isNull);
    });

    test('a manifest in another format is refused, not guessed at', () {
      final Map<String, Object?> json = sample().toJson()..['v'] = 99;
      expect(() => DVSymbolsManifest.fromJson(json), throwsFormatException);
    });

    test('a file name that could leave the directory is refused on read', () {
      for (final String bad in <String>['../x', 'a/b', r'a\b', '', '.', '..', '.hidden']) {
        final Map<String, Object?> json = sample().toJson();
        (json['files']! as List<Object?>)[0] = <String, Object?>{
          'name': bad, 'kind': 'r8Mapping', 'sha256': 'aa', 'bytes': 1,
        };
        expect(() => DVSymbolsManifest.fromJson(json), throwsFormatException,
            reason: bad);
      }
    });
  });

  group('names', () {
    test('a file name is one plain path segment', () {
      expect(dvSymbolFileNameOk('mapping.txt'), isTrue);
      expect(dvSymbolFileNameOk('app.android-arm64.symbols'), isTrue);
      expect(dvSymbolFileNameOk('native-debug-symbols.zip'), isTrue);
      for (final String bad in <String>[
        '', '.', '..', '../mapping.txt', 'a/b', r'a\b', '.env', 'a b', 'x' * 201, 'a\u0000b',
      ]) {
        expect(dvSymbolFileNameOk(bad), isFalse, reason: bad);
      }
    });

    test('a release is a version string, not a path', () {
      expect(dvSymbolReleaseOk('1.4.0+12'), isTrue);
      expect(dvSymbolReleaseOk('unversioned'), isTrue);
      expect(dvSymbolReleaseOk('2026.10.1-beta.2'), isTrue);
      for (final String bad in <String>['', '..', 'a/b', r'a\b', '.x', 'x' * 129]) {
        expect(dvSymbolReleaseOk(bad), isFalse, reason: bad);
      }
    });
  });

  group('repository', () {
    test('keeps files per release, and releases apart', () async {
      final DVMemorySymbolRepository repo = DVMemorySymbolRepository();
      await repo.putFile('1.0.0', 'mapping.txt', utf8.encode('one'));
      await repo.putFile('2.0.0', 'mapping.txt', utf8.encode('two'));
      expect(utf8.decode((await repo.readFile('1.0.0', 'mapping.txt'))!), 'one');
      expect(utf8.decode((await repo.readFile('2.0.0', 'mapping.txt'))!), 'two');
      expect(await repo.readFile('3.0.0', 'mapping.txt'), isNull);
    });

    test('a manifest is found by release', () async {
      final DVMemorySymbolRepository repo = DVMemorySymbolRepository();
      expect(await repo.manifest('1.4.0+12'), isNull);
      await repo.putManifest(sample());
      expect((await repo.manifest('1.4.0+12'))!.files, hasLength(3));
      expect(await repo.hasRelease('1.4.0+12'), isTrue);
      expect(await repo.hasRelease('9.9.9'), isFalse);
    });
  });
}

void directoryTests() {
  group('the server symbols directory', () {
    String dir({Map<String, String> env = const <String, String>{}, String cwd = '/srv/app'}) =>
        dvServerSymbolsDirectoryFor(
            appId: 'shop', environment: env, currentDirectory: cwd, tempDirectory: '/tmp');

    test('is the declared one when the deployment mounts one', () {
      expect(dir(env: <String, String>{'DARTVEL_SYMBOLS_DIR': '/data/symbols'}),
          '/data/symbols');
    });

    test('is beside the application otherwise', () {
      expect(dir(), '/srv/app/.dartvel/symbols');
      expect(dir(cwd: '/srv/app/'), '/srv/app/.dartvel/symbols');
    });

    test('is never the root of the machine', () {
      expect(dir(cwd: '/'), '/tmp/dartvel-symbols/shop');
      expect(dir(cwd: ''), '/tmp/dartvel-symbols/shop');
    });
  });
}
