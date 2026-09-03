// Background sync, in a real browser.
//
// The generated worker keeps an outbox of same-origin non-GET requests that
// could not be sent, answers the caller 202 with X-Dartvel-Queued, and
// replays the outbox in order when the network is back. That was held at
// the generator, since a worker cannot run under dart test; this runs it:
// Chrome loads a page under the generated worker, the page goes offline, a
// POST is queued, the page comes back, and the server the POST was meant
// for receives it. Skipped, and said so, where no Chrome can be launched.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:dartvel_cli/src/commands/capture_command.dart';
import 'package:dartvel_cli/src/build/pwa_sync_verification.dart';
import 'package:test/test.dart';

void main() {
  late Directory web;

  setUp(() {
    web = Directory.systemTemp.createTempSync('dv_pwa_sync_');
    File('${web.path}/index.html').writeAsStringSync('''
<!doctype html><html><head><meta charset="utf-8"><title>sync</title></head>
<body><p>sync fixture</p>
<script>navigator.serviceWorker.register('/sw.js');</script>
</body></html>''');
    File('${web.path}/sw.js').writeAsStringSync(dvServiceWorker(
      buildId: 'test',
      precache: const <String>['/index.html'],
      backgroundSync: true,
    ));
  });
  tearDown(() => web.deleteSync(recursive: true));

  test('a POST made offline is queued, and replayed once the network is back', () async {
    final DVPwaSyncResult result = await dvVerifyPwaSync(webRoot: web.path);
    if (result.skipped != null) {
      markTestSkipped(result.skipped!);
      return;
    }
    expect(result.queuedStatus, 202);
    expect(result.queuedHeader, isTrue);
    expect(result.replayed, <String>['{"order":1}']);
    expect(result.ok, isTrue);
    expect(result.summary, contains('replayed 1'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('with sync stripped from the worker, the same POST fails offline and nothing is replayed', () async {
    File('${web.path}/sw.js').writeAsStringSync(dvServiceWorker(
      buildId: 'test',
      precache: const <String>['/index.html'],
      backgroundSync: false,
    ));
    final DVPwaSyncResult result = await dvVerifyPwaSync(webRoot: web.path);
    if (result.skipped != null) {
      markTestSkipped(result.skipped!);
      return;
    }
    expect(result.queuedStatus, isNot(202));
    expect(result.replayed, isEmpty);
    expect(result.ok, isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the command fails on a worker with no outbox, and passes with one', () async {
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 't')..addCommand(CaptureCommand());
    final DVPwaSyncResult probe = await dvVerifyPwaSync(webRoot: web.path);
    if (probe.skipped != null) {
      markTestSkipped(probe.skipped!);
      return;
    }
    await runner.run(<String>['capture', 'pwa-sync', '--web', web.path]);

    File('${web.path}/sw.js').writeAsStringSync(dvServiceWorker(
      buildId: 'test',
      precache: const <String>['/index.html'],
      backgroundSync: false,
    ));
    await expectLater(
      runner.run(<String>['capture', 'pwa-sync', '--web', web.path]),
      throwsA(isA<UsageException>().having((UsageException e) => e.message, 'message', contains('replayed 0'))),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
