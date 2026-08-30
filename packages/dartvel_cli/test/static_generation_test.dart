// Turning a route template and its resolved values into concrete paths.
//
// A route like /posts/:slug is not a page. It is a shape, and the generator
// has to know which pages it stands for before it can write any of them --
// which is the whole difference between a router that matches at run time and
// a static site that has to exist on disk beforehand.
import 'package:dartvel_cli/src/build/static_generation.dart';
import 'package:test/test.dart';

void main() {
  group('expanding one template', () {
    test('a single parameter is substituted', () {
      expect(dvExpandStaticPath('/posts/:slug', 'hello-world'),
          '/posts/hello-world');
    });

    test('the value is URL-encoded, because a path is a URL', () {
      // A title used as a slug can contain anything. Writing it raw produces
      // a path the server will not match and a file name that may not be
      // legal.
      expect(dvExpandStaticPath('/posts/:slug', 'hello world'),
          '/posts/hello%20world');
      expect(dvExpandStaticPath('/posts/:slug', 'a/b'), '/posts/a%2Fb');
    });

    test('a template with no parameter is itself', () {
      expect(dvExpandStaticPath('/about', 'ignored'), '/about');
    });

    test('only the first parameter is filled', () {
      // Two parameters need two values and this takes one, so the honest
      // thing is to refuse rather than half-fill it and write a page at a
      // path containing a literal colon.
      expect(() => dvExpandStaticPath('/a/:x/b/:y', 'v'), throwsArgumentError);
    });
  });

  group('the pages a manifest stands for', () {
    test('every value becomes a path', () {
      final List<String> paths = dvStaticPathsFor(
        <String, Object?>{
          'route': '/posts/:slug',
          'values': <Object?>['first', 'second'],
        },
      );

      expect(paths, <String>['/posts/first', '/posts/second']);
    });

    test('an entry with no route produces nothing', () {
      // A provider that never declared its route cannot be turned into a
      // page, and guessing one would put the page at an address the router
      // does not serve.
      expect(
        dvStaticPathsFor(<String, Object?>{
          'route': null,
          'values': <Object?>['first'],
        }),
        isEmpty,
      );
    });

    test('duplicates collapse', () {
      // Two providers can resolve the same value, and writing the same file
      // twice is a race rather than a duplicate.
      expect(
        dvStaticPathsFor(<String, Object?>{
          'route': '/posts/:slug',
          'values': <Object?>['a', 'a', 'b'],
        }),
        <String>['/posts/a', '/posts/b'],
      );
    });

    test('an empty value is skipped rather than writing the parent', () {
      // /posts/ is the index, not a post, and generating it from an empty
      // slug would overwrite a real page with one that has no content.
      expect(
        dvStaticPathsFor(<String, Object?>{
          'route': '/posts/:slug',
          'values': <Object?>['', '  ', 'real'],
        }),
        <String>['/posts/real'],
      );
    });
  });

  group('which routes still need expanding', () {
    test('a parameterised route is not a page on its own', () {
      expect(dvIsTemplateRoute('/posts/:slug'), isTrue);
      expect(dvIsTemplateRoute('/about'), isFalse);
      expect(dvIsTemplateRoute('/'), isFalse);
    });

    test('a template is dropped from the routes written directly', () {
      // Writing /posts/:slug as a file produces a directory with a colon in
      // its name that nothing will ever request.
      expect(
        dvConcreteRoutes(<String>['/', '/about', '/posts/:slug']),
        <String>['/', '/about'],
      );
    });
  });

  group('pages the router will actually serve', () {
    test('a resolved path whose template is not a route is refused', () {
      // The manifest derives its route from the model's name, and nothing
      // checked the router had one. That generated /products/pro-kit at an
      // address the application 404s on: a crawler follows it, gets HTML, the
      // app boots and shows its own not-found page.
      expect(
        dvServedStaticPaths(
          <String>['/products/pro-kit', '/blog/7'],
          declared: <String>['/', '/blog/:id'],
        ),
        <String>['/blog/7'],
      );
    });

    test('a path matching a declared template is kept', () {
      expect(
        dvServedStaticPaths(
          <String>['/posts/hello'],
          declared: <String>['/posts/:slug'],
        ),
        <String>['/posts/hello'],
      );
    });

    test('segment counts have to match', () {
      // /posts/:slug does not serve /posts/a/b, and generating it would put a
      // page somewhere the router cannot reach.
      expect(
        dvServedStaticPaths(
          <String>['/posts/a/b'],
          declared: <String>['/posts/:slug'],
        ),
        isEmpty,
      );
    });

    test('a literal segment must match literally', () {
      expect(
        dvServedStaticPaths(
          <String>['/pages/hello'],
          declared: <String>['/posts/:slug'],
        ),
        isEmpty,
      );
    });

    test('which templates were never served', () {
      // Reported by name, because a model that generates no pages at all is
      // the failure this is meant to make visible.
      expect(
        dvUnservedTemplates(
          <String>['/products/:slug', '/blog/:id'],
          declared: <String>['/', '/blog/:id'],
        ),
        <String>['/products/:slug'],
      );
    });
  });
}
