// `dartvel updates release/patch/rollback --patch-source`: Shorebird patches
// with no Shorebird account, published into a patch source the project hosts.
//
// Every build and the patch tool are faked, because what is under test is the
// part Dartvel owns: which files a release keeps, which of them a patch is
// diffed against, what is published where, and what a device then gets when
// it asks. The patch source is a real server, asked the updater's own
// questions over HTTP. The silent failures:
//
//  * a patch diffed against the wrong architecture's release still produces a
//    file, and bricks the device that boots it;
//  * a hash taken of the diff rather than of the patched library is published
//    and every device refuses the patch as corrupt;
//  * a patch built by a different engine than its release is published;
//  * a rollback that marks one architecture leaves the others running it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_cli/src/commands/updates_command.dart';
import 'package:dartvel_cli/src/updates/self_hosted_updates.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVShorebirdPatchSource, DVShorebirdPatchTarget;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A zip of [files], stored uncompressed: what an APK is, as far as reading
/// one goes.
Uint8List _zip(Map<String, List<int>> files) {
  final BytesBuilder out = BytesBuilder();
  final BytesBuilder central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add(<int>[v & 0xff, (v >> 8) & 0xff]);
  void u32(BytesBuilder b, int v) => b.add(<int>[
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ]);
  for (final MapEntry<String, List<int>> file in files.entries) {
    final int offset = out.length;
    final List<int> name = utf8.encode(file.key);
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0);
    u32(out, 0);
    u32(out, file.value.length);
    u32(out, file.value.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(file.value);

    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, file.value.length);
    u32(central, file.value.length);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(name);
  }
  final int centralOffset = out.length;
  final Uint8List directory = central.takeBytes();
  out.add(directory);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, files.length);
  u16(out, files.length);
  u32(out, directory.length);
  u32(out, centralOffset);
  u16(out, 0);
  return out.takeBytes();
}

const String _pubspec = '''
name: shop
version: 1.2.0+7
flutter:
  assets:
    - assets/
    - shorebird.yaml
''';

const String _manifest = 'android/app/src/main/AndroidManifest.xml';

const String _internetManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:label="shop"/>
</manifest>
''';

class _Fakes {
  _Fakes(this.root, this.home);

  final Directory root;
  final Directory home;

  /// What the next build compiles: the Dart a libapp.so is made from.
  String source = 'ONE';

  String engine = 'engine-rev-1';

  final List<List<String>> calls = <List<String>>[];

  String get flutterDir => p.join(
    home.path,
    '.dartvel',
    'toolchains',
    'shorebird_flutter',
    '3.44.5',
  );

  String get patchTool => p.join(
    home.path,
    '.dartvel',
    'toolchains',
    'shorebird_patch',
    engine,
    Platform.isWindows ? 'patch.exe' : 'patch',
  );

  void install() {
    File(p.join(flutterDir, 'bin', 'internal', 'engine.version'))
      ..createSync(recursive: true)
      ..writeAsStringSync('$engine\n');
    File(patchTool)
      ..createSync(recursive: true)
      ..writeAsStringSync('fake');
  }

  static List<int> libapp(String abi, String source) =>
      utf8.encode('libapp $abi $source');

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    if (executable == p.join(flutterDir, 'bin', 'flutter') &&
        arguments.take(2).join(' ') == 'build apk') {
      expect(
        environment?['FLUTTER_STORAGE_BASE_URL'],
        'https://download.shorebird.dev',
        reason: 'the engine has to be Shorebird\'s, or it has no updater',
      );
      final File apk = File(
        p.join(
          root.path,
          'build',
          'app',
          'outputs',
          'flutter-apk',
          'app-release.apk',
        ),
      )..createSync(recursive: true);
      apk.writeAsBytesSync(
        _zip(<String, List<int>>{
          'AndroidManifest.xml': <int>[0],
          for (final String abi in <String>['arm64-v8a', 'x86_64'])
            'lib/$abi/libapp.so': libapp(abi, source),
        }),
      );
      return ProcessResult(1, 0, 'built', '');
    }
    if (executable == patchTool) {
      final List<int> from = File(arguments[0]).readAsBytesSync();
      final List<int> to = File(arguments[1]).readAsBytesSync();
      File(arguments[2]).writeAsBytesSync(
        utf8.encode('diff ${utf8.decode(from)} -> ${utf8.decode(to)}'),
      );
      return ProcessResult(2, 0, '', '');
    }
    return ProcessResult(3, 127, '', 'unexpected: $executable $arguments');
  }
}

void main() {
  late Directory root;
  late Directory home;
  late Directory store;
  late _Fakes fakes;
  late HttpServer server;
  late CommandRunner<void> runner;
  late String sourceUrl;
  const String token = 'self-hosted-token-7d2a';

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dv_updates_project_');
    home = Directory.systemTemp.createTempSync('dv_updates_home_');
    store = Directory.systemTemp.createTempSync('dv_updates_store_');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(_pubspec);
    File(p.join(root.path, _manifest))
      ..createSync(recursive: true)
      ..writeAsStringSync(_internetManifest);
    File(p.join(root.path, 'shorebird.yaml')).writeAsStringSync(
      'app_id: shop-app\nbase_url: https://shop.example.test/updates\n'
      'auto_update: false\n',
    );
    fakes = _Fakes(root, home)..install();

    final DVShorebirdPatchSource source = DVShorebirdPatchSource(
      store.path,
      publishToken: token,
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sourceUrl = 'http://127.0.0.1:${server.port}/updates';
    server.listen((HttpRequest request) async {
      if (!await source.handle(request, prefix: '/updates')) {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });

    runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(
        UpdatesCommand(
          context: DVUpdatesContext(
            root: root.path,
            home: home.path,
            environment: <String, String>{'DARTVEL_UPDATES_TOKEN': token},
            run: fakes.run,
            flutterVersion: () async => '3.44.5',
          ),
        ),
      );
    exitCode = 0;
  });

  tearDown(() async {
    exitCode = 0;
    await server.close(force: true);
    for (final Directory d in <Directory>[root, home, store]) {
      d.deleteSync(recursive: true);
    }
  });

  Future<Map<String, Object?>> check(String arch, {int? current}) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.postUrl(
        Uri.parse('$sourceUrl/api/v1/patches/check'),
      );
      request.write(
        jsonEncode(<String, Object?>{
          'app_id': 'shop-app',
          'channel': 'stable',
          'release_version': '1.2.0+7',
          'platform': 'android',
          'arch': arch,
          'current_patch_number': ?current,
        }),
      );
      final HttpClientResponse response = await request.close();
      return jsonDecode(await utf8.decodeStream(response))
          as Map<String, Object?>;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> download(String url) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response = await (await client.getUrl(
        Uri.parse(url),
      )).close();
      expect(response.statusCode, 200);
      return await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    } finally {
      client.close(force: true);
    }
  }

  test(
    'a patch is diffed per architecture against the release it patches, '
    'published, and offered to a device with the patched library\'s hash',
    () async {
      await runner.run(<String>[
        'updates',
        'release',
        '--platform',
        'android',
        '--patch-source',
        sourceUrl,
      ]);
      expect(exitCode, 0);

      fakes.source = 'TWO';
      await runner.run(<String>[
        'updates',
        'patch',
        '--platform',
        'android',
        '--patch-source',
        sourceUrl,
      ]);
      expect(exitCode, 0);

      for (final (String abi, String arch) in <(String, String)>[
        ('arm64-v8a', 'aarch64'),
        ('x86_64', 'x86_64'),
      ]) {
        final Map<String, Object?> answer = await check(arch);
        expect(answer['patch_available'], isTrue, reason: arch);
        final Map<String, Object?> patch =
            answer['patch']! as Map<String, Object?>;
        expect(
          patch['hash'],
          sha256.convert(_Fakes.libapp(abi, 'TWO')).toString(),
          reason: 'the hash is of the patched library the device will boot',
        );
        expect(
          utf8.decode(await download(patch['download_url']! as String)),
          'diff libapp $abi ONE -> libapp $abi TWO',
          reason: 'the $arch patch is the diff from the $arch release',
        );
      }
    },
  );

  test('rollback over the patch source withdraws the patch on every '
      'architecture', () async {
    await runner.run(<String>[
      'updates',
      'release',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    fakes.source = 'TWO';
    await runner.run(<String>[
      'updates',
      'patch',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    await runner.run(<String>[
      'updates',
      'rollback',
      '--patch-source',
      sourceUrl,
      '--release-version',
      '1.2.0+7',
      '--patch-number',
      '1',
    ]);
    expect(exitCode, 0);
    for (final String arch in <String>['aarch64', 'x86_64']) {
      final Map<String, Object?> answer = await check(arch, current: 1);
      expect(answer['patch_available'], isFalse, reason: arch);
      expect(answer['rolled_back_patch_numbers'], <int>[1], reason: arch);
    }
  });

  test(
    'a patch source that is a directory is published into directly',
    () async {
      await runner.run(<String>[
        'updates',
        'release',
        '-p',
        'android',
        '--patch-source',
        store.path,
      ]);
      fakes.source = 'TWO';
      await runner.run(<String>[
        'updates',
        'patch',
        '-p',
        'android',
        '--patch-source',
        store.path,
      ]);
      expect(exitCode, 0);
      final List<int> diff = File(
        p.join(
          store.path,
          'shop-app',
          '1.2.0+7',
          'android',
          'x86_64',
          '1',
          'patch.bin',
        ),
      ).readAsBytesSync();
      expect(utf8.decode(diff), 'diff libapp x86_64 ONE -> libapp x86_64 TWO');
      expect(
        DVShorebirdPatchSource(store.path).patches(
          const DVShorebirdPatchTarget(
            appId: 'shop-app',
            releaseVersion: '1.2.0+7',
            platform: 'android',
            arch: 'aarch64',
          ),
        ),
        hasLength(1),
      );
    },
  );

  test('a patch for a release that was never made here is refused before '
      'anything is built', () async {
    await runner.run(<String>[
      'updates',
      'patch',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    expect(exitCode, isNot(0));
    expect(fakes.calls, isEmpty);
    expect((await check('x86_64'))['patch_available'], isFalse);
  });

  test('a patch built by another engine than its release is refused and '
      'nothing is published', () async {
    await runner.run(<String>[
      'updates',
      'release',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    fakes
      ..engine = 'engine-rev-2'
      ..install()
      ..source = 'TWO';
    await runner.run(<String>[
      'updates',
      'patch',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    expect(exitCode, isNot(0));
    expect((await check('x86_64'))['patch_available'], isFalse);
  });

  test('publishing to a URL without DARTVEL_UPDATES_TOKEN is refused before '
      'anything is built', () async {
    final CommandRunner<void> tokenless = CommandRunner<void>('dartvel', 'test')
      ..addCommand(
        UpdatesCommand(
          context: DVUpdatesContext(
            root: root.path,
            home: home.path,
            environment: const <String, String>{},
            run: fakes.run,
            flutterVersion: () async => '3.44.5',
          ),
        ),
      );
    await tokenless.run(<String>[
      'updates',
      'release',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    expect(exitCode, isNot(0));
    expect(fakes.calls, isEmpty);
  });

  test('a project whose shorebird.yaml names Shorebird\'s service is refused a '
      'self-hosted release', () async {
    File(
      p.join(root.path, 'shorebird.yaml'),
    ).writeAsStringSync('app_id: shop-app\n');
    await runner.run(<String>[
      'updates',
      'release',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    expect(exitCode, isNot(0));
    expect(fakes.calls, isEmpty);
  });

  test(
    'an iOS patch into a self-hosted source is refused, saying why',
    () async {
      await runner.run(<String>[
        'updates',
        'release',
        '-p',
        'ios',
        '--patch-source',
        sourceUrl,
      ]);
      expect(exitCode, isNot(0));
      expect(fakes.calls, isEmpty);
    },
  );

  // Both build and install cleanly and then never update: the updater reads
  // its base_url from the bundled shorebird.yaml, and a release manifest has
  // no INTERNET permission unless the project added one.
  test('a release that does not bundle shorebird.yaml is refused', () async {
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: shop\nversion: 1.2.0+7\n');
    await runner.run(<String>[
      'updates',
      'release',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    expect(exitCode, isNot(0));
    expect(fakes.calls, isEmpty);
  });

  test('an Android release whose main manifest cannot reach the network is '
      'refused', () async {
    File(p.join(root.path, _manifest)).writeAsStringSync(
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
      '<application/></manifest>',
    );
    await runner.run(<String>[
      'updates',
      'release',
      '-p',
      'android',
      '--patch-source',
      sourceUrl,
    ]);
    expect(exitCode, isNot(0));
    expect(fakes.calls, isEmpty);
  });
}
