/// Capturing each route's semantics tree, so the crawler-visible HTML is
/// built from what the application declares.
library dartvel_cli.build.semantics_capture;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import '../utils/logger.dart';

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
      if (tag !== 'a' && tag !== 'flt-semantics' && !heading) continue;
      const aria = child.getAttribute('aria-level');
      // A Dartvel role travels as the node's identifier, because Flutter's
      // Semantics has no role for code and SelectableText would otherwise be
      // a textarea with no readable content at all.
      const identifier = child.getAttribute('flt-semantics-identifier') || '';
      const declared = identifier.startsWith('dartvel:')
        ? identifier.slice('dartvel:'.length)
        : null;
      const node = {
        role: declared || child.getAttribute('role')
              || (tag === 'a' ? 'link' : null),
        level: heading ? parseInt(heading[1], 10)
                       : (aria ? parseInt(aria, 10) : null),
        label: labelOf(child),
        href: child.getAttribute('href'),
        children: walk(child),
      };
      // Nothing to say, nowhere to go, nothing inside.
      if (!node.label && !node.href && node.children.length === 0) continue;
      out.push(node);
    }
    return out;
  };

  return JSON.stringify(walk(host));
}""";

/// Where a route's captured tree is written.
String dvSemanticsPathFor(String projectRoot, String route) {
  final String name = route == '/'
      ? 'index'
      : route.replaceAll(RegExp(r'^/|/$'), '').replaceAll('/', '_');
  return p.join(projectRoot, '.dart_tool', 'dartvel_semantics', '$name.json');
}

/// Capture [routes] from the build in [webRoot], writing one JSON tree each.
///
/// Returns the number of routes that produced a tree. Zero means the caller
/// should fall back to the source-literal extractor rather than ship pages
/// with no crawler-visible content at all — which is what a build on a
/// machine with no browser must still do.
Future<int> dvCaptureSemantics({
  required String projectRoot,
  required String webRoot,
  required List<String> routes,
  Duration settle = const Duration(seconds: 20),
}) async {
  if (routes.isEmpty) return 0;

  Browser? browser;
  try {
    browser = await puppeteer.launch(
      headless: true,
      args: <String>['--no-sandbox', '--disable-setuid-sandbox'],
    );
  } on Object catch (error) {
    // A build without a browser is a normal thing, not a failure. Said out
    // loud, because silently shipping the weaker content is how nobody
    // notices the pages got worse.
    Logger.log('   No browser for the semantics capture ($error).');
    Logger.log('   Falling back to page text; run `dartvel prerender` on a '
        'machine with Chrome for headings, links and landmarks.');
    return 0;
  }

  final HttpServer server = await shelf_io.serve(
    createStaticHandler(webRoot, defaultDocument: 'index.html'),
    InternetAddress.loopbackIPv4,
    0,
  );
  final String base = 'http://${server.address.host}:${server.port}';

  var captured = 0;
  try {
    Directory(p.join(projectRoot, '.dart_tool', 'dartvel_semantics'))
        .createSync(recursive: true);

    for (final String route in routes) {
      final Page page = await browser.newPage();
      try {
        await page.goto('$base$route', wait: Until.networkIdle);

        // Polled rather than slept: a page that is ready early should not
        // cost the whole budget, and one that never builds a tree has to be
        // reported rather than written out empty.
        String tree = '[]';
        final DateTime deadline = DateTime.now().add(settle);
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          tree = await page.evaluate<String>(_extract);
          if (tree != '[]') break;
        }

        File(dvSemanticsPathFor(projectRoot, route)).writeAsStringSync(tree);
        final int nodes = (jsonDecode(tree) as List<Object?>).length;
        if (nodes > 0) captured++;
      } finally {
        await page.close();
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
    }
  }

  return captured;
}
