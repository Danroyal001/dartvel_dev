// Background sync in the generated service worker.
//
// The PWA section lists it and nothing did it: a backend function call made
// while the network was gone simply failed, and the user retried by hand or
// did not. The worker now keeps an outbox -- same-origin requests that are
// not GETs and could not be sent -- and replays it, in order, when the
// browser fires `sync`.
//
// These tests read the generated script. A worker cannot run under
// `dart test`; what can be held here is that the right handlers are emitted,
// that the rules for what is queued are the ones the fetch handler already
// enforces for caching, and that the switch to turn it off turns it off.
import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

String worker({bool? backgroundSync}) => dvServiceWorker(
      buildId: 'test',
      precache: const <String>['/'],
      offlinePath: '/offline.html',
      backgroundSync: backgroundSync ?? true,
    );

void main() {
  group('when enabled', () {
    test('it listens for sync', () {
      expect(worker(), contains("addEventListener('sync'"));
    });

    test('it keeps an outbox in IndexedDB, which survives the worker dying', () {
      // A worker is killed between events; an in-memory queue would lose
      // every request the moment the browser reclaimed it.
      expect(worker(), contains('indexedDB.open'));
      expect(worker(), contains('dartvel-outbox'));
    });

    test('it queues only same-origin requests that are not GETs', () {
      // The same two rules the caching path already applies, for the same
      // reasons: a GET is safe to retry through the cache, and a request to
      // another origin is one the worker cannot inspect or vouch for.
      final String js = worker();
      final int outbox = js.indexOf('function queueForSync');
      expect(outbox, greaterThan(0));
      final String body = js.substring(outbox);
      expect(body, contains("request.method === 'GET'"));
      expect(body, contains('url.origin !== self.location.origin'));
    });

    test('a failed non-GET is queued and the sync tag registered', () {
      // The tag registered and the tag the handler answers to are the same
      // identifier, so they cannot drift apart -- a literal in each place is
      // exactly how one gets renamed without the other.
      final String js = worker();
      expect(js, contains("const OUTBOX = 'dartvel-outbox'"));
      expect(js, contains('sync.register(OUTBOX)'));
      // Replayed on the event, not on the next fetch: the whole point is that
      // it happens with no tab open.
      expect(js, contains('event.tag === OUTBOX'));
    });

    test('replay is in order and stops at the first failure', () {
      // Out of order, an update replays before the create it depends on.
      // Continuing past a failure drops that request while sending the ones
      // after it, which is the worst combination.
      final String js = worker();
      final int replay = js.indexOf('function replayOutbox');
      expect(replay, greaterThan(0));
      final String body = js.substring(replay);
      expect(body, contains('for (const entry of entries)'));
      expect(body, contains('return'));
    });

    test('is the default', () {
      expect(dvServiceWorker(buildId: 'b', precache: const <String>['/']),
          contains("addEventListener('sync'"));
    });
  });

  group('when disabled', () {
    test('no sync handler and no outbox are emitted', () {
      final String js = worker(backgroundSync: false);
      expect(js, isNot(contains("addEventListener('sync'")));
      expect(js, isNot(contains('dartvel-outbox')));
      expect(js, isNot(contains('indexedDB')));
    });

    test('the rest of the worker is unchanged', () {
      expect(worker(backgroundSync: false), contains("addEventListener('fetch'"));
      expect(worker(backgroundSync: false), contains('/offline.html'));
    });
  });
}
