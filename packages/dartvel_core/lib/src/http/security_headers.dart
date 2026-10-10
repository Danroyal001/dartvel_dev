/// The response headers a Dartvel server sends unless a handler chose its own.
///
/// Studio's pages have always carried `X-Frame-Options` and a referrer
/// policy, and a route could opt into more through the `securityHeaders`
/// middleware. An application's own pages and files carried none, so any
/// other site could frame them and a browser was free to sniff a served file
/// into a type it was never sent as. A framework default is the same default
/// in every application, so these are on unless a deployment turns them off.
///
/// What is left out is left out on purpose. A Content-Security-Policy states
/// one application's own scripts and origins, so there is no safe guess for
/// it (`dartvel.security.csp` sets one). `Strict-Transport-Security` is only
/// meaningful on a response that arrived over HTTPS, so [dvApplySecurityHeaders]
/// adds it only when told the connection was TLS; a server behind a proxy
/// that terminates TLS leaves it to the proxy.
library;

import 'wintercg.dart' show Headers;

/// The headers every response gets when it has not set the same name itself.
///
/// `SAMEORIGIN` rather than `DENY`, so an application can still frame its own
/// pages (Studio's preview does); Studio's own pages send `DENY`.
const Map<String, String> dvDefaultSecurityHeaders = <String, String>{
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'SAMEORIGIN',
  'referrer-policy': 'strict-origin-when-cross-origin',
};

/// HSTS for a response served over TLS: one year, no `includeSubDomains`,
/// since a framework cannot know what else runs under the same domain.
const String dvDefaultStrictTransportSecurity = 'max-age=31536000';

/// Adds [baseline] to [headers], keeping any header the handler already set,
/// and HSTS when [overTls] is true.
void dvApplySecurityHeaders(
  Headers headers, {
  Map<String, String> baseline = dvDefaultSecurityHeaders,
  bool overTls = false,
}) {
  baseline.forEach((String name, String value) {
    if (!headers.has(name)) headers.set(name, value);
  });
  if (overTls && !headers.has('strict-transport-security')) {
    headers.set('strict-transport-security', dvDefaultStrictTransportSecurity);
  }
}
