/// The Flutter web renderer, asked for by the page while it parses.
///
/// The renderer is the largest thing a Flutter web page downloads --
/// CanvasKit is 7 MB of wasm, skwasm 3.5 MB -- and nothing asked for it until
/// flutter_bootstrap.js had arrived and run. The page's HTML now starts the
/// renderer's two files itself, so they overlap the bootstrap's own download
/// instead of queueing behind it, and opens the connection first when they
/// come from another origin.
///
/// A wrong guess is megabytes downloaded for nothing, which is worse than no
/// hint. So the page picks the renderer and its variant with the loader's own
/// tests, and the build writes no hint when the application's loader
/// configuration could make the loader fetch anything else.
library;

import 'dart:convert';

const String _open = '<!-- dartvel:renderer -->';
const String _close = '<!-- /dartvel:renderer -->';

/// Where a build's renderer files are, and whether skwasm is among them.
class DVRendererSource {
  const DVRendererSource({required this.base, required this.wasm});

  /// The directory the loader fetches the renderer from: gstatic's copy for
  /// the engine revision, or the application's own `canvasKitBaseUrl`.
  final String base;

  /// Whether the build has a dart2wasm/skwasm app the loader may choose.
  final bool wasm;
}

/// Where the build whose flutter_bootstrap.js is [bootstrapJs] loads its
/// renderer from, or null when the loader could fetch something a hint
/// cannot predict.
///
/// Null for builds other than dart2js/CanvasKit, alone or behind
/// dart2wasm/skwasm, and for an application whose call to
/// `_flutter.loader.load` sets the variant, a local copy, the renderer or the
/// wasm allow list, or a `canvasKitBaseUrl` that is not a plain string. Only
/// that call is read: flutter.js itself mentions every one of those names.
DVRendererSource? dvRendererSource(String bootstrapJs) {
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
  final List<String> kinds = <String>[
    for (final Object? build in builds)
      if (build is Map && build.isNotEmpty)
        '${build['compileTarget']}/${build['renderer']}',
  ];
  final bool wasm;
  if (kinds.length == 1 && kinds.single == 'dart2js/canvaskit') {
    wasm = false;
  } else if (kinds.length == 2 &&
      kinds[0] == 'dart2wasm/skwasm' &&
      kinds[1] == 'dart2js/canvaskit') {
    wasm = true;
  } else {
    return null;
  }

  final int call = bootstrapJs.lastIndexOf('_flutter.loader.load(');
  if (call < 0) return null;
  final String load = bootstrapJs.substring(call);
  for (final String setting in <String>[
    'canvasKitVariant',
    'useLocalCanvasKit',
    'renderer',
    'wasmAllowList',
  ]) {
    if (load.contains(setting)) return null;
  }
  String base = 'https://www.gstatic.com/flutter-canvaskit/$revision/';
  if (load.contains('canvasKitBaseUrl')) {
    final RegExpMatch? literal =
        RegExp(r'''canvasKitBaseUrl\s*:\s*(["'])([^"'\\<>\s]*)\1''')
            .firstMatch(load);
    if (literal == null) return null;
    base = literal.group(2)!;
    if (base.isEmpty) return null;
    if (!base.endsWith('/')) base = '$base/';
  }
  return DVRendererSource(base: base, wasm: wasm);
}

/// The hints for [source]: a preconnect when the files are on another origin,
/// and a script that preloads the files the loader will choose.
///
/// A script rather than `<link>`s because the choice depends on the browser,
/// and the tests are flutter.js's own, condition for condition: skwasm on
/// Blink with WasmGC when the build has it (`skwasm_heavy` where ImageDecoder
/// or the ICU break iterators are missing), otherwise CanvasKit (its smaller
/// `chromium` build where Blink has both). Each file is requested the way the
/// loader will request it, the `.js` as a module and the `.wasm` through
/// fetch(), both anonymous CORS: a preload asked for any other way is not
/// reused, and the file downloads twice.
String dvRendererHints(DVRendererSource source) {
  final String base = source.base;
  final Uri? origin = Uri.tryParse(base);
  final bool remote =
      origin != null && origin.hasScheme && origin.scheme.startsWith('http');
  return <String>[
    _open,
    if (remote)
      '<link rel="preconnect" href="${origin.scheme}://${origin.authority}" '
          'crossorigin>',
    '<script>(function(){'
        'var n=navigator,d=document;'
        'var blink=n.vendor==="Google Inc."||n.userAgent.indexOf("Edg/")>=0;'
        'var chromium=blink&&typeof ImageDecoder!=="undefined"'
        '&&typeof Intl.v8BreakIterator!=="undefined"'
        '&&typeof Intl.Segmenter!=="undefined";'
        'var base=${jsonEncode(base)};'
        'function hint(rel,href,as){var l=d.createElement("link");'
        'l.rel=rel;l.href=href;if(as){l.as=as;}l.crossOrigin="anonymous";'
        'd.head.appendChild(l);}'
        '${source.wasm ? 'var wasm=false;try{wasm=blink&&WebAssembly.validate('
            'new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,95,1,120,0]))}catch(e){}'
            'if(wasm){var s=base+(chromium?"skwasm":"skwasm_heavy");'
            'hint("modulepreload",s+".js");hint("preload",s+".wasm","fetch");'
            'return;}' : ''}'
        'var ck=base+(chromium?"chromium/":"");'
        'hint("modulepreload",ck+"canvaskit.js");'
        'hint("preload",ck+"canvaskit.wasm","fetch");'
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
