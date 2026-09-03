/// `dartvel capture pwa-sync --web build/web`: run the generated worker's
/// outbox in a real browser and fail unless a POST made offline is queued
/// and replayed once the network is back.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../build/pwa_sync_verification.dart';
import '../utils/logger.dart';

class PwaSyncCaptureCommand extends Command<void> {
  @override
  final String name = 'pwa-sync';

  @override
  final String description =
      'Fail unless a POST made offline is queued by the worker and replayed once online, in a real browser.';

  @override
  String get invocation => 'dartvel capture pwa-sync --web build/web';

  PwaSyncCaptureCommand() {
    argParser
      ..addOption('web', defaultsTo: 'build/web', help: 'The built web output, with its sw.js.')
      ..addOption('chrome', help: 'The browser to run. Defaults to DARTVEL_CHROME or a system Chrome.')
      ..addFlag('allow-skip',
          defaultsTo: false,
          help: 'Exit 0 when no browser can be launched, instead of failing. For machines that never had one.');
  }

  @override
  Future<void> run() async {
    final String web = argResults!['web'] as String;
    if (!File('$web/sw.js').existsSync()) {
      usageException('$web has no sw.js; build the web target first.');
    }
    final DVPwaSyncResult result = await dvVerifyPwaSync(
      webRoot: web,
      chromePath: argResults!['chrome'] as String?,
    );
    Logger.log('pwa-sync: ${result.summary}');
    if (result.skipped != null) {
      if (argResults!['allow-skip'] == true) return;
      usageException('pwa-sync could not run: ${result.skipped}');
    }
    if (!result.ok) usageException('pwa-sync failed: ${result.summary}');
  }
}
