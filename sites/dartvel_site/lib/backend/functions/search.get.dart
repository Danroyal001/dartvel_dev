import 'package:dartvel_core/dartvel.dart';

import '../site_search.dart';

/// GET /api/search?q=...: the site search behind the search box.
///
/// Rate limited per caller with the framework's own limit: the caller is the
/// connection's address, or the address the trusted proxy in front of the
/// server says it forwarded, never a header a client wrote. A caller over
/// the limit is answered 429 with Retry-After.
@DVUseMiddleware(<DVMiddlewareKey>[DVMiddlewares.rateLimit])
@DVBackendFunction()
Future<List<Map<String, Object?>>> _search(String q) async => <Map<String, Object?>>[
      for (final SiteSearchResult result in await siteSearch(q)) result.toJson(),
    ];
