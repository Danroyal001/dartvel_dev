/// `dartvel capture pages --web build/web`: photograph every page in the
/// build's sitemap at each size, and fail on a page that showed no text.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../build/page_shots.dart';
import '../utils/logger.dart';

class PageShotsCaptureCommand extends Command<void> {
  @override
  final String name = 'pages';

  @override
  final String description =
      'Photograph every page in a web build\'s sitemap at each size, in a real browser, and fail on a page that shows no text.';

  @override
  String get invocation =>
      'dartvel capture pages --web build/web --out build/shots';

  PageShotsCaptureCommand() {
    argParser
      ..addOption('web', defaultsTo: 'build/web', help: 'The built web output, with its sitemap.xml.')
      ..addOption('out', defaultsTo: 'build/shots', help: 'Where the screenshots are written.')
      ..addOption('sizes',
          defaultsTo: '1440x900,390x844',
          help: 'Viewports as WIDTHxHEIGHT, comma separated.')
      ..addOption('routes', help: 'Paths to photograph, comma separated. Defaults to every page in sitemap.xml.')
      ..addOption('chrome', help: 'The browser to run. Defaults to DARTVEL_CHROME or a system Chrome.')
      ..addFlag('allow-skip',
          defaultsTo: false,
          help: 'Exit 0 when no browser can be launched, instead of failing.');
  }

  @override
  Future<void> run() async {
    final String web = argResults!['web'] as String;
    if (!File(p.join(web, 'index.html')).existsSync()) {
      usageException('$web has no index.html; build the web target first.');
    }
    final List<DVShotSize> sizes;
    try {
      sizes = dvParseShotSizes(argResults!['sizes'] as String);
    } on FormatException catch (error) {
      usageException('--sizes: ${error.message} (got ${error.source})');
    }
    final String? listed = argResults!['routes'] as String?;
    final File sitemap = File(p.join(web, 'sitemap.xml'));
    final List<String> routes = listed != null
        ? <String>[
            for (final String route in listed.split(','))
              if (route.trim().isNotEmpty) route.trim(),
          ]
        : dvSitemapRoutes(sitemap.existsSync() ? sitemap.readAsStringSync() : '');

    final DVPageShotsResult result = await dvCapturePages(
      webRoot: web,
      outDir: argResults!['out'] as String,
      routes: routes,
      sizes: sizes,
      chromePath: argResults!['chrome'] as String?,
    );
    if (result.skipped != null) {
      if (argResults!['allow-skip'] == true) {
        Logger.log('pages: skipped, ${result.skipped}');
        return;
      }
      usageException('pages could not run: ${result.skipped}');
    }
    for (final DVPageShot shot in result.shots) {
      Logger.log('${shot.ok ? 'ok  ' : 'FAIL'} ${shot.size} ${shot.route} '
          '(${shot.textLength} characters) ${shot.file}');
    }
    Logger.log('pages: ${result.shots.length} screenshots of ${routes.length} '
        'routes at ${sizes.length} sizes, ${result.failures.length} showed no text');
    if (result.failures.isNotEmpty) {
      throw UsageException(
          '${result.failures.length} page(s) showed no text: '
          '${result.failures.map((DVPageShot s) => '${s.route} at ${s.size}').join(', ')}',
          usage);
    }
  }
}
