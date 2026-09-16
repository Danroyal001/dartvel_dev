// Route order: which of two routes a URL reaches first.
//
// go_router matches the first route in its list that fits, so a parameter
// route listed ahead of a static one makes the static one unreachable, with
// no error and no warning. File routes were emitted in file-name order, where
// `[id].dart` sorts before `new.dart`, and config routes arrive in whatever
// order somebody typed them. Both now pass through one ordering, and the
// order that cannot be satisfied is a named error rather than a dead page.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('dvRouteShape', () {
    test('parameter names and a trailing slash do not make routes differ', () {
      expect(dvRouteShape('/users/:id'), dvRouteShape('/users/:slug'));
      expect(dvRouteShape('/users/'), dvRouteShape('/users'));
      expect(dvRouteShape('/'), '/');
    });

    test('a static segment is not a parameter', () {
      expect(dvRouteShape('/users/new'), isNot(dvRouteShape('/users/:id')));
    });
  });

  group('dvRoutesOverlap', () {
    test('a static path and the parameter route that also matches it', () {
      expect(dvRoutesOverlap('/users/new', '/users/:id'), isTrue);
    });

    test('different statics never meet', () {
      expect(dvRoutesOverlap('/users/new', '/teams/:id'), isFalse);
    });

    test('different lengths never meet, unless one is a catch-all', () {
      expect(dvRoutesOverlap('/users', '/users/:id'), isFalse);
      expect(dvRoutesOverlap('/docs/a/b', '/docs/*rest'), isTrue);
    });
  });

  group('dvOrderRoutes', () {
    List<String> order(List<String> paths) =>
        dvOrderRoutes<String>(paths, (String p) => <String>[p]);

    test(
      'a static route comes before the parameter route that would hide it',
      () {
        expect(order(<String>['/users/:id', '/users/new']), <String>[
          '/users/new',
          '/users/:id',
        ]);
      },
    );

    test('unrelated routes keep the order they were given in', () {
      expect(order(<String>['/b', '/a', '/c/:x']), <String>[
        '/b',
        '/a',
        '/c/:x',
      ]);
    });

    test('a catch-all goes after everything it would swallow', () {
      expect(
        order(<String>['/docs/*rest', '/docs/:page', '/docs/intro']),
        <String>['/docs/intro', '/docs/:page', '/docs/*rest'],
      );
    });

    test('a group moves as one: a shell is not split across the list', () {
      final List<List<String>> groups = <List<String>>[
        <String>['/feed', '/users/:id'],
        <String>['/users/new'],
      ];
      expect(
        dvOrderRoutes<List<String>>(groups, (List<String> g) => g),
        <List<String>>[
          <String>['/users/new'],
          <String>['/feed', '/users/:id'],
        ],
      );
    });

    test('a group that has to be both before and after another is refused', () {
      final List<List<String>> groups = <List<String>>[
        <String>['/a/:x', '/b/new'],
        <String>['/a/new', '/b/:x'],
      ];
      expect(
        () => dvOrderRoutes<List<String>>(groups, (List<String> g) => g),
        throwsA(
          isA<DVRouteOrderException>().having(
            (DVRouteOrderException e) => e.toString(),
            'message',
            allOf(
              contains('DV-ROUTE-004'),
              contains('/a/new'),
              contains('/b/new'),
            ),
          ),
        ),
      );
    });
  });

  test('the four DV-ROUTE codes are registered as build errors', () {
    for (final String code in <String>[
      'DV-ROUTE-001',
      'DV-ROUTE-002',
      'DV-ROUTE-003',
      'DV-ROUTE-004',
    ]) {
      expect(DVDiagnostics.find(code)?.level, 'error', reason: code);
    }
  });
}
