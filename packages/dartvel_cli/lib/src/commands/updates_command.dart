import 'dart:io';
import 'package:args/command_runner.dart';
import '../utils/logger.dart';

class UpdatesCommand extends Command<void> {
  @override
  final String name = 'updates';

  @override
  final String description = 'Manage Over-The-Air (OTA) updates.';

  UpdatesCommand() {
    addSubcommand(UpdatesPushCommand());
  }
}

class UpdatesPushCommand extends Command<void> {
  @override
  final String name = 'push';

  @override
  final String description = 'Push a new update to devices via Shorebird.';

  @override
  Future<void> run() async {
    Logger.log('Checking for Shorebird...');
    final check = await Process.run('shorebird', ['--version']);
    if (check.exitCode != 0) {
      Logger.error(
          'Shorebird CLI not found. Please install it first: https://shorebird.dev');
      exit(1);
    }

    Logger.log('Pushing update to Android...');
    final android = await Process.start('shorebird', ['patch', 'android']);
    await stdout.addStream(android.stdout);
    await stderr.addStream(android.stderr);
    final androidExit = await android.exitCode;
    if (androidExit != 0) {
      Logger.error('Failed to patch Android.');
    }

    Logger.log('Pushing update to iOS...');
    final ios = await Process.start('shorebird', ['patch', 'ios']);
    await stdout.addStream(ios.stdout);
    await stderr.addStream(ios.stderr);
    final iosExit = await ios.exitCode;
    if (iosExit != 0) {
      Logger.error('Failed to patch iOS.');
    }

    if (androidExit == 0 && iosExit == 0) {
      Logger.log('Updates pushed successfully!');
    }
  }
}
