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

/// What a generated query names, for the tenant the current work is for.
///
/// Called by every generated model statement. Under [DVTenantIsolation
/// .sharedDatabase] this is the table's own name and the separation is the
/// column, so nothing changes for the strategy almost everyone uses.
///
/// Under [DVTenantIsolation.schemaPerTenant] the name is qualified, which is
/// the whole of that strategy: one database, a schema each. Under
/// [DVTenantIsolation.databasePerTenant] it is not, because there the
/// connection differs and qualifying the name as well would look for a
/// schema inside the tenant's own database, which is not where its tables
/// are.
///
/// This is what those two strategies were missing. The enum values existed,
/// [DVTenants.qualifierFor] built the name correctly and was unit tested,
/// and nothing anywhere called it -- so configuring either produced exactly
/// the queries sharedDatabase produces against exactly the same database.
/// Every query returned rows and the separation somebody selected was simply
/// not there.
String dvTenantTable(String table) {
  const DVTenants tenants = DVTenants();
  if (tenants.isolation != DVTenantIsolation.schemaPerTenant) return table;
  final String? qualifier = tenants.qualifierFor(tenants.currentTenant);
  return qualifier == null ? table : '$qualifier.$table';
}

/// The tables whose rows belong to a tenant, registered by the generated
/// client.
///
/// Held rather than derived because the check runs in the database layer,
/// which has no idea what a model is. The generated registration is the only
/// place that knows, and it runs before anything queries.
final Set<String> _scopedTables = <String>{};

/// Records which tables carry the tenant column. Called by generated code.
///
/// Added rather than replaced, because more than one generated client runs
/// in a process: an application registers its own and every module it mounts
/// registers the module's, and a call that replaced would leave whichever
/// ran last as the only scoped set -- so the other's tables would go
/// unchecked, silently, on the strategy where the column is the only thing
/// separating tenants.
void dvRegisterTenantScopedTables(Set<String> tables) {
  _scopedTables.addAll(tables);
}

/// Forgets every registered table. Called by [DVTenants.reset].
void dvResetTenantScopedTables() => _scopedTables.clear();

/// The tables currently registered as tenant-scoped.
Set<String> get dvTenantScopedTables => Set<String>.unmodifiable(_scopedTables);

/// The scoped tables a statement names without scoping by tenant.
///
/// Generated model queries carry the predicate. Everything else does not: a
/// report, a dashboard count, a join the generator cannot express, a query
/// written before the model was scoped. Each returns rows, the numbers look
/// plausible, and one tenant is shown another tenant's data.
///
/// Deliberately coarse. It knows which tables are scoped because the
/// generator registered them, and it looks for the column in the statement.
/// A false positive is a refusal somebody reads and fixes; a false negative
/// leaves today's behaviour exactly as it is. What it must never do is guess
/// quietly in the direction of allowing.
///
/// Only under [DVTenantIsolation.sharedDatabase]. Under the other two the
/// separation is the schema or the connection, and a predicate on a column
/// that is not there would fail every query.
List<String> dvUnscopedTablesIn(String sql) {
  if (const DVTenants().isolation != DVTenantIsolation.sharedDatabase) {
    return const <String>[];
  }
  if (_scopedTables.isEmpty) return const <String>[];
  final String lower = sql.toLowerCase();
  if (lower.contains(dvTenantColumnName)) return const <String>[];
  return <String>[
    for (final String table in _scopedTables)
      // On a word boundary: "orders" inside "workorders" is a different
      // table, and refusing it would teach people to reach for the escape
      // hatch out of habit.
      if (RegExp('(?<![A-Za-z0-9_])${RegExp.escape(table.toLowerCase())}'
              '(?![A-Za-z0-9_])')
          .hasMatch(lower))
        table,
  ];
}

/// The column a tenant-scoped row carries, as the check looks for it.
const String dvTenantColumnName = 'dv_tenant';

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

  /// Whether a [withTenant] scope is carrying the tenant for this work.
  ///
  /// What reads it is code deciding whether to write the process-wide
  /// tenant. Under a scope that write reaches every other request in the
  /// isolate and belongs to none of them.
  static bool get hasScope => Zone.current[_zoneTenant] != null;

  set currentTenant(String tenant) {
    final trimmed = tenant.trim();
    _current = trimmed.isEmpty ? defaultTenant : trimmed;
  }

  /// Each tenant's default locale, by tenant id.
  ///
  /// A multi-tenant application serves companies whose users mostly share a
  /// language, and the application's fallback is the wrong answer for a
  /// French tenant's visitor who sent no Accept-Language. This sits between
  /// the visitor's own signals and the application's fallback in
  /// `dvNegotiateLocale`: it never overrides what a person asked for.
  static final Map<String, String> _localeDefaults = <String, String>{};

  /// Sets [tenant]'s default locale.
  static void setLocaleDefault(String tenant, String locale) {
    _localeDefaults[tenant.trim()] = locale.trim();
  }

  /// Forgets every tenant's default. Tests use this.
  static void clearLocaleDefaults() => _localeDefaults.clear();

  /// [tenant]'s default locale, or null when it has none.
  String? localeDefaultFor(String tenant) => _localeDefaults[tenant.trim()];

  /// The current tenant's default locale, or null.
  String? get currentLocaleDefault => localeDefaultFor(currentTenant);

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
    dvResetTenantScopedTables();
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
