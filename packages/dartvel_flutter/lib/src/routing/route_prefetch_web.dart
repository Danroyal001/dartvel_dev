/// The browser half of a route prefetch: a `<link rel="prefetch">` for the
/// route's prerendered document and one for each image the build recorded
/// the page painting.
///
/// Links rather than fetch() calls, because a prefetch is a hint the browser
/// schedules at idle priority, below everything the current page is loading,
/// and keeps for the next navigation -- including one in a new tab, which a
/// fetch() from this page's script would not help.
library dartvel_flutter.routing.route_prefetch.web;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web/web.dart' as web;

import '../media/image_view.dart' show DVImageView;
import 'route_prefetch_paths.dart';

/// How long an image prefetch may take before it is left to the page.
///
/// A prefetch runs at the lowest priority there is, so on a busy page it can
/// wait a long time; the image is then fetched when the page asks for it, as
/// it always was. Completing with nothing is the fallback, not a failure.
const Duration dvPrefetchTimeout = Duration(seconds: 10);

/// Each address asked for, and whether the browser got it. One link per
/// address however many links on the page point at the route.
final Map<String, Future<bool>> _requested = <String, Future<bool>>{};

/// Fetched once, on the first prefetch, and never on a page with no links.
Future<String?>? _manifest;

/// Where the manifest comes from. Replaced by the browser test, which has no
/// build to read one from.
@visibleForTesting
Future<String?> Function() dvPrefetchManifestLoader = _loadManifest;

/// Prefetches [path]'s document and its images, and completes with the
/// images the browser now has.
Future<List<String>> dvPrefetchDocument(String path) async {
  unawaited(_prefetch(dvPrefetchHref(path)));
  final List<String> images = dvPrefetchImages(
    await (_manifest ??= dvPrefetchManifestLoader()),
    path,
    // This screen's, not the build's: the variant a denser screen draws is a
    // different file, and prefetching the build's would be a download the
    // page then does not use.
    variants: DVImageView.variants,
    devicePixelRatio: web.window.devicePixelRatio,
  );
  final List<bool> fetched = await Future.wait(<Future<bool>>[
    for (final String url in images) _prefetch(url, as: 'image'),
  ]);
  // Only what arrived. Handing Flutter an image the browser failed to fetch
  // is a second failing request, and one still in flight is a second
  // download.
  return <String>[
    for (int i = 0; i < images.length; i++)
      if (fetched[i]) images[i],
  ];
}

/// Forgets what was asked for and the manifest, for tests.
void dvResetPrefetchDocument() {
  _requested.clear();
  _manifest = null;
  dvPrefetchManifestLoader = _loadManifest;
}

Future<bool> _prefetch(String href, {String? as}) =>
    _requested[href] ??= _append(href, as);

Future<bool> _append(String href, String? as) {
  final web.HTMLHeadElement? head = web.document.head;
  if (head == null) return Future<bool>.value(false);

  final Completer<bool> done = Completer<bool>();
  void settle(bool ok) {
    if (!done.isCompleted) done.complete(ok);
  }

  final web.HTMLLinkElement link = web.HTMLLinkElement()
    ..rel = 'prefetch'
    ..href = href;
  if (as != null) link.as = as;
  link.addEventListener('load', ((web.Event _) => settle(true)).toJS);
  link.addEventListener('error', ((web.Event _) => settle(false)).toJS);
  head.appendChild(link);
  return done.future.timeout(dvPrefetchTimeout, onTimeout: () => false);
}

/// The manifest next to index.html, or null on a site built without one --
/// an older build, or a host that does not serve it.
Future<String?> _loadManifest() async {
  try {
    final web.Response response =
        await web.window.fetch(dvPrefetchManifestPath.toJS).toDart;
    if (!response.ok) return null;
    return (await response.text().toDart).toDart;
  } on Object {
    return null;
  }
}
