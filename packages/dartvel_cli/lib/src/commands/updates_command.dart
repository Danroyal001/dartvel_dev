import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../updates/self_hosted_updates.dart';
import '../utils/logger.dart';

const String _patchSourceHelp =
    'Publish into a patch source this project hosts instead of Shorebird\'s '
    'service: the URL shorebird.yaml\'s base_url names on the web-server '
    'binary (with DARTVEL_UPDATES_TOKEN set to the token it was started '
    'with), or a directory a patch source is served from. Builds with '
    'Shorebird\'s Flutter at this project\'s Flutter version; needs no '
    'Shorebird account. Android only.';

void _addSelfHostedOptions(ArgParser parser) {
  parser
    ..addOption('patch-source', help: _patchSourceHelp, valueHelp: 'url|dir')
    ..addFlag(
      'auto-install',
      defaultsTo: null,
      help:
          'With --patch-source: install Shorebird\'s Flutter and patch tool '
          'without prompting. Defaults to prompting when interactive, and to '
          'installing in CI.',
    );
}

class UpdatesCommand extends Command<void> {
  @override
  final String name = 'updates';

  @override
  final String description = 'Manage Over-The-Air (OTA) updates.';

  UpdatesCommand({DVUpdatesContext? context}) {
    addSubcommand(UpdatesReleaseCommand(context: context));
    addSubcommand(UpdatesPatchCommand(context: context));
    addSubcommand(UpdatesRollbackCommand(context: context));
    addSubcommand(UpdatesPushCommand(context: context));
  }
}

class UpdatesReleaseCommand extends _ShorebirdPlatformsCommand {
  @override
  final String name = 'release';

  @override
  final String description =
      'Create Shorebird releases for target platforms. Arguments after -- go '
      'to the build.';

  UpdatesReleaseCommand({super.context}) : super(action: 'release');

  @override
  Future<void> runSelfHosted(
    DVSelfHostedUpdates updates,
    String platform,
    DVPatchSourceLocation source,
  ) => updates.release(
    platform: platform,
    source: source,
    buildArguments: argResults?.rest ?? const <String>[],
  );
}

class UpdatesPatchCommand extends _ShorebirdPlatformsCommand {
  @override
  String get name => 'patch';

  @override
  String get description =>
      'Create Shorebird patches for target platforms. Arguments after -- go '
      'to the build.';

  UpdatesPatchCommand({super.context}) : super(action: 'patch') {
    argParser
      ..addOption(
        'release-version',
        help:
            'Existing release version to patch. With --patch-source, defaults '
            'to the pubspec version.',
      )
      ..addOption(
        'channel',
        defaultsTo: 'stable',
        help: 'With --patch-source: the channel the patch is published to.',
      );
  }

  @override
  List<String> argsForPlatform(String platform) {
    final args = super.argsForPlatform(platform);
    final releaseVersion = argResults?['release-version'] as String?;
    if (releaseVersion != null && releaseVersion.trim().isNotEmpty) {
      args.addAll(<String>['--release-version', releaseVersion.trim()]);
    }
    return args;
  }

  @override
  Future<void> runSelfHosted(
    DVSelfHostedUpdates updates,
    String platform,
    DVPatchSourceLocation source,
  ) {
    final String? version = (argResults?['release-version'] as String?)?.trim();
    return updates.patch(
      platform: platform,
      source: source,
      releaseVersion: version == null || version.isEmpty ? null : version,
      channel: (argResults?['channel'] as String? ?? 'stable').trim(),
      buildArguments: argResults?.rest ?? const <String>[],
    );
  }
}

class UpdatesPushCommand extends UpdatesPatchCommand {
  UpdatesPushCommand({super.context});

  @override
  String get name => 'push';

  @override
  String get description =>
      'Alias for updates patch. Use updates patch in new scripts.';
}

class UpdatesRollbackCommand extends Command<void> {
  @override
  final String name = 'rollback';

  @override
  final String description = 'Roll back a Shorebird patch track.';

  final DVUpdatesContext? context;

  UpdatesRollbackCommand({this.context}) {
    argParser
      ..addOption(
        'release-version',
        help: 'Release version containing the patch.',
        mandatory: true,
      )
      ..addOption(
        'patch-number',
        help: 'Patch number to move to the selected track.',
        mandatory: true,
      )
      ..addOption(
        'track',
        defaultsTo: 'stable',
        help: 'Target Shorebird track.',
      )
      ..addOption(
        'platform',
        defaultsTo: 'android',
        allowed: const <String>['android', 'ios'],
        help: 'With --patch-source: the platform whose patch is rolled back.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        help: 'Print the Shorebird command without executing it.',
      );
    _addSelfHostedOptions(argParser);
  }

  @override
  Future<void> run() async {
    final releaseVersion = (argResults?['release-version'] as String).trim();
    final patchNumber = (argResults?['patch-number'] as String).trim();
    final track = (argResults?['track'] as String? ?? 'stable').trim();
    if (releaseVersion.isEmpty || patchNumber.isEmpty || track.isEmpty) {
      throw UsageException(
        'release-version, patch-number, and track must be non-empty.',
        usage,
      );
    }
    final String? patchSource = argResults?['patch-source'] as String?;
    if (patchSource != null) {
      final int? number = int.tryParse(patchNumber);
      if (number == null || number < 1) {
        throw UsageException('patch-number must be a positive integer.', usage);
      }
      await _selfHosted(
        () =>
            DVSelfHostedUpdates(
              context ?? DVUpdatesContext(),
              autoInstall: argResults?['auto-install'] as bool?,
            ).rollback(
              platform: argResults?['platform'] as String? ?? 'android',
              source: DVPatchSourceLocation.parse(patchSource),
              releaseVersion: releaseVersion,
              number: number,
            ),
      );
      return;
    }
    final args = <String>[
      'patches',
      'set-track',
      '--release-version',
      releaseVersion,
      '--patch-number',
      patchNumber,
      '--track',
      track,
    ];
    await _runShorebird(args, dryRun: argResults?['dry-run'] == true);
  }
}

abstract class _ShorebirdPlatformsCommand extends Command<void> {
  final String action;
  final DVUpdatesContext? context;

  _ShorebirdPlatformsCommand({required this.action, this.context}) {
    argParser
      ..addMultiOption(
        'platform',
        abbr: 'p',
        defaultsTo: const <String>['android', 'ios'],
        allowed: const <String>['android', 'ios'],
        help:
            'Target platform. Repeat to run multiple platforms. With '
            '--patch-source, defaults to android.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        help: 'Print Shorebird commands without executing them.',
      );
    _addSelfHostedOptions(argParser);
  }

  List<String> argsForPlatform(String platform) => <String>[action, platform];

  Future<void> runSelfHosted(
    DVSelfHostedUpdates updates,
    String platform,
    DVPatchSourceLocation source,
  );

  @override
  Future<void> run() async {
    final String? patchSource = argResults?['patch-source'] as String?;
    final List<String> platforms =
        patchSource != null && !(argResults?.wasParsed('platform') ?? false)
        ? const <String>['android']
        : argResults?['platform'] as List<String>? ?? const <String>[];
    if (platforms.isEmpty) {
      throw UsageException('At least one --platform is required.', usage);
    }
    if (patchSource != null) {
      final DVSelfHostedUpdates updates = DVSelfHostedUpdates(
        context ?? DVUpdatesContext(),
        autoInstall: argResults?['auto-install'] as bool?,
      );
      for (final String platform in platforms) {
        if (!await _selfHosted(
          () => runSelfHosted(
            updates,
            platform,
            DVPatchSourceLocation.parse(patchSource),
          ),
        )) {
          return;
        }
      }
      return;
    }
    for (final platform in platforms) {
      await _runShorebird(
        argsForPlatform(platform),
        dryRun: argResults?['dry-run'] == true,
      );
    }
  }
}

/// Runs a self-hosted step, reporting a refusal and setting the exit code.
Future<bool> _selfHosted(Future<Object?> Function() step) async {
  try {
    await step();
    return true;
  } on DVSelfHostedUpdateError catch (error) {
    Logger.error(error.message);
    exitCode = 1;
    return false;
  }
}

Future<void> _runShorebird(List<String> args, {required bool dryRun}) async {
  if (dryRun) {
    stdout.writeln('shorebird ${args.join(' ')}');
    return;
  }
  final check = await Process.run('shorebird', <String>['--version']);
  if (check.exitCode != 0) {
    Logger.error(
      'Shorebird CLI not found. Install it first: https://shorebird.dev',
    );
    exitCode = 1;
    return;
  }
  Logger.log('Running shorebird ${args.join(' ')}');
  final process = await Process.start('shorebird', args);
  await stdout.addStream(process.stdout);
  await stderr.addStream(process.stderr);
  final code = await process.exitCode;
  if (code != 0) {
    Logger.error('shorebird ${args.join(' ')} failed with exit code $code.');
    exitCode = code;
  }
}
