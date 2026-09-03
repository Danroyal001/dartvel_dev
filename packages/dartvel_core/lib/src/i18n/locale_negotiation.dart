/// Choosing which language to answer in.
///
/// Listed in the specification as "route locale negotiation" and never built,
/// so an application with translated catalogues had no way to pick between
/// them: every request got the fallback and the translations were dead weight.
///
/// Everything that goes wrong here goes wrong quietly. A q-value read in the
/// wrong order serves French to a German speaker; `q=0` honoured as a
/// preference serves the one language the client said it could not read; an
/// unknown first path segment taken for a locale eats the first segment of
/// every URL. None of them throw.
library dartvel.i18n.locale_negotiation;

/// Where a chosen locale came from.
enum DVLocaleSource { path, preference, header, tenant, fallback }

/// The locale to answer in, and the route with any locale prefix removed.
class DVLocaleChoice {
  const DVLocaleChoice({
    required this.locale,
    required this.source,
    required this.path,
  });

  /// Always one of the supported locales, spelled as they are: a caller looks
  /// the catalogue up by this string.
  final String locale;

  final DVLocaleSource source;

  /// The route without its locale segment.
  final String path;
}

/// Picks a locale from a path prefix, a stored preference and Accept-Language.
///
/// Precedence is path, then preference, then header, then [tenantDefault],
/// then [fallback]. The path wins because it is in the URL the user shared, so
/// it has to survive being opened by someone whose browser prefers another
/// language. A stored preference beats the header because the user chose it,
/// where Accept-Language is whatever their OS was installed as. A tenant's
/// default never overrides what a person asked for; it is what they get when
/// they asked for nothing, and it is skipped when the application does not
/// support it, or a tenant configured for a removed catalogue would pin every
/// visitor to a locale nothing can render.
DVLocaleChoice dvNegotiateLocale({
  required List<String> supported,
  required String fallback,
  String? path,
  String? acceptLanguage,
  String? preferred,
  String? tenantDefault,
}) {
  final String route = (path == null || path.isEmpty) ? '/' : path;

  // The path first, and only when the segment is a locale that exists --
  // otherwise "/orders" reads as locale "orders" with an empty path.
  final List<String> segments =
      route.split('/').where((String s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty) {
    final String? matched = _exact(supported, segments.first);
    if (matched != null) {
      final String rest = segments.skip(1).join('/');
      return DVLocaleChoice(
        locale: matched,
        source: DVLocaleSource.path,
        path: rest.isEmpty ? '/' : '/$rest',
      );
    }
  }

  // A stale preference naming a locale that has since been removed must not
  // pin the user to it.
  if (preferred != null) {
    final String? matched = _best(supported, preferred);
    if (matched != null) {
      return DVLocaleChoice(
        locale: matched,
        source: DVLocaleSource.preference,
        path: route,
      );
    }
  }

  final String? fromHeader = _fromAcceptLanguage(supported, acceptLanguage);
  if (fromHeader != null) {
    return DVLocaleChoice(
      locale: fromHeader,
      source: DVLocaleSource.header,
      path: route,
    );
  }

  if (tenantDefault != null) {
    final String? matched = _best(supported, tenantDefault);
    if (matched != null) {
      return DVLocaleChoice(
        locale: matched,
        source: DVLocaleSource.tenant,
        path: route,
      );
    }
  }

  return DVLocaleChoice(
    locale: fallback,
    source: DVLocaleSource.fallback,
    path: route,
  );
}

/// The best supported locale for an Accept-Language header.
String? _fromAcceptLanguage(List<String> supported, String? header) {
  if (header == null || header.trim().isEmpty) return null;

  final List<({String tag, double q, int order})> wanted =
      <({String tag, double q, int order})>[];
  var order = 0;
  for (final String part in header.split(',')) {
    final List<String> bits = part.split(';');
    final String tag = bits.first.trim();
    if (tag.isEmpty) continue;

    var q = 1.0;
    for (final String bit in bits.skip(1)) {
      final List<String> kv = bit.split('=');
      if (kv.length != 2 || kv.first.trim().toLowerCase() != 'q') continue;
      // An unparseable q is unweighted rather than zero: zero would mean the
      // client refuses this language, which it did not say.
      q = double.tryParse(kv[1].trim()) ?? 1.0;
    }
    wanted.add((tag: tag, q: q, order: order++));
  }

  wanted.sort((({String tag, double q, int order}) a,
          ({String tag, double q, int order}) b) =>
      a.q == b.q ? a.order.compareTo(b.order) : b.q.compareTo(a.q));

  for (final ({String tag, double q, int order}) entry in wanted) {
    // q=0 is "not acceptable". Serving it would hand the client the one
    // language it said it could not read.
    if (entry.q <= 0) continue;
    // "*" means "anything else", which names no particular locale, so the
    // fallback is the honest answer rather than whichever is listed first.
    if (entry.tag == '*') continue;
    final String? matched = _best(supported, entry.tag);
    if (matched != null) return matched;
  }
  return null;
}

/// A supported locale equal to [tag], ignoring case.
String? _exact(List<String> supported, String tag) {
  final String wanted = tag.toLowerCase();
  for (final String candidate in supported) {
    if (candidate.toLowerCase() == wanted) return candidate;
  }
  return null;
}

/// The closest supported locale to [tag].
///
/// Exact first, then progressively shorter prefixes of the request -- `fr-CA`
/// falls back to `fr` -- and finally a supported locale that starts with the
/// request, so a bare `de` finds `de-DE`. Prefixes are compared on whole
/// subtags, or `de` would match `de-DE` and also `dez`.
String? _best(List<String> supported, String tag) {
  final String wanted = tag.trim();
  if (wanted.isEmpty) return null;

  final String? exact = _exact(supported, wanted);
  if (exact != null) return exact;

  final List<String> parts = wanted.toLowerCase().split('-');
  for (var take = parts.length - 1; take >= 1; take--) {
    final String shorter = parts.take(take).join('-');
    final String? matched = _exact(supported, shorter);
    if (matched != null) return matched;
  }

  for (var take = parts.length; take >= 1; take--) {
    final String prefix = '${parts.take(take).join('-')}-';
    for (final String candidate in supported) {
      if (candidate.toLowerCase().startsWith(prefix)) return candidate;
    }
  }
  return null;
}
