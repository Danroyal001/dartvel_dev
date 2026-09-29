// The two routes an app has when a page cannot be shown, as routes.
//
// Both were documents of their own: `pwa_service_worker.dart` wrote a
// hand-written 404 and a hand-written offline page, and the service worker
// served the second when a navigation failed. That put two pages in the
// application that no `@DVPage` declared, no theme reached, no capture saw
// and no reader could edit -- and the offline page, being the one shown when
// the network is gone, could not have been a real page even in principle.
//
// They are routes now: the generator declares them, `dvRenderRoutePage`
// renders them, and the worker redirects to the offline one.
//
// The constants live here rather than in either package that needs them. The
// CLI declares the routes and the worker redirects to one, and it does not
// depend on `dartvel_flutter` where the widgets are drawn; `dartvel_flutter`
// needs the same two strings to build the pages. One place, so a rename
// cannot leave the worker pointing at a path the app does not serve.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('the routes themselves', () {
    test('are the paths a person can see, without a file extension', () {
      expect(dvNotFoundRoute, '/404');
      expect(dvOfflineRoute, '/offline');
    });

    test('are absolute, so a build mounted under a subpath can still join '
        'them', () {
      expect(dvNotFoundRoute, startsWith('/'));
      expect(dvOfflineRoute, startsWith('/'));
    });

    test('differ from each other', () {
      expect(dvNotFoundRoute, isNot(dvOfflineRoute));
    });
  });

  group('recognising an error route', () {
    // The build has to leave both out of the sitemap and the page list a
    // crawler is offered, and it has to know it by the path it was asked
    // about rather than by the shape of that path: a trailing slash, a
    // mounted prefix, a query the offline page carries.
    test('the bare paths are error pages', () {
      expect(dvIsErrorPageRoute('/404'), isTrue);
      expect(dvIsErrorPageRoute('/offline'), isTrue);
    });

    test('so is either served with a trailing slash', () {
      expect(dvIsErrorPageRoute('/404/'), isTrue);
      expect(dvIsErrorPageRoute('/offline/'), isTrue);
    });

    test('so is one carrying the query the worker adds', () {
      expect(dvIsErrorPageRoute('/offline?from=%2Farticles'), isTrue);
      expect(dvIsErrorPageRoute('/404/'), isTrue);
    });

    test('so is one carrying a fragment, which never reaches a server but '
        'does reach a link', () {
      expect(dvIsErrorPageRoute('/404#main'), isTrue);
    });

    test('a site under a mount is recognised once the mount is stripped, '
        'which is how a build asks about it', () {
      const String mount = '/app';
      String relative(String path) =>
          path.startsWith(mount) ? path.substring(mount.length) : path;
      expect(dvIsErrorPageRoute(relative('$mount/404')), isTrue);
      expect(dvIsErrorPageRoute(relative('$mount/offline/')), isTrue);
    });

    test('an ordinary page is not one, however it is spelled', () {
      expect(dvIsErrorPageRoute('/'), isFalse);
      expect(dvIsErrorPageRoute('/articles'), isFalse);
      expect(dvIsErrorPageRoute('/4040'), isFalse);
      expect(dvIsErrorPageRoute('/404-help'), isFalse);
      expect(dvIsErrorPageRoute('/offline-notes'), isFalse);
    });

    test('a path that only ends like one is not', () {
      // `/x/404` is a page whose own slug is 404 -- a numbered recipe, a
      // product code. Reading it as the error page would delete a page from
      // the sitemap and hand its visitors a dead end.
      expect(dvIsErrorPageRoute('/x/404'), isFalse);
      expect(dvIsErrorPageRoute('/blog/404'), isFalse);
    });

    test('an empty or nonsensical path is not', () {
      expect(dvIsErrorPageRoute(''), isFalse);
      expect(dvIsErrorPageRoute('404'), isFalse);
    });
  });

  group('the page a failure redirects to', () {
    // The worker writes the failure URL into `from` so the person lands back
    // where they were once the network is back. That value is a URL somebody
    // can write, and following it would be an open redirect on the
    // application's own offline page.
    test('is the safe path for a path in this application', () {
      expect(dvOfflineReturn('/articles/one'), '/articles/one');
      expect(dvOfflineReturn('/articles/one?page=2'), '/articles/one?page=2');
    });

    test('is the home page for anything that could leave the site', () {
      expect(dvOfflineReturn('//evil.example'), '/');
      expect(dvOfflineReturn('https://evil.example'), '/');
      expect(dvOfflineReturn(r'/\evil.example'), '/');
      expect(dvOfflineReturn('javascript:alert(1)'), '/');
    });

    test('is the home page for nothing at all', () {
      expect(dvOfflineReturn(null), '/');
      expect(dvOfflineReturn(''), '/');
    });

    test('is never the offline page itself, which is a loop', () {
      // `/offline?from=/offline` is what a failure *serving* the offline page
      // would write, and following it is a redirect that never lands.
      expect(dvOfflineReturn('/offline'), '/');
      expect(dvOfflineReturn('/offline?from=%2F'), '/');
      expect(dvOfflineReturn('/offline/'), '/');
    });

    test('is the home page when the path cannot be parsed at all', () {
      expect(dvOfflineReturn('http://['), '/');
    });
  });
}
