// Photographing every section of Studio.
//
// The site showed five Studio screenshots and Studio has a dozen sections, so
// somebody deciding whether to use it could see the page builder and had to
// take the rest on trust. The five were also captured by hand, which is why
// they went stale twice: a section added after the last session is a section
// nobody photographs.
//
// This is the part that does not need a browser: what each file is called,
// and what counts as a section that failed to render. The capture itself is
// proved by running it.
import 'package:dartvel_cli/src/build/studio_shots.dart';
import 'package:test/test.dart';

void main() {
  inFlightTests();

  group('what a section is called on disk', () {
    test('a label becomes a file name anybody can read', () {
      expect(dvStudioShotName('Pages'), 'pages.png');
      expect(dvStudioShotName('Site map'), 'site-map.png');
      expect(dvStudioShotName('Data'), 'data.png');
    });

    test('a label with punctuation still makes one path segment', () {
      // The rail is labelled by whoever attached the section, so nothing
      // stops a label carrying a slash or a colon. Either would write the
      // file somewhere nobody asked for.
      expect(dvStudioShotName('Tasks / Queue'), 'tasks-queue.png');
      expect(dvStudioShotName('../etc'), 'etc.png');
    });
  });

  group('a section that did not render is a failure, not a picture', () {
    test('a blank section fails the capture', () {
      const DVStudioShot blank =
          DVStudioShot(label: 'Cache', file: 'cache.png', textLength: 0);

      expect(blank.ok, isFalse);
      expect(
        const DVStudioShotsResult(shots: <DVStudioShot>[blank]).failures,
        hasLength(1),
      );
    });

    test('a capture with no sections at all is a failure', () {
      // Studio that would not open photographs as nothing, and a run that
      // wrote no files used to look the same as a run that had none to
      // write.
      const DVStudioShotsResult empty = DVStudioShotsResult();

      expect(empty.ok, isFalse);
    });

    test('every section rendering is the passing case', () {
      const DVStudioShotsResult result = DVStudioShotsResult(
        shots: <DVStudioShot>[
          DVStudioShot(label: 'Pages', file: 'pages.png', textLength: 120),
          DVStudioShot(label: 'Data', file: 'data.png', textLength: 80),
        ],
      );

      expect(result.ok, isTrue);
      expect(result.failures, isEmpty);
    });
  });
}

// The panel is photographed while it still reads "Loading cache tags…".
//
// The capture asked the semantics tree whether anything was loading, and the
// tree does not carry the placeholder: one run passed with seven of eleven
// sections photographed mid-fetch, and reported every one of them as fine.
// Studio holds no long-lived connection, so its own requests are the honest
// signal -- a section that is still asking the server has not arrived.
void inFlightTests() {
  test('a section with a request outstanding has not arrived', () {
    final DVInFlight flight = DVInFlight();
    expect(flight.idle, isTrue, reason: 'nothing asked for yet');

    flight.started();
    expect(flight.idle, isFalse);

    flight.ended();
    expect(flight.idle, isTrue);
  });

  test('several at once all have to finish', () {
    final DVInFlight flight = DVInFlight();
    flight.started();
    flight.started();
    flight.ended();

    expect(flight.idle, isFalse, reason: 'one is still out');

    flight.ended();
    expect(flight.idle, isTrue);
  });

  test('a response nothing asked for does not make it negative', () {
    // A request that began before the tracker was attached ends after it, and
    // a count that went below nought would report idle through the next fetch.
    final DVInFlight flight = DVInFlight();
    flight.ended();
    flight.started();

    expect(flight.idle, isFalse);
  });
}
