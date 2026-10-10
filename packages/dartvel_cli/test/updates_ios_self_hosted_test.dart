// `dartvel updates release/patch --platform ios --patch-source`: iOS patches
// the way Shorebird makes them, into a patch source the project hosts.
//
// An iOS patch is not a diff of two builds. Apple's licence lets an app
// download interpreted code only (Apple Developer Program License Agreement
// 3.3.1(B)), so Shorebird's engine runs a patch's changed functions in an
// interpreter and everything unchanged from the release's AOT snapshot. The
// shorebird CLI's iOS patcher (packages/shorebird_cli/lib/src/commands/patch/
// ios_patcher.dart) gets there in four steps, which this follows:
//
//  1. compile the patch's app.dill to an ELF AOT snapshot with the iOS
//     gen_snapshot, `out.aot`;
//  2. `aot_tools link` it against the release's App.framework/App, with the
//     link supplement files of both builds beside them, into `out.vmcode` --
//     the file the device boots, so its SHA-256 is the patch hash;
//  3. `aot_tools dump_blobs` the release snapshot into a stable diff base;
//  4. diff the base against `out.vmcode` with Shorebird's patch tool.
//
// Every tool is faked here; what is under test is which files go where. The
// failures this guards are silent: a patch linked against the build it was
// just made from instead of the release links "100%" and crashes on boot; a
// hash of the diff instead of the vmcode is refused by every device; a
// release's supplement files left behind make the linker fall back and run
// the whole app interpreted, a hundred times slower.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_cli/src/commands/updates_command.dart';
import 'package:dartvel_cli/src/updates/self_hosted_updates.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _pubspec = '''
name: shop
version: 1.2.0+7
flutter:
  assets:
    - shorebird.yaml
''';

class _IosFakes {
  _IosFakes(this.root, this.home);

  final Directory root;
  final Directory home;

  String source = 'ONE';
  String engine = 'engine-rev-1';
  bool linkFails = false;
  final List<List<String>> calls = <List<String>>[];
  final List<Map<String, String>?> buildEnvironments = <Map<String, String>?>[];

  String get flutterDir => p.join(
    home.path,
    '.dartvel',
    'toolchains',
    'shorebird_flutter',
    '3.44.5',
  );
  String get iosRelease =>
      p.join(flutterDir, 'bin', 'cache', 'artifacts', 'engine', 'ios-release');
  String get genSnapshot => p.join(iosRelease, 'gen_snapshot_arm64');
  String get analyzeSnapshot => p.join(iosRelease, 'analyze_snapshot_arm64');
  String get dart =>
      p.join(flutterDir, 'bin', 'cache', 'dart-sdk', 'bin', 'dart');
  String get aotTools => p.join(
    home.path,
    '.dartvel',
    'toolchains',
    'shorebird_aot_tools',
    engine,
    'aot-tools.dill',
  );
  String get patchTool => p.join(
    home.path,
    '.dartvel',
    'toolchains',
    'shorebird_patch',
    engine,
    'patch',
  );

  void install() {
    File(p.join(flutterDir, 'bin', 'internal', 'engine.version'))
      ..createSync(recursive: true)
      ..writeAsStringSync('$engine\n');
    for (final String tool in <String>[
      genSnapshot,
      analyzeSnapshot,
      dart,
      aotTools,
      patchTool,
    ]) {
      File(tool)
        ..createSync(recursive: true)
        ..writeAsStringSync('fake');
    }
  }

  String flag(List<String> args, String name) => args
      .firstWhere((String a) => a.startsWith('--$name='))
      .substring(name.length + 3);

  String read(String path) => File(path).readAsStringSync();

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    if (executable == p.join(flutterDir, 'bin', 'flutter') &&
        arguments.take(2).join(' ') == 'build ipa') {
      buildEnvironments.add(environment);
      expect(
        environment?['FLUTTER_STORAGE_BASE_URL'],
        'https://download.shorebird.dev',
      );
      File(
          p.join(
            root.path,
            'build/ios/archive/Runner.xcarchive/Products/Applications/'
            'Runner.app/Frameworks/App.framework/App',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('App $source');
      File(p.join(root.path, 'build/ios/shorebird/App.ct.link'))
        ..createSync(recursive: true)
        ..writeAsStringSync('ct $source');
      File(p.join(root.path, '.dart_tool/flutter_build/abc123/app.dill'))
        ..createSync(recursive: true)
        ..writeAsStringSync('dill $source');
      return ProcessResult(1, 0, 'built', '');
    }
    if (executable == genSnapshot) {
      expect(
        arguments,
        containsAll(<String>['--deterministic', '--snapshot-kind=app-aot-elf']),
      );
      File(flag(arguments, 'elf'))
          .writeAsStringSync('aot of ${read(arguments.last)}');
      return ProcessResult(2, 0, '', '');
    }
    if (executable == dart && arguments.length >= 2 && arguments[0] == 'run') {
      expect(arguments[1], aotTools);
      final List<String> tool = arguments.sublist(2);
      if (tool.first == '--version') return ProcessResult(3, 0, '0.0.2\n', '');
      if (tool.first == '--help') {
        return ProcessResult(3, 0, 'Commands: link dump_blobs', '');
      }
      if (tool.first == 'link') {
        final String base = flag(tool, 'base');
        final String patch = flag(tool, 'patch');
        expect(flag(tool, 'analyze-snapshot'), analyzeSnapshot);
        expect(flag(tool, 'gen-snapshot'), genSnapshot);
        expect(read(flag(tool, 'kernel')), 'dill $source');
        final String jsonl = flag(tool, 'redirect-to');
        if (linkFails) {
          File(jsonl).writeAsStringSync(
            '${jsonEncode(<String, Object?>{'type': 'link_failure', 'reason': 'snapshot versions differ'})}\n',
          );
          return ProcessResult(3, 1, '', 'link failed');
        }
        File(flag(tool, 'output')).writeAsStringSync(
          'vmcode [${read(base)} | ${read(p.join(p.dirname(base), 'App.ct.link'))}]'
          ' + [${read(patch)} | ${read(p.join(p.dirname(patch), 'out.ct.link'))}]',
        );
        File(jsonl).writeAsStringSync(
          '${jsonEncode(<String, Object?>{'type': 'link_success', 'link_percentage': 99.4})}\n',
        );
        return ProcessResult(3, 0, '', '');
      }
      if (tool.first == 'dump_blobs') {
        expect(flag(tool, 'analyze-snapshot'), analyzeSnapshot);
        File(flag(tool, 'output'))
            .writeAsStringSync('blobs of ${read(flag(tool, 'snapshot'))}');
        return ProcessResult(3, 0, '', '');
      }
    }
    if (executable == patchTool) {
      File(arguments[2]).writeAsStringSync(
        'diff ${read(arguments[0])} -> ${read(arguments[1])}',
      );
      return ProcessResult(4, 0, '', '');
    }
    return ProcessResult(9, 127, '', 'unexpected: $executable $arguments');
  }
}

void main() {
  late Directory root;
  late Directory home;
  late Directory store;
  late _IosFakes fakes;
  late HttpServer server;
  late DVShorebirdPatchSource source;
  late String sourceUrl;
  const String token = 'ios-token-7d2a';

  CommandRunner<void> runnerOn(String hostOs) =>
      CommandRunner<void>('dartvel', 'test')..addCommand(
        UpdatesCommand(
          context: DVUpdatesContext(
            root: root.path,
            home: home.path,
            environment: <String, String>{'DARTVEL_UPDATES_TOKEN': token},
            run: fakes.run,
            flutterVersion: () async => '3.44.5',
            hostOs: hostOs,
          ),
        ),
      );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dv_ios_updates_project_');
    home = Directory.systemTemp.createTempSync('dv_ios_updates_home_');
    store = Directory.systemTemp.createTempSync('dv_ios_updates_store_');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(_pubspec);
    File(p.join(root.path, 'shorebird.yaml')).writeAsStringSync(
      'app_id: shop-app\nbase_url: https://shop.example.test/updates\n',
    );
    fakes = _IosFakes(root, home)..install();
    source = DVShorebirdPatchSource(store.path, publishToken: token);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sourceUrl = 'http://127.0.0.1:${server.port}/updates';
    server.listen((HttpRequest request) async {
      if (!await source.handle(request, prefix: '/updates')) {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
    exitCode = 0;
  });

  tearDown(() async {
    exitCode = 0;
    await server.close(force: true);
    for (final Directory d in <Directory>[root, home, store]) {
      d.deleteSync(recursive: true);
    }
  });

  Map<String, Object?> check({int? current}) => source.check(<String, Object?>{
    'app_id': 'shop-app',
    'channel': 'stable',
    'release_version': '1.2.0+7',
    'platform': 'ios',
    'arch': 'aarch64',
    'client_id': 'device-1',
    'current_patch_number': ?current,
  }, downloadBase: Uri.parse(sourceUrl));

  List<int> downloaded(int number) => File(
    p.join(
      store.path,
      'shop-app',
      '1.2.0+7',
      'ios',
      'aarch64',
      '$number',
      'patch.bin',
    ),
  ).readAsBytesSync();

  Future<void> run(CommandRunner<void> runner, List<String> args) async {
    exitCode = 0;
    await runner.run(<String>['updates', ...args]);
  }

  test(
    'iOS releases and patches are refused off macOS before anything runs',
    () async {
      final CommandRunner<void> linux = runnerOn('linux');
      await run(linux, <String>[
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

  test('a release keeps the App snapshot and its link supplements, and a '
      'patch is linked against them, diffed from the dumped base and '
      'published with the hash of what the device boots', () async {
    final CommandRunner<void> mac = runnerOn('macos');
    await run(mac, <String>[
      'release',
      '-p',
      'ios',
      '--patch-source',
      sourceUrl,
    ]);
    expect(exitCode, 0);
    final String kept = p.join(
      root.path,
      '.dartvel',
      'updates',
      'releases',
      'shop-app',
      '1.2.0+7',
      'ios',
      'aarch64',
    );
    expect(File(p.join(kept, 'App')).readAsStringSync(), 'App ONE');
    expect(
      File(p.join(kept, 'supplement', 'App.ct.link')).readAsStringSync(),
      'ct ONE',
    );

    fakes.source = 'TWO';
    await run(mac, <String>['patch', '-p', 'ios', '--patch-source', sourceUrl]);
    expect(exitCode, 0);

    const String vmcode =
        'vmcode [App ONE | ct ONE] + [aot of dill TWO | ct TWO]';
    final Map<String, Object?> answer = check();
    expect(answer['patch_available'], isTrue);
    final Map<String, Object?> patch = answer['patch']! as Map<String, Object?>;
    expect(
      patch['hash'],
      sha256.convert(utf8.encode(vmcode)).toString(),
      reason: 'the updater hashes the linked vmcode it boots',
    );
    expect(utf8.decode(downloaded(1)), 'diff blobs of App ONE -> $vmcode');
  });

  test('a failed link publishes nothing and says why', () async {
    final CommandRunner<void> mac = runnerOn('macos');
    await run(mac, <String>[
      'release',
      '-p',
      'ios',
      '--patch-source',
      sourceUrl,
    ]);
    fakes
      ..source = 'TWO'
      ..linkFails = true;
    await run(mac, <String>['patch', '-p', 'ios', '--patch-source', sourceUrl]);
    expect(exitCode, isNot(0));
    expect(check()['patch_available'], isFalse);
  });

  group('signed', () {
    final bool haveOpenssl =
        Process.runSync('openssl', <String>['version']).exitCode == 0;
    late String keys;

    setUp(() {
      if (!haveOpenssl) return;
      keys = p.join(root.path, 'keys');
      Directory(keys).createSync();
      for (final String name in <String>['private', 'other']) {
        Process.runSync('openssl', <String>[
          'genrsa', '-out', p.join(keys, '$name.pem'), '2048', //
        ]);
      }
      Process.runSync('openssl', <String>[
        'rsa', '-in', p.join(keys, 'private.pem'), '-pubout', //
        '-out', p.join(keys, 'public.pem'),
      ]);
    });

    test(
      'a release built with a public key carries it, registers it with '
      'the patch source, and takes only patches signed by its private key',
      () async {
        final CommandRunner<void> mac = runnerOn('macos');
        final String releaseKey = DVPatchSigning.releasePublicKey(
          File(p.join(keys, 'public.pem')).readAsStringSync(),
        );
        await run(mac, <String>[
          'release', '-p', 'ios', '--patch-source', sourceUrl, //
          '--public-key', p.join(keys, 'public.pem'),
        ]);
        expect(exitCode, 0);
        expect(
          fakes.buildEnvironments.single?['SHOREBIRD_PUBLIC_KEY'],
          releaseKey,
          reason: 'Shorebird\'s Flutter embeds it as patch_public_key',
        );
        expect(
          source
              .releaseRecord(
                appId: 'shop-app',
                releaseVersion: '1.2.0+7',
                platform: 'ios',
              )
              ?.patchPublicKey,
          releaseKey,
        );

        fakes.source = 'TWO';
        fakes.calls.clear();
        await run(mac, <String>[
          'patch',
          '-p',
          'ios',
          '--patch-source',
          sourceUrl,
        ]);
        expect(
          exitCode,
          isNot(0),
          reason: 'no private key for a signed release',
        );
        expect(fakes.calls, isEmpty, reason: 'refused before building');

        await run(mac, <String>[
          'patch', '-p', 'ios', '--patch-source', sourceUrl, //
          '--private-key', p.join(keys, 'other.pem'),
        ]);
        expect(exitCode, isNot(0), reason: 'not the release\'s key pair');
        expect(fakes.calls, isEmpty);

        await run(mac, <String>[
          'patch', '-p', 'ios', '--patch-source', sourceUrl, //
          '--private-key', p.join(keys, 'private.pem'),
        ]);
        expect(exitCode, 0);
        final Map<String, Object?> patch =
            check()['patch']! as Map<String, Object?>;
        expect(
          DVPatchSigning.verifyHash(
            patch['hash']! as String,
            patch['hash_signature']! as String,
            releaseKey,
          ),
          isTrue,
        );
      },
      skip: haveOpenssl ? false : 'openssl is not installed',
    );
  });

  test(
    'a patch is published at a rollout, which the rollout command raises',
    () async {
      final CommandRunner<void> mac = runnerOn('macos');
      await run(mac, <String>[
        'release',
        '-p',
        'ios',
        '--patch-source',
        sourceUrl,
      ]);
      fakes.source = 'TWO';
      await run(mac, <String>[
        'patch', '-p', 'ios', '--patch-source', sourceUrl, '--rollout', '0', //
      ]);
      expect(exitCode, 0);
      expect(check()['patch_available'], isFalse);
      await run(mac, <String>[
        'rollout', '--platform', 'ios', '--patch-source', sourceUrl, //
        '--release-version',
        '1.2.0+7',
        '--patch-number',
        '1',
        '--percent',
        '100',
      ]);
      expect(exitCode, 0);
      expect(check()['patch_available'], isTrue);
    },
  );
}
