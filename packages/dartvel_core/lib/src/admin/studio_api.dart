/// Studio's data, served under the admin mount.
///
/// The dashboard a web-server binary carried was a static manifest: it could
/// name a model and show none of its records, because the backend offered it
/// nothing to read. These are the endpoints the full Studio reads and writes
/// through -- a model's records, the page builder's documents, the grants --
/// and they are the admin's, so [DVAdminServer] answers them only for a
/// caller it would serve the dashboard to. Everybody else gets the same
/// nothing an unknown route gets.
///
/// A record goes through [DVRecordTable], the one write path the rest of the
/// runtime reads, so an edit in Studio is checked against the version it was
/// read at, lands in history and capture, and is scoped to the request's
/// tenant exactly as a model's own save is. A sensitive field is never sent
/// and cannot be written: Studio is one of the places the specification
/// keeps those out of by default.
library;

import 'dart:async';
import 'dart:convert';

import '../data/record_history.dart';
import '../database/adapter.dart';
import '../http/wintercg.dart';
import '../schema/generated_schema.dart' show dvTenantColumn;
import '../tenancy/tenants.dart';
import 'studio_access.dart';

/// One field of a model, as Studio edits it.
class DVStudioFieldSpec {
  const DVStudioFieldSpec({
    required this.name,
    required this.type,
    this.sensitive = false,
  });

  final String name;

  /// The declared Dart type, with `?` when nullable.
  final String type;

  /// Never sent to Studio, and refused when Studio sends it.
  final bool sensitive;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type,
    if (sensitive) 'sensitive': true,
  };
}

/// Where one model's records are, generated beside the model.
class DVStudioModelSpec {
  const DVStudioModelSpec({
    required this.model,
    required this.table,
    required this.key,
    required this.fields,
    this.tenantScoped = false,
    this.versioned = true,
    this.softDelete = false,
  });

  final String model;

  /// The plain table name; the tenant's schema is resolved per request.
  final String table;

  /// The field records are found by.
  final String key;
  final List<DVStudioFieldSpec> fields;
  final bool tenantScoped;
  final bool versioned;
  final bool softDelete;

  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    'key': key,
    'fields': <Object?>[
      for (final DVStudioFieldSpec field in fields) field.toJson(),
    ],
    'versioned': versioned,
    'softDelete': softDelete,
  };
}

/// A refusal with a status and a code Studio can show.
class _StudioRefusal implements Exception {
  _StudioRefusal(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

}

/// The table page documents are kept in: the one `DVPageStore` writes.
const String dvStudioPagesTable = 'dartvel_pages';

/// The Studio API, for requests already decided to be the admin's and
/// allowed.
class DVStudioApi {
  DVStudioApi({this.models = const <DVStudioModelSpec>[], this.database});

  final List<DVStudioModelSpec> models;

  /// The application's database. Null answers every data endpoint 503: a
  /// process with no database has no records, pages or grants to show.
  final DVDatabaseAdapter? database;

  static const Map<String, String> _headers = <String, String>{
    'content-type': 'application/json; charset=utf-8',
    // A proxy that kept one operator's records would serve them to the next
    // person who asked.
    'cache-control': 'no-store',
  };

  /// The answer to [request], whose path below the API is [rest] (no
  /// leading slash).
  Future<Response> respond(Request request, String rest) async {
    try {
      final String method = request.method.toUpperCase();
      if (method != 'GET' && method != 'HEAD') _requireCsrf(request);
      final List<String> segments = rest
          .split('/')
          .where((String s) => s.isNotEmpty)
          .map(Uri.decodeComponent)
          .toList(growable: false);
      if (segments.isEmpty) {
        throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
      }
      switch (segments.first) {
        case 'models':
          return await _models(request, method, segments.sublist(1));
        case 'pages':
          return await _pages(request, method);
        case 'grants':
          if (segments.length == 1 && method == 'GET') return await _grants();
      }
      throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
    } on _StudioRefusal catch (refusal) {
      return _reply(<String, Object?>{
        'error': refusal.code,
        'message': refusal.message,

      }, status: refusal.status);
    } on DVConflictError catch (conflict) {
      return _reply(<String, Object?>{
        'error': 'conflict',
        'message':
            'The record changed after it was read. Reload it and '
            'make the edit again.',
        'version': conflict.actualVersion,
      }, status: 409);
    }
  }

  Response _reply(Object? body, {int status = 200}) => Response(
    status,
    headers: Headers(_headers),
    body: Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
  );

  /// A write has to carry the CSRF header. A cross-site form cannot set a
  /// header, and the session cookie is what would otherwise authenticate it.
  void _requireCsrf(Request request) {
    final String? token = request.headers.get('x-dartvel-csrf-token');
    if (token == null || token.trim().length < 16) {
      throw _StudioRefusal(
        403,
        'csrf',
        'A Studio write has to carry the x-dartvel-csrf-token header.',
      );
    }
  }

  DVDatabaseAdapter get _database {
    final DVDatabaseAdapter? adapter = database;
    if (adapter == null) {
      throw _StudioRefusal(
        503,
        'no_database',
        'This process has no database, so there is nothing to show.',
      );
    }
    return adapter;
  }

  Future<Map<String, Object?>> _body(Request request) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await request.body.text());
    } on FormatException {
      throw _StudioRefusal(400, 'bad_body', 'The body is not JSON.');
    }
    if (decoded is! Map) {
      throw _StudioRefusal(400, 'bad_body', 'The body is not a JSON object.');
    }
    return decoded.cast<String, Object?>();
  }

  // ---- models ------------------------------------------------------------

  Future<Response> _models(
    Request request,
    String method,
    List<String> path,
  ) async {
    if (path.isEmpty) {
      if (method != 'GET') _notAllowed();
      return _reply(<String, Object?>{
        'models': <Object?>[
          for (final DVStudioModelSpec model in models) model.toJson(),
        ],
      });
    }
    final DVStudioModelSpec spec = models.firstWhere(
      (DVStudioModelSpec m) => m.model == path.first,
      orElse: () => throw _StudioRefusal(
        404,
        'not_found',
        'No model named ${path.first} is declared.',
      ),
    );
    if (path.length < 2 || path[1] != 'records' || path.length > 3) {
      throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
    }
    final DVRecordTable table = _table(spec);
    await table.ensureSchema();
    if (path.length == 2) {
      if (method == 'GET') {
        final List<DVRecord> records = await table.all();
        return _reply(<String, Object?>{
          'records': <Object?>[
            for (final DVRecord record in records) _recordJson(spec, record),
          ],
        });
      }
      if (method == 'POST') return _create(spec, table, await _body(request));
      _notAllowed();
    }
    final String key = path[2];
    switch (method) {
      case 'GET':
        final DVRecord? record = await table.read(key);
        if (record == null) _missing(spec, key);
        return _reply(_recordJson(spec, record));
      case 'PUT':
        return _update(spec, table, key, await _body(request));
      case 'DELETE':
        final DVRecord? current = await table.read(key);
        if (current == null) _missing(spec, key);
        final int? version = int.tryParse(
          request.url.queryParameters['version'] ?? '',
        );
        if (spec.versioned && version != current.version) {
          throw DVConflictError(
            table: spec.table,
            key: key,
            mine: const <String, Object?>{},
            theirs: current.values,
            base: null,
            expectedVersion: version,
            actualVersion: current.version,
          );
        }
        await table.delete(key, base: current);
        return _reply(<String, Object?>{'deleted': key});
    }
    _notAllowed();
  }

  Never _notAllowed() =>
      throw _StudioRefusal(405, 'method', 'That method is not answered here.');

  Never _missing(DVStudioModelSpec spec, String key) => throw _StudioRefusal(
    404,
    'not_found',
    'No ${spec.model} with ${spec.key} $key.',
  );

  DVRecordTable _table(DVStudioModelSpec spec) => DVRecordTable(
    table: dvTenantTable(spec.table),
    key: spec.key,
    columns: <String>[
      if (spec.tenantScoped) dvTenantColumn,
      for (final DVStudioFieldSpec field in spec.fields) field.name,
    ],
    sensitive: <String>{
      for (final DVStudioFieldSpec field in spec.fields)
        if (field.sensitive) field.name,
    },
    versioned: spec.versioned,
    softDelete: spec.softDelete,
    scope: spec.tenantScoped
        ? DVRecordScope(dvTenantColumn, const DVTenants().currentTenant)
        : null,
    database: _database,
  );

  Map<String, Object?> _recordJson(DVStudioModelSpec spec, DVRecord record) =>
      <String, Object?>{
        'key': '${record.key}',
        'version': record.version,
        'values': <String, Object?>{
          for (final DVStudioFieldSpec field in spec.fields)
            if (!field.sensitive)
              field.name: _out(field, record.values[field.name]),
        },
      };

  Future<Response> _create(
    DVStudioModelSpec spec,
    DVRecordTable table,
    Map<String, Object?> body,
  ) async {
    final Map<String, Object?> values = _in(spec, body['values']);
    final Object? key = values[spec.key];
    if (key == null || '$key'.isEmpty) {
      throw _StudioRefusal(
        400,
        'bad_values',
        'A new ${spec.model} needs a ${spec.key}.',
      );
    }
    if (await table.read(key, withDeleted: true) != null) {
      throw _StudioRefusal(
        409,
        'exists',
        'A ${spec.model} with ${spec.key} $key already exists.',
      );
    }
    final DVWriteResult written = await table.write(values);
    return _reply(_recordJson(spec, written.record), status: 201);
  }

  Future<Response> _update(
    DVStudioModelSpec spec,
    DVRecordTable table,
    String key,
    Map<String, Object?> body,
  ) async {
    final Map<String, Object?> values = _in(spec, body['values']);
    if (values.containsKey(spec.key) && '${values[spec.key]}' != key) {
      throw _StudioRefusal(
        400,
        'bad_values',
        'The ${spec.key} of a stored record is not changed by an edit.',
      );
    }
    final DVRecord? current = await table.read(key);
    if (current == null) _missing(spec, key);
    final Object? version = body['version'];
    if (spec.versioned && version != current.version) {
      throw DVConflictError(
        table: spec.table,
        key: key,
        mine: values,
        theirs: current.values,
        base: null,
        expectedVersion: version is int ? version : null,
        actualVersion: current.version,
      );
    }
    final DVWriteResult written = await table.write(<String, Object?>{
      for (final MapEntry<String, Object?> entry in current.values.entries)
        if (entry.key != dvTenantColumn) entry.key: entry.value,
      ...values,
    }, base: current);
    return _reply(_recordJson(spec, written.record));
  }

  /// What Studio sent, checked against the model and stored the way the
  /// generated model stores it.
  Map<String, Object?> _in(DVStudioModelSpec spec, Object? values) {
    if (values is! Map) {
      throw _StudioRefusal(400, 'bad_values', 'values has to be an object.');
    }
    final Map<String, Object?> stored = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in values.entries) {
      final String name = '${entry.key}';
      final DVStudioFieldSpec? field = spec.fields
          .where((DVStudioFieldSpec f) => f.name == name)
          .firstOrNull;
      if (field == null) {
        throw _StudioRefusal(
          400,
          'bad_values',
          '${spec.model} has no field named $name.',
        );
      }
      if (field.sensitive) {
        throw _StudioRefusal(
          400,
          'sensitive',
          '$name is sensitive, and Studio does not write sensitive fields.',
        );
      }
      stored[name] = _stored(field, entry.value);
    }
    return stored;
  }

  static String _base(String type) => type.replaceAll('?', '').trim();

  Object? _stored(DVStudioFieldSpec field, Object? value) {
    if (value == null) {
      if (!field.type.endsWith('?')) {
        throw _StudioRefusal(
          400,
          'bad_values',
          '${field.name} cannot be empty.',
        );
      }
      return null;
    }
    Never wrong() => throw _StudioRefusal(
      400,
      'bad_values',
      '${field.name} has to be a ${_base(field.type)}.',
    );
    switch (_base(field.type)) {
      case 'String':
        return '$value';
      case 'int':
        if (value is num && value == value.toInt()) return value.toInt();
        return int.tryParse('$value') ?? wrong();
      case 'double':
      case 'num':
        if (value is num) return value;
        return num.tryParse('$value') ?? wrong();
      case 'bool':
        if (value is bool) return value ? 1 : 0;
        wrong();
      case 'DateTime':
        final DateTime? parsed = DateTime.tryParse('$value');
        return parsed?.toIso8601String() ?? wrong();
    }
    return value;
  }

  /// A stored value, as the field's type. Columns have TEXT affinity, so a
  /// number or a flag can come back as a string.
  Object? _out(DVStudioFieldSpec field, Object? value) {
    if (value == null) return null;
    switch (_base(field.type)) {
      case 'int':
        return value is num ? value.toInt() : int.tryParse('$value') ?? value;
      case 'double':
      case 'num':
        return value is num ? value : num.tryParse('$value') ?? value;
      case 'bool':
        return value == true || value == 1 || value == '1' || value == 'true';
      case 'String':
      case 'DateTime':
        return '$value';
    }
    return value is num || value is bool || value is String ? value : '$value';
  }

  // ---- pages -------------------------------------------------------------

  Future<Response> _pages(Request request, String method) async {
    final DVDatabaseAdapter database = _database;
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $dvStudioPagesTable (route TEXT, '
      'title TEXT, document TEXT)',
    );
    switch (method) {
      case 'GET':
        final List<Map<String, Object?>> rows = await database.query(
          'SELECT route, title, document FROM $dvStudioPagesTable',
        );
        final List<Map<String, Object?>> pages =
            <Map<String, Object?>>[
              for (final Map<String, Object?> row in rows)
                <String, Object?>{
                  'route': '${row['route']}',
                  'title': row['title'] == null ? null : '${row['title']}',
                  'document': jsonDecode('${row['document']}'),
                },
            ]..sort(
              (Map<String, Object?> a, Map<String, Object?> b) =>
                  '${a['route']}'.compareTo('${b['route']}'),
            );
        return _reply(<String, Object?>{'pages': pages});
      case 'PUT':
        final Object? document = (await _body(request))['document'];
        if (document is! Map || document['route'] is! String) {
          throw _StudioRefusal(
            400,
            'bad_document',
            'document has to name its route.',
          );
        }
        final String route = document['route']! as String;
        if (!route.startsWith('/')) {
          throw _StudioRefusal(
            400,
            'bad_document',
            'A page route begins with "/".',
          );
        }
        await database.execute(
          'DELETE FROM $dvStudioPagesTable WHERE route = ?',
          <Object?>[route],
        );
        await database.execute(
          'INSERT INTO $dvStudioPagesTable (route, title, document) '
          'VALUES (?, ?, ?)',
          <Object?>[route, document['title'], jsonEncode(document)],
        );
        return _reply(<String, Object?>{'route': route});
      case 'DELETE':
        final String? route = request.url.queryParameters['route'];
        if (route == null || route.isEmpty) {
          throw _StudioRefusal(400, 'bad_route', 'Name the route to remove.');
        }
        await database.execute(
          'DELETE FROM $dvStudioPagesTable WHERE route = ?',
          <Object?>[route],
        );
        return _reply(<String, Object?>{'deleted': route});
    }
    _notAllowed();
  }

  // ---- grants ------------------------------------------------------------

  Future<Response> _grants() async {
    final List<DVStudioGrant> grants = await DVStudioGrants(_database).list();
    return _reply(<String, Object?>{
      'grants': <Object?>[
        for (final DVStudioGrant grant in grants)
          <String, Object?>{
            'userId': grant.userId,
            'tenant': grant.tenant,
            'grantedAt': grant.grantedAt.toIso8601String(),
          },
      ],
    });
  }
}
