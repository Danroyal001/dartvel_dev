/// Shorebird releases and patches with no Shorebird account.
///
/// `dartvel updates release|patch|rollback --patch-source <url|dir>` does what
/// the shorebird CLI does against its hosted service, against a patch source
/// the project hosts instead -- the web-server binary, which serves one when
/// shorebird.yaml's base_url names it, or a directory one is served from:
///
///  * release: build with Shorebird's Flutter at the project's Flutter
///    version, whose engine carries the updater, and keep each
///    architecture's compiled Dart (`libapp.so`) under
///    `.dartvel/updates/releases`, with the engine revision it was built by;
///  * patch: build again, diff each architecture's `libapp.so` against the
///    release's with Shorebird's patch tool for that engine, and publish the
///    diff with the SHA-256 of the patched library, which is what the updater
///    checks before it boots a patch;
///  * rollback: mark a patch rolled back on every architecture.
///
/// On iOS a patch is not a diff of two builds. Apple's Developer Program
/// License Agreement 3.3.1(B) lets an app download interpreted code only, so
/// Shorebird's engine runs a patch's changed functions in an interpreter and
/// every unchanged one from the release's AOT snapshot
/// (docs.shorebird.dev/code-push/system-architecture). Making one follows the
/// shorebird CLI's iOS patcher (`commands/patch/ios_patcher.dart` in
/// shorebirdtech/shorebird):
///
///  * release: `flutter build ipa` with Shorebird's Flutter, keeping the
///    archive's `App.framework/App` and the link supplement files Shorebird's
///    Flutter writes to `build/ios/shorebird`;
///  * patch: build again, compile the new `app.dill` with the iOS
///    gen_snapshot, `aot_tools link` it against the release's snapshot into
///    `out.vmcode` (what the device boots, so its SHA-256 is the patch hash),
///    `aot_tools dump_blobs` the release snapshot into a diff base, and diff
///    that against `out.vmcode` with the patch tool.
///
/// iOS releases and patches run on macOS, where Xcode, the iOS gen_snapshot
/// and analyze_snapshot are.
///
/// Signing: `release --public-key public.pem` builds the key into the release
/// (`SHOREBIRD_PUBLIC_KEY`, which Shorebird's Flutter writes into the bundled
/// shorebird.yaml as `patch_public_key`) and registers it with the patch
/// source; `patch --private-key private.pem` signs each patch's hash, checks
/// the signature against the release's key, and publishes it with the patch.
/// A signed release's devices refuse every patch whose signature does not
/// verify, and so does the patch source.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart'
    show
        DVPatchSigning,
        DVPatchSigningException,
        DVShorebirdPatch,
        DVShorebirdPatchSource,
        DVShorebirdPatchTarget;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/toolchain.dart'
    show
        dartvelToolchainRoot,
        decideAutoInstall,
        isCiEnvironment,
        AutoInstallDecision;
import 'shorebird_config.dart';
import 'zip_entries.dart';

/// Runs a process: [Process.run] outside tests.
typedef DVUpdatesRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// Where Shorebird's engine artifacts are fetched from. The updater is in
/// them; Google's are the same engine without it.
const String dvShorebirdStorageBaseUrl = 'https://download.shorebird.dev';

/// Android ABIs as the APK names them, and as the updater reports them.
const Map<String, String> dvAndroidAbiArch = <String, String>{
  'arm64-v8a': 'aarch64',
  'armeabi-v7a': 'arm',
  'x86_64': 'x86_64',
};

/// A self-hosted update that could not be made, and why. Nothing was
/// published when one is thrown.
class DVSelfHostedUpdateError implements Exception {
  const DVSelfHostedUpdateError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the commands need from the world, so a test can fake the builds.
class DVUpdatesContext {
  DVUpdatesContext({
    String? root,
    String? home,
    Map<String, String>? environment,
    DVUpdatesRun? run,
    Future<String> Function()? flutterVersion,
    this.log = _stdoutLog,
    this.confirmInstall,
    String? hostOs,
  }) : root = root ?? Directory.current.path,
       hostOs = hostOs ?? Platform.operatingSystem,
       home =
           home ??
           Platform.environment['HOME'] ??
           Platform.environment['USERPROFILE'] ??
           '.',
       environment = environment ?? Platform.environment,
       run = run ?? _processRun,
       flutterVersion = flutterVersion ?? _projectFlutterVersion;

  final String root;
  final String home;
  final Map<String, String> environment;
  final DVUpdatesRun run;
  final Future<String> Function() flutterVersion;
  final void Function(String line) log;

  /// The operating system the build runs on, as [Platform.operatingSystem]
  /// names it.
  final String hostOs;

  /// Asks before installing a toolchain; null asks on stdin.
  final bool Function(String what)? confirmInstall;

  static void _stdoutLog(String line) => stdout.writeln(line);

  static Future<ProcessResult> _processRun(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: Platform.isWindows,
  );

  static Future<String> _projectFlutterVersion() async {
    final ProcessResult result = await Process.run('flutter', const <String>[
      '--version',
      '--machine',
    ], runInShell: true);
    if (result.exitCode != 0) {
      throw const DVSelfHostedUpdateError(
        'flutter --version failed, so the Flutter version Shorebird\'s engine '
        'must match is unknown. Is Flutter on PATH?',
      );
    }
    final String out = '${result.stdout}';
    final Object? decoded = jsonDecode(out.substring(out.indexOf('{')));
    final Object? version = decoded is Map ? decoded['frameworkVersion'] : null;
    if (version is! String) {
      throw const DVSelfHostedUpdateError(
        'flutter --version --machine reported no frameworkVersion.',
      );
    }
    return version;
  }
}

/// A patch source given on the command line: a URL the web-server binary
/// answers at, or a directory.
class DVPatchSourceLocation {
  DVPatchSourceLocation.parse(String value) : raw = value.trim() {
    final Uri? uri = Uri.tryParse(raw);
    url = uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
        ? uri
        : null;
  }

  final String raw;
  late final Uri? url;

  bool get isUrl => url != null;
}

class DVSelfHostedUpdates {
  DVSelfHostedUpdates(this.context, {this.autoInstall});

  final DVUpdatesContext context;

  /// `--auto-install` / `--no-auto-install`, or null.
  final bool? autoInstall;

  String get _root => context.root;

  DVShorebirdConfig _config() {
    final DVShorebirdConfig? config;
    try {
      config = DVShorebirdConfig.read(_root);
    } on FormatException catch (error) {
      throw DVSelfHostedUpdateError(error.message);
    }
    if (config == null) {
      throw const DVSelfHostedUpdateError(
        'There is no shorebird.yaml. A self-hosted release needs one naming '
        'app_id and a base_url on the server the patch source runs on, e.g.\n'
        '  app_id: my-app\n  base_url: https://example.com/updates\n'
        'and listed under flutter: assets: in pubspec.yaml.',
      );
    }
    if (!config.selfHosted) {
      throw const DVSelfHostedUpdateError(
        'shorebird.yaml has no base_url, or names Shorebird\'s hosted '
        'service, so a device built from it would never ask the patch source '
        'this publishes to. Set base_url to where the patch source is served.',
      );
    }
    return config;
  }

  /// The version the updater reports: versionName+versionCode, from the
  /// pubspec, with Flutter's default versionCode of 1.
  String releaseVersion() {
    final File pubspec = File(p.join(_root, 'pubspec.yaml'));
    final Object? doc = pubspec.existsSync()
        ? loadYaml(pubspec.readAsStringSync())
        : null;
    final Object? version = doc is Map ? doc['version'] : null;
    if (version is! String || version.trim().isEmpty) {
      throw const DVSelfHostedUpdateError(
        'pubspec.yaml has no version, and a release is identified by it.',
      );
    }
    final String v = version.trim();
    return v.contains('+') ? v : '$v+1';
  }

  void _checkPlatform(String platform) {
    if (platform == 'android') return;
    if (platform != 'ios') {
      throw DVSelfHostedUpdateError(
        'A self-hosted patch source takes android and ios patches, not '
        '$platform.',
      );
    }
    if (context.hostOs != 'macos') {
      throw DVSelfHostedUpdateError(
        'iOS releases and patches build with Xcode and link with the iOS '
        'gen_snapshot and analyze_snapshot, which run on macOS only, and '
        'this is ${context.hostOs}. Run it on a Mac, or with '
        '`dartvel build ios --cloud` on a Cloud macOS worker.',
      );
    }
  }

  /// Refuses a release that would build, install and never update: one that
  /// does not bundle shorebird.yaml, where the updater reads base_url, or,
  /// on Android, whose main manifest has no INTERNET permission, which
  /// Flutter's template grants only to debug and profile builds.
  void _checkReachesPatchSource(String platform) {
    final Object? doc = loadYaml(
      File(p.join(_root, 'pubspec.yaml')).readAsStringSync(),
    );
    final Object? flutter = doc is Map ? doc['flutter'] : null;
    final Object? assets = flutter is Map ? flutter['assets'] : null;
    final bool bundled =
        assets is List &&
        assets.any(
          (Object? a) =>
              a == 'shorebird.yaml' ||
              (a is Map && a['path'] == 'shorebird.yaml'),
        );
    if (!bundled) {
      throw const DVSelfHostedUpdateError(
        'pubspec.yaml does not list shorebird.yaml under flutter: assets:, '
        'so the release would not carry the base_url its updater asks. Add '
        '`- shorebird.yaml` there.',
      );
    }
    if (platform != 'android') return;
    final File manifest = File(
      p.join(_root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (!manifest.existsSync() ||
        !manifest.readAsStringSync().contains('android.permission.INTERNET')) {
      throw const DVSelfHostedUpdateError(
        'android/app/src/main/AndroidManifest.xml does not request '
        'android.permission.INTERNET. Flutter grants it to debug and profile '
        'builds only, so a release could never reach its patch source. Add '
        '<uses-permission android:name="android.permission.INTERNET"/>.',
      );
    }
  }

  /// iOS build arguments a self-hosted patch cannot be made from yet.
  void _checkIosArguments(List<String> buildArguments) {
    if (buildArguments.any((String a) => a == '--obfuscate')) {
      throw const DVSelfHostedUpdateError(
        '--obfuscate is not supported for self-hosted iOS patches: the patch '
        'snapshot would have to be compiled with the release\'s obfuscation '
        'map, which is not built here. Release and patch without it.',
      );
    }
  }

  String? _token(DVPatchSourceLocation source) {
    if (!source.isUrl) return null;
    final String? token = context.environment['DARTVEL_UPDATES_TOKEN'];
    if (token == null || token.isEmpty) {
      throw DVSelfHostedUpdateError(
        'Publishing to ${source.raw} needs DARTVEL_UPDATES_TOKEN: the token '
        'the server was started with.',
      );
    }
    return token;
  }

  String _readKeyFile(String path, String what) {
    final File file = File(p.isAbsolute(path) ? path : p.join(_root, path));
    if (!file.existsSync()) {
      throw DVSelfHostedUpdateError('There is no $what at ${file.path}.');
    }
    return file.readAsStringSync();
  }

  /// The release key for the PEM public key at [path].
  String _releaseKeyFrom(String path) {
    try {
      return DVPatchSigning.releasePublicKey(_readKeyFile(path, 'public key'));
    } on DVPatchSigningException catch (error) {
      throw DVSelfHostedUpdateError('$path: ${error.message}');
    }
  }

  String _releaseDir(String appId, String release, String platform) => p.join(
    _root,
    '.dartvel',
    'updates',
    'releases',
    appId,
    release,
    platform,
  );

  /// Builds a release with Shorebird's engine and keeps what patches are
  /// made against. Returns the architectures kept.
  ///
  /// With [publicKeyPath], the release carries that key and its devices
  /// boot only patches signed by its private key.
  Future<List<String>> release({
    required String platform,
    required DVPatchSourceLocation source,
    List<String> buildArguments = const <String>[],
    String? publicKeyPath,
  }) async {
    _checkPlatform(platform);
    final String? token = _token(source);
    final DVShorebirdConfig config = _config();
    _checkReachesPatchSource(platform);
    if (platform == 'ios') _checkIosArguments(buildArguments);
    final String? releaseKey = publicKeyPath == null
        ? null
        : _releaseKeyFrom(publicKeyPath);
    final String version = releaseVersion();
    final _Toolchain toolchain = await _toolchain();
    final Map<String, String> signing = <String, String>{
      'SHOREBIRD_PUBLIC_KEY': ?releaseKey,
    };

    final Directory dir = Directory(
      _releaseDir(config.appId, version, platform),
    );
    final List<String> architectures;
    if (platform == 'ios') {
      final _IosBuild build = await _buildIos(
        toolchain,
        buildArguments,
        signing,
      );
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      final String arch = p.join(dir.path, 'aarch64');
      File(p.join(arch, 'App'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(build.appSnapshot.readAsBytesSync());
      final Directory supplement = Directory(p.join(arch, 'supplement'))
        ..createSync(recursive: true);
      for (final File file in build.supplements) {
        file.copySync(p.join(supplement.path, p.basename(file.path)));
      }
      architectures = const <String>['aarch64'];
    } else {
      final Map<String, List<int>> libraries = await _buildAndroid(
        toolchain,
        buildArguments,
        signing,
      );
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      for (final MapEntry<String, List<int>> library in libraries.entries) {
        File(p.join(dir.path, library.key, 'libapp.so'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(library.value);
      }
      architectures = libraries.keys.toList();
    }
    File(p.join(dir.path, 'release.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'app_id': config.appId,
        'release_version': version,
        'platform': platform,
        'engine': toolchain.engine,
        'flutter': toolchain.flutterVersion,
        'architectures': architectures,
        'patch_public_key': ?releaseKey,
        'build_arguments': buildArguments,
      }),
    );
    await _registerRelease(
      source,
      token,
      config.appId,
      version,
      platform,
      releaseKey,
    );
    context.log(
      'Release ${config.appId} $version ($platform: '
      '${architectures.join(', ')}) built with Shorebird\'s engine '
      '${toolchain.engine}${releaseKey == null ? '' : ', signed'}. '
      '${platform == 'ios' ? 'Upload the archive in build/ios/archive (or the IPA in build/ios/ipa) to App Store Connect, and leave "Manage Version and Build Number" unchecked so the version stays $version' : 'Distribute the APK in build/app/outputs'}; '
      'what patches are made against is kept in '
      '${p.relative(dir.path, from: _root)}.',
    );
    return architectures;
  }

  Future<void> _registerRelease(
    DVPatchSourceLocation source,
    String? token,
    String appId,
    String version,
    String platform,
    String? releaseKey,
  ) async {
    if (!source.isUrl) {
      DVShorebirdPatchSource(source.raw).registerRelease(
        appId: appId,
        releaseVersion: version,
        platform: platform,
        patchPublicKey: releaseKey,
      );
      return;
    }
    final ({int status, String body}) answer = await _post(
      _endpoint(source.url!, '_dartvel/release'),
      token!,
      utf8.encode(
        jsonEncode(<String, Object?>{
          'app_id': appId,
          'release_version': version,
          'platform': platform,
          'patch_public_key': ?releaseKey,
        }),
      ),
      contentType: 'application/json',
    );
    if (answer.status == 404) {
      context.log(
        'The patch source at ${source.raw} does not register releases (it '
        'predates release signing). Patches are still checked against the '
        'release here before they are published.',
      );
      return;
    }
    if (answer.status != 201) {
      throw DVSelfHostedUpdateError(
        'The patch source refused the release (HTTP ${answer.status}): '
        '${answer.body}',
      );
    }
  }

  /// Builds the patched app, makes it into a patch against
  /// [releaseVersion]'s release and publishes one per architecture.
  Future<List<DVShorebirdPatch>> patch({
    required String platform,
    required DVPatchSourceLocation source,
    String? releaseVersion,
    String channel = 'stable',
    List<String> buildArguments = const <String>[],
    String? privateKeyPath,
    int rolloutPercent = 100,
  }) async {
    _checkPlatform(platform);
    final String? token = _token(source);
    final DVShorebirdConfig config = _config();
    if (rolloutPercent < 0 || rolloutPercent > 100) {
      throw const DVSelfHostedUpdateError('--rollout is 0 to 100.');
    }
    if (platform == 'ios') _checkIosArguments(buildArguments);
    final String version = releaseVersion ?? this.releaseVersion();
    final Directory dir = Directory(
      _releaseDir(config.appId, version, platform),
    );
    final File record = File(p.join(dir.path, 'release.json'));
    if (!record.existsSync()) {
      throw DVSelfHostedUpdateError(
        'There is no release ${config.appId} $version for $platform here: a '
        'patch is made against the release\'s compiled Dart, which '
        '`dartvel updates release --patch-source` keeps in '
        '${p.relative(dir.path, from: _root)}. Patch the version you released, '
        'with --release-version.',
      );
    }
    final Map<String, Object?> released = (jsonDecode(
      record.readAsStringSync(),
    ) as Map<Object?, Object?>).cast<String, Object?>();

    // Signing is settled before anything is built: a signed release's
    // devices refuse an unsigned patch, and one signed by another key.
    final String? releaseKey = released['patch_public_key'] as String?;
    String? privateKey;
    if (releaseKey != null) {
      if (privateKeyPath == null) {
        throw DVSelfHostedUpdateError(
          'Release $version was built with a signing key, so its devices '
          'refuse unsigned patches. Pass --private-key with the private key '
          'of the public key the release was made with.',
        );
      }
      privateKey = _readKeyFile(privateKeyPath, 'private key');
      final String pair;
      try {
        pair = DVPatchSigning.releasePublicKeyOf(privateKey);
      } on DVPatchSigningException catch (error) {
        throw DVSelfHostedUpdateError('$privateKeyPath: ${error.message}');
      }
      if (pair != releaseKey) {
        throw DVSelfHostedUpdateError(
          '$privateKeyPath is not the private key of the public key release '
          '$version was built with, so every device would refuse the patch. '
          'Nothing was built.',
        );
      }
    } else if (privateKeyPath != null) {
      throw DVSelfHostedUpdateError(
        'Release $version was built without a signing key, so its devices '
        'do not verify signatures. Make a signed release with '
        '`dartvel updates release --public-key` to sign its patches.',
      );
    }

    final _Toolchain toolchain = await _toolchain();
    if (released['engine'] != toolchain.engine) {
      throw DVSelfHostedUpdateError(
        'Release $version was built by Shorebird\'s engine '
        '${released['engine']}, and this Flutter is on ${toolchain.engine}. '
        'A patch made across engines does not boot, so nothing was '
        'published. Patch with the Flutter version the release was built '
        'with (${released['flutter']}).',
      );
    }
    final String tool = await _patchTool(toolchain.engine);
    final Map<String, String> signing = <String, String>{
      'SHOREBIRD_PUBLIC_KEY': ?releaseKey,
    };

    final List<({DVShorebirdPatchTarget target, List<int> diff, String hash})>
    diffs = platform == 'ios'
        ? <({DVShorebirdPatchTarget target, List<int> diff, String hash})>[
            await _patchIos(
              toolchain,
              tool,
              dir,
              buildArguments,
              signing,
              DVShorebirdPatchTarget(
                appId: config.appId,
                releaseVersion: version,
                platform: platform,
                arch: 'aarch64',
              ),
            ),
          ]
        : await _patchAndroid(
            toolchain,
            tool,
            dir,
            buildArguments,
            signing,
            config.appId,
            version,
            platform,
          );

    final List<DVShorebirdPatch> published = <DVShorebirdPatch>[];
    for (final d in diffs) {
      String? signature;
      if (privateKey != null) {
        signature = DVPatchSigning.signHash(d.hash, privateKey);
        if (!DVPatchSigning.verifyHash(d.hash, signature, releaseKey!)) {
          throw const DVSelfHostedUpdateError(
            'The patch signature did not verify against the release key.',
          );
        }
      }
      final DVShorebirdPatch patch = source.isUrl
          ? await _publishOverHttp(
              source.url!,
              token!,
              d.target,
              d.diff,
              d.hash,
              channel,
              signature,
              rolloutPercent,
            )
          : _publishToDirectory(
              source.raw,
              d,
              channel,
              signature,
              rolloutPercent,
            );
      published.add(patch);
      context.log(
        'Published patch ${patch.number} for ${config.appId} $version '
        '$platform ${d.target.arch} (${d.diff.length} bytes'
        '${signature == null ? '' : ', signed'}'
        '${rolloutPercent == 100 ? '' : ', to $rolloutPercent% of devices'}) '
        'to ${source.raw}.',
      );
    }
    return published;
  }

  DVShorebirdPatch _publishToDirectory(
    String root,
    ({DVShorebirdPatchTarget target, List<int> diff, String hash}) d,
    String channel,
    String? signature,
    int rolloutPercent,
  ) {
    try {
      return DVShorebirdPatchSource(root).publish(
        d.target,
        diff: d.diff,
        patchedHash: d.hash,
        channel: channel,
        hashSignature: signature,
        rolloutPercent: rolloutPercent,
      );
    } on FormatException catch (error) {
      throw DVSelfHostedUpdateError(error.message);
    }
  }

  Future<List<({DVShorebirdPatchTarget target, List<int> diff, String hash})>>
  _patchAndroid(
    _Toolchain toolchain,
    String tool,
    Directory dir,
    List<String> buildArguments,
    Map<String, String> signing,
    String appId,
    String version,
    String platform,
  ) async {
    final Map<String, List<int>> libraries = await _buildAndroid(
      toolchain,
      buildArguments,
      signing,
    );
    final Directory work = Directory.systemTemp.createTempSync('dv_patch_');
    final List<({DVShorebirdPatchTarget target, List<int> diff, String hash})>
    diffs = <({DVShorebirdPatchTarget target, List<int> diff, String hash})>[];
    try {
      for (final MapEntry<String, List<int>> library in libraries.entries) {
        final File base = File(p.join(dir.path, library.key, 'libapp.so'));
        if (!base.existsSync()) {
          throw DVSelfHostedUpdateError(
            'The patch build has ${library.key} and release $version did not; '
            'build the patch for the architectures the release has.',
          );
        }
        final File patched = File(p.join(work.path, '${library.key}.so'))
          ..writeAsBytesSync(library.value);
        final File out = File(p.join(work.path, '${library.key}.patch'));
        final ProcessResult diffed = await context.run(tool, <String>[
          base.path,
          patched.path,
          out.path,
        ]);
        if (diffed.exitCode != 0 || !out.existsSync()) {
          throw DVSelfHostedUpdateError(
            'Shorebird\'s patch tool failed for ${library.key} '
            '(exit ${diffed.exitCode}): ${diffed.stderr}',
          );
        }
        diffs.add((
          target: DVShorebirdPatchTarget(
            appId: appId,
            releaseVersion: version,
            platform: platform,
            arch: library.key,
          ),
          diff: out.readAsBytesSync(),
          hash: sha256.convert(library.value).toString(),
        ));
      }
    } finally {
      work.deleteSync(recursive: true);
    }
    return diffs;
  }

  /// Sets patch [number] of [releaseVersion] to reach [percent] of devices,
  /// on every architecture.
  Future<List<String>> rollout({
    required String platform,
    required DVPatchSourceLocation source,
    required String releaseVersion,
    required int number,
    required int percent,
  }) async {
    if (percent < 0 || percent > 100) {
      throw const DVSelfHostedUpdateError('--percent is 0 to 100.');
    }
    final String? token = _token(source);
    final DVShorebirdConfig config = _config();
    final List<String> changed;
    if (source.isUrl) {
      final ({int status, String body}) answer = await _post(
        _endpoint(source.url!, '_dartvel/rollout'),
        token!,
        utf8.encode(
          jsonEncode(<String, Object?>{
            'app_id': config.appId,
            'release_version': releaseVersion,
            'platform': platform,
            'number': number,
            'percent': percent,
          }),
        ),
        contentType: 'application/json',
      );
      if (answer.status != 200) {
        throw DVSelfHostedUpdateError(
          'The patch source refused the rollout (HTTP ${answer.status}): '
          '${answer.body}',
        );
      }
      changed = ((jsonDecode(answer.body) as Map)['architectures'] as List)
          .cast<String>();
    } else {
      try {
        changed = DVShorebirdPatchSource(source.raw).rolloutRelease(
          appId: config.appId,
          releaseVersion: releaseVersion,
          platform: platform,
          number: number,
          percent: percent,
        );
      } on StateError catch (error) {
        throw DVSelfHostedUpdateError(error.message);
      }
    }
    context.log(
      'Patch $number of ${config.appId} $releaseVersion on $platform '
      '(${changed.join(', ')}) now reaches $percent% of devices.',
    );
    return changed;
  }

  /// Rolls patch [number] of [releaseVersion] back on every architecture.
  Future<List<String>> rollback({
    required String platform,
    required DVPatchSourceLocation source,
    required String releaseVersion,
    required int number,
  }) async {
    // A rollback builds nothing, so any host can make one.
    if (platform != 'android' && platform != 'ios') {
      throw DVSelfHostedUpdateError(
        'There are no $platform patches to roll back.',
      );
    }
    final String? token = _token(source);
    final DVShorebirdConfig config = _config();
    final List<String> rolled;
    if (source.isUrl) {
      final ({int status, String body}) answer = await _post(
        _endpoint(source.url!, '_dartvel/rollback'),
        token!,
        utf8.encode(
          jsonEncode(<String, Object?>{
            'app_id': config.appId,
            'release_version': releaseVersion,
            'platform': platform,
            'number': number,
          }),
        ),
        contentType: 'application/json',
      );
      if (answer.status != 200) {
        throw DVSelfHostedUpdateError(
          'The patch source refused the rollback (HTTP ${answer.status}): '
          '${answer.body}',
        );
      }
      rolled = ((jsonDecode(answer.body) as Map)['architectures'] as List)
          .cast<String>();
    } else {
      try {
        rolled = DVShorebirdPatchSource(source.raw).rollBackRelease(
          appId: config.appId,
          releaseVersion: releaseVersion,
          platform: platform,
          number: number,
        );
      } on StateError catch (error) {
        throw DVSelfHostedUpdateError(error.message);
      }
    }
    context.log(
      'Rolled back patch $number of ${config.appId} $releaseVersion on '
      '$platform (${rolled.join(', ')}). Devices running it drop it at their '
      'next check.',
    );
    return rolled;
  }

  Uri _endpoint(Uri base, String path) {
    final String prefix = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$prefix/$path');
  }

  Future<DVShorebirdPatch> _publishOverHttp(
    Uri base,
    String token,
    DVShorebirdPatchTarget target,
    List<int> diff,
    String hash,
    String channel,
    String? signature,
    int rolloutPercent,
  ) async {
    final Uri endpoint = _endpoint(base, '_dartvel/publish').replace(
      queryParameters: <String, String>{
        'app_id': target.appId,
        'release_version': target.releaseVersion,
        'platform': target.platform,
        'arch': target.arch,
        'hash': hash,
        'channel': channel,
        'hash_signature': ?signature,
        'rollout': '$rolloutPercent',
      },
    );
    final ({int status, String body}) answer = await _post(
      endpoint,
      token,
      diff,
      contentType: 'application/octet-stream',
    );
    if (answer.status != 201) {
      throw DVSelfHostedUpdateError(
        'The patch source at $base refused the ${target.arch} patch '
        '(HTTP ${answer.status}): ${answer.body}',
      );
    }
    return DVShorebirdPatch.fromJson(
      (jsonDecode(answer.body) as Map<Object?, Object?>)
          .cast<String, Object?>(),
    );
  }

  Future<({int status, String body})> _post(
    Uri url,
    String token,
    List<int> body, {
    required String contentType,
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.postUrl(url);
      request.headers
        ..set('authorization', 'Bearer $token')
        ..set('content-type', contentType);
      request.contentLength = body.length;
      request.add(body);
      final HttpClientResponse response = await request.close();
      return (
        status: response.statusCode,
        body: await utf8.decodeStream(response),
      );
    } on IOException catch (error) {
      throw DVSelfHostedUpdateError('Could not reach $url: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, List<int>>> _buildAndroid(
    _Toolchain toolchain,
    List<String> buildArguments,
    Map<String, String> signing,
  ) async {
    final ProcessResult built = await context.run(
      toolchain.flutter,
      <String>['build', 'apk', '--release', ...buildArguments],
      workingDirectory: _root,
      environment: <String, String>{
        ...context.environment,
        'FLUTTER_STORAGE_BASE_URL': dvShorebirdStorageBaseUrl,
        ...signing,
      },
    );
    if (built.exitCode != 0) {
      throw DVSelfHostedUpdateError(
        'The release build with Shorebird\'s Flutter failed '
        '(exit ${built.exitCode}):\n${built.stdout}\n${built.stderr}',
      );
    }
    final Directory outputs = Directory(
      p.join(_root, 'build', 'app', 'outputs', 'flutter-apk'),
    );
    final List<File> apks = outputs.existsSync()
        ? outputs
              .listSync()
              .whereType<File>()
              .where((File f) => f.path.endsWith('-release.apk'))
              .toList()
        : <File>[];
    if (apks.isEmpty) {
      throw DVSelfHostedUpdateError(
        'The build wrote no release APK in ${outputs.path}.',
      );
    }
    apks.sort(
      (File a, File b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    final Map<String, List<int>> libraries = <String, List<int>>{};
    final RegExp entry = RegExp(r'^lib/([^/]+)/libapp\.so$');
    for (final MapEntry<String, Uint8List> file in dvReadZipEntries(
      apks.first.path,
      (String name) => entry.hasMatch(name),
    ).entries) {
      final String abi = entry.firstMatch(file.key)!.group(1)!;
      final String? arch = dvAndroidAbiArch[abi];
      if (arch != null) libraries[arch] = file.value;
    }
    if (libraries.isEmpty) {
      throw DVSelfHostedUpdateError(
        '${apks.first.path} carries no libapp.so, so there is no compiled '
        'Dart to release or patch.',
      );
    }
    return Map<String, List<int>>.fromEntries(
      libraries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// `flutter build ipa --release` with Shorebird's Flutter, and what an iOS
  /// patch is made from: the archive's App snapshot, the link supplement
  /// files, and the kernel the build compiled.
  Future<_IosBuild> _buildIos(
    _Toolchain toolchain,
    List<String> buildArguments,
    Map<String, String> signing,
  ) async {
    // Stale supplement files from an earlier build would be linked against
    // as if they were this build's.
    final Directory supplementDir = Directory(
      p.join(_root, 'build', 'ios', 'shorebird'),
    );
    if (supplementDir.existsSync()) supplementDir.deleteSync(recursive: true);
    final DateTime started = DateTime.now();
    final ProcessResult built = await context.run(
      toolchain.flutter,
      <String>['build', 'ipa', '--release', ...buildArguments],
      workingDirectory: _root,
      environment: <String, String>{
        ...context.environment,
        'FLUTTER_STORAGE_BASE_URL': dvShorebirdStorageBaseUrl,
        ...signing,
      },
    );
    if (built.exitCode != 0) {
      throw DVSelfHostedUpdateError(
        'The iOS build with Shorebird\'s Flutter failed '
        '(exit ${built.exitCode}):\n${built.stdout}\n${built.stderr}',
      );
    }
    final Directory archives = Directory(
      p.join(_root, 'build', 'ios', 'archive'),
    );
    final List<Directory> xcarchives = archives.existsSync()
        ? archives
              .listSync()
              .whereType<Directory>()
              .where((Directory d) => d.path.endsWith('.xcarchive'))
              .toList()
        : <Directory>[];
    if (xcarchives.isEmpty) {
      throw DVSelfHostedUpdateError(
        'The build left no .xcarchive in ${archives.path}, which is where '
        '`flutter build ipa` writes the archive the release is made of.',
      );
    }
    final Directory applications = Directory(
      p.join(xcarchives.first.path, 'Products', 'Applications'),
    );
    final List<Directory> apps = applications.existsSync()
        ? applications
              .listSync()
              .whereType<Directory>()
              .where((Directory d) => d.path.endsWith('.app'))
              .toList()
        : <Directory>[];
    final File? snapshot = apps.isEmpty
        ? null
        : File(p.join(apps.first.path, 'Frameworks', 'App.framework', 'App'));
    if (snapshot == null || !snapshot.existsSync()) {
      throw DVSelfHostedUpdateError(
        '${xcarchives.first.path} has no Products/Applications/*.app/'
        'Frameworks/App.framework/App, the compiled Dart a patch is linked '
        'against.',
      );
    }
    final List<File> supplements = supplementDir.existsSync()
        ? supplementDir.listSync().whereType<File>().toList()
        : <File>[];
    if (supplements.isEmpty) {
      throw DVSelfHostedUpdateError(
        'Shorebird\'s Flutter wrote no link supplement files to '
        '${supplementDir.path}, so a patch could not be linked against this '
        'build and every patched function would run in the interpreter. Is '
        '${toolchain.flutter} Shorebird\'s Flutter?',
      );
    }
    final Directory flutterBuild = Directory(
      p.join(_root, '.dart_tool', 'flutter_build'),
    );
    final List<File> kernels =
        flutterBuild.existsSync()
              ? flutterBuild
                    .listSync(recursive: true)
                    .whereType<File>()
                    .where((File f) => p.basename(f.path) == 'app.dill')
                    .toList()
              : <File>[]
          ..sort(
            (File a, File b) =>
                b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    final File? kernel =
        kernels.isNotEmpty &&
            !kernels.first.lastModifiedSync().isBefore(
              started.subtract(const Duration(seconds: 2)),
            )
        ? kernels.first
        : null;
    return _IosBuild(
      appSnapshot: snapshot,
      supplements: supplements,
      kernel: kernel,
    );
  }

  /// The gen_snapshot flags `--split-debug-info` turns on, which the patch
  /// snapshot needs too: a release and patch built with different flags do
  /// not link.
  List<String> _debugInfoArguments(List<String> buildArguments, String work) {
    for (int i = 0; i < buildArguments.length; i++) {
      final String argument = buildArguments[i];
      final bool split =
          argument.startsWith('--split-debug-info=') ||
          (argument == '--split-debug-info' && i + 1 < buildArguments.length);
      if (split) {
        return <String>[
          '--dwarf-stack-traces',
          '--resolve-dwarf-paths',
          '--save-debugging-info=${p.join(work, 'app.ios-arm64.symbols')}',
        ];
      }
    }
    return const <String>[];
  }

  /// Builds the patched app and makes the iOS patch against the release kept
  /// in [dir].
  Future<({DVShorebirdPatchTarget target, List<int> diff, String hash})>
  _patchIos(
    _Toolchain toolchain,
    String patchTool,
    Directory dir,
    List<String> buildArguments,
    Map<String, String> signing,
    DVShorebirdPatchTarget target,
  ) async {
    final File releaseSnapshot = File(p.join(dir.path, 'aarch64', 'App'));
    final Directory releaseSupplement = Directory(
      p.join(dir.path, 'aarch64', 'supplement'),
    );
    if (!releaseSnapshot.existsSync()) {
      throw DVSelfHostedUpdateError(
        'Release ${target.releaseVersion} kept no App snapshot in '
        '${p.relative(dir.path, from: _root)}; make the release again.',
      );
    }
    final String aotTools = await _aotTools(toolchain.engine);
    final _IosBuild build = await _buildIos(toolchain, buildArguments, signing);
    final File? kernel = build.kernel;
    if (kernel == null) {
      throw const DVSelfHostedUpdateError(
        'The build wrote no fresh app.dill under .dart_tool/flutter_build, '
        'and the patch snapshot is compiled from it.',
      );
    }
    for (final String tool in <String>[
      toolchain.genSnapshotIos,
      toolchain.analyzeSnapshotIos,
      toolchain.dart,
    ]) {
      if (!File(tool).existsSync()) {
        throw DVSelfHostedUpdateError(
          '$tool is missing; Shorebird\'s Flutter fetches it for an iOS '
          'release build, so the build above should have.',
        );
      }
    }

    final Directory work = Directory.systemTemp.createTempSync('dv_ios_patch_');
    try {
      // The linker finds each snapshot's supplement files beside it, named
      // after it: App.ct.link beside App, out.ct.link beside out.aot.
      final Directory releaseCopy = Directory(p.join(work.path, 'release'))
        ..createSync();
      final File base = releaseSnapshot.copySync(
        p.join(releaseCopy.path, 'App'),
      );
      if (releaseSupplement.existsSync()) {
        for (final File file
            in releaseSupplement.listSync().whereType<File>()) {
          file.copySync(p.join(releaseCopy.path, p.basename(file.path)));
        }
      }
      for (final File file in build.supplements) {
        file.copySync(
          p.join(work.path, p.basename(file.path).replaceFirst('App', 'out')),
        );
      }

      final List<String> debugInfo = _debugInfoArguments(
        buildArguments,
        work.path,
      );
      final String aot = p.join(work.path, 'out.aot');
      final ProcessResult compiled = await context.run(
        toolchain.genSnapshotIos,
        <String>[
          '--deterministic',
          '--snapshot-kind=app-aot-elf',
          '--elf=$aot',
          ...debugInfo,
          kernel.path,
        ],
      );
      if (compiled.exitCode != 0 || !File(aot).existsSync()) {
        throw DVSelfHostedUpdateError(
          'gen_snapshot could not compile the patch '
          '(exit ${compiled.exitCode}): ${compiled.stderr}',
        );
      }

      Future<ProcessResult> tools(List<String> arguments) => context.run(
        toolchain.dart,
        <String>['run', aotTools, ...arguments],
        workingDirectory: work.path,
      );

      final ProcessResult versionResult = await tools(const <String>[
        '--version',
      ]);
      final bool linkerUsesGenSnapshot =
          versionResult.exitCode == 0 &&
          _atLeast('${versionResult.stdout}', const <int>[0, 0, 1]);
      final String vmcode = p.join(work.path, 'out.vmcode');
      final String report = p.join(work.path, 'link.jsonl');
      final ProcessResult linked = await tools(<String>[
        'link',
        '--base=${base.path}',
        '--patch=$aot',
        '--analyze-snapshot=${toolchain.analyzeSnapshotIos}',
        '--output=$vmcode',
        '--verbose',
        if (linkerUsesGenSnapshot) ...<String>[
          '--gen-snapshot=${toolchain.genSnapshotIos}',
          '--kernel=${kernel.path}',
          '--reporter=json',
          '--redirect-to=$report',
        ],
        if (debugInfo.isNotEmpty) ...<String>['--', ...debugInfo],
      ]);
      final List<Map<String, Object?>> events = _jsonLines(File(report));
      if (linked.exitCode != 0 || !File(vmcode).existsSync()) {
        final Map<String, Object?>? failure = events
            .where((Map<String, Object?> e) => e['type'] == 'link_failure')
            .firstOrNull;
        throw DVSelfHostedUpdateError(
          'aot_tools could not link the patch against release '
          '${target.releaseVersion}'
          '${failure == null ? '' : ': ${failure['reason']}'} '
          '(exit ${linked.exitCode}). A release and its patch must be built '
          'by the same Flutter with the same build flags. ${linked.stderr}',
        );
      }
      final Object? percentage = events
          .where((Map<String, Object?> e) => e['type'] == 'link_success')
          .firstOrNull?['link_percentage'];
      if (percentage is num) {
        context.log(
          'Linked: ${percentage.toStringAsFixed(1)}% of the patch runs from '
          'the release\'s compiled code; the rest runs in the interpreter.',
        );
      }

      final List<int> booted = File(vmcode).readAsBytesSync();
      List<int> diff = booted;
      final ProcessResult help = await tools(const <String>['--help']);
      if ('${help.stdout}'.contains('dump_blobs')) {
        final String diffBase = p.join(work.path, 'diff_base');
        final ProcessResult dumped = await tools(<String>[
          'dump_blobs',
          '--analyze-snapshot=${toolchain.analyzeSnapshotIos}',
          '--output=$diffBase',
          '--snapshot=${base.path}',
        ]);
        if (dumped.exitCode != 0 || !File(diffBase).existsSync()) {
          throw DVSelfHostedUpdateError(
            'aot_tools could not dump the release snapshot into a diff base '
            '(exit ${dumped.exitCode}): ${dumped.stderr}',
          );
        }
        final String out = p.join(work.path, 'out.patch');
        final ProcessResult diffed = await context.run(patchTool, <String>[
          diffBase,
          vmcode,
          out,
        ]);
        if (diffed.exitCode != 0 || !File(out).existsSync()) {
          throw DVSelfHostedUpdateError(
            'Shorebird\'s patch tool failed (exit ${diffed.exitCode}): '
            '${diffed.stderr}',
          );
        }
        diff = File(out).readAsBytesSync();
      }
      return (
        target: target,
        diff: diff,
        hash: sha256.convert(booted).toString(),
      );
    } finally {
      work.deleteSync(recursive: true);
    }
  }

  static List<Map<String, Object?>> _jsonLines(File file) {
    if (!file.existsSync()) return const <Map<String, Object?>>[];
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    for (final String line in file.readAsLinesSync()) {
      try {
        final Object? decoded = jsonDecode(line);
        if (decoded is Map) lines.add(decoded.cast<String, Object?>());
      } on FormatException {
        // A line that is not JSON is the linker's own chatter.
      }
    }
    return lines;
  }

  /// Whether the version printed in [output] is at least [floor].
  static bool _atLeast(String output, List<int> floor) {
    final Match? match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(output);
    if (match == null) return false;
    for (int i = 0; i < 3; i++) {
      final int part = int.parse(match.group(i + 1)!);
      if (part != floor[i]) return part > floor[i];
    }
    return true;
  }

  /// Shorebird's `aot-tools.dill` for [engine], run with that engine's Dart.
  Future<String> _aotTools(String engine) async {
    final File tool = File(
      p.join(
        dartvelToolchainRoot(context.home),
        'shorebird_aot_tools',
        engine,
        'aot-tools.dill',
      ),
    );
    if (tool.existsSync()) return tool.path;
    final Uri url = Uri.parse(
      'https://storage.googleapis.com/download.shorebird.dev/shorebird/'
      '$engine/aot-tools.dill',
    );
    _consentToInstall('Shorebird\'s aot_tools for engine $engine ($url)');
    context.log('Fetching $url...');
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response = await (await client.getUrl(url))
          .close();
      if (response.statusCode != 200) {
        throw DVSelfHostedUpdateError(
          'Shorebird\'s aot_tools for engine $engine is not at $url '
          '(HTTP ${response.statusCode}), so an iOS patch cannot be linked.',
        );
      }
      final File partial = File('${tool.path}.part')
        ..createSync(recursive: true);
      await response.pipe(partial.openWrite());
      partial.renameSync(tool.path);
      return tool.path;
    } on IOException catch (error) {
      throw DVSelfHostedUpdateError('Could not fetch $url: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<_Toolchain> _toolchain() async {
    final String version = await context.flutterVersion();
    final String dir = p.join(
      dartvelToolchainRoot(context.home),
      'shorebird_flutter',
      version,
    );
    final File engineFile = File(
      p.join(dir, 'bin', 'internal', 'engine.version'),
    );
    if (!engineFile.existsSync()) {
      final List<String> clone = <String>[
        'clone',
        '--filter=tree:0',
        '-b',
        'flutter_release/$version',
        'https://github.com/shorebirdtech/flutter',
        dir,
      ];
      _consentToInstall(
        'Shorebird\'s Flutter $version (git ${clone.join(' ')})',
      );
      context.log('Installing Shorebird\'s Flutter $version into $dir...');
      final ProcessResult cloned = await context.run('git', clone);
      if (cloned.exitCode != 0 || !engineFile.existsSync()) {
        throw DVSelfHostedUpdateError(
          'Could not fetch Shorebird\'s Flutter $version. Shorebird publishes '
          'a flutter_release branch per Flutter release it supports; if there '
          'is none for $version yet, a self-hosted release cannot be built '
          'on it. ${cloned.stderr}',
        );
      }
    }
    return _Toolchain(
      root: dir,
      flutter: p.join(
        dir,
        'bin',
        Platform.isWindows ? 'flutter.bat' : 'flutter',
      ),
      engine: engineFile.readAsStringSync().trim(),
      flutterVersion: version,
    );
  }

  Future<String> _patchTool(String engine) async {
    final String dir = p.join(
      dartvelToolchainRoot(context.home),
      'shorebird_patch',
      engine,
    );
    final File tool = File(
      p.join(dir, Platform.isWindows ? 'patch.exe' : 'patch'),
    );
    if (tool.existsSync()) return tool.path;
    final String os = Platform.isMacOS
        ? 'darwin'
        : Platform.isWindows
        ? 'windows'
        : 'linux';
    final Uri url = Uri.parse(
      'https://storage.googleapis.com/download.shorebird.dev/shorebird/'
      '$engine/patch-$os-x64.zip',
    );
    _consentToInstall('Shorebird\'s patch tool for engine $engine ($url)');
    context.log('Fetching $url...');
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response = await (await client.getUrl(url))
          .close();
      if (response.statusCode != 200) {
        throw DVSelfHostedUpdateError(
          'Shorebird\'s patch tool for engine $engine is not at $url '
          '(HTTP ${response.statusCode}).',
        );
      }
      final File zip = File(p.join(dir, 'patch.zip'))
        ..createSync(recursive: true);
      await response.pipe(zip.openWrite());
      final Map<String, Uint8List> entries = dvReadZipEntries(
        zip.path,
        (String name) => p.basenameWithoutExtension(name) == 'patch',
      );
      if (entries.isEmpty) {
        throw DVSelfHostedUpdateError('$url holds no patch executable.');
      }
      tool.writeAsBytesSync(entries.values.first);
      zip.deleteSync();
      if (!Platform.isWindows) {
        await Process.run('chmod', <String>['755', tool.path]);
      }
      return tool.path;
    } on IOException catch (error) {
      throw DVSelfHostedUpdateError('Could not fetch $url: $error');
    } finally {
      client.close(force: true);
    }
  }

  void _consentToInstall(String what) {
    final AutoInstallDecision decision = decideAutoInstall(
      hasMissing: true,
      isCi: isCiEnvironment(context.environment),
      autoInstallFlag: autoInstall,
    );
    switch (decision) {
      case AutoInstallDecision.installWithoutPrompting:
      case AutoInstallDecision.nothingToDo:
        return;
      case AutoInstallDecision.declined:
        throw DVSelfHostedUpdateError(
          '$what is not installed, and --no-auto-install was given.',
        );
      case AutoInstallDecision.prompt:
        final bool yes =
            context.confirmInstall?.call(what) ?? _askOnStdin(what);
        if (!yes) {
          throw DVSelfHostedUpdateError(
            '$what is needed and was not installed.',
          );
        }
    }
  }

  static bool _askOnStdin(String what) {
    stdout.write('Install $what? [Y/n] ');
    try {
      final String answer = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
      return answer.isEmpty || answer == 'y' || answer == 'yes';
    } on StdinException {
      return false;
    }
  }
}

class _Toolchain {
  const _Toolchain({
    required this.root,
    required this.flutter,
    required this.engine,
    required this.flutterVersion,
  });

  /// Shorebird's Flutter checkout.
  final String root;
  final String flutter;
  final String engine;
  final String flutterVersion;

  String get _iosRelease =>
      p.join(root, 'bin', 'cache', 'artifacts', 'engine', 'ios-release');

  /// The iOS gen_snapshot, which Shorebird's Flutter fetches for an iOS
  /// release build.
  String get genSnapshotIos => p.join(_iosRelease, 'gen_snapshot_arm64');

  String get analyzeSnapshotIos =>
      p.join(_iosRelease, 'analyze_snapshot_arm64');

  /// The Dart of this Flutter, which aot_tools.dill is compiled for.
  String get dart => p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', 'dart');
}

class _IosBuild {
  const _IosBuild({
    required this.appSnapshot,
    required this.supplements,
    required this.kernel,
  });

  /// The archive's `App.framework/App`: the release's AOT snapshot.
  final File appSnapshot;

  /// The link supplement files Shorebird's Flutter wrote for this build.
  final List<File> supplements;

  /// The `app.dill` this build compiled, or null when none is fresh.
  final File? kernel;
}
