/// `dartvel capture pages`: every page in a web build's sitemap, photographed
/// in a real browser at each size asked for.
///
/// A page is photographed once its Flutter view has drawn text, not on a
/// timer: Chrome's own --screenshot fires when its virtual time runs out, and
/// on a slow runner that caught pages with their backgrounds drawn and their
/// text not yet painted. Dartvel turns semantics on, so the text a page shows
/// is in the DOM to wait for; a page that never shows any is a failure.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'chrome_launch.dart';
import 'semantics_capture.dart' show dvCaptureHandler;

/// A viewport, in logical pixels.
class DVShotSize {
  const DVShotSize(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is DVShotSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// `1440x900,390x844` as sizes. A size that does not parse is refused: a
/// typo that quietly dropped the phone width would pass every check.
List<DVShotSize> dvParseShotSizes(String flag) {
  final List<DVShotSize> sizes = <DVShotSize>[];
  for (final String part in flag.split(',')) {
    final String text = part.trim();
    if (text.isEmpty) continue;
    final RegExpMatch? match = RegExp(r'^(\d+)x(\d+)$').firstMatch(text);
    if (match == null) {
      throw FormatException('A size is WIDTHxHEIGHT, such as 390x844', text);
    }
    sizes.add(DVShotSize(int.parse(match[1]!), int.parse(match[2]!)));
  }
  return sizes;
}

/// The paths a sitemap lists, in order and once each; `/` when it lists
/// none, since every site has a home page.
List<String> dvSitemapRoutes(String xml) {
  final List<String> routes = <String>[];
  for (final RegExpMatch match
      in RegExp(r'<loc>\s*([^<\s]+)\s*</loc>').allMatches(xml)) {
    final Uri uri = Uri.parse(match[1]!);
    final String path = uri.path.isEmpty ? '/' : uri.path;
    if (!routes.contains(path)) routes.add(path);
  }
  return routes.isEmpty ? <String>['/'] : routes;
}

/// `docs_ai-390x844.png` for `/docs/ai` at 390 by 844.
String dvShotName(String route, DVShotSize size) {
  final String trimmed = route.replaceAll(RegExp(r'^/+|/+$'), '');
  final String name = trimmed.isEmpty ? 'home' : trimmed.replaceAll('/', '_');
  return '$name-$size.png';
}

/// Whether a page's text has stopped changing: the same non-zero length
/// three looks running. A shell that draws its navigation before the page
/// it loads has text long before it has its content.
class DVTextSettle {
  int _lastLength = -1;
  int _lastResources = -1;
  int _same = 0;

  /// Records one look at the page: how much text it shows, and how many
  /// resources it has fetched.
  ///
  /// True once both have held still for three looks. Text alone is not
  /// enough. Every page is a deferred library, so the docs shell draws its
  /// sidebar from the first chunk and the article arrives in a second one:
  /// the text stands at the sidebar's length for longer than three looks
  /// while that chunk is still on its way, and a capture that trusted it
  /// photographed the shell. The resource count is the part that is still
  /// moving while that happens.
  bool add(int length, [int resources = 0]) {
    if (length > 0 && length == _lastLength && resources == _lastResources) {
      _same++;
    } else {
      _same = 1;
    }
    _lastLength = length;
    _lastResources = resources;
    return length > 0 && _same >= 3;
  }
}

/// One photographed page.
class DVPageShot {
  const DVPageShot({
    required this.route,
    required this.size,
    required this.file,
    required this.textLength,
  });

  final String route;
  final DVShotSize size;
  final String file;

  /// How much text the page showed; nought is a page that did not render.
  final int textLength;

  bool get ok => textLength > 0;
}

/// Every page at every size, or why it could not run.
class DVPageShotsResult {
  const DVPageShotsResult({this.shots = const <DVPageShot>[], this.skipped});

  final List<DVPageShot> shots;

  /// Set when no browser could be launched.
  final String? skipped;

  List<DVPageShot> get failures =>
      <DVPageShot>[for (final DVPageShot shot in shots) if (!shot.ok) shot];
}

/// The text Flutter's semantics tree shows, which is empty until the first
/// frame with text in it has been drawn.
const String _pageText = '''() => {
  const host = document.querySelector('flt-semantics-host');
  return host ? (host.innerText || '').trim().length : 0;
}''';

/// How many resources the page has fetched.
///
/// A page that is still pulling its own deferred chunk is still moving, even
/// when the text on screen has stopped, and this is the part that says so.
/// Counted rather than timed, so a fast machine waits less and a slow one
/// waits as long as it needs to.
const String _pageResources = '''() => {
  try {
    return performance.getEntriesByType('resource').length;
  } catch (e) {
    return 0;
  }
}''';
/// Photographs [routes] from the build in [webRoot] at each of [sizes] into
/// [outDir].
Future<DVPageShotsResult> dvCapturePages({
  required String webRoot,
  required String outDir,
  required List<String> routes,
  required List<DVShotSize> sizes,
  String? chromePath,
  Duration settle = const Duration(seconds: 30),
  Duration afterText = const Duration(milliseconds: 1500),
}) async {
  Browser browser;
  try {
    browser = await puppeteer.launch(
      headless: true,
      executablePath: chromePath ?? await dvChromeExecutable(),
      args: dvChromeLaunchArgs,
    );
  } on Object catch (error) {
    return DVPageShotsResult(skipped: 'no browser to photograph in ($error)');
  }
  final HttpServer server = await shelf_io.serve(
    dvCaptureHandler(webRoot),
    InternetAddress.loopbackIPv4,
    0,
  );
  final String base = 'http://${server.address.host}:${server.port}';
  Directory(outDir).createSync(recursive: true);

  final List<DVPageShot> shots = <DVPageShot>[];
  try {
    for (final DVShotSize size in sizes) {
      for (final String route in routes) {
        final Page page = await browser.newPage();
        try {
          await page.setViewport(
              DeviceViewport(width: size.width, height: size.height));
          await page.goto('$base$route',
              wait: Until.networkIdle, timeout: const Duration(seconds: 90));
          // Polled rather than slept: a page ready early costs nothing, and
          // one that never shows text is reported rather than photographed
          // blank and passed.
          int text = 0;
          final DVTextSettle settled = DVTextSettle();
          final DateTime deadline = DateTime.now().add(settle);
          while (DateTime.now().isBefore(deadline)) {
            text = await page.evaluate<int>(_pageText);
            final int resources = await page.evaluate<int>(_pageResources);
            if (settled.add(text, resources)) break;
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          // Fonts and images arrive after the first frame with text in it.
          await page.evaluate<Object?>(
              '() => document.fonts ? document.fonts.ready.then(() => 0) : 0');
          await Future<void>.delayed(afterText);
          final String file = p.join(outDir, dvShotName(route, size));
          File(file).writeAsBytesSync(await page.screenshot());
          shots.add(DVPageShot(
              route: route, size: size, file: file, textLength: text));
        } finally {
          await page.close();
        }
      }
    }
  } finally {
    await server.close(force: true);
    await browser.close();
  }
  return DVPageShotsResult(shots: shots);
}
