/// Every page names the fonts it will draw with, so they download beside the
/// app instead of after it.
///
/// Flutter web reads FontManifest.json only once main.dart.wasm (or .js) has
/// downloaded, compiled and started, then fetches every font in it, and the
/// engine waits for all of them before its first frame. On a slow phone
/// network that put the fonts, and the first frame, seconds behind the app's
/// own download (sigmadev.digital, Fast 3G: fonts began 25 s in).
///
/// Each font is preloaded the way the engine fetches it -- `fetch()`, which is
/// a CORS request even to its own site, so `crossorigin` -- or the browser
/// does not hand one to the other and the bytes download twice. Not with the
/// page, but the moment main.dart.wasm (or .js) and the renderer have
/// downloaded (dartvel_core's dvAfterBootPreloadsBody): as plain preloads
/// they shared a slow line with the app and delayed it by 10 s on Slow 3G,
/// while from then on the network is idle as the app compiles and starts.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvAfterBootPreloadsBody;

import 'package:path/path.dart' as p;

import 'web_fonts.dart' show DVManifestFamily, DVManifestFont, dvParseFontManifest;

const String _open = '<!-- dartvel:fonts -->';
const String _close = '<!-- /dartvel:fonts -->';

/// The address of each font [manifestJson] lists, once each, in the order the
/// engine meets them: `assets/<asset key>`, encoded as the engine encodes it.
/// Nothing for a manifest that is not one.
List<String> dvFontPreloadHrefs(String manifestJson) {
  final List<DVManifestFamily> manifest;
  try {
    manifest = dvParseFontManifest(manifestJson);
  } on FormatException {
    return const <String>[];
  }
  final Set<String> seen = <String>{};
  return <String>[
    for (final DVManifestFamily family in manifest)
      for (final DVManifestFont font in family.fonts)
        if (seen.add(font.asset)) Uri.encodeFull('assets/${font.asset}'),
  ];
}

/// [html] with its font list replaced by one naming [hrefs], at the end of
/// its head. Between markers, so a rebuild replaces rather than adds; with no
/// fonts the list is removed and the page is otherwise unchanged.
String dvApplyFontPreloads(String html, List<String> hrefs) {
  final String cleared = html.replaceAll(
    RegExp('${RegExp.escape(_open)}[\\s\\S]*?${RegExp.escape(_close)}'),
    '',
  );
  if (hrefs.isEmpty) return cleared;
  final int at = cleared.indexOf('</head>');
  if (at < 0) return cleared;
  final String block =
      '$_open<script>(function(){${dvAfterBootPreloadsBody(hrefs)}})();</script>$_close';
  return '${cleared.substring(0, at)}$block${cleared.substring(at)}';
}

/// Everything the engine asks for between starting and its first frame that
/// the build can name, for the head of every page in [webRoot]: the two
/// manifests it reads first -- FontManifest.json, which names the fonts, and
/// AssetManifest.bin.json, which an AssetImage reads to choose its file --
/// then every font. Each manifest was a round trip after the app started.
/// A manifest the build did not write is not named.
List<String> dvBootPreloadHrefs(String webRoot) {
  final File fonts = File(p.join(webRoot, 'assets', 'FontManifest.json'));
  final File assets = File(p.join(webRoot, 'assets', 'AssetManifest.bin.json'));
  return <String>[
    if (fonts.existsSync()) 'assets/FontManifest.json',
    if (assets.existsSync()) 'assets/AssetManifest.bin.json',
    if (fonts.existsSync()) ...dvFontPreloadHrefs(fonts.readAsStringSync()),
  ];
}
