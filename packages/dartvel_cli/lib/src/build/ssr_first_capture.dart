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

import 'package:dartvel_core/dartvel.dart' show DVLayoutFont, dvSsrFirstLayout;
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

import 'semantics_capture.dart' show dvSemanticsPathFor;

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
Future<Map<String, Object?>?> _settledSnapshot(Page page, Duration settle, String scheme) async {
  final List<String> reads = <String>[];
  final DateTime deadline = DateTime.now().add(settle);
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final String? now = await page.evaluate<String?>(_snapshotScript);
    if (now == null) return null;
    final Object? decoded = jsonDecode(now);
    if (decoded is! Map) return null;
    final Object? told = decoded['brightness'];
    final bool arrived = told == null || told == scheme;
    if (arrived) reads.add(now);
    final int count = reads.length;
    final bool still = count >= 3 && reads[count - 1] == reads[count - 2] && reads[count - 2] == reads[count - 3];
    if (still || DateTime.now().isAfter(deadline)) return decoded.cast<String, Object?>();
  }
}

/// Records the route open in [page] at each of [widths], light and dark, and
/// writes it to [path]. Returns false, writing nothing, when the app has no
/// capture hook. The page is put back at [restore] and the light scheme.
///
/// Every width in the light scheme first, then every width in the dark: one
/// switch of scheme rather than one per width.
Future<bool> dvCaptureLayout(
  Page page,
  List<int> widths, {
  required String path,
  DeviceViewport restore = const DeviceViewport(width: 800, height: 600),
  Duration settle = const Duration(seconds: 8),
}) async {
  final List<Map<String, Object?>> captured = <Map<String, Object?>>[];
  try {
    await _scheme(page, 'light');
    for (final int width in widths) {
      final int height = dvSsrFirstHeight(width);
      await page.setViewport(DeviceViewport(width: width, height: height));
      final Map<String, Object?>? light = await _settledSnapshot(page, settle, 'light');
      if (light == null) return false;
      final List<Object?> controls =
          jsonDecode(await page.evaluate<String>(dvLayoutControlsScript)) as List<Object?>;
      captured.add(<String, Object?>{'width': width, 'height': height, 'light': light, 'controls': controls});
    }
    await _scheme(page, 'dark');
    for (final Map<String, Object?> entry in captured) {
      final int width = entry['width']! as int;
      await page.setViewport(DeviceViewport(width: width, height: entry['height']! as int));
      final Map<String, Object?>? dark = await _settledSnapshot(page, settle, 'dark');
      if (dark != null) entry['dark'] = dark;
    }
  } finally {
    await _scheme(page, 'light');
    await page.setViewport(restore);
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
