/// The app's first frame, captured at build time and shown before it loads.
///
/// A page is a picture of the app from its first byte: the build opens each
/// route in Chrome at the widths `dartvel.web.firstFrame` names, in light and
/// dark, takes a picture of the first screen and notes where each piece of
/// text and each link was drawn. The page shows the picture with the text laid
/// over it, selectable, findable and followable, and Flutter's own first frame
/// then replaces it pixel for pixel. A window of any other width keeps the
/// splash.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart' show DVFirstFrame, DVFirstFrameText;
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

/// The common phone width and the common desktop widths.
const List<int> dvDefaultFirstFrameWidths = <int>[390, 1366, 1920];

/// The widths `dartvel.web.firstFrame` asks for: the defaults when it says
/// nothing, none when it is `false` or `enabled: false`.
List<int> dvFirstFrameWidths(Object? config) {
  if (config == false) return const <int>[];
  if (config is! Map) return dvDefaultFirstFrameWidths;
  if (config['enabled'] == false) return const <int>[];
  final Object? widths = config['widths'];
  if (widths == null) return dvDefaultFirstFrameWidths;
  if (widths is! List) {
    throw const FormatException('dartvel.web.firstFrame.widths is a list of window widths, such as [390, 1366].');
  }
  final Set<int> out = <int>{};
  for (final Object? width in widths) {
    final int? value = width is int ? width : int.tryParse('$width');
    if (value == null || value < 200 || value > 7680) {
      throw FormatException('dartvel.web.firstFrame.widths: "$width" is not a window width (200 to 7680).');
    }
    out.add(value);
  }
  return out.toList()..sort();
}

String _routeName(String route) =>
    route == '/' ? 'index' : route.replaceAll(RegExp(r'^/|/$'), '').replaceAll('/', '_');

/// Where a route's capture is described.
String dvFirstFramePathFor(String projectRoot, String route) =>
    p.join(projectRoot, '.dart_tool', 'dartvel_semantics', '${_routeName(route)}.first-frame.json');

/// Where a route's pictures are kept until the site is written.
String dvFirstFrameDirFor(String projectRoot, String route) =>
    p.join(projectRoot, '.dart_tool', 'dartvel_semantics', '${_routeName(route)}.first-frame');

/// Forgets what was captured for [route].
void dvForgetFirstFrames(String projectRoot, String route) {
  final File description = File(dvFirstFramePathFor(projectRoot, route));
  if (description.existsSync()) description.deleteSync();
  final Directory pictures = Directory(dvFirstFrameDirFor(projectRoot, route));
  if (pictures.existsSync()) pictures.deleteSync(recursive: true);
}

/// The text and links drawn on screen, where they were drawn: what the
/// semantics tree says, with each node's place in the window.
const String _layout = r"""() => {
  const host = document.querySelector('flt-semantics-host');
  if (!host) return '[]';
  const out = [];
  for (const el of host.querySelectorAll('flt-semantics, a, h1, h2, h3, h4, h5, h6')) {
    let text = el.getAttribute('aria-label') || '';
    if (!text) {
      for (const child of el.childNodes) {
        if (child.nodeType === Node.TEXT_NODE || child.tagName === 'SPAN') text += child.textContent;
      }
    }
    text = text.trim();
    if (!text) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2 || r.bottom <= 0 || r.top >= innerHeight || r.right <= 0 || r.left >= innerWidth) continue;
    const node = { text, left: r.left, top: r.top, width: r.width, height: r.height };
    const link = el.closest('a[href]');
    if (link) node.href = link.getAttribute('href');
    out.push(node);
  }
  return JSON.stringify(out);
}""";

/// Sets the colour scheme the page sees, or clears it with null.
///
/// Sent to Chrome directly: puppeteer's MediaFeature spells the feature
/// `prefers-colors-scheme`, which Chrome refuses as invalid parameters.
Future<void> dvEmulateColourScheme(Page page, String? scheme) =>
    page.devTools.client.send('Emulation.setEmulatedMedia', <String, Object?>{
      'features': <Object?>[
        if (scheme != null) <String, String>{'name': 'prefers-color-scheme', 'value': scheme},
      ],
    });

/// Waits for the app to lay out again after the window or the scheme changed.
Future<void> _settle(Page page) async {
  await page.evaluate<Object?>('() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)))');
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await page.evaluate<Object?>('() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)))');
}

/// Captures [route], already open and rendered in [page], at each of
/// [widths], light and dark. A dark picture identical to the light one is not
/// kept: an app with no dark look shows its light one in either scheme.
Future<int> dvCaptureFirstFrames(
  Page page, {
  required String projectRoot,
  required String route,
  required List<int> widths,
}) async {
  dvForgetFirstFrames(projectRoot, route);
  if (widths.isEmpty) return 0;
  final Directory pictures = Directory(dvFirstFrameDirFor(projectRoot, route))..createSync(recursive: true);
  final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
  try {
    for (final int width in widths) {
      // A phone is taller than it is wide, a desktop window the other way.
      await page.setViewport(DeviceViewport(width: width, height: width < 700 ? 844 : 900));
      Digest? light;
      for (final bool dark in <bool>[false, true]) {
        await dvEmulateColourScheme(page, dark ? 'dark' : 'light');
        await page.evaluate<Object?>('() => window.scrollTo(0, 0)');
        await _settle(page);
        final List<int> bytes = base64Decode(
            await page.devTools.page.captureScreenshot(format: 'webp', quality: 90));
        final Digest digest = sha256.convert(bytes);
        if (dark && digest == light) continue;
        if (!dark) light = digest;
        final String file = '$width-${dark ? 'dark' : 'light'}.webp';
        File(p.join(pictures.path, file)).writeAsBytesSync(bytes);
        frames.add(<String, Object?>{
          'width': width,
          'dark': dark,
          'file': file,
          'texts': jsonDecode(await page.evaluate<String>(_layout)),
        });
      }
    }
  } finally {
    await dvEmulateColourScheme(page, null);
  }
  File(dvFirstFramePathFor(projectRoot, route)).writeAsStringSync(jsonEncode(frames));
  return frames.length;
}

/// [route]'s captured first frames, their pictures copied into the site at
/// [webRoot] under names that change with them.
List<DVFirstFrame> dvPublishFirstFrames({
  required String root,
  required String route,
  required String webRoot,
}) {
  final File description = File(dvFirstFramePathFor(root, route));
  if (!description.existsSync()) return const <DVFirstFrame>[];
  final Object? decoded = jsonDecode(description.readAsStringSync());
  if (decoded is! List) return const <DVFirstFrame>[];
  final Directory pictures = Directory(dvFirstFrameDirFor(root, route));
  final Directory published = Directory(p.join(webRoot, 'dv-first-frame'))..createSync(recursive: true);
  final List<DVFirstFrame> out = <DVFirstFrame>[];
  for (final Object? entry in decoded) {
    if (entry is! Map) continue;
    final File picture = File(p.join(pictures.path, '${entry['file']}'));
    if (!picture.existsSync()) continue;
    final List<int> bytes = picture.readAsBytesSync();
    final int width = (entry['width'] as num).toInt();
    final bool dark = entry['dark'] == true;
    final String name =
        '${_routeName(route)}-$width-${dark ? 'dark' : 'light'}-${sha256.convert(bytes).toString().substring(0, 10)}.webp';
    File(p.join(published.path, name)).writeAsBytesSync(bytes);
    out.add(DVFirstFrame(
      width: width,
      dark: dark,
      src: 'dv-first-frame/$name',
      texts: <DVFirstFrameText>[
        for (final Object? text in (entry['texts'] as List?) ?? const <Object?>[])
          if (text is Map) DVFirstFrameText.fromJson(text.cast<String, Object?>()),
      ],
    ));
  }
  return out;
}
