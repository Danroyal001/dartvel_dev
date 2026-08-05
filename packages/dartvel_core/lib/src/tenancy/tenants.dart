import 'dart:async';

/// How tenant data is separated.
enum DVTenantIsolation {
  /// One database, one schema, rows scoped by a tenant column.
  sharedDatabase,

  /// One database, a schema per tenant.
  schemaPerTenant,

  /// A database per tenant.
  databasePerTenant,
}

/// Where a request's tenant is read from.
enum DVTenantSource {
  /// The leftmost host label: `acme.example.com` is `acme`.
  subdomain,

  /// A request header, `X-Tenant` by default.
  header,

  /// The first path segment: `/acme/orders` is `acme`.
  pathPrefix,

  /// A query parameter, `tenant` by default.
  queryParameter,
}

/// Resolves a tenant from a request, and holds the tenant the current work is
/// running for.
///
/// `DV.currentTenant` is an alias for [currentTenant].
class DVTenants {
  const DVTenants();

  /// The tenant used when nothing resolves one.
  static const String defaultTenant = 'default';

  static String _current = defaultTenant;
  static DVTenantIsolation _isolation = DVTenantIsolation.sharedDatabase;
  static DVTenantSource _source = DVTenantSource.subdomain;
  static String _headerName = 'x-tenant';
  static String _queryParameterName = 'tenant';
  static Set<String> _ignoredHostLabels = const <String>{'www'};
  static String? Function(Uri uri, Map<String, String> headers)? _resolver;

  /// Host labels that are never a tenant. `www.example.com` is the site, not a
  /// tenant called "www".
  static Set<String> get ignoredHostLabels => _ignoredHostLabels;

  DVTenantIsolation get isolation => _isolation;
  DVTenantSource get source => _source;

  /// Zone key carrying the tenant through [withTenant] scopes.
  static const Symbol _zoneTenant = #dartvelTenant;

  /// The tenant the current work is running for.
  ///
  /// A [withTenant] scope wins over the process-wide tenant: zone values
  /// follow async work across awaits, so a callback keeps its tenant through
  /// its whole body and concurrent scopes cannot bleed into each other.
  String get currentTenant =>
      (Zone.current[_zoneTenant] as String?) ?? _current;

  set currentTenant(String tenant) {
    final trimmed = tenant.trim();
    _current = trimmed.isEmpty ? defaultTenant : trimmed;
  }

  /// Configures resolution. [resolver] overrides [source] entirely, for hosts
  /// that map tenants some other way (a lookup table, a signed token).
  void configure({
    DVTenantIsolation? isolation,
    DVTenantSource? source,
    String? headerName,
    String? queryParameterName,
    Set<String>? ignoredHostLabels,
    String? Function(Uri uri, Map<String, String> headers)? resolver,
  }) {
    if (isolation != null) _isolation = isolation;
    if (source != null) _source = source;
    if (headerName != null) _headerName = headerName.toLowerCase();
    if (queryParameterName != null) _queryParameterName = queryParameterName;
    if (ignoredHostLabels != null) {
      _ignoredHostLabels = ignoredHostLabels
          .map((String label) => label.toLowerCase())
          .toSet();
    }
    if (resolver != null) _resolver = resolver;
  }

  /// Restores the defaults. Intended for tests.
  static void reset() {
    _current = defaultTenant;
    _isolation = DVTenantIsolation.sharedDatabase;
    _source = DVTenantSource.subdomain;
    _headerName = 'x-tenant';
    _queryParameterName = 'tenant';
    _ignoredHostLabels = const <String>{'www'};
    _resolver = null;
  }

  /// The tenant [uri] and [headers] identify, or null when they identify none.
  ///
  /// Returning null rather than [defaultTenant] keeps "no tenant in the
  /// request" distinguishable from "the tenant is literally default", which a
  /// caller may want to reject rather than serve.
  String? resolve(Uri uri, {Map<String, String> headers = const {}}) {
    final normalizedHeaders = <String, String>{
      for (final MapEntry<String, String> entry in headers.entries)
        entry.key.toLowerCase(): entry.value,
    };

    final resolver = _resolver;
    if (resolver != null) {
      return _normalize(resolver(uri, normalizedHeaders));
    }

    switch (_source) {
      case DVTenantSource.subdomain:
        final labels = uri.host.split('.');
        // A tenant subdomain needs a domain under it: `acme.example.com` has
        // one, `example.com` and `localhost` do not.
        if (labels.length < 3) return null;
        final label = labels.first.toLowerCase();
        if (_ignoredHostLabels.contains(label)) return null;
        return _normalize(label);
      case DVTenantSource.header:
        return _normalize(normalizedHeaders[_headerName]);
      case DVTenantSource.pathPrefix:
        final segments = uri.pathSegments;
        return segments.isEmpty ? null : _normalize(segments.first);
      case DVTenantSource.queryParameter:
        return _normalize(uri.queryParameters[_queryParameterName]);
    }
  }

  /// Resolves the tenant for [uri] and makes it current, returning what it
  /// resolved to. Falls back to [defaultTenant] when the request names none.
  String adopt(Uri uri, {Map<String, String> headers = const {}}) {
    final resolved = resolve(uri, headers: headers) ?? defaultTenant;
    currentTenant = resolved;
    return resolved;
  }

  /// Runs [callback] with [tenant] current for its entire execution.
  ///
  /// The tenant is carried by a zone value rather than set-and-restored
  /// around the call: an async callback crosses awaits, and a synchronous
  /// restore would strip its tenant at the first one while the work is still
  /// running. Outside the scope nothing changes, throw or not.
  R withTenant<R>(String tenant, R Function() callback) {
    final trimmed = tenant.trim();
    return runZoned(
      callback,
      zoneValues: <Object?, Object?>{
        _zoneTenant: trimmed.isEmpty ? defaultTenant : trimmed,
      },
    );
  }

  /// The database or schema name for [tenant] under the configured isolation.
  ///
  /// Under [DVTenantIsolation.sharedDatabase] there is nothing to qualify, so
  /// this returns null and callers scope by column instead.
  String? qualifierFor(String tenant, {String base = 'dartvel'}) {
    switch (_isolation) {
      case DVTenantIsolation.sharedDatabase:
        return null;
      case DVTenantIsolation.schemaPerTenant:
      case DVTenantIsolation.databasePerTenant:
        return '${base}_${_slug(tenant)}';
    }
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Tenant ids reach SQL identifiers under per-schema and per-database
  /// isolation, so anything that is not a plain identifier character is
  /// replaced rather than passed through.
  static String _slug(String tenant) {
    final slug = tenant
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (slug.isEmpty) {
      throw ArgumentError.value(
        tenant,
        'tenant',
        'A tenant id needs at least one letter, digit or underscore to be '
            'usable as a schema or database name.',
      );
    }
    return slug;
  }
}
