// A route is a URL, not a filesystem path. Deriving one from a file layout
// means the separator the host happens to use must not survive into it.
//
// Windows found this the hard way. A backend function at
// `lib\backend\functions\user\[id].delete.dart` produced the route
// `\user\:id`, which was then written into a Dart string literal as
// '\user\:id' — and `\u` is an invalid escape, so functions.g.dart failed to
// parse and every generated symbol in it disappeared. Forty cascading errors,
// none of them about separators.
//
// The tests assert an invariant rather than an expected string: the same
// relative path, written either way, must produce the same route. That holds
// no matter how the route conventions change.
import 'package:dartvel_cli/src/generators/route_utils.dart';
import 'package:test/test.dart';

void main() {
  group('route derivation ignores the host separator', () {
    const cases = <String>[
      'lib/backend/functions/user/[id].delete.dart',
      'lib/backend/functions/index.get.dart',
      'lib/backend/functions/hello.get.dart',
      'lib/backend/functions/db/todos/[id].put.dart',
      'lib/backend/functions/files/[...path].get.dart',
      'lib/backend/functions/(admin)/users.get.dart',
    ];

    for (final posix in cases) {
      test('$posix resolves the same with backslashes', () {
        final windows = posix.replaceAll('/', r'\');
        expect(
          RouteUtils.routeFromRel(windows, 'lib/backend'),
          RouteUtils.routeFromRel(posix, 'lib/backend'),
          reason: 'a route is a URL; the host separator must not reach it',
        );
      });
    }

    test('no derived route contains a backslash', () {
      // The property that actually broke the build: a backslash in a route
      // becomes an escape sequence in generated Dart.
      for (final posix in cases) {
        final windows = posix.replaceAll('/', r'\');
        expect(
          RouteUtils.routeFromRel(windows, 'lib/backend'),
          isNot(contains(r'\')),
          reason: '$windows produced a route containing a backslash',
        );
      }
    });

    test('a backend directory given with backslashes still strips', () {
      // The prefix is stripped with a regex built from backendDir, so it has
      // to survive the same normalisation.
      expect(
        RouteUtils.routeFromRel(
          r'lib\backend\functions\hello.get.dart',
          r'lib\backend',
        ),
        RouteUtils.routeFromRel(
          'lib/backend/functions/hello.get.dart',
          'lib/backend',
        ),
      );
    });
  });
}
