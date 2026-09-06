// Where the admin lives, and who may reach it.
//
// The admin is one dashboard for one application, serving every platform
// that application ships to -- so it is not a page in the client. It is
// mounted by the backend, at a path the project chooses.
//
// Two things about that path are worth being careful with.
//
// It is a default, not a constant. /wp-admin is fixed, which is most of why
// it is the most scanned URL on the internet, and a framework that shipped a
// fixed admin path would have created that for every application built with
// it. The default exists so a new project works with no configuration; the
// setting exists so a deployed one can move it.
//
// And it is a route in the same space as the application's own. If a page
// claims the mount, one of the two becomes unreachable, and which one
// depends on the order they were registered in -- so it is refused at build
// time rather than resolved at run time.
import 'package:dartvel_cli/src/build/admin_mount.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Object? _dartvel(String yaml) {
  final Object? document = loadYaml('dartvel:\n$yaml');
  return document is Map ? document['dartvel'] : null;
}

void main() {
  group('the path', () {
    test('a project that says nothing gets the default', () {
      expect(dvAdminMount(null, release: false).path, '/__studio');
    });

    test('a project that names one gets that', () {
      expect(
        dvAdminMount(_dartvel('  admin:\n    path: /_ops-9f2a1c'),
                release: false)
            .path,
        '/_ops-9f2a1c',
      );
    });

    test('a trailing slash is the same mount, not a second one', () {
      // /admin/ and /admin differ only in how they were typed, and two
      // mounts that behave differently for that reason is a support call
      // nobody can reproduce.
      expect(
        dvAdminMount(_dartvel('  admin:\n    path: /admin/'), release: false)
            .path,
        '/admin',
      );
    });

    test('a path with no leading slash is refused, not silently fixed', () {
      // "studio" never matches a request. Repairing it quietly would teach
      // the next person that either form works.
      expect(dvAdminMountProblem('studio'), isNotNull);
      expect(dvAdminMountProblem('studio'), contains('/'));
    });

    test('the root is refused, because it would swallow the application', () {
      expect(dvAdminMountProblem('/'), isNotNull);
      expect(dvAdminMountProblem('/')!.toLowerCase(), contains('application'));
    });

    test('a path with a parameter in it is refused', () {
      // /:id is a template, and a mount is a literal. Accepted, it would
      // match every one-segment route in the application.
      expect(dvAdminMountProblem('/:id'), isNotNull);
    });

    test('an ordinary path has nothing wrong with it', () {
      expect(dvAdminMountProblem('/__studio'), isNull);
      expect(dvAdminMountProblem('/_ops-9f2a1c'), isNull);
      expect(dvAdminMountProblem('/team/admin'), isNull);
    });
  });

  group('whether it is served at all', () {
    test('a debug build serves it, so a new project just works', () {
      expect(dvAdminMount(null, release: false).enabled, isTrue);
    });

    test('a release build does not, unless the project asked', () {
      // The one that matters. An application deployed by somebody who never
      // read this page must not acquire an admin endpoint because a
      // framework thought it would be convenient.
      expect(dvAdminMount(null, release: true).enabled, isFalse);
      expect(
        dvAdminMount(_dartvel('  admin:\n    enabled: true'), release: true)
            .enabled,
        isTrue,
      );
    });

    test('a project can turn it off in development too', () {
      expect(
        dvAdminMount(_dartvel('  admin:\n    enabled: false'), release: false)
            .enabled,
        isFalse,
      );
    });

    test('it always requires authentication once it is released', () {
      // Not a separate setting. An admin reachable without a sign-in on a
      // deployed application is the whole of the risk, and making it
      // optional is offering somebody a way to get it wrong.
      expect(dvAdminMount(_dartvel('  admin:\n    enabled: true'),
              release: true)
          .requiresAuth, isTrue);
    });

    test('development does not, which is what makes it zero-config', () {
      expect(dvAdminMount(null, release: false).requiresAuth, isFalse);
    });
  });

  group('a page that claims the mount', () {
    test('is refused, naming both the page and the setting', () {
      // Whichever of the two is registered second becomes unreachable, and
      // which one that is depends on generation order. A build that picks
      // silently is a build that moves the bug around.
      final String? problem = dvAdminMountConflict(
        '/__studio',
        <String, String>{'/__studio': 'lib/pages/studio.page.dart'},
      );

      expect(problem, isNotNull);
      expect(problem, contains('lib/pages/studio.page.dart'));
      expect(problem, contains('dartvel.admin.path'));
    });

    test('a page underneath the mount is refused too', () {
      // The admin owns everything below its mount: /__studio/models is the
      // admin's own section, and an application page there is shadowed by
      // it rather than colliding visibly.
      expect(
        dvAdminMountConflict('/__studio',
            <String, String>{'/__studio/models': 'lib/pages/models.page.dart'}),
        isNotNull,
      );
    });

    test('a page that merely starts with the same letters is not', () {
      // /__studios is a different route. Refusing it would be a framework
      // taking a name it does not use.
      expect(
        dvAdminMountConflict('/__studio',
            <String, String>{'/__studios': 'lib/pages/studios.page.dart'}),
        isNull,
      );
    });

    test('an application with no page near it is fine', () {
      expect(
        dvAdminMountConflict('/__studio',
            <String, String>{'/': 'lib/pages/index.page.dart'}),
        isNull,
      );
    });
  });
}
