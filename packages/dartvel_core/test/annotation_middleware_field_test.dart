// Middleware is declared on the annotation that declares the thing it guards:
//
//     @DVBackendFunction(middleware: [DVMiddlewares.rateLimit])
//     @DVPage(title: 'Account', middleware: [DVMiddlewares.auth])
//
// The generators read these from source, so what this holds is the other
// half: that the argument exists, keeps the order it was written in, and
// that leaving it out declares nothing rather than something.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('a backend function carries the middleware it declares, in order', () {
    const DVBackendFunction fn = DVBackendFunction(
      policy: 'Order.create',
      middleware: <DVMiddlewareKey>[
        DVMiddlewares.securityHeaders,
        DVMiddlewares.rateLimit,
      ],
    );

    expect(
      fn.middleware.map((DVMiddlewareKey k) => k.name),
      <String>['securityHeaders', 'rateLimit'],
    );
    // Additive: the arguments that were there keep meaning what they meant.
    expect(fn.policy, 'Order.create');
  });

  test('a page carries the middleware it declares, in order', () {
    const DVPage page = DVPage(
      title: 'Account',
      middleware: <DVMiddlewareKey>[
        DVMiddlewares.maintenance,
        DVMiddlewares.auth,
      ],
    );

    expect(
      page.middleware.map((DVMiddlewareKey k) => k.name),
      <String>['maintenance', 'auth'],
    );
    expect(page.title, 'Account');
  });

  test('declaring nothing is an empty list, not a guard', () {
    expect(const DVBackendFunction().middleware, isEmpty);
    expect(const DVPage().middleware, isEmpty);
  });
}
