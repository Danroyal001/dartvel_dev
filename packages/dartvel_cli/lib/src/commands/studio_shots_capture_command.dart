import 'dart:io';

import 'package:args/command_runner.dart';

import '../build/page_shots.dart' show DVShotSize, dvParseShotSizes;
import '../build/studio_shots.dart';
import '../utils/logger.dart';

/// `dartvel capture studio` — a picture of every section of a running Studio.
///
/// The site showed five Studio screenshots and Studio has a dozen sections,
/// so somebody deciding whether to use it could see the page builder and had
/// to take the rest on trust. Captured by hand, they also went stale twice; a
/// command means a section added today is photographed today.
class StudioShotsCaptureCommand extends Command<void> {
  @override
  final String name = 'studio';

  @override
  final String description =
      "Photograph every section of a running Studio, and fail on one that "
      'renders nothing.';

  @override
  String get invocation =>
      'dartvel capture studio --url http://127.0.0.1:8080/__studio/';

  StudioShotsCaptureCommand() {
    argParser
      ..addOption('url',
          defaultsTo: 'http://127.0.0.1:8080/__studio/',
          help: 'Where the running Studio is.')
      ..addOption('out',
          defaultsTo: 'build/studio-shots',
          help: 'Where the screenshots are written.')
      ..addOption('sections',
          defaultsTo: 'Pages,Data,Site map,Frontend,Backend,Modules,Tasks,'
              'Queue,Cache,Team,Flags,Operations',
          help: 'The rail labels to photograph, comma separated. One that is '
              'not on this rail is skipped.')
      ..addOption('size',
          defaultsTo: '1440x900', help: 'The viewport, as WIDTHxHEIGHT.')
      ..addOption('sign-in',
          help: 'The sign-in endpoint, e.g. http://127.0.0.1:8080/api/auth/'
              'sign-in. Studio answers somebody who may not open it exactly '
              'as it answers a route that does not exist, so without this a '
              'capture photographs a 404.')
      ..addOption('email', help: 'The account to sign in as.')
      ..addOption('password', help: 'Its password.')
      ..addOption('chrome',
          help: 'The browser to run. Defaults to DARTVEL_CHROME or a system '
              'Chrome.')
      ..addFlag('allow-skip',
          defaultsTo: false,
          help: 'Exit 0 when no browser can be launched, instead of failing.');
  }

  @override
  Future<void> run() async {
    final List<DVShotSize> sizes;
    try {
      sizes = dvParseShotSizes(argResults!['size'] as String);
    } on FormatException catch (error) {
      usageException('--size: ${error.message} (got ${error.source})');
    }
    if (sizes.length != 1) usageException('--size takes one viewport.');

    final String? email = argResults!['email'] as String?;
    final String? password = argResults!['password'] as String?;
    final String? signIn = argResults!['sign-in'] as String?;
    if ((email == null) != (password == null)) {
      usageException('--email and --password go together.');
    }
    if (email != null && signIn == null) {
      usageException('--email needs --sign-in, which is where to post it.');
    }

    final DVStudioShotsResult result = await dvCaptureStudio(
      studio: Uri.parse(argResults!['url'] as String),
      outDir: argResults!['out'] as String,
      sections: <String>[
        for (final String label in (argResults!['sections'] as String).split(','))
          if (label.trim().isNotEmpty) label.trim(),
      ],
      signIn: signIn == null ? null : Uri.parse(signIn),
      email: email,
      password: password,
      size: sizes.single,
      chromePath: argResults!['chrome'] as String?,
    );

    if (result.skipped != null) {
      if (argResults!['allow-skip'] == true) {
        Logger.log('studio: skipped, ${result.skipped}');
        return;
      }
      usageException('studio could not run: ${result.skipped}');
    }
    for (final DVStudioShot shot in result.shots) {
      Logger.log('   ${shot.ok ? '✓' : '✗'} ${shot.label} -> ${shot.file} '
          '(${shot.textLength} characters)');
    }
    if (!result.ok) {
      final String blank = result.failures
          .map((DVStudioShot shot) => shot.label)
          .join(', ');
      stderr.writeln(result.shots.isEmpty
          ? 'studio: photographed no section at all'
          : 'studio: these sections rendered nothing: $blank');
      exitCode = 1;
      return;
    }
    Logger.log('studio: ${result.shots.length} section(s) photographed.');
  }
}
