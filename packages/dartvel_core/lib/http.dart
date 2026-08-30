/// The wire types in full: Request, Response, Headers, Body, URLPattern and
/// Router.
///
/// The main barrel exports only Request, Response and Headers, which is the
/// surface it has always had. Widening it to the whole set broke a downstream
/// application that had its own `Body` -- a generic name, and a reasonable one
/// for an application to use.
///
/// Server code that wants all of them imports this instead.
library dartvel_core.http;

export 'src/http/router.dart' show Router;
export 'src/http/wintercg.dart'
    show Request, Response, Headers, Body, URLPattern;
