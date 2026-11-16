import 'package:args/command_runner.dart';

import '../utils/logger.dart';

/// `dartvel prerender` -- the build's own capture, by its old name.
///
/// Capturing each route's document in Chrome, and writing sitemap.xml and
/// robots.txt from the project's declarations, are steps of `dartvel build
/// web`. This command used to be a second pipeline: its own server, an older
/// semantics walker that lost headings inside landmarks and captured guarded
/// routes, written over the build's capture files, and its own sitemap and
/// robots naming `http://localhost:8080` unless told otherwise. It now runs
/// the build and writes nothing of its own.
class PrerenderCommand extends Command<void> {
  PrerenderCommand() {
    // Kept so a script that passes them still runs; none is used.
    argParser
      ..addOption('port', abbr: 'p', hide: true)
      ..addOption('output', abbr: 'o', hide: true)
      ..addOption('base-url', hide: true);
  }

  @override
  final String name = 'prerender';

  @override
  final String description =
      'Capture every route for crawlers and no-script readers '
      '(the same capture `dartvel build web` runs).';

  @override
  Future<void> run() async {
    for (final String old in <String>['port', 'output', 'base-url']) {
      if (argResults?.wasParsed(old) ?? false) {
        Logger.log('   --$old is not used: the capture is the build\'s, and the '
            'sitemap and robots.txt take the site URL from dartvel.seo.siteUrl.');
      }
    }
    Logger.log('🕷️  Prerendering is part of `dartvel build web`; running it.');
    await runner!.run(<String>['build', 'web']);
  }
}
