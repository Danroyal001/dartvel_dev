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
import 'publish_plan.dart';

typedef PublishProcessRun =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
    });

/// The stores `dartvel deploy --store` takes, by the name the command line
/// uses, to the name the project declares them under in
/// `dartvel.publish.<name>` and the Dartvel Cloud protocol sends.
///
/// Firebase is spelled out on the command line because `dartvel deploy`
/// already reaches Firebase Hosting through `--provider`; `firebase` alone
/// named Hosting on one command and App Distribution on the other. The
/// declaration and the wire keep `firebase`: under `dartvel.publish`, and in
/// a request's `publish` field, there is no Hosting for it to be confused
/// with, and renaming either would break every declared project and every
/// running worker for a spelling.
const Map<String, String> dvDeployStores = <String, String>{
  'play': 'play',
  'appstore': 'appstore',
  'testflight': 'testflight',
  'firebase-app-distribution': 'firebase',
};

/// The command-line name of the store declared or sent as [declared]; the
/// name itself when it is one already, and null when it is neither.
String? dvDeployStoreName(String declared) {
  if (dvDeployStores.containsKey(declared)) return declared;
  for (final MapEntry<String, String> store in dvDeployStores.entries) {
    if (store.value == declared) return store.key;
  }
  return null;
}

class DVStoreDeploy {
  /// [root] is the project; null reads the working directory when it runs.
  DVStoreDeploy({PublishProcessRun? processRun, this._root, this._cloud})
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

  final PublishProcessRun _processRun;
  final String? _root;
  final DVCloudBuilder? _cloud;

  /// Publishes to [store], a key of [dvDeployStores], and answers the exit
  /// code.
  Future<int> run({
    required String store,
    bool dryRun = false,
    String? artifact,
    bool cloud = false,
    String? cloudToken,
  }) async {
    final String? declared = dvDeployStores[store];
    if (declared == null) {
      Logger.log(
        '❌ "$store" is not a store Dartvel deploys to. The ones it '
        'knows are ${dvDeployStores.keys.join(', ')}.',
      );
      return 64; // EX_USAGE
    }
    final String root = _root ?? Directory.current.path;

    if (cloud) {
      return _inTheCloud(store, declared, root, dryRun, cloudToken);
    }
    final DVPublishPlan plan = dvPublishPlan(
      store: declared,
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
      final String? refusal = dvDevClientPublishRefusal(
        store: declared,
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
        'firebase': ('android', null, 'linux'),
        'play': ('android', 'aab', 'linux'),
        'appstore': ('ios', 'ipa', 'macos'),
        'testflight': ('ios', 'ipa', 'macos'),
      };

  Future<int> _inTheCloud(
    String store,
    String declared,
    String root,
    bool dryRun,
    String? token,
  ) async {
    // The declaration is checked here, where a refusal costs nothing, rather
    // than on a worker after the build.
    final (String target, String? format, String workerOs) =
        _cloudBuilds[declared]!;
    final DVPublishPlan plan = dvPublishPlan(
      store: declared,
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
        // The protocol's name, which a worker already running understands.
        publish: declared,
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
