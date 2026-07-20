import 'dart:io';

import 'package:args/command_runner.dart';

import '../utils/logger.dart';

class UpdatesCommand extends Command<void> {
  @override
  final String name = 'updates';

  @override
  final String description = 'Manage Over-The-Air (OTA) updates.';

  UpdatesCommand() {
    addSubcommand(UpdatesReleaseCommand());
    addSubcommand(UpdatesPatchCommand());
    addSubcommand(UpdatesRollbackCommand());
    addSubcommand(UpdatesPushCommand());
  }
}

class UpdatesReleaseCommand extends _ShorebirdPlatformsCommand {
  @override
  final String name = 'release';

  @override
  final String description = 'Create Shorebird releases for target platforms.';

  UpdatesReleaseCommand() : super(action: 'release');
}

class UpdatesPatchCommand extends _ShorebirdPlatformsCommand {
  @override
  final String name = 'patch';

  @override
  final String description = 'Create Shorebird patches for target platforms.';

  UpdatesPatchCommand() : super(action: 'patch') {
    argParser.addOption(
      'release-version',
      help: 'Existing release version to patch.',
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
}

class UpdatesPushCommand extends UpdatesPatchCommand {
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

  UpdatesRollbackCommand() {
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
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        help: 'Print the Shorebird command without executing it.',
      );
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
    await _runShorebird(
      args,
      dryRun: argResults?['dry-run'] == true,
    );
  }
}

abstract class _ShorebirdPlatformsCommand extends Command<void> {
  final String action;

  _ShorebirdPlatformsCommand({required this.action}) {
    argParser
      ..addMultiOption(
        'platform',
        abbr: 'p',
        defaultsTo: const <String>['android', 'ios'],
        allowed: const <String>['android', 'ios'],
        help: 'Target platform. Repeat to run multiple platforms.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        help: 'Print Shorebird commands without executing them.',
      );
  }

  List<String> argsForPlatform(String platform) => <String>[action, platform];

  @override
  Future<void> run() async {
    final platforms =
        argResults?['platform'] as List<String>? ?? const <String>[];
    if (platforms.isEmpty) {
      throw UsageException('At least one --platform is required.', usage);
    }
    for (final platform in platforms) {
      await _runShorebird(
        argsForPlatform(platform),
        dryRun: argResults?['dry-run'] == true,
      );
    }
  }
}

Future<void> _runShorebird(
  List<String> args, {
  required bool dryRun,
}) async {
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
