/// What a link fetches for its page besides the page's code.
///
/// `loadLibrary()` fetches a page's Dart and nothing else. On the web each
/// route is also a prerendered document -- what a new tab, a reload or a
/// shared link opens -- and a page paints images that were left to be
/// fetched once the visitor got there. A preloading link asks the browser for
/// both with a `<link rel="prefetch">` each, then hands every image to
/// Flutter's image cache once the browser has it, so the page paints them on
/// its first frame instead of after it.
///
/// In that order on purpose. Flutter asking for an image the browser is still
/// fetching is a second download of the same bytes; asking for one the
/// browser has finished is a cache hit.
library dartvel_flutter.routing.route_prefetch;

import 'package:dartvel_core/dartvel.dart' show dvStaticImageVariantDir;
import 'package:flutter/widgets.dart';

import 'route_prefetch_stub.dart'
    if (dart.library.js_interop) 'route_prefetch_web.dart';

export 'route_prefetch_paths.dart' show dvPrefetchHref, dvPrefetchImages;

/// The two steps of a document prefetch, replaceable for tests and for a
/// host that serves its pages some other way.
class DVRoutePrefetch {
  const DVRoutePrefetch._();

  /// Fetches the document for a route and its images, and completes with the
  /// images the browser now has. Nothing, off the web.
  static Future<List<String>> Function(String path) fetch = dvPrefetchDocument;

  /// Puts one fetched image into Flutter's image cache.
  static Future<void> Function(BuildContext context, String url) precache =
      _precache;

  /// The provider the page itself will ask for, for an image address the
  /// build recorded.
  ///
  /// The image cache is keyed by provider, not by URL. The right bytes under
  /// the wrong key are decoded for nothing, and the page fetches them again.
  /// An asset served as `assets/<key>` is the `AssetImage` of that key, less
  /// any resolution variant: the capture ran at one pixel ratio, and
  /// AssetImage picks the variant for this screen from the name the page used.
  static ImageProvider providerFor(String url) {
    final String path = url.startsWith('/') ? url.substring(1) : url;
    // A variant the build wrote is a file the site serves, not an asset in
    // the bundle: DVImageView fetches it by address, so that is its key.
    if (path.startsWith('$dvStaticImageVariantDir/')) return NetworkImage(url);
    if (path.startsWith('assets/')) {
      return AssetImage(path
          .substring('assets/'.length)
          .replaceFirstMapped(RegExp(r'(^|/)\d+(?:\.\d+)?x/([^/]+)$'),
              (Match m) => '${m[1]}${m[2]}'));
    }
    return NetworkImage(url);
  }

  @visibleForTesting
  static void reset() {
    fetch = dvPrefetchDocument;
    precache = _precache;
    dvResetPrefetchDocument();
  }

  static Future<void> _precache(BuildContext context, String url) =>
      precacheImage(
        providerFor(url),
        context,
        // Reported, not thrown: the page would show the same failure, and a
        // prefetch must never be what breaks the tap after it.
        onError: (Object error, StackTrace? stack) =>
            FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'dartvel',
          context: ErrorDescription('precaching $url'),
        )),
      );
}
