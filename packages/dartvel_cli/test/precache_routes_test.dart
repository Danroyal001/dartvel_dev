// What the service worker precaches, and where that list comes from.
//
// It came from scanning build/web for directories with an index.html in
// them -- written before the route pages were, so on a clean build there was
// nothing to find and the worker precached the root alone. It only ever
// looked right because a second build ran over the first: the directories
// were still there from last time, the count said four, and deleting
// build/web took it back to one.
//
// That is the worst shape a bug can have. CI always builds clean, so CI
// always shipped the broken artifact; a developer always builds twice, so a
// developer never saw it.
//
// The routes are known before anything is written -- they are the same list
// the prerenderer and the semantics capture work from -- so the worker takes
// them from there and cannot be wrong about the order it ran in.
import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

void main() {
  test('every prerendered route is precached', () {
    expect(
      dvPrecacheRoutes(const <String>['/', '/docs', '/features', '/cloud']),
      containsAll(<String>['/', '/docs', '/features', '/cloud']),
    );
  });

  test('the root is there even when the router never names it', () {
    expect(dvPrecacheRoutes(const <String>['/docs']), contains('/'));
  });

  // A worker that fetches the same address twice on install pays for it
  // twice, on a connection that is the reason it exists.
  test('a route named twice is precached once', () {
    expect(dvPrecacheRoutes(const <String>['/', '/docs', '/docs']),
        <String>['/', '/docs']);
  });

  // A parameterised route is a template, not a page. Precaching the literal
  // "/posts/:id" caches a 404 and makes it the offline answer for every post.
  test('a template is not a page and is not precached', () {
    expect(dvPrecacheRoutes(const <String>['/', '/posts/:id', '/posts/hello']),
        <String>['/', '/posts/hello']);
  });

  test('an empty route list still precaches the root', () {
    expect(dvPrecacheRoutes(const <String>[]), <String>['/']);
  });
}
