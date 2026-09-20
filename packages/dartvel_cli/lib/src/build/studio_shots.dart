/// Photographing every section of Studio, in a real browser, against a
/// running server.
///
/// The site showed five Studio screenshots and Studio has a dozen sections,
/// so somebody deciding whether to use it could see the page builder and had
/// to take the rest on trust. The five were also captured by hand, which is
/// why they went stale twice: a section added after the last session is a
/// section nobody photographs.
///
/// Studio is one application with a rail, not a set of URLs, so this drives
/// it the way a person does -- it reads the rail, clicks each item, waits for
/// the section to draw, and photographs what is on screen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

import 'chrome_launch.dart';
import 'page_shots.dart' show DVShotSize, DVTextSettle;

/// `Site map` becomes `site-map.png`.
///
/// The rail is labelled by whoever attached the section, so nothing stops a
/// label carrying a slash or a colon, and either would write the file
/// somewhere nobody asked for.
String dvStudioShotName(String label) {
  final String slug = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${slug.isEmpty ? 'section' : slug}.png';
}

/// One photographed section.
class DVStudioShot {
  const DVStudioShot({
    required this.label,
    required this.file,
    required this.textLength,
  });

  /// What the rail calls it.
  final String label;
  final String file;

  /// How much text the section showed. Nought is a section that did not
  /// render, which photographs as a plausible empty panel.
  final int textLength;

  bool get ok => textLength > 0;
}

/// Every section, or why the capture could not run.
class DVStudioShotsResult {
  const DVStudioShotsResult({
    this.shots = const <DVStudioShot>[],
    this.skipped,
  });

  final List<DVStudioShot> shots;

  /// Set when no browser could be launched, or Studio would not open.
  final String? skipped;

  List<DVStudioShot> get failures =>
      <DVStudioShot>[for (final DVStudioShot shot in shots) if (!shot.ok) shot];

  /// A run that photographed no section at all is a failure. Studio that
  /// would not open writes no files, and that used to look exactly like a
  /// Studio with no sections to write.
  bool get ok => skipped == null && shots.isNotEmpty && failures.isEmpty;
}

/// Turns Flutter's semantics tree on.
///
/// Flutter web builds no semantics tree until something asks for one: it
/// renders a hidden placeholder labelled "Enable accessibility" and waits for
/// a screen reader to click it. Nothing can read the canvas without it, so a
/// capture that skipped this saw an application drawing nothing and could not
/// find the rail at all.
const String _enableSemantics = r'''() => {
  const spot = document.querySelector('flt-semantics-placeholder')
      || document.querySelector('[aria-label="Enable accessibility"]');
  if (!spot) return false;
  spot.click();
  return true;
}''';

/// The semantics tree's text length, which is nought until Flutter has drawn
/// a frame with text in it.
const String _text = '''() => {
  const host = document.querySelector('flt-semantics-host');
  return host ? (host.innerText || '').trim().length : 0;
}''';

/// The labels on the rail, read out of the semantics tree.
///
/// Taken from the running Studio instead of a list written here, because a
/// list written here is a list that stops matching the day somebody attaches
/// a section. [expect] is the order to prefer when the tree returns them
/// unordered; anything not in it keeps the order it was found in.
String _railScript(List<String> known) => '''() => {
  const known = ${jsonEncode(known)};
  const host = document.querySelector('flt-semantics-host');
  if (!host) return [];
  const found = [];
  for (const node of host.querySelectorAll('[aria-label],flt-semantics')) {
    const label = (node.getAttribute('aria-label') || node.innerText || '')
        .trim();
    if (!label || label.includes('\\n')) continue;
    if (!known.includes(label)) continue;
    const rect = node.getBoundingClientRect();
    if (rect.width < 1 || rect.height < 1) continue;
    if (found.some((f) => f.label === label)) continue;
    found.push({
      label: label,
      x: rect.left + rect.width / 2,
      y: rect.top + rect.height / 2,
    });
  }
  return found;
}''';

/// Photographs each section of the Studio at [studio] into [outDir].
///
/// [sections] are the labels to look for on the rail. [email] and [password]
/// sign in first through [signIn], because Studio answers a request from
/// somebody who may not open it exactly as it answers a route that does not
/// exist -- so a capture that skipped the sign-in would photograph the
/// application's own 404 and call it Studio.
Future<DVStudioShotsResult> dvCaptureStudio({
  required Uri studio,
  required String outDir,
  required List<String> sections,
  Uri? signIn,
  String? email,
  String? password,
  DVShotSize size = const DVShotSize(1440, 900),
  String? chromePath,
  Duration settle = const Duration(seconds: 30),
  Duration afterText = const Duration(milliseconds: 1200),
}) async {
  Browser browser;
  try {
    browser = await puppeteer.launch(
      headless: true,
      executablePath: chromePath ?? await dvChromeExecutable(),
      args: dvChromeLaunchArgs,
    );
  } on Object catch (error) {
    return DVStudioShotsResult(skipped: 'no browser to photograph in ($error)');
  }
  Directory(outDir).createSync(recursive: true);
  final List<DVStudioShot> shots = <DVStudioShot>[];
  final Page page = await browser.newPage();
  try {
    await page.setViewport(DeviceViewport(width: size.width, height: size.height));
    // Signed in from a page on the same origin, so the session cookie is set
    // the way the browser would set it.
    if (signIn != null && email != null && password != null) {
      await page.goto(studio.replace(path: '/').toString(),
          wait: Until.domContentLoaded, timeout: const Duration(seconds: 60));
      final String ok = await page.evaluate<String>('''async () => {
        const r = await fetch(${jsonEncode(signIn.toString())}, {
          method: 'POST', credentials: 'same-origin',
          headers: { 'content-type': 'application/json',
            'x-dartvel-csrf-token': 'c'.repeat(32) },
          body: JSON.stringify(${jsonEncode(<String, String>{
        'email': email,
        'password': password,
      })}),
        });
        return r.ok ? 'ok' : (r.status + ' ' + await r.text());
      }''');
      if (ok != 'ok') {
        return DVStudioShotsResult(skipped: 'could not sign in ($ok)');
      }
    }

    await page.goto(studio.toString(),
        wait: Until.networkIdle, timeout: const Duration(seconds: 120));
    // Polled: the engine adds the placeholder after its first frame, so one
    // look straight after the load finds nothing.
    final DateTime enableBy = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(enableBy)) {
      if (await page.evaluate<bool>(_enableSemantics)) break;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!await _settled(page, settle)) {
      return const DVStudioShotsResult(
          skipped: 'Studio drew no text; it may not be served here');
    }
    await Future<void>.delayed(afterText);

    final List<Map<String, Object?>> rail = await _rail(page, sections);
    if (rail.isEmpty) {
      return const DVStudioShotsResult(
          skipped: 'no sections on the rail; is this Studio?');
    }
    for (final Map<String, Object?> item in rail) {
      final String label = '${item['label']}';
      // Found again before each click: the rail is a live tree and a node
      // read before the previous section drew can have moved.
      final String leaving = await _panel(page);
      final List<Map<String, Object?>> now = await _rail(page, <String>[label]);
      final Map<String, Object?> target = now.isEmpty ? item : now.first;
      await page.mouse.click(Point<num>(
        (target['x']! as num).toDouble(),
        (target['y']! as num).toDouble(),
      ));
      final bool arrived = await _settled(page, settle, leaving: leaving);
      await Future<void>.delayed(afterText);
      final String file = p.join(outDir, dvStudioShotName(label));
      File(file).writeAsBytesSync(await page.screenshot());
      shots.add(DVStudioShot(
        label: label,
        file: file,
        // Nought when the section never arrived, so a placeholder
        // photographed as though it were the section is a failure.
        textLength: arrived ? await page.evaluate<int>(_text) : 0,
      ));
    }
  } finally {
    await page.close();
    await browser.close();
  }
  return DVStudioShotsResult(shots: shots);
}

Future<List<Map<String, Object?>>> _rail(Page page, List<String> known) async {
  final Object? found = await page.evaluate<Object?>(_railScript(known));
  return <Map<String, Object?>>[
    if (found is List)
      for (final Object? item in found)
        if (item is Map) item.cast<String, Object?>(),
  ];
}

/// How long the section has been showing, and whether it is still waiting on
/// the server.
///
/// Both in one look, because asking separately is what produced the first
/// batch of screenshots. A section that has just been clicked has an empty
/// semantics tree for a moment: "is it loading?" answered no, the shot was
/// taken of the placeholder, and the length measured afterwards was the
/// loaded section's. The picture said one thing and the number said another.
const String _state = r'''() => {
  const host = document.querySelector('flt-semantics-host');
  const text = host ? (host.innerText || '').trim() : '';
  // The panel's own heading: the first line that is not the application's
  // name. It is how the capture knows the click has landed -- the section it
  // clicked away from is still painted for a moment, and its text is
  // perfectly steady while it is.
  let title = '';
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed === 'Dartvel Studio') continue;
    title = trimmed;
    break;
  }
  return {
    length: text.length,
    title: title,
    waiting: /Loading[^\n]*…/.test(text) || text.length === 0,
  };
}''';

/// Polls until the section has arrived and stopped changing.
///
/// Arrived is the part that matters: every panel says "Loading …" while its
/// fetch is in flight, and on a debug build that is seconds. A placeholder
/// holds one length for as long as it takes, so "the text stopped changing"
/// on its own is true of a section that never came.
Future<bool> _settled(Page page, Duration limit, {String? leaving}) async {
  final DVTextSettle settle = DVTextSettle();
  final DateTime deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    final Map<String, Object?> state =
        (await page.evaluate<Map<dynamic, dynamic>>(_state))
            .cast<String, Object?>();
    final bool waiting = state['waiting'] == true;
    // The heading has to have moved off the one the capture clicked away
    // from. Not matched against the rail label, because a panel is titled
    // for what it holds and the rail for where it is: the Cache section is
    // headed "Cache tags", and requiring the two to agree waited out the
    // whole timeout on a section that had been open for half a minute.
    final bool opened = leaving == null || state['title'] != leaving;
    final int length = (state['length'] as num?)?.toInt() ?? 0;
    if (!waiting && opened && settle.add(length)) return true;
    // Anything else resets the count, so the section being clicked away from
    // -- perfectly steady while it is still painted -- cannot be mistaken
    // for the one that was asked for.
    if (waiting || !opened) settle.add(0);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// The heading showing now, for [_settled] to wait past.
Future<String> _panel(Page page) async {
  final Map<String, Object?> state =
      (await page.evaluate<Map<dynamic, dynamic>>(_state))
          .cast<String, Object?>();
  return '${state['title'] ?? ''}';
}
