/// `dartvel deploy --store <store>`: the application to a store, or the
/// reason not.
///
/// Host support first, then the tooling, then the work -- the build
/// toolchain rule, and here it matters more than usual: the work is an
/// upload of a binary that took minutes to produce, and a credential that
/// was never declared is discovered after all of it.
///
/// `--dry-run` prints the command instead of running it, which is how
/// somebody sees what Dartvel would do to their store account before it does
/// it.
library;

import 'dart:io';

import '../cloud/cloud_build.dart';
import '../devclient/dev_client_artifact.dart';
import '../utils/logger.dart';
import 'store_plan.dart';

typedef StoreProcessRun =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
    });

/// The name the Dartvel Cloud protocol gives [store], a store in [dvStores].
///
/// The protocol predates the command line's spelling and still says
/// `firebase` for App Distribution. It is kept so a worker already running
/// reads the request; nothing a person types or declares uses it.
String dvCloudStoreName(String store) =>
    store == 'firebase-app-distribution' ? 'firebase' : store;

class DVStoreDeploy {
  /// [root] is the project; null reads the working directory when it runs.
  DVStoreDeploy({StoreProcessRun? processRun, this._root, this._cloud})
    : _processRun = processRun ?? _defaultRun;

  static Future<ProcessResult> _defaultRun(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) => Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: runInShell,
  );

  final StoreProcessRun _processRun;
  final String? _root;
  final DVCloudBuilder? _cloud;

  /// Deploys to [store], one of [dvStores], and answers the exit code.
  Future<int> run({
    required String store,
    bool dryRun = false,
    String? artifact,
    bool cloud = false,
    String? cloudToken,
  }) async {
    if (!dvStores.contains(store)) {
      Logger.log(
        '❌ "$store" is not a store Dartvel deploys to. The ones it '
        'knows are ${dvStores.join(', ')}.',
      );
      return 64; // EX_USAGE
    }
    final String root = _root ?? Directory.current.path;

    if (cloud) {
      return _inTheCloud(store, root, dryRun, cloudToken);
    }
    final DVStorePlan plan = dvStorePlan(
      store: store,
      root: root,
      host: Platform.isMacOS
          ? 'macos'
          : Platform.isWindows
          ? 'windows'
          : 'linux',
      environment: Platform.environment,
    );

    if (!plan.ok) {
      Logger.log('❌ Cannot deploy to $store:');
      for (final String problem in plan.problems) {
        Logger.log('   $problem');
      }
      return 78; // EX_CONFIG
    }

    final String upload = artifact ?? plan.artifact;
    // Before the tooling check, because a missing artifact is the project's
    // own business and says to build first; a missing tool is the machine's.
    if (!File(upload).existsSync()) {
      Logger.log('❌ There is nothing at $upload to deploy.');
      Logger.log('   Build it first, or pass --artifact.');
      return 66; // EX_NOINPUT
    }

    // Before the dry run, which would otherwise print a command that puts a
    // dev menu in front of the public.
    if (dvArtifactIsDevClient(upload)) {
      final int track = plan.arguments.indexOf('--track');
      final String? refusal = dvDevClientStoreRefusal(
        store: store,
        track: track < 0 ? null : plan.arguments[track + 1],
      );
      if (refusal != null) {
        Logger.log('❌ $refusal');
        return 78; // EX_CONFIG
      }
    }

    final List<String> arguments = <String>[
      for (final String argument in plan.arguments)
        if (argument == plan.artifact) upload else argument,
    ];

    if (dryRun) {
      Logger.log('${plan.executable} ${arguments.join(' ')}');
      return 0;
    }

    if (!_isOnPath(plan.toolchain)) {
      Logger.log(
        '❌ ${plan.toolchain} is not installed, and deploying to '
        '$store is done with it.',
      );
      Logger.log(
        '   Install it and run this again; Dartvel will not fetch a '
        'store toolchain unattended.',
      );
      return 69; // EX_UNAVAILABLE
    }

    Logger.log('🚀 Deploying to $store...');
    final ProcessResult result = await _processRun(
      plan.executable,
      arguments,
      workingDirectory: root,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      Logger.log('❌ ${plan.executable} exited ${result.exitCode}');
      final String error = '${result.stderr}'.trim();
      if (error.isNotEmpty) Logger.log(error);
      return result.exitCode;
    }
    Logger.log('✅ Deployed to $store.');
    return 0;
  }

  /// What each store is built from in the cloud: the target, the package
  /// format, and the operating system the upload runs on.
  static const Map<String, (String, String?, String)> _cloudBuilds =
      <String, (String, String?, String)>{
        'firebase-app-distribution': ('android', null, 'linux'),
        'play': ('android', 'aab', 'linux'),
        'appstore': ('ios', 'ipa', 'macos'),
        'testflight': ('ios', 'ipa', 'macos'),
      };

  Future<int> _inTheCloud(
    String store,
    String root,
    bool dryRun,
    String? token,
  ) async {
    // The declaration is checked here, where a refusal costs nothing, rather
    // than on a worker after the build.
    final (String target, String? format, String workerOs) =
        _cloudBuilds[store]!;
    final DVStorePlan plan = dvStorePlan(
      store: store,
      root: root,
      host: workerOs,
    );
    if (!plan.ok) {
      Logger.log('❌ Cannot deploy to $store:');
      for (final String problem in plan.problems) {
        Logger.log('   $problem');
      }
      return 78; // EX_CONFIG
    }
    return (_cloud ?? DVCloudBuilder()).run(
      DVCloudBuildRequest(
        root: root,
        target: target,
        profile: 'release',
        format: format,
        store: dvCloudStoreName(store),
        dryRun: dryRun,
        token: token,
      ),
    );
  }

  static bool _isOnPath(String executable) {
    final ProcessResult result = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      <String>[executable],
      runInShell: true,
    );
    return result.exitCode == 0;
  }
}
