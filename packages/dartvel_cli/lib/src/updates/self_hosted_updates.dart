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
/// Android only. A Shorebird iOS patch is not a diff of `App.framework/App`:
/// the shorebird CLI links the patch against the release's snapshot with
/// Shorebird's `aot_tools` first, and that step is not built here.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart'
    show DVShorebirdPatch, DVShorebirdPatchSource, DVShorebirdPatchTarget;
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
typedef DVUpdatesRun =
    Future<ProcessResult> Function(
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
  }) : root = root ?? Directory.current.path,
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
    if (platform != 'android') {
      throw const DVSelfHostedUpdateError(
        'A self-hosted patch source takes Android patches only. A Shorebird '
        'iOS patch is linked against the release snapshot by Shorebird\'s '
        'aot_tools before it is diffed, and Dartvel does not do that step; '
        'use `dartvel updates release --platform ios` without --patch-source, which runs '
        'the shorebird CLI against its hosted service.',
      );
    }
  }

  /// Refuses a release that would build, install and never update: one that
  /// does not bundle shorebird.yaml, where the updater reads base_url, or
  /// whose main Android manifest has no INTERNET permission, which Flutter's
  /// template grants only to debug and profile builds.
  void _checkReachesPatchSource() {
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
  /// diffed against. Returns the architectures kept.
  Future<List<String>> release({
    required String platform,
    required DVPatchSourceLocation source,
    List<String> buildArguments = const <String>[],
  }) async {
    _checkPlatform(platform);
    _token(source);
    final DVShorebirdConfig config = _config();
    _checkReachesPatchSource();
    final String version = releaseVersion();
    final _Toolchain toolchain = await _toolchain();

    final Map<String, List<int>> libraries = await _buildAndroid(
      toolchain,
      buildArguments,
    );
    final Directory dir = Directory(
      _releaseDir(config.appId, version, platform),
    );
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    for (final MapEntry<String, List<int>> library in libraries.entries) {
      File(p.join(dir.path, library.key, 'libapp.so'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(library.value);
    }
    File(p.join(dir.path, 'release.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'app_id': config.appId,
        'release_version': version,
        'platform': platform,
        'engine': toolchain.engine,
        'flutter': toolchain.flutterVersion,
        'architectures': libraries.keys.toList(),
      }),
    );
    context.log(
      'Release ${config.appId} $version ($platform: '
      '${libraries.keys.join(', ')}) built with Shorebird\'s engine '
      '${toolchain.engine}. Distribute the APK in build/app/outputs; its '
      'compiled Dart is kept in ${p.relative(dir.path, from: _root)} for the '
      'patches made against it.',
    );
    return libraries.keys.toList();
  }

  /// Builds the patched app, diffs it against [releaseVersion]'s release and
  /// publishes one patch per architecture.
  Future<List<DVShorebirdPatch>> patch({
    required String platform,
    required DVPatchSourceLocation source,
    String? releaseVersion,
    String channel = 'stable',
    List<String> buildArguments = const <String>[],
  }) async {
    _checkPlatform(platform);
    final String? token = _token(source);
    final DVShorebirdConfig config = _config();
    final String version = releaseVersion ?? this.releaseVersion();
    final Directory dir = Directory(
      _releaseDir(config.appId, version, platform),
    );
    final File record = File(p.join(dir.path, 'release.json'));
    if (!record.existsSync()) {
      throw DVSelfHostedUpdateError(
        'There is no release ${config.appId} $version for $platform here: a '
        'patch is a diff against the release\'s compiled Dart, which '
        '`dartvel updates release --patch-source` keeps in '
        '${p.relative(dir.path, from: _root)}. Patch the version you released, '
        'with --release-version.',
      );
    }
    final Map<String, Object?> released =
        (jsonDecode(record.readAsStringSync()) as Map<Object?, Object?>)
            .cast<String, Object?>();

    final _Toolchain toolchain = await _toolchain();
    if (released['engine'] != toolchain.engine) {
      throw DVSelfHostedUpdateError(
        'Release $version was built by Shorebird\'s engine '
        '${released['engine']}, and this Flutter is on ${toolchain.engine}. '
        'A patch diffed across engines does not boot, so nothing was '
        'published. Patch with the Flutter version the release was built '
        'with (${released['flutter']}).',
      );
    }
    final String tool = await _patchTool(toolchain.engine);
    final Map<String, List<int>> libraries = await _buildAndroid(
      toolchain,
      buildArguments,
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
            appId: config.appId,
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

    final List<DVShorebirdPatch> published = <DVShorebirdPatch>[];
    for (final d in diffs) {
      final DVShorebirdPatch patch = source.isUrl
          ? await _publishOverHttp(
              source.url!,
              token!,
              d.target,
              d.diff,
              d.hash,
              channel,
            )
          : DVShorebirdPatchSource(source.raw).publish(
              d.target,
              diff: d.diff,
              patchedHash: d.hash,
              channel: channel,
            );
      published.add(patch);
      context.log(
        'Published patch ${patch.number} for ${config.appId} $version '
        '$platform ${d.target.arch} (${d.diff.length} bytes) to ${source.raw}.',
      );
    }
    return published;
  }

  /// Rolls patch [number] of [releaseVersion] back on every architecture.
  Future<List<String>> rollback({
    required String platform,
    required DVPatchSourceLocation source,
    required String releaseVersion,
    required int number,
  }) async {
    _checkPlatform(platform);
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
  ) async {
    final Uri endpoint = _endpoint(base, '_dartvel/publish').replace(
      queryParameters: <String, String>{
        'app_id': target.appId,
        'release_version': target.releaseVersion,
        'platform': target.platform,
        'arch': target.arch,
        'hash': hash,
        'channel': channel,
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
  ) async {
    final ProcessResult built = await context.run(
      toolchain.flutter,
      <String>['build', 'apk', '--release', ...buildArguments],
      workingDirectory: _root,
      environment: <String, String>{
        ...context.environment,
        'FLUTTER_STORAGE_BASE_URL': dvShorebirdStorageBaseUrl,
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
      final HttpClientResponse response = await (await client.getUrl(
        url,
      )).close();
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
    required this.flutter,
    required this.engine,
    required this.flutterVersion,
  });

  final String flutter;
  final String engine;
  final String flutterVersion;
}
