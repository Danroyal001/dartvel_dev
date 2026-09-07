// Which pages reach the client's router.
//
// `dartvel admin` writes its dashboard into lib/pages/_dartvel_admin, and the
// page scanner walks lib/pages -- so the editor, the model browser, the queue
// inspector and the telemetry read-out are compiled into every client the
// application ships. On web that is bundle weight; on mobile it is app size
// and review surface; everywhere it is the admin inheriting the application's
// own guards, shell and theme, so a module with shell: override can change
// the chrome of the screen somebody administers from.
//
// They carry a policy now and refuse by default, which closes the hole. This
// is the other half: where the backend serves the admin, the client should
// not also carry it.
import 'package:dartvel_cli/src/build/admin_mount.dart';
import 'package:test/test.dart';

void main() {
  group('a page under the admin directory', () {
    test('is left out when the backend is serving the admin', () {
      // The mount being enabled is the signal: something else is serving
      // these, so shipping them twice is shipping the editor to everybody
      // for no gain.
      expect(
        dvPageBelongsToClient('lib/pages/_dartvel_admin/studio.page.dart',
            admin: const DVAdminMount(
                path: '/__studio', enabled: true, requiresAuth: false)),
        isFalse,
      );
    });

    test('is kept when nothing else is serving it', () {
      // An application with no backend admin still reaches its dashboard the
      // way it always did. Dropping the pages then would remove the feature
      // rather than move it.
      expect(
        dvPageBelongsToClient('lib/pages/_dartvel_admin/studio.page.dart',
            admin: const DVAdminMount(
                path: '/__studio', enabled: false, requiresAuth: false)),
        isTrue,
      );
    });

    test('is kept when there is no admin configuration at all', () {
      expect(
        dvPageBelongsToClient('lib/pages/_dartvel_admin/studio.page.dart',
            admin: null),
        isTrue,
      );
    });
  });

  group('every other page', () {
    test('is the client\'s, whatever the admin is doing', () {
      const DVAdminMount served = DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: false);

      for (final String page in <String>[
        'lib/pages/index.page.dart',
        'lib/pages/users/[id].page.dart',
        'lib/pages/admin.page.dart',
      ]) {
        expect(dvPageBelongsToClient(page, admin: served), isTrue,
            reason: page);
      }
    });

    test('including one whose directory merely starts the same way', () {
      // lib/pages/_dartvel_admin_notes is somebody's own folder. Taking it
      // would be the framework claiming a name it does not use.
      expect(
        dvPageBelongsToClient(
            'lib/pages/_dartvel_admin_notes/index.page.dart',
            admin: const DVAdminMount(
                path: '/__studio', enabled: true, requiresAuth: false)),
        isTrue,
      );
    });

    test('and one on Windows, where the separator is the other one', () {
      // The scanner hands back whatever the platform's paths look like, and
      // a rule that only knew forward slashes would ship the admin to every
      // client built on Windows and nowhere else.
      expect(
        dvPageBelongsToClient(r'lib\pages\_dartvel_admin\studio.page.dart',
            admin: const DVAdminMount(
                path: '/__studio', enabled: true, requiresAuth: false)),
        isFalse,
      );
    });
  });
}
