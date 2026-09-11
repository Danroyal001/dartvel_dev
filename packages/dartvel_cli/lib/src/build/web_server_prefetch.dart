/// What each route of a web-server build loads, for the server to name in
/// the head it sends.
///
/// The static build writes each page's deferred parts and first-frame images
/// into that page's own HTML (see route_prefetch.dart). A web-server build
/// has one shell for every route, so a list written into it would be one
/// route's list served for all of them. The same lists go into
/// `dartvel_prefetch.json` instead, keyed by route pattern -- the key a
/// request is matched to -- and the server adds the matched route's list to
/// the head, in the part `streaming: shell` sends before the data.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'route_prefetch.dart'
    show
        DVCapturedImage,
        dvDeferredParts,
        dvDeferredPrefixes,
        dvNamedByPage,
        dvPrefetchManifestFile,
        dvReadCapturedImages;

/// Writes the prefetch manifest for a web-server build in [webRoot] and
/// returns how many routes name something. The shell is not touched.
///
/// [routes] are the router's patterns, parameterised ones included: the
/// server can serve `/products/:id` and the static writer cannot, so a
/// parameterised route gets its parts here and nowhere else. It has no
/// captured images, since the capture renders concrete pages.
int dvWriteWebServerPrefetch({
  required String projectRoot,
  required String webRoot,
  required String routerSource,
  required List<String> routes,
}) {
  final File mainJs = File(p.join(webRoot, 'main.dart.js'));
  final Map<String, List<String>> parts = mainJs.existsSync()
      ? dvDeferredParts(mainJs.readAsStringSync())
      : const <String, List<String>>{};
  final Map<String, String> prefixes = dvDeferredPrefixes(routerSource);
  // What the shell asks for itself -- the splash, the icons -- is requested
  // on every route, so the capture saw it on every route. It is none of
  // theirs.
  final File shell = File(p.join(webRoot, 'index.html'));
  final Set<String> named = shell.existsSync()
      ? dvNamedByPage(shell.readAsStringSync())
      : const <String>{};

  final Map<String, Object?> manifest = <String, Object?>{};
  var naming = 0;
  for (final String route in routes) {
    final List<String> scripts = parts[prefixes[route]] ?? const <String>[];
    final List<DVCapturedImage> images = <DVCapturedImage>[
      for (final DVCapturedImage image
          in dvReadCapturedImages(projectRoot, route))
        if (!named.contains(image.url)) image,
    ];
    manifest[route] = <String, Object?>{
      'scripts': scripts,
      'images': <Object?>[
        for (final DVCapturedImage image in images) image.toJson(),
      ],
    };
    if (scripts.isNotEmpty || images.isNotEmpty) naming++;
  }

  File(p.join(webRoot, dvPrefetchManifestFile)).writeAsStringSync(
    const JsonEncoder.withIndent('  ')
        .convert(<String, Object?>{'routes': manifest}),
  );
  return naming;
}
