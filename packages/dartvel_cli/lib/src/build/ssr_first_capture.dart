/// SSR-first in the app's own look, the build's side (`dartvel.web.ssrFirst`).
///
/// While the semantics capture has a route open in Chrome, [dvCaptureLayout]
/// resizes the page to each width the document is laid out for, in light and
/// dark, and records what the app painted (its capture hook's `snapshot()`,
/// `dvPaintSnapshot` in dartvel_flutter) and where each link, button and
/// field is ([dvLayoutControlsScript]). [dvApplySsrFirstLayout] then lays the
/// route's semantic HTML out from that file with `dvSsrFirstLayout`
/// (dartvel_core), in the app's own fonts ([dvLayoutFonts]). The result is the
/// route's captured HTML, which the static build writes and the web-server
/// binary serves from its manifest.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVLayoutFont, dvSsrFirstLayout, dvSsrFirstTheme, dvSsrFirstThemeStyle, dvSsrThemeId;
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

import 'semantics_capture.dart' show dvSemanticsPathFor;

/// The size every route's semantics tree is read at: the document is the
/// page as a laptop shows it, with what a narrow screen folds into a menu
/// (a docs side menu, header links) written out. It is puppeteer's own
/// default, which is what the first route of every tab was always read at;
/// it is named so that nothing else decides it.
const DeviceViewport dvSemanticsReadViewport = DeviceViewport(width: 1280, height: 1024);

/// The widths the document is laid out for unless `ssrFirst.widths` says:
/// small and common phones, a tablet upright and lying down, a laptop and a
/// desktop. Between two of them every box moves linearly.
const List<int> dvSsrFirstDefaultWidths = <int>[360, 390, 768, 1024, 1366, 1920];

/// The screen height a width is captured at: what a screen that wide
/// usually is, since a section sized to the screen is laid out from it.
int dvSsrFirstHeight(int width) {
  if (width < 375) return 800;
  if (width <= 480) return 844;
  if (width <= 900) return 1024;
  if (width <= 1100) return 768;
  if (width <= 1500) return 900;
  return 1080;
}

/// The second screen height a width is read at: a quarter taller. What
/// moves or grows between the two (a hero the height of the screen, what
/// follows it, a bar pinned to the bottom) is laid out in `dvh`, so the
/// document fits a screen of any height as the app does.
int dvSsrFirstTallHeight(int height) => (height * 1.25).round();

/// Where a route's layout capture is written: beside its semantics tree.
String dvLayoutCapturePathFor(String projectRoot, String route) =>
    dvSemanticsPathFor(projectRoot, route).replaceFirst(RegExp(r'\.json$'), '.layout.json');

/// Each link, button, field and password eye on the semantics host, with
/// its box: `[{k: a|b|f|r, href, name, r: [left, top, width, height]}]`.
const String dvLayoutControlsScript = r'''() => {
  const host = document.querySelector('flt-semantics-host');
  if (!host) return '[]';
  const own = (el) => {
    let text = '';
    for (const child of el.childNodes) {
      if (child.nodeType === Node.TEXT_NODE || child.tagName === 'SPAN') text += child.textContent;
    }
    return text.trim();
  };
  const box = (el) => {
    const r = el.getBoundingClientRect();
    const round = (v) => Math.round(v * 100) / 100;
    return [round(r.left + scrollX), round(r.top + scrollY), round(r.width), round(r.height)];
  };
  const out = [];
  const seen = new Set();
  for (const el of host.querySelectorAll('a[href], [role="button"], input, textarea, [flt-semantics-identifier^="dartvel:reveal"]')) {
    if (seen.has(el)) continue;
    seen.add(el);
    const r = box(el);
    if (r[2] < 1 || r[3] < 1) continue;
    const identifier = el.getAttribute('flt-semantics-identifier') || '';
    if (identifier.startsWith('dartvel:reveal')) {
      out.push({k: 'r', name: el.getAttribute('aria-label') || own(el), r});
    } else if (el.tagName === 'A') {
      out.push({k: 'a', href: el.getAttribute('href'), name: el.getAttribute('aria-label') || own(el), r});
    } else if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
      // The field's node, not the input Flutter sizes inside it.
      const node = el.closest('flt-semantics');
      out.push({k: 'f', name: el.getAttribute('aria-label') || '', r: node ? box(node) : r});
    } else {
      out.push({k: 'b', name: el.getAttribute('aria-label') || own(el), r});
    }
  }
  return JSON.stringify(out);
}''';

/// What the app has painted now, or null when it has no capture hook.
const String _snapshotScript = '''() => {
  const hook = globalThis.__dartvelCapture;
  return hook && typeof hook.snapshot === "function" ? hook.snapshot() : null;
}''';

/// Whether the app's hook says when it is idle.
const String _saysIdleScript = '''() => {
  const hook = globalThis.__dartvelCapture;
  return !!hook && typeof hook.idle === "function" && typeof hook.brightness === "function";
}''';

/// Whether the app has nothing left to draw and has been told [scheme].
const String _readyScript = '''(scheme) => {
  const hook = globalThis.__dartvelCapture;
  return hook.idle() && hook.brightness() === scheme;
}''';

Future<void> _scheme(Page page, String scheme) =>
    // puppeteer's MediaFeature spells the colour-scheme feature wrongly, so
    // the protocol call is made as written. Reduced motion stays on: the
    // document is the page at rest, as the semantics read is.
    page.devTools.client.send('Emulation.setEmulatedMedia', <String, Object?>{
      'features': <Map<String, String>>[
        <String, String>{'name': 'prefers-color-scheme', 'value': scheme},
        <String, String>{'name': 'prefers-reduced-motion', 'value': 'reduce'},
      ],
    });

/// The snapshot once the app has been told [scheme] and three reads a
/// quarter second apart agree (or after [settle]).
///
/// Waiting for the scheme matters: a theme switch reaches the app a frame
/// or more after the browser's, and Material animates it, so a read taken at
/// once is the old scheme's colours, and holds still long enough to look
/// settled. sigmadev.digital's pricing page was laid out in dark colours for the
/// light scheme at 1024 that way.
Future<Map<String, Object?>?> _settledSnapshot(Page page, Duration settle, String scheme, int width, {int? height}) async {
  final DateTime deadline = DateTime.now().add(settle);
  // An app whose hook says when it is idle and which scheme it has been told
  // is read once, when both are so: a picture is the largest thing the
  // capture moves, and three of each per width made the read of a site of
  // two hundred pages take an hour.
  //
  // Idle is not enough on its own: a resize reaches the app a frame or more
  // after the browser's, and on a loaded machine the app can be idle at its
  // old width meanwhile. A picture at the wrong width is read again.
  if (await page.evaluate<bool>(_saysIdleScript)) {
    while (true) {
      int quiet = 0;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final bool ready = await page.evaluate<bool>(_readyScript, args: <Object?>[scheme]);
        quiet = ready ? quiet + 1 : 0;
        if (quiet >= 2) break;
      }
      final String? now = await page.evaluate<String?>(_snapshotScript);
      if (now == null) return null;
      final Object? decoded = jsonDecode(now);
      if (decoded is! Map) return null;
      if ((_atWidth(decoded, width) && _atHeight(decoded, height)) || !DateTime.now().isBefore(deadline)) {
        return decoded.cast<String, Object?>();
      }
    }
  }
  final List<String> reads = <String>[];
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final String? now = await page.evaluate<String?>(_snapshotScript);
    if (now == null) return null;
    final Object? decoded = jsonDecode(now);
    if (decoded is! Map) return null;
    final Object? told = decoded['brightness'];
    final bool arrived = (told == null || told == scheme) && _atWidth(decoded, width) && _atHeight(decoded, height);
    if (arrived) reads.add(now);
    final int count = reads.length;
    final bool still = count >= 3 && reads[count - 1] == reads[count - 2] && reads[count - 2] == reads[count - 3];
    if (still || DateTime.now().isAfter(deadline)) return decoded.cast<String, Object?>();
  }
}

/// Whether [snapshot] was drawn at [height] (within a pixel), when one is
/// asked for.
bool _atHeight(Map<Object?, Object?> snapshot, int? height) {
  final Object? drawn = snapshot['height'];
  return height == null || drawn is! num || (drawn - height).abs() <= 1;
}

/// Whether [snapshot] was drawn at [width] (within a pixel).
bool _atWidth(Map<Object?, Object?> snapshot, int width) {
  final Object? drawn = snapshot['width'];
  return drawn is! num || (drawn - width).abs() <= 1;
}

/// Records the route open in [page] at each of [widths], light and dark, and
/// writes it to [path]. Returns false, writing nothing, when the app has no
/// capture hook. The page is put back at [restore] -- by default the size it
/// was at when the capture began -- and the light scheme.
///
/// Put back where it was found, not at a fixed size: the semantics read of
/// the next route in the same tab happens at whatever size this leaves. It
/// used to leave a fixed 800 x 600, so every route a tab moved to after its
/// first was read at 800 px. dartvel.dev's docs shell is the narrow one there,
/// and every docs page but the first few shipped a menu button and no menu,
/// while the menu and header links, painted at 1366 and 1920, were laid out
/// as pictures of text with no link behind them.
///
/// Every width in the light scheme first, then every width in the dark: one
/// switch of scheme rather than one per width.
Future<bool> dvCaptureLayout(
  Page page,
  List<int> widths, {
  required String path,
  DeviceViewport? restore,
  Duration settle = const Duration(seconds: 8),
}) async {
  final DeviceViewport back = restore ?? page.viewport ?? dvSemanticsReadViewport;
  final List<Map<String, Object?>> captured = <Map<String, Object?>>[];
  try {
    await _scheme(page, 'light');
    for (final int width in widths) {
      final int height = dvSsrFirstHeight(width);
      await page.setViewport(DeviceViewport(width: width, height: height));
      final Map<String, Object?>? light = await _settledSnapshot(page, settle, 'light', width);
      if (light == null) return false;
      final List<Object?> controls =
          jsonDecode(await page.evaluate<String>(dvLayoutControlsScript)) as List<Object?>;
      final Map<String, Object?> entry = <String, Object?>{
        'width': width,
        'height': height,
        'light': light,
        'controls': controls,
      };
      // The same width at a taller screen, light only: the layout does not
      // change with the scheme.
      final int tallHeight = dvSsrFirstTallHeight(height);
      await page.setViewport(DeviceViewport(width: width, height: tallHeight));
      final Map<String, Object?>? tall = await _settledSnapshot(page, settle, 'light', width, height: tallHeight);
      if (tall != null) {
        entry['tall'] = <String, Object?>{
          'height': tallHeight,
          'items': tall['items'],
          'controls': jsonDecode(await page.evaluate<String>(dvLayoutControlsScript)) as List<Object?>,
        };
      }
      captured.add(entry);
    }
    await _scheme(page, 'dark');
    for (final Map<String, Object?> entry in captured) {
      final int width = entry['width']! as int;
      await page.setViewport(DeviceViewport(width: width, height: entry['height']! as int));
      final Map<String, Object?>? dark = await _settledSnapshot(page, settle, 'dark', width);
      if (dark != null) entry['dark'] = dark;
    }
  } finally {
    await _scheme(page, 'light');
    await page.setViewport(back);
  }
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(<String, Object?>{'widths': captured}));
  return true;
}

/// The fonts the app draws with, from the FontManifest.json under [webRoot]
/// as the build left it (subset, WOFF2, content-hashed), by family.
Map<String, List<DVLayoutFont>> dvLayoutFonts(String webRoot) {
  final File manifest = File(p.join(webRoot, 'assets', 'FontManifest.json'));
  if (!manifest.existsSync()) return const <String, List<DVLayoutFont>>{};
  final Object? decoded;
  try {
    decoded = jsonDecode(manifest.readAsStringSync());
  } on FormatException {
    return const <String, List<DVLayoutFont>>{};
  }
  if (decoded is! List) return const <String, List<DVLayoutFont>>{};
  final Map<String, List<DVLayoutFont>> fonts = <String, List<DVLayoutFont>>{};
  for (final Object? family in decoded) {
    if (family is! Map || family['family'] is! String) continue;
    final List<DVLayoutFont> files = <DVLayoutFont>[
      for (final Object? font in (family['fonts'] as List<Object?>? ?? const <Object?>[]))
        if (font is Map && font['asset'] is String)
          DVLayoutFont(
            'assets/${font['asset']}',
            weight: font['weight'] is num ? (font['weight'] as num).toInt() : int.tryParse('${font['weight']}'),
            style: font['style'] is String ? font['style'] as String : null,
          ),
    ];
    if (files.isNotEmpty) fonts[family['family'] as String] = files;
  }
  return fonts;
}

/// [html], the semantic HTML of [route], laid out from its layout capture
/// when there is one; as it was otherwise.
String dvApplySsrFirstLayout(
  String projectRoot,
  String route,
  String html,
  Map<String, List<DVLayoutFont>> fonts,
) {
  final File file = File(dvLayoutCapturePathFor(projectRoot, route));
  if (!file.existsSync()) return html;
  final Object? capture;
  try {
    capture = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return html;
  }
  if (capture is! Map) return html;
  return dvSsrFirstLayout(html, capture.cast<String, Object?>(), fonts: fonts);
}

/// [shell] carrying the app's look for a page the build could not capture
/// (`dvSsrFirstTheme`), worked out from each route of [pages] (its semantic
/// HTML, before it was laid out) that has a layout capture. The web-server
/// binary renders a parameterised route's data document in it. A theme from
/// an earlier build is replaced; with nothing captured the shell is returned
/// without one.
String dvWithSsrFirstTheme(
  String projectRoot,
  String shell,
  Map<String, String> pages,
  Map<String, List<DVLayoutFont>> fonts,
) {
  final String bare = shell.replaceAll(RegExp('<style id="$dvSsrThemeId">[\\s\\S]*?</style>'), '');
  final List<(String, Map<String, Object?>)> captured = <(String, Map<String, Object?>)>[];
  pages.forEach((String route, String html) {
    final File file = File(dvLayoutCapturePathFor(projectRoot, route));
    if (!file.existsSync()) return;
    try {
      final Object? capture = jsonDecode(file.readAsStringSync());
      if (capture is Map) captured.add((html, capture.cast<String, Object?>()));
    } on FormatException {
      return;
    }
  });
  final String? theme = dvSsrFirstTheme(captured, fonts: fonts);
  if (theme == null) return bare;
  final int head = bare.indexOf('</head>');
  if (head < 0) return bare;
  return '${bare.substring(0, head)}${dvSsrFirstThemeStyle(theme)}${bare.substring(head)}';
}
