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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

import 'chrome_launch.dart';
import 'page_shots.dart' show DVInFlight, DVShotSize, DVTextSettle;

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
  Map<String, String> open = const <String, String>{},
  Uri? signIn,
  String? email,
  String? password,
  DVShotSize size = const DVShotSize(1440, 900),
  String? chromePath,
  Duration settle = const Duration(seconds: 30),
  Duration afterText = const Duration(milliseconds: 2500),
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
  // Counted from the page's own requests, because a panel still fetching is
  // a panel that has not arrived and the semantics tree does not say so.
  final DVInFlight flight = DVInFlight();
  final List<StreamSubscription<Object?>> watching =
      <StreamSubscription<Object?>>[
    page.onRequest.listen((Object? _) => flight.started()),
    page.onRequestFinished.listen((Object? _) => flight.ended()),
    page.onRequestFailed.listen((Object? _) => flight.ended()),
  ];
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
    if (!await _settled(page, settle, flight: flight)) {
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
      bool arrived = await _settled(page, settle, flight: flight, leaving: leaving);
      // Something inside the section, when one was named: the function a
      // builder should have open, the model whose records to show.
      final String? inside = open[label];
      if (inside != null) {
        // Polled. The section's own list arrives after the section does, so
        // one look finds nothing and the capture silently photographed a
        // builder with the function sitting unopened beside it.
        final DateTime by = DateTime.now().add(const Duration(seconds: 15));
        List<Map<String, Object?>> found = const <Map<String, Object?>>[];
        while (DateTime.now().isBefore(by)) {
          found = await _rail(page, <String>[inside]);
          if (found.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (found.isEmpty) {
          stderr.writeln('studio: nothing called "$inside" in $label');
        } else {
          final String before = await _panel(page);
          await page.mouse.click(Point<num>(
            (found.first['x']! as num).toDouble(),
            (found.first['y']! as num).toDouble(),
          ));
          arrived = await _settled(page, settle, flight: flight, leaving: before) && arrived;
        }
      }
      // Then again, from the far side of the delay. The semantics tree
      // lags the click: at the moment the heading changes, the panel under
      // it can still be the old section's, so the first look reports
      // nothing loading while the new section has not begun. This one is
      // asked when the tree is certainly the section's own, and it is what
      // catches a panel still reading "Loading models…".
      await Future<void>.delayed(afterText);
      arrived = await _settled(page, settle, flight: flight) && arrived;
      // Then a frame, and then time for the renderer to put it on screen.
      // The tree is updated in the frame that builds and the picture handed
      // back is the last one rastered; on a debug build in a headless
      // browser those are seconds apart, which is how a section reported its
      // finished text while the screenshot still showed "Loading …".
      await _painted(page);
      await Future<void>.delayed(const Duration(seconds: 3));
      await _painted(page);
      final String file = p.join(outDir, dvStudioShotName(label));
      File(file).writeAsBytesSync(await _stablePicture(page));
      shots.add(DVStudioShot(
        label: label,
        file: file,
        // Nought when the section never arrived, so a placeholder
        // photographed as though it were the section is a failure.
        textLength: arrived ? await page.evaluate<int>(_text) : 0,
      ));
    }
  } finally {
    for (final StreamSubscription<Object?> subscription in watching) {
      await subscription.cancel();
    }
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
Future<bool> _settled(
  Page page,
  Duration limit, {
  DVInFlight? flight,
  String? leaving,
  Duration insist = const Duration(seconds: 5),
}) async {
  final DVTextSettle settle = DVTextSettle();
  final DateTime deadline = DateTime.now().add(limit);
  // The first section is already open, so clicking it changes no heading and
  // insisting on a change would wait out the whole timeout on the one
  // section that was ready before the capture started.
  final DateTime insistUntil = DateTime.now().add(insist);
  while (DateTime.now().isBefore(deadline)) {
    final Map<String, Object?> state =
        (await page.evaluate<Map<dynamic, dynamic>>(_state))
            .cast<String, Object?>();
    // Either answer is enough to say the section has not arrived: the
    // tree's own word for it, and a request still out that the tree does
    // not mention.
    final bool waiting =
        state['waiting'] == true || !(flight?.idle ?? true);
    // The heading has to have moved off the one the capture clicked away
    // from. Not matched against the rail label, because a panel is titled
    // for what it holds and the rail for where it is: the Cache section is
    // headed "Cache tags", and requiring the two to agree waited out the
    // whole timeout on a section that had been open for half a minute.
    final bool opened = leaving == null ||
        state['title'] != leaving ||
        !DateTime.now().isBefore(insistUntil);
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

/// Waits for two composited frames.
///
/// The semantics tree is updated in the frame that builds, and the picture
/// the browser hands back is the last one it rastered. On a debug build
/// those are far enough apart that a section could report its finished text
/// while the screenshot still showed "Loading …" -- the number and the
/// picture disagreed, and only the picture went on the site.
Future<void> _painted(Page page) => page.evaluate<Object?>(
      '() => new Promise((done) => requestAnimationFrame(() => '
      'requestAnimationFrame(() => done(0))))',
    );

/// Photographs until two shots in a row are the same picture.
///
/// Every earlier attempt at this guessed a delay, and every guess was wrong
/// somewhere: the semantics tree is updated in the frame that builds while
/// the picture the browser hands back is the frame it last rastered, and on a
/// debug build in a headless browser the gap between them is neither small
/// nor constant. Sections reported their finished text and photographed as
/// "Loading modules…".
///
/// Two identical frames is the thing actually being waited for, and it needs
/// no guess: a renderer still catching up produces a different picture each
/// time it is asked.
///
/// Bounded, and the last shot kept when the tries run out. Anything animating
/// on the page -- a caret, a hover, a transition -- means two frames are never
/// identical, and a section is better photographed mid-animation than after a
/// wait nobody budgeted for.
Future<List<int>> _stablePicture(Page page, {int tries = 8}) async {
  List<int> previous = await page.screenshot();
  for (int i = 0; i < tries; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final List<int> next = await page.screenshot();
    if (_same(previous, next)) return next;
    previous = next;
  }
  return previous;
}

/// Whether two PNGs are byte for byte the same.
bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
