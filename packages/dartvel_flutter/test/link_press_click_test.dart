// A click the browser sends after a press already navigated.
//
// A link now navigates on the mouse press. On the web the link is also a real
// anchor, and when the button comes up the browser fires `click` on it, which
// the router's interceptor routes -- so the page would be navigated to twice.
// It only happens when the press and the release land on the same element,
// because a browser sends `click` to the common ancestor otherwise, and the
// element survives only when the link does: a header, a sidebar, a tab strip.
// Which is to say the links a site has the most of.
//
// So the press records what it followed, and the interceptor asks before
// routing. The decision is here, off the DOM, so it can be tested on the VM;
// the listener only calls it.
import 'package:dartvel_flutter/src/routing/link_interception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime t0 = DateTime(2026, 9, 11, 12);
  setUp(DVPressedLink.reset);

  test('nothing recorded, nothing swallowed', () {
    expect(DVPressedLink.consume('/docs', now: t0), isFalse);
  });

  test('the click on the path a press just followed is swallowed', () {
    DVPressedLink.record('/docs', now: t0);
    expect(
      DVPressedLink.consume('/docs', now: t0.add(const Duration(milliseconds: 120))),
      isTrue,
    );
  });

  test('only once: the next click on it is a new intention', () {
    DVPressedLink.record('/docs', now: t0);
    DVPressedLink.consume('/docs', now: t0.add(const Duration(milliseconds: 120)));
    expect(
      DVPressedLink.consume('/docs', now: t0.add(const Duration(milliseconds: 900))),
      isFalse,
    );
  });

  test('a click on a different path is followed', () {
    DVPressedLink.record('/docs', now: t0);
    expect(
      DVPressedLink.consume('/features', now: t0.add(const Duration(milliseconds: 120))),
      isFalse,
    );
  });

  test('a record the release never collected goes stale', () {
    // The press navigated and the button came up somewhere else, so no click
    // ever arrived to consume it. A genuine click on the same link later must
    // still be followed.
    DVPressedLink.record('/docs', now: t0);
    expect(
      DVPressedLink.consume('/docs', now: t0.add(dvPressClickWindow + const Duration(milliseconds: 1))),
      isFalse,
    );
  });
}
