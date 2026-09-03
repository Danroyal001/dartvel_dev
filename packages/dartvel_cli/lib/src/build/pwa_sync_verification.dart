/// Background sync, in a real browser.
///
/// The generated worker keeps an outbox of same-origin non-GET requests that
/// could not be sent, answers the caller 202 with X-Dartvel-Queued, and
/// replays the outbox when the network is back. This runs it: Chrome loads
/// a page under the worker, the page goes offline, a POST is queued, the
/// page comes back, and the server the POST was meant for receives it. The
/// replay is asked for through the worker's own message, the same one the
/// generated client sends on regaining connectivity, rather than waiting on
/// the browser's sync scheduler, which headless Chrome fires on no clock a
/// test can hold.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'semantics_capture.dart' show dvCaptureHandler;

class DVPwaSyncResult {
  /// Why nothing was verified -- no browser -- or null when it ran.
  final String? skipped;

  /// What the offline POST got back: 202 when queued; 0 when the fetch
  /// threw, as it does with no worker or no outbox.
  final int queuedStatus;
  final bool queuedHeader;

  /// The bodies the server received after the network returned, in order.
  final List<String> replayed;

  const DVPwaSyncResult({
    this.skipped,
    this.queuedStatus = 0,
    this.queuedHeader = false,
    this.replayed = const <String>[],
  });

  bool get ok => skipped == null && queuedStatus == 202 && queuedHeader && replayed.isNotEmpty;

  String get summary => skipped != null
      ? 'skipped: $skipped'
      : 'offline POST answered $queuedStatus${queuedHeader ? ' with X-Dartvel-Queued' : ''}; '
          'replayed ${replayed.length} once online';
}

/// The bodies to send, in order; the replay must keep the order.
const List<String> _bodies = <String>['{"order":1}'];

Future<DVPwaSyncResult> dvVerifyPwaSync({
  required String webRoot,
  String? chromePath,
  Duration replayTimeout = const Duration(seconds: 20),
}) async {
  final List<String> received = <String>[];
  final shelf.Handler static = dvCaptureHandler(webRoot);
  Future<shelf.Response> handler(shelf.Request request) async {
    if (request.url.path == 'api/echo' && request.method == 'POST') {
      received.add(await request.readAsString());
      return shelf.Response.ok('{"received":true}', headers: <String, String>{'Content-Type': 'application/json'});
    }
    return static(request);
  }

  HttpServer server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
  final int port = server.port;
  final String base = 'http://${server.address.host}:$port';

  Browser browser;
  try {
    browser = await puppeteer.launch(
      headless: true,
      executablePath: chromePath ?? _systemChrome(),
      args: <String>['--no-sandbox', '--disable-setuid-sandbox'],
    );
  } on Object catch (error) {
    await server.close(force: true);
    return DVPwaSyncResult(skipped: 'no browser to run the worker in ($error)');
  }

  try {
    final Page page = await browser.newPage();
    await page.goto('$base/', wait: Until.networkIdle);
    // Registered on first load, controlling from the second: a page the
    // worker did not intercept is a page whose POST never reached it.
    await page.evaluate<Object?>('navigator.serviceWorker.ready.then(() => true)');
    final bool controlled = await page.evaluate<bool>('!!navigator.serviceWorker.controller');
    if (!controlled) {
      await page.reload(wait: Until.networkIdle);
      await page.evaluate<Object?>('navigator.serviceWorker.ready.then(() => true)');
    }

    // The network goes away at the transport: the server is closed, so the
    // worker's own fetch fails the way it does when the cable is out.
    // Emulating offline on the page does not reach the worker, whose fetch
    // is its own -- which is precisely why the outbox lives there.
    await server.close(force: true);
    final String answer = await page.evaluate<String>('''
      fetch('/api/echo', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '${_bodies.first}' })
        .then((r) => JSON.stringify({ status: r.status, queued: r.headers.get('X-Dartvel-Queued') }))
        .catch((e) => JSON.stringify({ status: 0, queued: null, error: String(e) }))
    ''');
    final Map<String, Object?> parsed = (jsonDecode(answer) as Map).cast<String, Object?>();
    final int status = parsed['status'] is int ? parsed['status']! as int : 0;
    final bool header = parsed['queued'] == '1';

    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
    await page.evaluate<Object?>(
        "navigator.serviceWorker.controller && navigator.serviceWorker.controller.postMessage('dartvel:replay-outbox')");
    final DateTime deadline = DateTime.now().add(replayTimeout);
    while (received.length < _bodies.length && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return DVPwaSyncResult(
      queuedStatus: status,
      queuedHeader: header,
      replayed: List<String>.unmodifiable(received),
    );
  } finally {
    await browser.close();
    await server.close(force: true);
  }
}

/// A system Chrome, when one is installed, so nothing is downloaded on a
/// machine that already has a browser.
String? _systemChrome() {
  final String? env = Platform.environment['DARTVEL_CHROME'];
  if (env != null && env.isNotEmpty) return env;
  for (final String candidate in <String>[
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/opt/google/chrome/chrome',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}
