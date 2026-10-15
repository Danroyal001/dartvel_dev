/// The site's own server, as a page of it reaches it: what a visitor's
/// browser sends, with no Studio session and no CSRF header. A published
/// form is read and answered through it.
library;

import 'studio_server.dart' show DVStudioTransport;
import 'studio_site_transport_io.dart'
    if (dart.library.js_interop) 'studio_site_transport_web.dart' as site;

/// A transport to the server that served this application.
DVStudioTransport dvStudioSiteTransport() => site.dvSiteSend;
