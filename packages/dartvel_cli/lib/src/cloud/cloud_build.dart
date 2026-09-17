/// `dartvel build <target> --cloud` and `dartvel deploy --store <store> --cloud`: the
/// project packed and sent to Dartvel Cloud, built on a Dartvel worker, its
/// log printed as it arrives, and its artifacts brought home into
/// `build/cloud/<target>`.
///
/// This machine needs no SDK for the target: iOS and macOS build on a macOS
/// worker, Windows on a Windows one. Every cloud build needs a paid plan, and
/// an account without one is told so with the plans page before anything is
/// built.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/cloud.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/qr_code.dart';
import 'cloud_client.dart';
import 'source_archive.dart';

class DVCloudBuildRequest {
  const DVCloudBuildRequest({
    required this.root,
    required this.target,
    this.profile = 'release',
    this.store,
    this.dryRun = false,
    this.token,
    this.format,
    this.codesign = true,
    this.simulator = false,
    this.os,
  });

  /// `--cloud-os`: the worker OS for a target in [dvCloudHostTargets], by
  /// name. Null builds on the OS the target has.
  final String? os;

  /// `--simulator`: the tvOS build Dartvel Cloud makes.
  final bool simulator;

  /// `aab` or `ipa`: the store package to build instead of an APK or an
  /// unsigned app.
  final String? format;

  /// With `ipa`: whether the worker signs it.
  final bool codesign;

  /// The application directory.
  final String root;
  final String target;
  final String profile;

  /// The store `dartvel deploy --store` sends the build to once it is
  /// built, by its protocol name (dvCloudStoreName).
  final String? store;

  /// Passed to that deploy as `--dry-run`.
  final bool dryRun;

  /// `--cloud-token`; `DARTVEL_CLOUD_TOKEN` when null.
  final String? token;
}

/// The Dartvel Cloud URL and token a command uses.
class DVCloudAccess {
  const DVCloudAccess(this.url, this.token);

  final Uri url;
  final String token;

  /// Null, having said why through [log], when there is no token.
  static DVCloudAccess? resolve(
    Map<String, String> environment,
    String? token,
    void Function(String) log,
  ) {
    final String? chosen = token != null && token.trim().isNotEmpty
        ? token.trim()
        : environment[dvCloudTokenVariable]?.trim();
    if (chosen == null || chosen.isEmpty) {
      log('❌ No Dartvel Cloud token. Set $dvCloudTokenVariable, or pass '
          '--cloud-token. Cloud builds need a paid plan: $dvCloudPlansUrl');
      return null;
    }
    final String url = environment[dvCloudUrlVariable]?.trim() ?? '';
    return DVCloudAccess(Uri.parse(url.isEmpty ? dvCloudDefaultUrl : url), chosen);
  }
}

/// The exit code for a refusal: 77 for the account (no plan, a bad token),
/// 65 for the request, 69 for anything else the service could not do.
int dvCloudRefusalExit(DVCloudRefusal refusal, void Function(String) log) {
  if (refusal.planRequired) {
    log('❌ ${refusal.message}');
    log('   Choose a plan: ${refusal.url ?? dvCloudPlansUrl}');
    return 77;
  }
  log('❌ Dartvel Cloud refused: ${refusal.message}');
  if (refusal.url != null) log('   ${refusal.url}');
  if (refusal.status == 401 || refusal.status == 403) return 77;
  if (refusal.status >= 400 && refusal.status < 500) return 65;
  return 69;
}

/// The pubspec name of the project at [root], or null.
String? dvCloudProjectName(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  try {
    final Object? doc = loadYaml(pubspec.readAsStringSync());
    final Object? name = doc is Map ? doc['name'] : null;
    return name is String && dvCloudIsProjectName(name) ? name : null;
  } on YamlException {
    return null;
  }
}

class DVCloudBuilder {
  DVCloudBuilder({
    Map<String, String>? environment,
    void Function(String message)? log,
    this.retryDelay = const Duration(seconds: 3),
    this.maxReconnects = 20,
  })  : _environment = environment ?? Platform.environment,
        _log = log ?? ((String m) => stdout.writeln('[dartvel] $m'));

  final Map<String, String> _environment;
  final void Function(String) _log;
  final Duration retryDelay;
  final int maxReconnects;

  /// The exit code: 0 built and downloaded, 1 the build failed, 64 usage,
  /// 65 refused as a request, 69 unreachable, 77 no token or no plan, 78 the
  /// project is not ready.
  Future<int> run(DVCloudBuildRequest request) async {
    if (!dvCloudTargets.containsKey(request.target)) {
      _log('❌ ${request.target} does not build in Dartvel Cloud. Cloud targets: '
          '${dvCloudTargets.keys.join(', ')}.');
      return 64;
    }
    if (request.simulator != dvCloudSimulatorOnlyTargets.contains(request.target)) {
      _log(request.simulator
          ? '❌ ${request.target} does not build for a simulator in Dartvel Cloud.'
          : '❌ ${request.target} builds in Dartvel Cloud for the simulator only: a '
              'device build is signed with a team Dartvel Cloud does not keep. '
              'Pass --simulator.');
      return 64;
    }
    final DVCloudWorkerOs home = dvCloudTargets[request.target]!;
    final DVCloudWorkerOs? os = request.os == null
        ? null
        : DVCloudWorkerOs.values.where((DVCloudWorkerOs o) => o.name == request.os).firstOrNull;
    if (request.os != null && (os == null || (os != home && !dvCloudHostTargets.contains(request.target)))) {
      _log(os == null
          ? '❌ "${request.os}" is not a Dartvel Cloud worker OS: linux, macos or windows.'
          : '❌ ${request.target} builds on a ${home.name} worker in Dartvel Cloud. Only '
              '${dvCloudHostTargets.join(', ')} builds for the worker OS asked for.');
      return 64;
    }
    final String root = p.normalize(Directory(p.absolute(request.root)).resolveSymbolicLinksSync());
    final String? project = dvCloudProjectName(root);
    if (project == null) {
      _log('❌ $root has no pubspec.yaml naming a package, and a cloud build is '
          'filed under that name.');
      return 78;
    }
    final DVCloudAccess? access = DVCloudAccess.resolve(_environment, request.token, _log);
    if (access == null) return 77;

    // A repository is sent whole, so a path dependency on a sibling package
    // resolves on the worker as it does here.
    final String? top = await _gitTop(root);
    final String source = top ?? root;
    final String app = top == null
        ? '.'
        : p.posix.joinAll(p.split(p.relative(root, from: top)));
    final DVSourceArchive archive = await dvPackSource(source, app: app);
    final DVCloudClient client = DVCloudClient(access.url, access.token);
    try {
      _log('📦 Sending ${archive.fileCount} files '
          '(${_size(archive.file.lengthSync())}) to ${access.url}...');
      final DVCloudBuild queued = await client.submit(
        DVCloudBuildSpec(
          project: project,
          target: request.target,
          profile: request.profile,
          publish: request.store,
          dryRun: request.dryRun,
          app: app,
          format: request.format,
          codesign: request.codesign,
          simulator: request.simulator,
          os: os,
        ),
        archive.file,
      );
      final int ahead = queued.queuePosition ?? 0;
      _log('☁️  Queued ${request.target} (${request.profile}) as ${queued.id}'
          '${ahead == 0 ? '' : ', $ahead ahead of it'}.');

      final DVCloudBuildStatus? finished = await _follow(client, queued.id);
      if (finished == null) {
        _log('❌ The event stream for ${queued.id} kept dropping. The build goes '
            'on in Dartvel Cloud.');
        return 69;
      }
      final DVCloudBuild build = await client.build(queued.id);
      if (build.status != DVCloudBuildStatus.succeeded) {
        _log('❌ The cloud build ${build.status.name}'
            '${build.message == null ? '.' : ': ${build.message}'}');
        return 1;
      }

      final Directory out = Directory(p.join(root, 'build', 'cloud', request.target));
      if (out.existsSync()) out.deleteSync(recursive: true);
      for (final DVCloudArtifact artifact in build.artifacts) {
        final String path = p.joinAll(<String>[out.path, ...artifact.name.split('/')]);
        if (artifact.link != null) {
          // Made here, not fetched: what a framework reaches its binary and
          // resources through. Links are the protocol's own and were checked
          // to stay inside the download when the build was read.
          Directory(p.dirname(path)).createSync(recursive: true);
          try {
            Link(path).createSync(p.joinAll(artifact.link!.split('/')));
          } on FileSystemException catch (error) {
            _log('⚠️  ${artifact.name} is a link to ${artifact.link}, and this machine '
                'would not make it: ${error.osError?.message ?? error.message}');
          }
          continue;
        }
        final File file = File(path);
        await client.download(build.id, artifact.name, file);
        final int size = file.lengthSync();
        final String digest = '${await sha256.bind(file.openRead()).first}';
        if (size != artifact.size || digest != artifact.sha256) {
          file.deleteSync();
          _log('❌ ${artifact.name} arrived with the wrong checksum, so it was '
              'not kept. Run the build again.');
          return 1;
        }
        if (artifact.executable && !Platform.isWindows) {
          final ProcessResult chmod = await Process.run('chmod', <String>['755', file.path]);
          if (chmod.exitCode != 0) {
            _log('❌ ${artifact.name} is a program and could not be made executable: ${chmod.stderr}');
            return 1;
          }
        }
      }
      _log('✅ Built in Dartvel Cloud: ${build.artifacts.length} file(s) in '
          '${p.relative(out.path, from: root)}');
      if (build.installUrl != null) {
        _log('📲 Install on a device: ${build.installUrl}');
        // Scanned from the screen by the phone the build is for.
        dvQrTerminalLines(
          DVQrCode.encodeText(build.installUrl!),
          ansi: stdout.hasTerminal && stdout.supportsAnsiEscapes,
        ).forEach(_log);
      }
      return 0;
    } on DVCloudException catch (error) {
      return dvCloudRefusalExit(error.refusal, _log);
    } on DVCloudUnreachable catch (error) {
      _log('❌ $error');
      return 69;
    } finally {
      client.close();
      archive.file.parent.deleteSync(recursive: true);
    }
  }

  /// Prints the build's log until it finishes; its final status, or null when
  /// the stream could not be kept open.
  Future<DVCloudBuildStatus?> _follow(DVCloudClient client, String id) async {
    int? last;
    int reconnects = 0;
    while (reconnects <= maxReconnects) {
      try {
        await for (final DVCloudEvent event in client.events(id, lastEventId: last)) {
          if (last != null && event.id <= last) continue;
          last = event.id;
          reconnects = 0;
          if (event.line != null) {
            _log(event.line!);
          } else if (event.status!.isFinished) {
            return event.status;
          } else {
            _log('   ${event.status!.name}');
          }
        }
      } on DVCloudUnreachable {
        // Resumed below from the last event seen.
      } on HttpException {
        // A connection dropped mid-stream.
      } on SocketException {
        // The same, a layer down.
      }
      reconnects++;
      await Future<void>.delayed(retryDelay);
    }
    return null;
  }

  static Future<String?> _gitTop(String root) async {
    try {
      final ProcessResult r = await Process.run(
          'git', <String>['rev-parse', '--show-toplevel'],
          workingDirectory: root);
      final String top = '${r.stdout}'.trim();
      return r.exitCode == 0 && top.isNotEmpty ? p.normalize(Directory(top).resolveSymbolicLinksSync()) : null;
    } on ProcessException {
      return null;
    }
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
