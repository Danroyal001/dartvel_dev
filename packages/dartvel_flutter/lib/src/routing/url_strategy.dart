/// Path URLs on the web, behind a conditional import so no other target sees
/// `flutter_web_plugins`.
///
/// Flutter web defaults to the hash strategy, which puts every route behind a
/// `#`. That is not untidy, it is broken for a site: the browser asks for
/// `/docs`, the app boots, and the router sees only `/`, so every deep link
/// renders the home page. A crawler indexes `/#/docs` as `/`, and a shared
/// link opens the wrong page.
///
/// It requires the server to serve `index.html` for unknown paths, which is
/// what the generated `.htaccess` and `dartvel deploy` configuration do.
library dartvel_flutter.routing.url_strategy;

export 'url_strategy_stub.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
