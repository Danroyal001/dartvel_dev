/// Checks that the browser's own find reaches a built Dartvel page and moves
/// the Flutter page to the match.
///
///     dart tool/ci/serve.dart 8090 --spa &          # from build/web
///     dart tool/ci/find_in_page_check.dart http://localhost:8090 \
///         /docs/web-hosting 'phrase below the fold' [screenshot-dir]
///
/// A find bar cannot be driven from a script, so this checks the pieces it
/// relies on, each in a real Chrome against the real build:
///
/// 1. The HTML the build wrote holds the phrase in a `hidden="until-found"`
///    section. That is what makes the text searchable at all.
/// 2. `window.find()` finds the phrase. It searches the document the way the
///    find bar does, so this shows the hidden copy is searchable. It does not
///    reveal the section or fire `beforematch`.
/// 3. `beforematch` on that section, fired the way the browser fires it,
///    scrolls the Flutter page until the phrase is on screen. The phrase has
///    to start below the fold, or the check proves nothing.
/// 4. Loading the page with a text fragment (`#:~:text=`) scrolls the page
///    to the phrase. Here the browser itself matches, reveals the section
///    and fires `beforematch`, the same path as the find bar. It fires while
///    the app is still loading, so this also covers the case where the
///    runtime picks up a section the browser revealed before it was
///    listening.
///
/// Where the Flutter page put the phrase is read from Flutter's semantics
/// tree, whose DOM nodes sit where the text is drawn.
///
/// Only dart:io: Chrome is driven over the DevTools protocol on a WebSocket,
/// so this runs from a checkout with nothing resolved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 3) {
    stderr.writeln('usage: find_in_page_check.dart <base-url> <route> '
        '<phrase> [screenshot-dir]');
    exit(2);
  }
  final String base = arguments[0].replaceAll(RegExp(r'/+$'), '');
  final String route = arguments[1];
  final String phrase = arguments[2];
  final String? shots = arguments.length > 3 ? arguments[3] : null;
  if (shots != null) Directory(shots).createSync(recursive: true);

  final List<String> failures = <String>[];
  void check(bool ok, String what) {
    stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $what');
    if (!ok) failures.add(what);
  }

  // 1. The build's HTML.
  final String html = await _get('$base$route');
  final RegExp section = RegExp(
      r'<section hidden="until-found" data-dv-anchor="\d+">(.*?)</section>',
      dotAll: true);
  final bool inSection = section
      .allMatches(html)
      .any((RegExpMatch m) => _text(m.group(1)!).contains(phrase));
  check(inSection,
      'the built HTML holds "$phrase" in a hidden="until-found" section');

  final _Chrome chrome = await _Chrome.launch();
  try {
    // 2 and 3: an ordinary load.
    await chrome.open('$base$route');
    await chrome.waitFor(_mirrorReady, 'the find runtime to take the block');
    check(await chrome.evaluate('window.find(${jsonEncode(phrase)})') == true,
        'window.find() finds "$phrase" in the document');

    await chrome.enableSemantics();
    final _Where before = await chrome.where(phrase);
    stdout.writeln('     before: $before');
    check(before.found && before.belowFold,
        'the phrase starts below the fold, so a scroll is needed');
    await chrome.shot(shots, '1-before');

    final Object? fired = await chrome.evaluate('''(() => {
      const phrase = ${jsonEncode(phrase)};
      for (const s of document.querySelectorAll('.dv-fallback [data-dv-anchor]')) {
        if (!s.textContent.includes(phrase)) continue;
        s.removeAttribute('hidden');
        s.dispatchEvent(new Event('beforematch', {bubbles: true}));
        return s.getAttribute('data-dv-anchor');
      }
      return null;
    })()''');
    check(fired != null, 'a mirror section holds the phrase (anchor $fired)');
    await Future<void>.delayed(const Duration(seconds: 2));
    final _Where after = await chrome.where(phrase);
    stdout.writeln('     after beforematch: $after');
    check(after.onScreen, 'beforematch scrolled the phrase onto the screen');
    check(
        await chrome.evaluate('''(() => {
          for (const s of document.querySelectorAll('.dv-fallback [data-dv-anchor]')) {
            if (s.textContent.includes(${jsonEncode(phrase)})) return s.getAttribute('hidden');
          }
          return null;
        })()''') == 'until-found',
        'the section is hidden again after the match');
    await chrome.shot(shots, '2-after-beforematch');

    // 4. The browser's own match: a text fragment on a fresh load.
    await chrome.open('about:blank');
    await chrome.open(
        '$base$route#:~:text=${Uri.encodeComponent(phrase)}');
    await chrome.waitFor(_mirrorReady, 'the find runtime to take the block');
    await Future<void>.delayed(const Duration(seconds: 2));
    await chrome.enableSemantics();
    final _Where fragment = await chrome.where(phrase);
    stdout.writeln('     after a text fragment: $fragment');
    check(fragment.onScreen,
        'a #:~:text= link, matched by the browser, scrolled the phrase onto the screen');
    await chrome.shot(shots, '3-after-text-fragment');
  } finally {
    await chrome.close();
  }

  if (failures.isNotEmpty) {
    stderr.writeln('::error::find in page: ${failures.length} check(s) '
        'failed: ${failures.join('; ')}');
    exit(1);
  }
  stdout.writeln('find in page: every check passed.');
}

/// The runtime has read the page and taken the block over.
const String _mirrorReady = '''(() => {
  const b = document.querySelector('.dv-fallback');
  return !!b && b.getAttribute('aria-hidden') === 'true';
})()''';

String _text(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\s+'), ' ');

Future<String> _get(String url) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    final HttpClientResponse response = await request.close();
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

/// Where the phrase is drawn, from the semantics node that carries it.
class _Where {
  const _Where(this.found, this.top, this.bottom, this.viewport);

  final bool found;
  final double top;
  final double bottom;
  final double viewport;

  bool get onScreen => found && top >= 0 && bottom <= viewport;
  bool get belowFold => found && top >= viewport;

  @override
  String toString() => found
      ? 'top ${top.round()}, bottom ${bottom.round()}, viewport ${viewport.round()}'
      : 'not in the semantics tree';
}

/// Chrome, headless, over the DevTools protocol.
class _Chrome {
  _Chrome._(this._process, this._socket, this._profile) {
    _socket.listen((Object? message) {
      final Map<String, Object?> decoded =
          jsonDecode(message! as String) as Map<String, Object?>;
      final Object? id = decoded['id'];
      if (id is int) _pending.remove(id)?.complete(decoded);
    });
  }

  final Process _process;
  final WebSocket _socket;
  final Directory _profile;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  int _next = 0;

  static Future<_Chrome> launch() async {
    final String executable = Platform.environment['CHROME_EXECUTABLE'] ??
        <String>[
          '/usr/bin/google-chrome',
          '/usr/bin/google-chrome-stable',
          '/usr/bin/chromium',
          '/usr/bin/chromium-browser',
        ].firstWhere((String path) => File(path).existsSync(),
            orElse: () => 'google-chrome');
    final Directory profile =
        Directory.systemTemp.createTempSync('dartvel_find_chrome_');
    final Process process = await Process.start(executable, <String>[
      '--headless=new',
      '--no-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage',
      '--no-first-run',
      '--window-size=1280,800',
      '--remote-debugging-port=0',
      '--user-data-dir=${profile.path}',
      'about:blank',
    ]);
    unawaited(process.stderr.drain<void>());
    unawaited(process.stdout.drain<void>());

    // Chrome writes the port it chose here once it is listening.
    final File active = File('${profile.path}/DevToolsActivePort');
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!active.existsSync() || active.readAsLinesSync().length < 2) {
      if (DateTime.now().isAfter(deadline)) {
        process.kill();
        throw StateError('Chrome did not start ($executable)');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final int port = int.parse(active.readAsLinesSync().first.trim());
    final List<Object?> targets =
        jsonDecode(await _get('http://127.0.0.1:$port/json/list'))
            as List<Object?>;
    final Map<String, Object?> page = targets
        .cast<Map<String, Object?>>()
        .firstWhere((Map<String, Object?> t) => t['type'] == 'page');
    // Closed in close(), which owns it from here.
    // ignore: close_sinks
    final WebSocket socket =
        await WebSocket.connect(page['webSocketDebuggerUrl']! as String);
    final _Chrome chrome = _Chrome._(process, socket, profile);
    await chrome._send('Page.enable');
    await chrome._send('Runtime.enable');
    return chrome;
  }

  Future<Map<String, Object?>> _send(String method,
      [Map<String, Object?> params = const <String, Object?>{}]) {
    final int id = ++_next;
    final Completer<Map<String, Object?>> done =
        Completer<Map<String, Object?>>();
    _pending[id] = done;
    _socket.add(jsonEncode(<String, Object?>{
      'id': id,
      'method': method,
      'params': params,
    }));
    return done.future.timeout(const Duration(seconds: 60));
  }

  Future<Object?> evaluate(String expression) async {
    final Map<String, Object?> reply = await _send('Runtime.evaluate',
        <String, Object?>{
          'expression': expression,
          'returnByValue': true,
          'awaitPromise': true,
        });
    final Map<String, Object?>? result =
        (reply['result'] as Map<String, Object?>?)?['result']
            as Map<String, Object?>?;
    return result?['value'];
  }

  Future<void> open(String url) async {
    await _send('Page.navigate', <String, Object?>{'url': url});
    if (url == 'about:blank') return;
    await waitFor(
        '!!(document.querySelector("flutter-view") || '
        'document.querySelector("flt-glass-pane"))',
        'Flutter to start on $url');
  }

  Future<void> waitFor(String expression, String what) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      if (await evaluate(expression) == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('timed out waiting for $what');
  }

  /// Turns Flutter's semantics tree on, as a screen reader would, and waits
  /// for it to be built.
  Future<void> enableSemantics() async {
    await evaluate('''(() => {
      const spot = document.querySelector('flt-semantics-placeholder');
      if (spot) spot.click();
    })()''');
    await waitFor(
        "document.querySelectorAll('flt-semantics-host flt-semantics').length > 3",
        'the semantics tree');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  /// Where [phrase] is drawn: the smallest semantics node whose text or
  /// label contains it.
  Future<_Where> where(String phrase) async {
    final Object? value = await evaluate('''(() => {
      const phrase = ${jsonEncode(phrase)};
      let best = null;
      for (const el of document.querySelectorAll('flt-semantics-host *')) {
        const text = (el.getAttribute('aria-label') || '') + ' ' + (el.textContent || '');
        if (!text.includes(phrase)) continue;
        const r = el.getBoundingClientRect();
        if (r.height <= 0) continue;
        if (!best || r.height < best.height) best = {top: r.top, bottom: r.bottom, height: r.height};
      }
      return JSON.stringify({best, viewport: window.innerHeight});
    })()''');
    final Map<String, Object?> decoded =
        jsonDecode(value! as String) as Map<String, Object?>;
    final Map<String, Object?>? best = decoded['best'] as Map<String, Object?>?;
    final double viewport = (decoded['viewport']! as num).toDouble();
    if (best == null) return _Where(false, 0, 0, viewport);
    return _Where(true, (best['top']! as num).toDouble(),
        (best['bottom']! as num).toDouble(), viewport);
  }

  Future<void> shot(String? directory, String name) async {
    if (directory == null) return;
    final Map<String, Object?> reply =
        await _send('Page.captureScreenshot', <String, Object?>{'format': 'png'});
    final String data =
        (reply['result']! as Map<String, Object?>)['data']! as String;
    File('$directory/$name.png').writeAsBytesSync(base64Decode(data));
  }

  Future<void> close() async {
    await _socket.close();
    _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 10),
        onTimeout: () => -1);
    try {
      _profile.deleteSync(recursive: true);
    } on FileSystemException {
      // Chrome can hold a file for a moment after it exits; a temp
      // directory left behind is not a failed check.
    }
  }
}
