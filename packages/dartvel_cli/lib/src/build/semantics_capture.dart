/// Capturing each route's semantics tree, so the crawler-visible HTML is
/// built from what the application declares.
library dartvel_cli.build.semantics_capture;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/protocol/target.dart' show TargetID;
import 'package:puppeteer/puppeteer.dart';
// Prefixed: puppeteer exports its own Request and Response, and importing
// both unprefixed makes every use of either ambiguous.
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import 'page_shots.dart' show DVInFlight, DVTextSettle;

import '../utils/logger.dart';
import 'chrome_launch.dart';
import 'capture_completeness.dart';
import 'route_prefetch.dart';

/// Walks `flt-semantics-host` and reports the structure, not Flutter's DOM.
///
/// Taking the host's innerHTML whole gives `<flt-semantics>` elements carrying
/// inline transforms and pixel sizes — a wall of positioned divs rather than a
/// document. What comes out here is role, heading level, label, destination
/// and children.
const String _extract = r"""() => {
  const host = document.querySelector('flt-semantics-host');
  if (!host) return '[]';

  const labelOf = (el) => {
    const aria = el.getAttribute('aria-label');
    if (aria) return aria;
    // This element's own text, not its descendants'.
    let text = '';
    for (const child of el.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) text += child.textContent;
      else if (child.tagName === 'SPAN') text += child.textContent;
    }
    return text.trim();
  };

  const walk = (el) => {
    const out = [];
    for (const child of el.children) {
      const tag = child.tagName.toLowerCase();
      if (tag === 'flt-semantics-scroll-overflow') continue;
      // Flutter emits a heading as a real h1..h6 element rather than as
      // role="heading", so the tag carries the level. A walker that accepted
      // only <a> and <flt-semantics> skipped every heading on the page.
      const heading = /^h([1-6])$/.exec(tag);
      // Anything else is a wrapper: Flutter puts an app bar's title in a <header>
      // landmark, and a heading inside it is the page's level 1. Its contents
      // are walked as if they sat here; the wrapper adds no node of its own.
      if (tag !== 'a' && tag !== 'flt-semantics' && !heading) {
        out.push(...walk(child));
        continue;
      }
      const aria = child.getAttribute('aria-level');
      // A Dartvel role travels as the node's identifier, because Flutter's
      // Semantics has no role for code and SelectableText would otherwise be
      // a textarea with no readable content at all.
      const identifier = child.getAttribute('flt-semantics-identifier') || '';
      let declared = identifier.startsWith('dartvel:')
        ? identifier.slice('dartvel:'.length)
        : null;
      // A player or camera box says what it plays after a bar:
      // `dartvel:video|{"src":...}`. Flutter's semantics has no source, so
      // without this the document could only say "Video player".
      let media = null;
      if (declared && declared.indexOf('|') >= 0) {
        const bar = declared.indexOf('|');
        try { media = JSON.parse(declared.slice(bar + 1)); } catch (e) {}
        declared = declared.slice(0, bar);
      }
      // A text field: Flutter puts a real <input> (or <textarea>) inside the
      // node, named by its own aria-label. Skipping it, as the walk did, left
      // every form out of the document -- a sign-in page went out as its
      // heading and nothing else.
      const field = tag === 'flt-semantics'
        ? child.querySelector(':scope > input, :scope > textarea')
        : null;
      const node = {
        role: field ? 'textbox'
              : declared || child.getAttribute('role')
              || (tag === 'a' ? 'link' : null),
        field: field
          ? (field.tagName === 'TEXTAREA' ? 'textarea'
             : (field.getAttribute('type') || 'text'))
          : null,
        level: heading ? parseInt(heading[1], 10)
                       : (aria ? parseInt(aria, 10) : null),
        label: field
          ? (field.getAttribute('aria-label') || labelOf(child))
          : labelOf(child),
        href: child.getAttribute('href'),
        media: media,
        children: walk(child),
      };
      // Nothing to say, nowhere to go, nothing inside.
      if (!node.label && !node.href && !node.media
          && node.children.length === 0) continue;
      out.push(node);
    }
    return out;
  };

  return JSON.stringify(walk(host));
}""";

/// [_extract], exported for the tests that run it in a browser on Flutter-shaped markup.
const String dvSemanticsExtractScript = _extract;

/// Where a route's captured tree is written.
String dvSemanticsPathFor(String projectRoot, String route) {
  final String name = route == '/'
      ? 'index'
      : route.replaceAll(RegExp(r'^/|/$'), '').replaceAll('/', '_');
  return p.join(projectRoot, '.dart_tool', 'dartvel_semantics', '$name.json');
}

/// Deletes what an earlier build captured for each of the [guarded] routes,
/// and returns the files it removed.
///
/// A guarded route is not captured -- the capturing browser has no session,
/// so it would capture the sign-in page -- but a capture from before the route
/// was guarded stayed on disk, and every later build rendered it into the
/// page and the server's manifest: a signed-in reader was sent the screen as
/// it looked on that old build, numbers and all.
List<String> dvForgetGuardedCaptures(String projectRoot, Iterable<String> guarded) {
  final List<String> removed = <String>[];
  for (final String route in guarded) {
    final String tree = dvSemanticsPathFor(projectRoot, route);
    for (final String path in <String>[tree, tree.replaceFirst(RegExp(r'\.json$'), '.images.json')]) {
      final File file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
        removed.add(p.relative(path, from: projectRoot));
      }
    }
  }
  return removed;
}

/// Capture [routes] from the build in [webRoot], writing one JSON tree each.
///
/// Returns the number of routes that produced a tree. Zero means the caller
/// should fall back to the source-literal extractor rather than ship pages
/// with no crawler-visible content at all — which is what a build on a
/// machine with no browser must still do.
/// Serves a built web directory the way the application's own router expects.
///
/// Single-page fallback, and it is the reason the capture works at all. After
/// `flutter build web` the directory holds one index.html at the root and
/// nothing else: the per-route index.html files are written later, out of this
/// very capture. A plain static handler therefore answers 404 for every route
/// but `/`, the application never boots on those pages, no semantics tree is
/// built, and the capture reports "1 of 4".
///
/// The fallback is limited to paths with no file extension. Routes have none
/// and assets do, and answering a missing `main.dart.js` with HTML would fail
/// as though the file were corrupt rather than absent -- Flutter's loader
/// hangs on that instead of reporting it.
shelf.Handler dvCaptureHandler(String webRoot) {
  final shelf.Handler static = createStaticHandler(
    webRoot,
    defaultDocument: 'index.html',
  );

  return (shelf.Request request) async {
    // The capture measures what a page asks for by itself. The last
    // build's manifest would have each page prefetch what its links need,
    // and those requests would be recorded as the page's own -- growing the
    // manifest, and every page's preloads, on every rebuild in one tree.
    if (request.url.path == dvPrefetchManifestFile ||
        request.url.path.endsWith('/$dvPrefetchManifestFile')) {
      return shelf.Response.notFound('');
    }
    final shelf.Response response = await static(request);
    if (response.statusCode != 404) return response;

    final String path = request.url.path;
    final String last = path.contains('/') ? path.split('/').last : path;
    if (last.contains('.')) return response;

    return static(
      shelf.Request('GET', request.requestedUri.replace(path: '/')),
    );
  };
}

/// How many routes the semantics read keeps open at once.
///
/// Most of a route's read is waiting -- for the app to boot, for its deferred
/// page to arrive, for the tree to hold still -- so one page at a time leaves
/// the machine idle; a site of two hundred routes took most of an hour. Each
/// open page is a Flutter app drawing in software, so the count follows the
/// cores, leaves a quarter of them for the browser and everything else, and
/// stops at eight,
/// past which pages only slow each other down. [requested] (the build's
/// `--capture-jobs`) overrides it.
int dvCaptureConcurrency({required int processors, String? requested}) {
  if (requested != null) {
    final int? count = int.tryParse(requested.trim());
    if (count == null || count < 1) {
      throw FormatException(
          '--capture-jobs is a number of pages to read at once, such as 4; '
          'got "$requested".');
    }
    return count;
  }
  return (processors * 3 ~/ 4).clamp(1, 8);
}

/// Runs [read] on each of [items], up to [concurrency] at once, and counts
/// the items it returned true for.
///
/// Each call is told which of the [concurrency] slots it runs in, so a slot
/// can keep what it set up (a booted app) for its next item.
///
/// Each item's work writes its own files, so the order the pages finish in
/// changes nothing that is written. The first error stops new items from
/// starting, waits for the ones under way, and is rethrown: the same build
/// failure the one-at-a-time loop gave.
Future<int> dvReadEach<T>(
  List<T> items,
  Future<bool> Function(T item, int slot) read, {
  required int concurrency,
}) async {
  int next = 0;
  int counted = 0;
  Object? failure;
  StackTrace? failureTrace;
  Future<void> worker(int slot) async {
    while (failure == null && next < items.length) {
      final T item = items[next++];
      try {
        if (await read(item, slot)) counted++;
      } on Object catch (error, trace) {
        failure ??= error;
        failureTrace ??= trace;
      }
    }
  }

  await Future.wait(<Future<void>>[
    for (int slot = 0; slot < concurrency.clamp(1, items.isEmpty ? 1 : items.length); slot++)
      worker(slot),
  ]);
  if (failure != null) Error.throwWithStackTrace(failure!, failureTrace!);
  return counted;
}

Future<DVCaptureRun> dvCaptureSemantics({
  required String projectRoot,
  required String webRoot,
  required List<String> routes,
  Duration settle = const Duration(seconds: 20),
  int? concurrency,
  bool inApp = true,
}) async {
  if (routes.isEmpty) {
    return const DVCaptureRun(captured: 0, browserAvailable: true);
  }

  Browser? browser;
  try {
    browser = await puppeteer.launch(
      headless: true,
      // The browser this machine already has, or the one copy shared by
      // every project on it. Left to itself puppeteer downloads into this
      // workspace's .dart_tool, once per project -- see dvChromeExecutable.
      executablePath: await dvChromeExecutable(),
      args: dvChromeLaunchArgs,
    );
  } on Object catch (error) {
    // A build without a browser is a normal thing, not a failure. Said out
    // loud, because silently shipping the weaker content is how nobody
    // notices the pages got worse.
    Logger.log('   No browser for the semantics capture ($error).');
    Logger.log('   Falling back to page text; run `dartvel prerender` on a '
        'machine with Chrome for headings, links and landmarks.');
    // Said out loud and then honoured. This used to promise a fallback and
    // then fail the build anyway, which made the message a lie on every
    // machine without Chrome.
    return const DVCaptureRun(captured: 0, browserAvailable: false);
  }

  final HttpServer server = await shelf_io.serve(
    dvCaptureHandler(webRoot),
    InternetAddress.loopbackIPv4,
    0,
  );
  final String base = 'http://${server.address.host}:${server.port}';

  var captured = 0;
  try {
    Directory(p.join(projectRoot, '.dart_tool', 'dartvel_semantics'))
        .createSync(recursive: true);

    final Browser chrome = browser;
    // A route is moved to inside an app a tab has already booted, when the
    // app has the capture hook.
    final bool reuse = inApp;
    final int slots = concurrency ??
        dvCaptureConcurrency(processors: Platform.numberOfProcessors);
    final List<_CaptureTab?> tabs = List<_CaptureTab?>.filled(slots, null);

    /// Reads one route, in the app [slot]'s tab is running when it can move
    /// there and in a fresh load otherwise, and says whether it drew a tree.
    Future<bool> readRoute(String route, int slot) async {
      _CaptureTab? tab = reuse ? tabs[slot] : null;
      if (tab != null && !await tab.moveTo(route)) {
        // No hook, or the router went somewhere else: a redirect, which a
        // fresh load reads as a visitor arriving there would see it.
        await tab.close();
        tab = null;
      }
      final bool fresh = tab == null;
      tab ??= await _CaptureTab.open(chrome, base);
      if (reuse) tabs[slot] = tab;
      final Page page = tab.page;
      bool drew = false;
      try {
        if (fresh) await tab.load(route);

        // Polled rather than slept: a page that is ready early should not
        // cost the whole budget, and one that never builds a tree has to be
        // reported rather than written out empty.
        //
        // Stopping at the first tree that is not empty is what this used to
        // do, and it is why every page on the site shipped six words to a
        // crawler. The docs shell draws first and its scroll button is a
        // node, so the loop broke on a tree holding "To the bottom" while
        // the article was still in a chunk on its way. The tree has to stop
        // growing, and the page has to have stopped asking for things.
        String tree = '[]';
        final DVTextSettle settled = DVTextSettle();
        final DateTime deadline = DateTime.now().add(settle);
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          tree = await page.evaluate<String>(_extract);
          final int resources = await page.evaluate<int>(_resourceCount);
          if (!tab.flight.busy &&
              settled.add(tree == '[]' ? 0 : tree.length, resources)) {
            break;
          }
        }

        File(dvSemanticsPathFor(projectRoot, route)).writeAsStringSync(tree);
        // Each image's slot, as DVImageView wrote it into the page while it
        // laid out. A request for the 384-wide file says only that the slot
        // was somewhere under 384; a link choosing the file for a denser
        // screen needs the slot itself.
        final Map<String, double> imageSlots = dvImageSlotsFrom(
          await page.evaluate<String>(
              '() => JSON.stringify(globalThis.__dartvelImages || {})'),
        );
        File(dvCapturedImagesPathFor(projectRoot, route)).writeAsStringSync(
          jsonEncode(<Object?>[
            for (final DVCapturedImage image
                in dvAttachImageSlots(tab.images, imageSlots))
              image.toJson(),
          ]),
        );
        final int nodes = (jsonDecode(tree) as List<Object?>).length;
        drew = nodes > 0;
      } finally {
        if (!reuse) await tab.close();
      }
      return drew;
    }

    try {
      captured = await dvReadEach<String>(routes, readRoute, concurrency: slots);
    } finally {
      for (final _CaptureTab? tab in tabs) {
        await tab?.close();
      }
    }
  } finally {
    await server.close(force: true);
    await browser.close();
  }

  // Deleting a stale tree matters more than writing a fresh one: a route that
  // stops rendering would otherwise keep publishing the content it had the
  // last time it worked.
  for (final String route in routes) {
    final File file = File(dvSemanticsPathFor(projectRoot, route));
    if (file.existsSync() && file.readAsStringSync().trim() == '[]') {
      file.deleteSync();
      // And its images with it: a page that did not render painted nothing,
      // and the list from the last build that did would be preloaded on a
      // page that no longer shows those images.
      final File images = File(dvCapturedImagesPathFor(projectRoot, route));
      if (images.existsSync()) images.deleteSync();
    }
  }

  return DVCaptureRun(captured: captured, browserAvailable: true);
}

/// Run in every captured page before it loads: tells the app it is being
/// captured, so its lazy lists build every row (dartvel_flutter DVLazyLists).
const String dvCaptureMarkScript = 'window.__dvCapture = true;';

/// One browser tab the semantics read works in: its page, the images the
/// page has asked for since the route it is on began, and its requests in
/// flight.
class _CaptureTab {
  _CaptureTab._(this.page, this.base);

  final Page page;
  final String base;

  /// The images the page asked for while it rendered the current route, for
  /// its own head and for the links that point at it to fetch early.
  final List<DVCapturedImage> images = <DVCapturedImage>[];
  final DVInFlight flight = DVInFlight();
  final List<StreamSubscription<Object?>> _listening =
      <StreamSubscription<Object?>>[];
  bool _closed = false;

  /// A new page, listening before any navigation, because the first frame's
  /// images are requested during it.
  ///
  /// In a window of its own. Flutter draws in animation frames, and a browser
  /// runs those only for the page a window shows: every other tab of the
  /// window is hidden and never draws, so with several tabs in one window
  /// most routes of a real app were read as empty.
  static Future<_CaptureTab> open(Browser browser, String base) async {
    final TargetID id = await browser.connection.targetApi
        .createTarget('about:blank', newWindow: true);
    final Target target =
        await browser.waitForTarget((Target candidate) => candidate.targetID == id);
    final _CaptureTab tab = _CaptureTab._(await target.page, base);
    // Before the app starts: every DVBox list builds whole while the page is
    // captured, so the HTML carries the rows a lazy list would not have
    // built (dartvel_flutter DVLazyLists).
    await tab.page.evaluateOnNewDocument(dvCaptureMarkScript);
    tab._listening.addAll(<StreamSubscription<Object?>>[
      tab.page.onResponse.listen((Response response) {
        final DVCapturedImage? image = dvPageImage(
          url: response.url,
          base: base,
          contentType: _header(response.headers, 'content-type'),
          resourceType: response.request.resourceType?.value ?? '',
        );
        if (image != null &&
            !tab.images.any((DVCapturedImage seen) => seen.url == image.url)) {
          tab.images.add(image);
        }
      }),
      tab.page.onRequest.listen((Object? _) => tab.flight.started()),
      tab.page.onRequestFinished.listen((Object? _) => tab.flight.ended()),
      tab.page.onRequestFailed.listen((Object? _) => tab.flight.ended()),
    ]);
    return tab;
  }

  /// Loads [route] afresh: the app boots.
  Future<void> load(String route) async {
    images.clear();
    // A generous timeout, and a second try: on a machine under load the
    // default 30 seconds failed whole builds on one slow first paint.
    for (int attempt = 1; ; attempt++) {
      try {
        await page.goto('$base$route',
            wait: Until.networkIdle, timeout: const Duration(seconds: 120));
        break;
      } on TimeoutException {
        if (attempt >= 3) rethrow;
      }
    }

    // Flutter web builds no semantics tree until something asks for one.
    // It renders a hidden placeholder labelled "Enable accessibility" and
    // waits for a screen reader to click it, so a capture that skips this
    // reads a host holding almost nothing -- which is why every page on
    // the site shipped its scroll button and none of its prose to a
    // crawler. The studio capture has always clicked it; this one never
    // did.
    final DateTime enableBy = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(enableBy)) {
      if (await page.evaluate<bool>(_enableSemantics)) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Moves the app already running here to [route] through its capture hook
  /// (dartvel_flutter's `dvInstallCaptureHook`), the way a link does: no
  /// second boot. The hook forgets the images the app decoded, so the route
  /// asks for its own and they are recorded as a fresh load records them.
  ///
  /// False when the app has no hook, or the router did not arrive at
  /// [route] -- a redirect -- and the route is to be loaded afresh.
  Future<bool> moveTo(String route) async {
    if (!await page.evaluate<bool>(
        '() => typeof globalThis.__dartvelCapture === "object"')) {
      return false;
    }
    final String from =
        await page.evaluate<String>('() => globalThis.__dartvelCapture.location()');
    images.clear();
    await page.evaluate<Object?>(
        '(path) => { globalThis.__dartvelCapture.go(path); }',
        args: <Object?>[route]);
    final DateTime giveUp = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(giveUp)) {
      final String at = await page
          .evaluate<String>('() => globalThis.__dartvelCapture.location()');
      if (at != from) return at == route;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final StreamSubscription<Object?> subscription in _listening) {
      await subscription.cancel();
    }
    await page.close();
  }
}

/// A response header by name, whatever case the server wrote it in.
String? _header(Map<String, String> headers, String name) {
  for (final MapEntry<String, String> header in headers.entries) {
    if (header.key.toLowerCase() == name) return header.value;
  }
  return null;
}
/// How many resources the page has fetched, which is still climbing while a
/// deferred chunk is on its way.
const String _resourceCount = '''() => {
  try {
    return performance.getEntriesByType('resource').length;
  } catch (e) {
    return 0;
  }
}''';
/// Turns Flutter's semantics tree on.
///
/// The same click the studio capture makes. Without it the host is there and
/// nearly empty, which reads as a page that rendered nothing rather than as a
/// tree nobody asked for.
const String _enableSemantics = '''() => {
  const spot = document.querySelector('flt-semantics-placeholder')
      || document.querySelector('[aria-label="Enable accessibility"]');
  if (!spot) return false;
  spot.click();
  return true;
}''';
