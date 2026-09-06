// What the backend does with a request for the admin.
//
// Three answers, and the difference between two of them is the whole
// security posture: a request that is refused because nobody signed in has
// to be indistinguishable from a request for a route that does not exist.
// An admin that answers 401 where the rest of the site answers 404 is an
// oracle -- it tells a scanner that this host is a Dartvel application with
// a studio on it, and where, before anybody has typed a password.
//
// That is the difference between /wp-admin, which announces itself, and an
// admin nobody outside the team can find.
import 'package:dartvel_cli/src/build/admin_mount.dart';
import 'package:dartvel_cli/src/build/admin_serving.dart';
import 'package:test/test.dart';

DVAdminMount _mount({
  String path = '/__studio',
  bool enabled = true,
  bool requiresAuth = false,
}) =>
    DVAdminMount(path: path, enabled: enabled, requiresAuth: requiresAuth);

void main() {
  group('a request that is not the admin', () {
    test('is left to the application', () {
      expect(dvAdminFor('/', _mount(), authenticated: false),
          DVAdminRequest.notTheAdmin);
      expect(dvAdminFor('/products/7', _mount(), authenticated: false),
          DVAdminRequest.notTheAdmin);
    });

    test('including one that merely begins with the same letters', () {
      // /__studios is the application's if it wants it.
      expect(dvAdminFor('/__studios', _mount(), authenticated: false),
          DVAdminRequest.notTheAdmin);
    });
  });

  group('development, where it is meant to just work', () {
    test('the mount is served', () {
      expect(dvAdminFor('/__studio', _mount(), authenticated: false),
          DVAdminRequest.serve);
    });

    test('and so is everything under it', () {
      // The admin owns its subtree: sections, assets, its own main.dart.js.
      expect(dvAdminFor('/__studio/models', _mount(), authenticated: false),
          DVAdminRequest.serve);
      expect(
          dvAdminFor('/__studio/main.dart.js', _mount(), authenticated: false),
          DVAdminRequest.serve);
    });
  });

  group('a deployment that never asked for an admin', () {
    test('does not have one, and does not say it does not', () {
      // Not "disabled", not 403. The same nothing the application returns
      // for any path it does not serve.
      expect(
        dvAdminFor('/__studio', _mount(enabled: false), authenticated: false),
        DVAdminRequest.hidden,
      );
    });
  });

  group('a deployment that has one', () {
    test('an unauthenticated request is hidden, not refused', () {
      // The assertion this file exists for. Refusing it in a way that
      // differs from a missing route confirms the endpoint to somebody who
      // was guessing.
      expect(
        dvAdminFor('/__studio', _mount(requiresAuth: true),
            authenticated: false),
        DVAdminRequest.hidden,
      );
    });

    test('and so is everything under it', () {
      // Otherwise the mount is hidden and /__studio/main.dart.js answers,
      // which gives the whole thing away for the sake of one asset.
      expect(
        dvAdminFor('/__studio/main.dart.js', _mount(requiresAuth: true),
            authenticated: false),
        DVAdminRequest.hidden,
      );
    });

    test('a signed-in request is served', () {
      expect(
        dvAdminFor('/__studio', _mount(requiresAuth: true),
            authenticated: true),
        DVAdminRequest.serve,
      );
    });
  });

  group('what hidden actually looks like', () {
    test('it is the same status as a route the application does not serve', () {
      // Said as a number rather than left to whoever wires the handler: two
      // people implementing "hidden" independently is how one of them
      // becomes a 403.
      expect(dvAdminHiddenStatus, 404);
    });

    test('it carries no header that names the admin', () {
      // A body or header that says "admin" undoes the whole thing.
      for (final String value in dvAdminHiddenHeaders.values) {
        expect(value.toLowerCase(), isNot(contains('admin')));
        expect(value.toLowerCase(), isNot(contains('studio')));
      }
    });
  });

  group('a moved mount behaves the same way', () {
    test('the protection is the mount, not the default path', () {
      // A project that moved the admin somewhere private must not lose the
      // auth check by doing so -- which is what happens if any of this is
      // written against the literal /__studio.
      final DVAdminMount moved =
          _mount(path: '/_ops-9f2a1c', requiresAuth: true);

      expect(dvAdminFor('/_ops-9f2a1c', moved, authenticated: false),
          DVAdminRequest.hidden);
      expect(dvAdminFor('/_ops-9f2a1c', moved, authenticated: true),
          DVAdminRequest.serve);
      expect(dvAdminFor('/__studio', moved, authenticated: true),
          DVAdminRequest.notTheAdmin);
    });
  });
}
