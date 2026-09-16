/// `dartvel publish <store>`: the application to a store, or the reason not.
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

import 'package:args/command_runner.dart';

import '../cloud/cloud_build.dart';
import '../devclient/dev_client_artifact.dart';
import '../publish/publish_plan.dart';
import '../utils/logger.dart';

typedef PublishProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

class PublishCommand extends Command<void> {
  /// [root] is the project; null reads the working directory when the command
  /// runs. A test passes its own, because that directory is one value shared
  /// by every suite in the process.
  PublishCommand({PublishProcessRun? processRun, this._root, this._cloud})
      : _processRun = processRun ?? _defaultRun {
    argParser
      ..addFlag('dry-run',
          defaultsTo: false,
          negatable: false,
          help: 'Print the command that would run, and run nothing.')
      ..addOption('artifact',
          help: 'The file to upload, when it is not where the build puts it.')
      ..addFlag('cloud',
          defaultsTo: false,
          negatable: false,
          help: 'Build and publish on Dartvel Cloud, with the credentials kept '
              'there by dartvel key cloud. With --dry-run the worker prints the '
              'upload instead of making it. Firebase only for now: Play needs '
              'an app bundle and App Store Connect a signed IPA, and dartvel '
              'build makes neither yet. Needs a paid Dartvel Cloud plan.')
      ..addOption('cloud-token',
          help: 'The Dartvel Cloud token for --cloud. Defaults to '
              'DARTVEL_CLOUD_TOKEN, which keeps it out of shell history.');
  }

  static Future<ProcessResult> _defaultRun(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) =>
      Process.run(executable, arguments,
          workingDirectory: workingDirectory, runInShell: runInShell);

  final PublishProcessRun _processRun;
  final String? _root;
  final DVCloudBuilder? _cloud;

  @override
  final String name = 'publish';

  @override
  String get description =>
      'Publish a built application to a store (${dvPublishStores.join(', ')}).';

  @override
  String get invocation => 'dartvel publish <store>';

  @override
  Future<void> run() async {
    final List<String> rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      Logger.log('❌ Name a store: ${dvPublishStores.join(', ')}.');
      exitCode = 64; // EX_USAGE
      return;
    }

    final String store = rest.first;
    final String root = _root ?? Directory.current.path;

    if (argResults?['cloud'] == true) {
      exitCode = await _publishInTheCloud(store, root);
      return;
    }
    final DVPublishPlan plan = dvPublishPlan(
      store: store,
      root: root,
      host: Platform.isMacOS
          ? 'macos'
          : Platform.isWindows
              ? 'windows'
              : 'linux',
    );

    if (!plan.ok) {
      Logger.log('❌ Cannot publish to $store:');
      for (final String problem in plan.problems) {
        Logger.log('   $problem');
      }
      exitCode = 78; // EX_CONFIG
      return;
    }

    final String artifact = argResults?['artifact'] as String? ?? plan.artifact;
    // Before the tooling check, because a missing artifact is the project's
    // own business and says to build first; a missing tool is the machine's.
    if (!File(artifact).existsSync()) {
      Logger.log('❌ There is nothing at $artifact to publish.');
      Logger.log('   Build it first, or pass --artifact.');
      exitCode = 66; // EX_NOINPUT
      return;
    }

    // Before the dry run, which would otherwise print a command that puts a
    // dev menu in front of the public.
    if (dvArtifactIsDevClient(artifact)) {
      final int track = plan.arguments.indexOf('--track');
      final String? refusal = dvDevClientPublishRefusal(
        store: store,
        track: track < 0 ? null : plan.arguments[track + 1],
      );
      if (refusal != null) {
        Logger.log('❌ $refusal');
        exitCode = 78; // EX_CONFIG
        return;
      }
    }

    final List<String> arguments = <String>[
      for (final String argument in plan.arguments)
        if (argument == plan.artifact) artifact else argument,
    ];

    if (argResults?['dry-run'] == true) {
      Logger.log('${plan.executable} ${arguments.join(' ')}');
      return;
    }

    if (!_isOnPath(plan.toolchain)) {
      Logger.log('❌ ${plan.toolchain} is not installed, and publishing to '
          '$store is done with it.');
      Logger.log('   Install it and run this again; Dartvel will not fetch a '
          'store toolchain unattended.');
      exitCode = 69; // EX_UNAVAILABLE
      return;
    }

    Logger.log('🚀 Publishing to $store...');
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
      exitCode = result.exitCode;
      return;
    }
    Logger.log('✅ Published to $store.');
  }

  /// What each store is built from in the cloud, and why a store is not.
  static const Map<String, String> _cloudTargets = <String, String>{
    'firebase': 'android',
  };

  static const Map<String, String> _cloudRefusals = <String, String>{
    'play': 'Google Play takes an app bundle, and dartvel build android '
        'writes an APK. Build the bundle and run dartvel publish play where '
        'it is.',
    'appstore': 'App Store Connect takes a signed IPA, and dartvel build ios '
        'builds without code signing. Signing on a Cloud worker is designed and '
        'not built.',
    'testflight': 'TestFlight takes a signed IPA, and dartvel build ios '
        'builds without code signing. Signing on a Cloud worker is designed and '
        'not built.',
  };

  Future<int> _publishInTheCloud(String store, String root) async {
    final String? refusal = _cloudRefusals[store];
    if (refusal != null) {
      Logger.log('❌ Cannot publish to $store from the cloud yet. $refusal');
      return 78; // EX_CONFIG
    }
    final String? target = _cloudTargets[store];
    if (target == null) {
      Logger.log('❌ "$store" is not a store Dartvel publishes to. The ones it '
          'knows are ${dvPublishStores.join(', ')}.');
      return 64; // EX_USAGE
    }
    // The declaration is checked here, where a refusal costs nothing, rather
    // than on a worker after the build.
    final DVPublishPlan plan =
        dvPublishPlan(store: store, root: root, host: 'linux');
    if (!plan.ok) {
      Logger.log('❌ Cannot publish to $store:');
      for (final String problem in plan.problems) {
        Logger.log('   $problem');
      }
      return 78; // EX_CONFIG
    }
    return (_cloud ?? DVCloudBuilder()).run(DVCloudBuildRequest(
      root: root,
      target: target,
      profile: 'release',
      publish: store,
      dryRun: argResults?['dry-run'] == true,
      token: argResults?['cloud-token'] as String?,
    ));
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
