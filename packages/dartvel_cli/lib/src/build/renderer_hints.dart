/// The Flutter web renderer, asked for by the page while it parses.
///
/// CanvasKit is the largest thing a Flutter web page downloads -- 7 MB of
/// wasm -- and nothing asked for it until flutter_bootstrap.js had arrived
/// and run. The page's HTML now opens the connection to gstatic and starts
/// both CanvasKit files itself, so they overlap the bootstrap's own download
/// instead of queueing behind it.
///
/// A wrong guess is a 7 MB download for nothing, which is worse than no hint.
/// So the page picks the variant with the loader's own test, and the build
/// writes no hint when the application's loader configuration could make the
/// loader fetch anything else.
library;

import 'dart:convert';

const String _open = '<!-- dartvel:renderer -->';
const String _close = '<!-- /dartvel:renderer -->';

/// The engine revision whose CanvasKit this build loads from gstatic, or
/// null when the loader could fetch something else.
///
/// Null for a build that is not CanvasKit on dart2js everywhere (a `--wasm`
/// build lets the loader choose skwasm per browser), and for an application
/// whose call to `_flutter.loader.load` sets the CanvasKit URL, the variant,
/// a local copy or the renderer. Only that call is read: flutter.js itself
/// mentions every one of those names.
String? dvCanvasKitRevision(String bootstrapJs) {
  final RegExpMatch? config =
      RegExp(r'_flutter\.buildConfig\s*=\s*(\{[^\n]*\})\s*;')
          .firstMatch(bootstrapJs);
  if (config == null) return null;
  final Object? json;
  try {
    json = jsonDecode(config.group(1)!);
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;

  final Object? revision = json['engineRevision'];
  if (revision is! String || !RegExp(r'^[0-9a-f]{7,64}$').hasMatch(revision)) {
    return null;
  }
  final Object? builds = json['builds'];
  if (builds is! List) return null;
  final List<Map<Object?, Object?>> real = <Map<Object?, Object?>>[
    for (final Object? build in builds)
      if (build is Map && build.isNotEmpty) build,
  ];
  if (real.isEmpty ||
      !real.every((Map<Object?, Object?> build) =>
          build['compileTarget'] == 'dart2js' &&
          build['renderer'] == 'canvaskit')) {
    return null;
  }

  final int call = bootstrapJs.lastIndexOf('_flutter.loader.load(');
  if (call < 0) return null;
  final String load = bootstrapJs.substring(call);
  for (final String setting in <String>[
    'canvasKitBaseUrl',
    'canvasKitVariant',
    'useLocalCanvasKit',
    'renderer',
  ]) {
    if (load.contains(setting)) return null;
  }
  return revision;
}

/// The hints for [revision]'s CanvasKit: a preconnect, and a script that
/// preloads the variant the loader will choose.
///
/// A script rather than two `<link>`s because the variant depends on the
/// browser -- the smaller `chromium` build where Blink has the ICU break
/// iterators and ImageDecoder, the full one elsewhere -- and the test is
/// flutter.js's own, condition for condition. Each file is requested the way
/// the loader will request it, the `.js` as a module and the `.wasm` through
/// fetch(), both anonymous CORS: a preload asked for any other way is not
/// reused, and the file downloads twice.
String dvRendererHints(String revision) {
  final String base = 'https://www.gstatic.com/flutter-canvaskit/$revision/';
  return <String>[
    _open,
    '<link rel="preconnect" href="https://www.gstatic.com" crossorigin>',
    '<script>(function(){'
        'var n=navigator,d=document;'
        'var blink=n.vendor==="Google Inc."||n.userAgent.indexOf("Edg/")>=0;'
        'var chromium=blink&&typeof ImageDecoder!=="undefined"'
        '&&typeof Intl.v8BreakIterator!=="undefined"'
        '&&typeof Intl.Segmenter!=="undefined";'
        'var base="$base"+(chromium?"chromium/":"");'
        'function hint(rel,href,as){var l=d.createElement("link");'
        'l.rel=rel;l.href=href;if(as){l.as=as;}l.crossOrigin="anonymous";'
        'd.head.appendChild(l);}'
        'hint("modulepreload",base+"canvaskit.js");'
        'hint("preload",base+"canvaskit.wasm","fetch");'
        '})();</script>',
    _close,
  ].join('\n');
}

/// [html] with its renderer hints replaced by [block], or removed when
/// [block] is null.
///
/// Right after the charset declaration rather than at the top of `<head>`:
/// the charset has to be within the first 1024 bytes, and the hints would
/// push it past them. Written as the block and a newline, so the next build
/// takes out exactly what this one put in.
String dvApplyRendererHints(String html, String? block) {
  final String cleared = html.replaceAll(
    RegExp('${RegExp.escape(_open)}[\\s\\S]*?${RegExp.escape(_close)}\\n?'),
    '',
  );
  if (block == null) return cleared;
  final RegExpMatch? anchor =
      RegExp(r'<meta\s+charset[^>]*>', caseSensitive: false)
              .firstMatch(cleared) ??
          RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(cleared);
  if (anchor == null) return cleared;
  return '${cleared.substring(0, anchor.end)}$block\n'
      '${cleared.substring(anchor.end)}';
}
