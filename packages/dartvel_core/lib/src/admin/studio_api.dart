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
/// tenant exactly as a model's own save is. A sensitive field is write-only
/// here, like a password field: its value is never sent, a value typed for
/// it is stored (sealed first when the field is encrypted), and an empty one
/// leaves what is stored alone.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../dartvel.dart'
    show DVCacheTags, DVJobEnvelope, DVJobPayload, DVQueues;
import '../annotations/model_access.dart';
import '../auth/auth.dart'
    show AuthUser, DVAccountDirectory, DVAccountLookup;
import '../auth/auth_endpoints.dart' show DVAuthEndpoints;
import '../auth/session_authentication.dart';
import '../auth/sessions.dart' show DVSessionCookie;
import '../crypto/field_cipher.dart' show DVFieldEncryption;
import '../data/change_capture.dart' show DVCapture;
import '../data/record_history.dart';
import '../database/adapter.dart';
import '../database/records.dart';
import '../http/wintercg.dart';
import '../modules/modules.dart'
    show DVModuleData, DVModuleDataMode, dvModuleRegistry;
import '../schema/generated_schema.dart' show dvTenantColumn;
import '../tenancy/tenants.dart';
import 'studio_access.dart';
import 'studio_model_schema.dart';
import 'studio_repository.dart';
import 'studio_source_files.dart';
import 'studio_site.dart';
import '../web/asset_source.dart';
import '../web/rendered_page_cache.dart';

/// One field of a model, as Studio edits it.
///
/// The same description whether the model was compiled from a `@DVModel`
/// or designed in Studio: the generator writes one of these for every field
/// it reads, Studio stores one for every field somebody adds, and the
/// checks a write goes through are read from here either way.
class DVStudioFieldSpec {
  const DVStudioFieldSpec({
    required this.name,
    required this.type,
    this.sensitive = false,
    this.encrypted = false,
    this.options,
    this.relation,
    this.unique = false,
    this.min,
    this.max,
    this.minLength,
    this.maxLength,
    this.pattern,
  });

  /// A field from [toJson]'s output.
  factory DVStudioFieldSpec.fromJson(Map<Object?, Object?> json) {
    num? number(Object? value) =>
        value is num ? value : num.tryParse('${value ?? ''}');
    int? whole(Object? value) => number(value)?.toInt();
    return DVStudioFieldSpec(
      name: '${json['name']}',
      type: '${json['type']}',
      sensitive: json['sensitive'] == true,
      encrypted: json['encrypted'] == true,
      options: json['options'] is List
          ? <String>[
              for (final Object? option in json['options']! as List) '$option',
            ]
          : null,
      relation: json['relation'] is String ? json['relation']! as String : null,
      unique: json['unique'] == true,
      min: number(json['min']),
      max: number(json['max']),
      minLength: whole(json['minLength']),
      maxLength: whole(json['maxLength']),
      pattern: json['pattern'] is String && '${json['pattern']}'.isNotEmpty
          ? json['pattern']! as String
          : null,
    );
  }

  final String name;

  /// The values an enum field can take, stored by name.
  final List<String>? options;

  /// The model, by the name Studio lists it under, that this field holds the
  /// key of: `userSlug` holding a `User`'s slug.
  final String? relation;

  /// No two records hold the same value here.
  final bool unique;

  /// The smallest and largest number the field takes.
  final num? min;
  final num? max;

  /// The shortest and longest text the field takes.
  final int? minLength;
  final int? maxLength;

  /// A regular expression the whole text has to match.
  final String? pattern;

  /// Whether the value is a list, set or map, kept as JSON.
  bool get isCollection {
    final String base = type.replaceAll('?', '').trim();
    return base.startsWith('List<') ||
        base.startsWith('Set<') ||
        base.startsWith('Map<') ||
        base == 'List' ||
        base == 'Map' ||
        base == 'Set';
  }

  /// The declared Dart type, with `?` when nullable.
  final String type;

  /// Whether the field may be left empty.
  bool get nullable => type.trim().endsWith('?');

  /// Write-only in Studio: never sent to it, and set from it only when a
  /// value is typed. An empty value leaves what is stored alone.
  final bool sensitive;

  /// Declared `@DVModel.sensitiveField(encrypted: true)`: sealed with
  /// [DVFieldEncryption] before it is stored, as the model's own save seals
  /// it, so a value written here reads back through the model.
  final bool encrypted;

  /// Whether the field carries a rule beyond its type.
  bool get hasRules =>
      unique ||
      min != null ||
      max != null ||
      minLength != null ||
      maxLength != null ||
      pattern != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type,
    if (sensitive) 'sensitive': true,
    if (encrypted) 'encrypted': true,
    'options': ?options,
    'relation': ?relation,
    if (unique) 'unique': true,
    'min': ?min,
    'max': ?max,
    'minLength': ?minLength,
    'maxLength': ?maxLength,
    'pattern': ?pattern,
  };
}

/// An index a model asks its database for: one field or several, and
/// whether no two records may share the combination.
class DVStudioIndexSpec {
  const DVStudioIndexSpec({required this.fields, this.unique = false});

  factory DVStudioIndexSpec.fromJson(Map<Object?, Object?> json) =>
      DVStudioIndexSpec(
        fields: <String>[
          for (final Object? field in (json['fields'] as List?) ?? const <Object?>[])
            '$field',
        ],
        unique: json['unique'] == true,
      );

  final List<String> fields;
  final bool unique;

  Map<String, Object?> toJson() => <String, Object?>{
    'fields': fields,
    if (unique) 'unique': true,
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
    this.offline,
    this.capture = false,
    this.module,
    this.data,
    this.indexes = const <DVStudioIndexSpec>[],
    this.access,
    this.origin = DVStudioModelOrigin.code,
  });

  /// The model's class name.
  final String model;

  /// The indexes the model asks its database for, beyond its key.
  final List<DVStudioIndexSpec> indexes;

  /// Who may do what to the model's records through its data API, or null
  /// for a model whose policies are written in code.
  final DVModelAccess? access;

  /// Where the model is defined: compiled from a `@DVModel`, or designed in
  /// Studio and stored beside the records it describes.
  final DVStudioModelOrigin origin;

  /// The mounted module the model belongs to, or null for the application's
  /// own. Studio names it `<module>.<Model>`, so a module's `Order` and the
  /// application's are two models rather than one.
  final String? module;

  /// Where a module's model resolves its table and database, which depends
  /// on how the module was mounted. Null for the application's own models.
  final DVModuleData? data;

  /// The name Studio lists and addresses the model by.
  String get id => module == null ? model : '$module.$model';

  /// The plain table name; the tenant's schema is resolved per request.
  final String table;

  /// The table this model's rows are actually in, for this request.
  ///
  /// Two different resolutions, and a caller that skips either writes rows
  /// where nobody reads them: a tenant whose separation is a schema keeps
  /// its rows in that schema, and a module's tables are named by the mount
  /// rather than by the model. Every server-side reader and writer of a
  /// spec's table goes through here so the two cannot drift apart -- Studio
  /// and the route that replays a device's offline writes read and write
  /// the same rows or one of them is silently alone.
  ///
  /// Throws [StateError] for a module mounted remotely: its deployment owns
  /// its data and this process has no table to name.
  String get resolvedTable =>
      data == null ? dvTenantTable(table) : data!.table(table);

  /// The database this model's rows are in, or [fallback] for the
  /// application's own models and for a module sharing the parent's data.
  ///
  /// Throws [StateError] for a module mounted remotely, and for one mounted
  /// with its own database before anything gave it one.
  DVDatabaseAdapter resolvedDatabase(DVDatabaseAdapter fallback) {
    final String? id = module;
    if (data == null || id == null) return fallback;
    return switch (dvModuleRegistry.maybeGet(id)?.dataMode) {
      DVModuleDataMode.databaseIsolated ||
      DVModuleDataMode.remote =>
        data!.database,
      _ => fallback,
    };
  }

  /// The field records are found by.
  final String key;
  final List<DVStudioFieldSpec> fields;
  final bool tenantScoped;
  final bool versioned;
  final bool softDelete;

  /// How a write this model made offline is resolved when it is replayed, or
  /// null when it declared no `offline:` at all.
  ///
  /// Null is what keeps the route that applies replayed writes from being an
  /// arbitrary-table write primitive: only the models that said so are in
  /// its registry, and a spec that defaulted to a strategy would put every
  /// model in it.
  ///
  /// Here rather than in a registry of its own because the backend cannot
  /// import models.g.dart -- that file imports Flutter -- and this spec
  /// already carries everything else a remote needs to resolve the table.
  final DVConflict? offline;

  /// Whether the data model declared `@DVModel(capture: true)`, so every
  /// write the server makes to it -- through Studio, through a device's
  /// replayed offline writes -- is recorded in the change capture log, as
  /// the model's own saves are.
  final bool capture;

  /// Everything a development server needs to serve this model's records
  /// without the generated code: [fromManifest] reads it back. The build
  /// writes the application's own models this way; a module's resolve their
  /// tables through a mount only a running backend has.
  Map<String, Object?> toManifest() => <String, Object?>{
    'model': model,
    'table': table,
    'key': key,
    'fields': <Object?>[
      for (final DVStudioFieldSpec field in fields) field.toJson(),
    ],
    'tenantScoped': tenantScoped,
    'versioned': versioned,
    'softDelete': softDelete,
    if (offline != null) 'offline': offline!.name,
    if (capture) 'capture': true,
    if (indexes.isNotEmpty)
      'indexes': <Object?>[
        for (final DVStudioIndexSpec index in indexes) index.toJson(),
      ],
    if (access != null) 'access': access!.toJson(),
    if (origin != DVStudioModelOrigin.code) 'origin': origin.name,
  };

  /// A spec from [toManifest]'s output.
  factory DVStudioModelSpec.fromManifest(Map<String, Object?> json) =>
      DVStudioModelSpec(
        model: '${json['model']}',
        table: '${json['table']}',
        key: '${json['key']}',
        tenantScoped: json['tenantScoped'] == true,
        versioned: json['versioned'] != false,
        softDelete: json['softDelete'] == true,
        capture: json['capture'] == true,
        offline: json['offline'] == null
            ? null
            : DVConflict.byName('${json['offline']}'),
        fields: <DVStudioFieldSpec>[
          for (final Object? field in (json['fields'] as List?) ?? const <Object?>[])
            if (field is Map) DVStudioFieldSpec.fromJson(field),
        ],
        indexes: <DVStudioIndexSpec>[
          for (final Object? index in (json['indexes'] as List?) ?? const <Object?>[])
            if (index is Map) DVStudioIndexSpec.fromJson(index),
        ],
        access: json['access'] is Map
            ? DVModelAccess.fromJson(json['access']! as Map)
            : null,
        origin: json['origin'] == DVStudioModelOrigin.studio.name
            ? DVStudioModelOrigin.studio
            : DVStudioModelOrigin.code,
      );

  /// This spec, with [origin] said.
  DVStudioModelSpec withOrigin(DVStudioModelOrigin origin) =>
      DVStudioModelSpec.fromManifest(<String, Object?>{
        ...toManifest(),
        'origin': origin.name,
      });

  Map<String, Object?> toJson() => <String, Object?>{
    'model': id,
    'module': ?module,
    'key': key,
    'table': table,
    'fields': <Object?>[
      for (final DVStudioFieldSpec field in fields) field.toJson(),
    ],
    'versioned': versioned,
    'softDelete': softDelete,
    'origin': origin.name,
    if (indexes.isNotEmpty)
      'indexes': <Object?>[
        for (final DVStudioIndexSpec index in indexes) index.toJson(),
      ],
    if (access != null) 'access': access!.toJson(),
  };
}

/// Where a data model is defined.
enum DVStudioModelOrigin {
  /// A `@DVModel` in the project's source, compiled into this build.
  code,

  /// Designed in Studio and stored in the application's database, served
  /// without a rebuild.
  studio,
}

/// A refusal with a status and a code Studio can show.
class _StudioRefusal implements Exception {
  _StudioRefusal(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

}

/// A new record key: twenty characters of secure random, lower case and
/// digits, so it reads in an address and sorts nowhere in particular.
String dvStudioNewKey() {
  final math.Random random = math.Random.secure();
  const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes(<int>[
    for (int i = 0; i < 20; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
}

/// The account id of the live session [request] carries, or null.
Future<String?> dvStudioSessionUserId(Request request) async {
  final DVSessionAuthenticationResult result =
      await DVSessionAuthentication.authenticateRequest(
    plainLocal: DVSessionCookie.plainLocal(
      request.url,
      forwardedProto: request.headers.get('x-forwarded-proto'),
      host: request.headers.get('host'),
    ),
    authorization: request.headers.get('authorization'),
    cookie: request.headers.get('cookie'),
  );
  return result.refused ? null : result.principal?.userId;
}

/// The table page documents are kept in: the one `DVPageStore` writes.
const String dvStudioPagesTable = 'dartvel_pages';

/// A page as a record, keyed by its route: one shape for `DVPageStore`, the
/// Studio API and the published-pages reader, so the three cannot disagree
/// about the fields.
const DVRecordShape dvStudioPagesShape = DVRecordShape(
  collection: dvStudioPagesTable,
  key: 'route',
  fields: <String, DVFieldType>{
    'route': DVFieldType.text,
    'title': DVFieldType.text,
    'document': DVFieldType.text,
  },
);

/// The collection Studio's frontend and backend functions are kept in.
const String dvStudioFunctionsTable = 'dartvel_functions';

/// A stored function: its name, and the document the builder saved.
const DVRecordShape dvStudioFunctionsShape = DVRecordShape(
  collection: dvStudioFunctionsTable,
  key: 'name',
  fields: <String, DVFieldType>{
    'name': DVFieldType.text,
    'document': DVFieldType.text,
  },
);

/// The Studio API, for requests already decided to be the admin's and
/// allowed.
class DVStudioApi {
  DVStudioApi({
    this.models = const <DVStudioModelSpec>[],
    this.database,
    Future<String?> Function(Request request)? caller,
    DVAccountDirectory? accounts,
    List<String> Function()? queues,
    this.root,
    this.sourceRoot,
    List<Map<String, Object?>> Function()? compiledRoutes,
    String? structureRoot,
    DVGitHubTransport? gitHub,
    String? gitHubToken,
  })  : _gitHub = gitHub,
        _gitHubToken = gitHubToken ?? Platform.environment[dvGitHubTokenVariable],
        _caller = caller ?? dvStudioSessionUserId,
        _compiledRoutes = compiledRoutes ?? (() => dvStudioGraphRoutes(root)),
        _structureRoot = structureRoot ??
            (root == null
                ? null
                : '$root${Platform.pathSeparator}$dvStudioStructureDirectory'),
        _accounts = accounts,
        _queues = queues ?? (() => const <String>['default']);

  final DVGitHubTransport? _gitHub;

  /// The server's GitHub token, never answered to anybody.
  final String? _gitHubToken;

  /// The queues the build declares, which Studio lists. Jobs are stored per
  /// queue, so there is nothing to enumerate them from but the build.
  final List<String> Function() _queues;

  /// The models compiled into this build.
  final List<DVStudioModelSpec> models;

  /// The directory Studio is served from, where the build writes the
  /// project graph and each page's captured structure. Null lists no
  /// compiled page.
  final String? root;

  /// The routes the application compiled: the project graph's by default.
  final List<Map<String, Object?>> Function() _compiledRoutes;

  /// Where each compiled page's captured structure is, one JSON file per
  /// route: the admin root's `structure` directory by default.
  final String? _structureRoot;

  /// The project's source tree, on a development server: a model designed in
  /// Studio can be written out to `lib/models` there. Null on a deployed
  /// server, which has no source to keep in step.
  final String? sourceRoot;

  /// The signed-in account making [Request], for the grants a caller may
  /// not revoke from under themselves without saying so.
  final Future<String?> Function(Request request) _caller;

  /// Where an account's address is found, so a grant can be made by address
  /// and listed by one. Null asks the auth endpoints' installed provider.
  final DVAccountDirectory? _accounts;

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
  Future<Response> respond(Request request, String rest) =>
      _guard(() async {
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
          case 'site':
            return await _site(request, method, segments.sublist(1));
          case 'functions':
            return await _functions(request, method);
          case 'grants':
            if (segments.length == 1) return await _grantsAt(request, method);
          case 'queues':
            return await _queuesAt(method, segments.sublist(1));
          case 'cache':
            return await _cacheAt(method, segments.sublist(1));
          case 'graph':
            if (segments.length == 1) return _graph(method);
          case 'me':
            if (segments.length == 1) return await _me(request, method);
          case 'repository':
            return await _repositoryAt(request, method, segments.sublist(1));
        }
        throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
      });

  /// The records of [spec], for a caller something else has already
  /// decided may reach them: the data API of the models designed in Studio.
  Future<Response> respondRecords(
    Request request,
    DVStudioModelSpec spec,
    List<String> rest, {
    String? method,
  }) =>
      _guard(
        () => _recordsOf(
          request,
          method ?? request.method.toUpperCase(),
          spec,
          rest,
        ),
      );

  /// [run]'s answer, with a refusal or a conflict answered as Studio shows
  /// one.
  Future<Response> _guard(Future<Response> Function() run) async {
    try {
      return await run();
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

  /// Every data model: the ones compiled into this build, then the ones
  /// designed in Studio.
  ///
  /// A stored definition under a compiled model's name is not served: the
  /// compiled one is what the application's own code reads and writes, and
  /// two descriptions of one table would disagree the first time either
  /// changed.
  Future<List<DVStudioModelSpec>> allModels() async {
    final Set<String> compiled = <String>{
      for (final DVStudioModelSpec model in models) model.id,
    };
    return <DVStudioModelSpec>[
      ...models,
      for (final DVStudioModelSpec model in await storedModels())
        if (!compiled.contains(model.id)) model,
    ];
  }

  /// The models designed in Studio, from the application's database.
  Future<List<DVStudioModelSpec>> storedModels() async {
    final DVDatabaseAdapter? adapter = database;
    if (adapter == null) return const <DVStudioModelSpec>[];
    final DVRecordAdapter records = DVRecordAdapter.over(adapter);
    await records.ensure(dvStudioModelsShape);
    final List<Map<String, Object?>> rows = await records.find(
      dvStudioModelsTable,
      fields: const <String>['name', 'document'],
      orderBy: const <DVSort>[DVSort('name')],
    );
    final List<DVStudioModelSpec> stored = <DVStudioModelSpec>[];
    for (final Map<String, Object?> row in rows) {
      try {
        final Object? decoded = jsonDecode('${row['document']}');
        if (decoded is! Map) continue;
        stored.add(DVStudioModelSpec.fromManifest(<String, Object?>{
          ...decoded.cast<String, Object?>(),
          'model': '${row['name']}',
          'table': dvStudioTableFor('${row['name']}'),
          'origin': DVStudioModelOrigin.studio.name,
        }));
      } on FormatException {
        // A definition that no longer parses is left out rather than taking
        // every other model down with it.
      }
    }
    return stored;
  }

  /// The model Studio lists as [name], or a 404.
  Future<DVStudioModelSpec> _spec(String name) async {
    for (final DVStudioModelSpec model in await allModels()) {
      if (model.id == name) return model;
    }
    throw _StudioRefusal(
      404,
      'not_found',
      'No model named $name is declared.',
    );
  }

  Future<Response> _models(
    Request request,
    String method,
    List<String> path,
  ) async {
    if (path.isEmpty) {
      if (method != 'GET') _notAllowed();
      return _reply(<String, Object?>{
        'models': <Object?>[
          for (final DVStudioModelSpec model in await allModels())
            model.toJson(),
        ],
        // Whether a model designed here can also be written to the
        // project's source: only a development server has any.
        'sourceWritable': sourceRoot != null,
      });
    }
    if (path.length == 1) {
      switch (method) {
        case 'GET':
          return _reply((await _spec(path.first)).toJson());
        case 'PUT':
          return _saveDefinition(request, path.first);
        case 'DELETE':
          return _deleteDefinition(path.first);
      }
      _notAllowed();
    }
    if (path.length == 2 && path[1] == 'source') {
      if (method != 'POST') _notAllowed();
      return _writeSource(await _spec(path.first));
    }
    final DVStudioModelSpec spec = await _spec(path.first);
    if (path.length < 2 || path[1] != 'records' || path.length > 3) {
      throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
    }
    return _recordsOf(request, method, spec, path.sublist(2));
  }

  /// The records of [spec]: all of them with an empty [rest], one with its
  /// key, created, changed and deleted -- through the checks every write
  /// here goes through, whoever is making it.
  Future<Response> _recordsOf(
    Request request,
    String method,
    DVStudioModelSpec spec,
    List<String> rest,
  ) async {
    final DVRecordTable table = _table(spec);
    await prepare(spec, table);
    if (rest.isEmpty) {
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
    final String key = rest.first;
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

  /// The tables, columns and indexes [spec] has been made sure of, per
  /// database, so a model is prepared once per process and again when its
  /// definition changes.
  static final Expando<Set<String>> _prepared = Expando<Set<String>>();

  /// Makes sure [spec]'s table has every column its fields name and every
  /// index it asks for.
  ///
  /// A model designed in Studio grows a field without a migration: the
  /// column is added the first time its records are touched. An index the
  /// database cannot make -- a unique one over values that already repeat,
  /// or an engine with no indexes to ask for -- is left to the check every
  /// write makes, so the rule holds either way.
  Future<void> prepare(DVStudioModelSpec spec, DVRecordTable table) async {
    final DVDatabaseAdapter adapter = _databaseFor(spec);
    final Set<String> done = _prepared[adapter] ??= <String>{};
    final String signature = jsonEncode(<Object?>[
      table.table,
      <String>[for (final DVStudioFieldSpec f in spec.fields) f.name],
      <Object?>[
        for (final ({String name, List<String> fields, bool unique}) index
            in dvStudioIndexesOf(spec))
          index.name,
      ],
    ]);
    await table.ensureSchema();
    if (done.contains(signature)) return;
    // Through the record layer, which knows how each engine adds a column
    // and asks for an index: a field added to a designed model gets its
    // column the first time its records are touched, with no migration.
    await DVRecordAdapter.over(adapter).ensure(
      DVRecordShape(
        collection: table.table,
        key: spec.key,
        fields: <String, DVFieldType>{
          for (final DVStudioFieldSpec field in spec.fields)
            field.name: DVFieldType.text,
        },
        indexes: <DVRecordIndex>[
          for (final ({String name, List<String> fields, bool unique}) index
              in dvStudioIndexesOf(spec))
            DVRecordIndex(index.fields, unique: index.unique),
        ],
      ),
    );
    done.add(signature);
  }

  /// Stores [name]'s definition, designed in Studio.
  Future<Response> _saveDefinition(Request request, String name) async {
    final Object? definition = (await _body(request))['definition'];
    if (definition is! Map) {
      throw _StudioRefusal(
        400,
        'bad_definition',
        'Send the model as {"definition": {...}}.',
      );
    }
    final DVStudioModelSpec spec = DVStudioModelSpec.fromManifest(
      <String, Object?>{
        ...definition.cast<String, Object?>(),
        'model': name,
        'table': dvStudioTableFor(name),
        'origin': DVStudioModelOrigin.studio.name,
      },
    );
    final List<DVStudioModelSpec> every = await allModels();
    final Map<String, DVStudioModelSpec> others = <String, DVStudioModelSpec>{
      for (final DVStudioModelSpec model in every)
        if (model.id != name) model.id: model,
    };
    final List<String> problems =
        dvStudioDefinitionProblems(spec, others: others);
    if (problems.isNotEmpty) {
      return _reply(<String, Object?>{
        'error': 'bad_definition',
        'message': problems.first,
        'problems': problems,
      }, status: 400);
    }
    final DVStudioModelSpec? compiled = models
        .where((DVStudioModelSpec m) => m.id == name)
        .firstOrNull;
    if (compiled != null) {
      // A compiled model is changed where it is written. On a development
      // server whose model file Studio wrote, that is here: the file is
      // written again and the next build compiles it.
      final File? file = _sourceFile(name);
      if (file == null || !_studioWritten(file)) {
        throw _StudioRefusal(
          409,
          'in_code',
          '$name is written in code, so it is changed there.',
        );
      }
      file.writeAsStringSync(dvStudioModelDartSource(spec));
      return _reply(<String, Object?>{
        ...spec.withOrigin(DVStudioModelOrigin.code).toJson(),
        'source': _relativeSource(name),
        'rebuild': true,
      });
    }
    final DVStudioModelSpec? existing = (await storedModels())
        .where((DVStudioModelSpec m) => m.id == name)
        .firstOrNull;
    if (existing != null && existing.key != spec.key) {
      final DVRecordTable table = _table(existing);
      await table.ensureSchema();
      if ((await table.all(withDeleted: true)).isNotEmpty) {
        throw _StudioRefusal(
          409,
          'key_change',
          '$name already has records found by ${existing.key}, so its key '
              'stays ${existing.key}.',
        );
      }
    }
    final DVRecordAdapter records = DVRecordAdapter.over(_database);
    await records.ensure(dvStudioModelsShape);
    await records.delete(
      dvStudioModelsTable,
      where: DVFilter.equals('name', name),
    );
    await records.insert(dvStudioModelsTable, <String, Object?>{
      'name': name,
      'document': jsonEncode(spec.toManifest()),
    });
    // Its table now, so the first record written through any path finds it.
    await prepare(spec, _table(spec));
    return _reply(spec.toJson(), status: existing == null ? 201 : 200);
  }

  /// Removes [name]'s definition. Its records stay where they are: defining
  /// the model again under the same name finds them.
  Future<Response> _deleteDefinition(String name) async {
    if (models.any((DVStudioModelSpec m) => m.id == name)) {
      throw _StudioRefusal(
        409,
        'in_code',
        '$name is written in code, so it is removed there.',
      );
    }
    final DVRecordAdapter records = DVRecordAdapter.over(_database);
    await records.ensure(dvStudioModelsShape);
    final int removed = await records.delete(
      dvStudioModelsTable,
      where: DVFilter.equals('name', name),
    );
    if (removed == 0) {
      throw _StudioRefusal(404, 'not_found', 'No model named $name is stored.');
    }
    return _reply(<String, Object?>{'deleted': name, 'recordsKept': true});
  }

  /// `lib/models/<name>.dart` in the source tree, or null without one.
  File? _sourceFile(String name) {
    final String? root = sourceRoot;
    if (root == null || name.contains('.')) return null;
    final String separator = Platform.pathSeparator;
    return File(
      '$root${separator}lib${separator}models$separator'
      '${dvStudioSnakeCase(name)}.dart',
    );
  }

  static String _relativeSource(String name) =>
      'lib/models/${dvStudioSnakeCase(name)}.dart';

  static bool _studioWritten(File file) {
    if (!file.existsSync()) return false;
    return file.readAsStringSync().startsWith(dvStudioModelSourceMarker);
  }

  /// Writes [spec] to the project's source as the `@DVModel` it compiles
  /// back from, so code and Studio describe one model.
  Future<Response> _writeSource(DVStudioModelSpec spec) async {
    final File? file = _sourceFile(spec.model);
    if (file == null || spec.module != null) {
      throw _StudioRefusal(
        404,
        'no_source',
        'This server has no source tree to write the model to. Run it with '
            'dartvel dev to keep a model in code as well.',
      );
    }
    if (file.existsSync() && !_studioWritten(file)) {
      throw _StudioRefusal(
        409,
        'hand_written',
        '${_relativeSource(spec.model)} was written by hand, so Studio '
            'leaves it alone.',
      );
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(dvStudioModelDartSource(spec));
    return _reply(<String, Object?>{
      'model': spec.id,
      'source': _relativeSource(spec.model),
    });
  }

  // ---- site --------------------------------------------------------------

  /// Every route of the site, compiled and stored, and the structure the
  /// build captured for a compiled one.
  Future<Response> _site(
    Request request,
    String method,
    List<String> path,
  ) async {
    if (method != 'GET') _notAllowed();
    if (path.isEmpty) {
      return _reply(<String, Object?>{
        'pages': <Object?>[
          for (final DVStudioSitePage page
              in await sitePages(compiled: _compiledRoutes()))
            page.toJson(),
        ],
      });
    }
    if (path.length == 1 && path.first == 'structure') {
      final String route = request.url.queryParameters['route'] ?? '';
      final Object? tree = dvStudioPageContentIn(_structureRoot, route);
      if (tree == null) {
        throw _StudioRefusal(
          404,
          'no_structure',
          'The build captured no structure for $route.',
        );
      }
      return _reply(<String, Object?>{'route': route, 'structure': tree});
    }
    throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
  }

  Never _notAllowed() =>
      throw _StudioRefusal(405, 'method', 'That method is not answered here.');

  /// Every page this application answers: the routes a build compiled
  /// alongside the documents stored here, each marked for what it is.
  ///
  /// Public because a server needs it for something Studio's own API is not:
  /// writing the document a Studio page is served with, so that a printer, a
  /// reader with scripting off and the browser's find all name the site's
  /// pages without the app having booted. The same list, composed the same
  /// way, so the document and the API cannot disagree about what exists.
  Future<List<DVStudioSitePage>> sitePages({
    List<Map<String, Object?>>? compiled,
  }) async {
    final Map<String, String?> stored = <String, String?>{};
    final DVDatabaseAdapter? adapter = database;
    if (adapter != null) {
      final DVRecordAdapter records = DVRecordAdapter.over(adapter);
      await records.ensure(dvStudioPagesShape);
      for (final Map<String, Object?> row in await records.find(
        dvStudioPagesTable,
        fields: const <String>['route', 'title'],
      )) {
        stored['${row['route']}'] =
            row['title'] == null ? null : '${row['title']}';
      }
    }
    return dvStudioSitePages(
      compiled: compiled ?? _compiledRoutes(),
      stored: stored,
      hasStructure: (String path) => dvStudioHasStructure(_structureRoot, path),
    );
  }

  Never _missing(DVStudioModelSpec spec, String key) => throw _StudioRefusal(
    404,
    'not_found',
    'No ${spec.model} with ${spec.key} $key.',
  );

  DVRecordTable _table(DVStudioModelSpec spec) => DVRecordTable(
    // A module's table is the one its mount gave it: the model's own name
    // under a shared mount, the module's id before it under a
    // schema-isolated one.
    table: spec.resolvedTable,
    key: spec.key,
    columns: <String>[
      if (spec.tenantScoped) dvTenantColumn,
      for (final DVStudioFieldSpec field in spec.fields) field.name,
    ],
    sensitive: <String>{
      for (final DVStudioFieldSpec field in spec.fields)
        if (field.sensitive) field.name,
    },
    // A generated model declares every field column TEXT (its createTableSql),
    // and Studio reads and writes that same table.
    types: <String, String>{
      if (spec.tenantScoped) dvTenantColumn: 'TEXT',
      for (final DVStudioFieldSpec field in spec.fields) field.name: 'TEXT',
    },
    versioned: spec.versioned,
    softDelete: spec.softDelete,
    // An edit made here is a write to the data model, and a captured one is
    // recorded as its own saves are.
    capture: spec.capture ? DVCapture.configured : null,
    scope: spec.tenantScoped
        ? DVRecordScope(dvTenantColumn, const DVTenants().currentTenant)
        : null,
    database: _databaseFor(spec),
  );

  /// The application's database, or the module's own for a module mounted
  /// with one. A remote module has none here: its deployment owns its data.
  DVDatabaseAdapter _databaseFor(DVStudioModelSpec spec) {
    try {
      return spec.resolvedDatabase(_database);
    } on StateError catch (error) {
      throw _StudioRefusal(503, 'module_data', error.message);
    }
  }

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
    final Map<String, Object?> values = await _in(spec, body['values']);
    Object? key = values[spec.key];
    if (key == null || '$key'.isEmpty) {
      final DVStudioFieldSpec? keyField = spec.fields
          .where((DVStudioFieldSpec f) => f.name == spec.key)
          .firstOrNull;
      // A text key nobody typed is made up, as a record in any content
      // system gets an id without being asked for one. Any other key is
      // the record's to say.
      if (keyField == null || _base(keyField.type) != 'String') {
        throw _StudioRefusal(
          400,
          'bad_values',
          'A new ${spec.model} needs a ${spec.key}.',
        );
      }
      key = values[spec.key] = dvStudioNewKey();
    }
    if (await table.read(key, withDeleted: true) != null) {
      throw _StudioRefusal(
        409,
        'exists',
        'A ${spec.model} with ${spec.key} $key already exists.',
      );
    }
    await _checkRequired(spec, values);
    await _checkUnique(spec, table, '$key', values);
    final DVWriteResult written = await table.write(values);
    return _reply(_recordJson(spec, written.record), status: 201);
  }

  Future<Response> _update(
    DVStudioModelSpec spec,
    DVRecordTable table,
    String key,
    Map<String, Object?> body,
  ) async {
    final Map<String, Object?> values = await _in(spec, body['values']);
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
    final Map<String, Object?> next = <String, Object?>{
      for (final MapEntry<String, Object?> entry in current.values.entries)
        if (entry.key != dvTenantColumn) entry.key: entry.value,
      ...values,
    };
    await _checkUnique(spec, table, key, next);
    final DVWriteResult written = await table.write(next, base: current);
    return _reply(_recordJson(spec, written.record));
  }

  /// What Studio sent, checked against the model and stored the way the
  /// generated model stores it.
  Future<Map<String, Object?>> _in(DVStudioModelSpec spec, Object? values) async {
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
        // Write-only, like a password field: Studio never had the value, so
        // an empty one is "leave it as it is", not "clear it".
        final Object? value = entry.value;
        if (value == null || (value is String && value.isEmpty)) continue;
      }
      stored[name] = _stored(field, entry.value);
      final String? broken = dvStudioValueProblem(field, stored[name]);
      if (broken != null) throw _StudioRefusal(400, 'bad_values', broken);
      if (field.encrypted && stored[name] != null) {
        stored[name] =
            DVFieldEncryption.encrypt(spec.model, name, '${stored[name]}');
      }
      if (field.relation != null && stored[name] != null) {
        await _checkRelation(spec, field, stored[name]!);
      }
    }
    return stored;
  }

  /// Refuses a new record of a model designed in Studio that leaves a
  /// field out which cannot be empty.
  ///
  /// Only those: a compiled model's fields can have defaults this spec does
  /// not know, which its own constructor fills in.
  Future<void> _checkRequired(
    DVStudioModelSpec spec,
    Map<String, Object?> values,
  ) async {
    if (spec.origin != DVStudioModelOrigin.studio) return;
    for (final DVStudioFieldSpec field in spec.fields) {
      if (field.nullable || field.sensitive) continue;
      if (values[field.name] != null) continue;
      if (_base(field.type) == 'bool') {
        values[field.name] = 0;
        continue;
      }
      throw _StudioRefusal(
        400,
        'bad_values',
        '${field.name} cannot be empty.',
      );
    }
  }

  /// Refuses a write that would give two records the same value in a field,
  /// or combination of fields, [spec] says no two may share.
  Future<void> _checkUnique(
    DVStudioModelSpec spec,
    DVRecordTable table,
    String key,
    Map<String, Object?> values,
  ) async {
    final List<List<String>> groups = <List<String>>[
      for (final ({String name, List<String> fields, bool unique}) index
          in dvStudioIndexesOf(spec))
        if (index.unique) index.fields,
    ];
    if (groups.isEmpty) return;
    final List<DVRecord> records = await table.all(withDeleted: true);
    for (final List<String> fields in groups) {
      if (fields.any((String f) => values[f] == null)) continue;
      String of(Map<String, Object?> v) =>
          jsonEncode(<String>[for (final String f in fields) '${v[f]}']);
      final String mine = of(values);
      for (final DVRecord record in records) {
        if ('${record.key}' == key) continue;
        if (of(record.values) == mine) {
          throw _StudioRefusal(
            409,
            'not_unique',
            'Another ${spec.model} already has '
                '${fields.map((String f) => '$f ${values[f]}').join(' and ')}.',
          );
        }
      }
    }
  }

  /// Refuses a key no record of the related model has: a reference to
  /// nothing saves, and then every page that follows it breaks.
  Future<void> _checkRelation(
    DVStudioModelSpec spec,
    DVStudioFieldSpec field,
    Object key,
  ) async {
    final String relation = field.relation!;
    final List<DVStudioModelSpec> models = await allModels();
    final DVStudioModelSpec? related = models
            .where((DVStudioModelSpec m) =>
                spec.module != null && m.id == '${spec.module}.$relation')
            .firstOrNull ??
        models.where((DVStudioModelSpec m) => m.id == relation).firstOrNull;
    // A relation to a model Studio does not know is shown and not checked.
    if (related == null) return;
    final DVRecordTable table = _table(related);
    await table.ensureSchema();
    if (await table.read(key) == null) {
      throw _StudioRefusal(
        400,
        'bad_relation',
        '${field.name} has to be the ${related.key} of a ${related.model}, '
            'and no ${related.model} has ${related.key} $key.',
      );
    }
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
    final List<String>? options = field.options;
    if (options != null) {
      if (options.contains('$value')) return '$value';
      throw _StudioRefusal(
        400,
        'bad_values',
        '${field.name} has to be one of ${options.join(', ')}.',
      );
    }
    if (field.isCollection) {
      Object? decoded = value;
      if (value is String) {
        try {
          decoded = jsonDecode(value);
        } on FormatException {
          throw _StudioRefusal(
              400, 'bad_values', '${field.name} is not valid JSON.');
        }
      }
      final bool map = _base(field.type).startsWith('Map');
      if (map ? decoded is! Map : decoded is! List) wrong();
      return jsonEncode(decoded);
    }
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
    if (field.isCollection) {
      if (value is List || value is Map) return value;
      try {
        return jsonDecode('$value');
      } on FormatException {
        return '$value';
      }
    }
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

  /// The project's GitHub repository: `GET repository` names it and lists
  /// what would change, `PUT repository` names it, `POST repository/sync`
  /// sends the changes as a pull request or a push. See studio_repository.
  Future<Response> _repositoryAt(
    Request request,
    String method,
    List<String> rest,
  ) async {
    final DVDatabaseAdapter? adapter = database;
    if (adapter == null) {
      throw _StudioRefusal(409, 'no_database',
          'This server has no database to keep the repository\'s name in.');
    }
    final DVStudioRepository repository = DVStudioRepository(
      database: adapter,
      storedModels: storedModels,
      token: _gitHubToken,
      transport: _gitHub,
    );
    try {
      if (rest.isEmpty && method == 'GET') {
        final ({String repository, String base})? settings =
            await repository.settings();
        final bool token = (_gitHubToken ?? '').isNotEmpty;
        List<DVStudioFileChange> changes = const <DVStudioFileChange>[];
        String? problem;
        if (settings != null && token) {
          try {
            changes = await repository.changes();
          } on DVStudioRepositoryRefusal catch (refusal) {
            problem = refusal.message;
          } on Object {
            problem = 'GitHub could not be reached.';
          }
        }
        return _reply(<String, Object?>{
          'connected': settings != null,
          'repository': settings?.repository,
          'base': settings?.base,
          'token': token,
          'tokenHelp': 'Studio sends with the server\'s GitHub token, from '
              '$dvGitHubTokenVariable in its environment, and never stores one.',
          'changes': <Object?>[for (final DVStudioFileChange c in changes) c.toJson()],
          'problem': ?problem,
        });
      }
      if (rest.isEmpty && method == 'PUT') {
        final Map<String, Object?> body = await _body(request);
        await repository.connect(
          '${body['repository'] ?? ''}'.trim(),
          '${body['base'] ?? 'main'}'.trim(),
        );
        return _reply(<String, Object?>{'connected': true});
      }
      if (rest.length == 1 && rest.first == 'sync' && method == 'POST') {
        final Map<String, Object?> body = await _body(request);
        return _reply(await repository.sync(
          pullRequest: body['mode'] != 'push',
          message: body['message'] is String ? body['message']! as String : null,
        ));
      }
    } on DVStudioRepositoryRefusal catch (refusal) {
      throw _StudioRefusal(refusal.status, refusal.code, refusal.message);
    }
    _notAllowed();
  }

  /// The project's studio/ files, on a development server; none on a
  /// deployed one.
  DVStudioSourceFiles? get _sourceFiles {
    final String? root = sourceRoot;
    return root == null
        ? null
        : DVStudioSourceFiles(root, DVRecordAdapter.over(_database));
  }

  /// A write refused because code changed the file: what is in the file,
  /// for Studio to show beside its own.
  Response _conflict(DVStudioSourceConflict conflict) => _reply(
        <String, Object?>{
          'error': 'changed_in_code',
          'message': '${conflict.path} was changed in code since Studio '
              'last saved it. Keep the version in code, or save Studio\'s '
              'over it.',
          'path': conflict.path,
          'inCode': conflict.inCode,
        },
        status: 409,
      );

  Future<Response> _pages(Request request, String method) async {
    // Records, not SQL: the same collection DVPageStore writes, on whatever
    // engine the server was given.
    final DVRecordAdapter records = DVRecordAdapter.over(_database);
    await records.ensure(dvStudioPagesShape);
    final DVStudioSourceFiles? sources = _sourceFiles;
    switch (method) {
      case 'GET':
        // What code changed in the project's studio/ files comes into
        // Studio first, so both show the same pages.
        if (sources != null) {
          for (final MapEntry<String, Map<String, Object?>?> changed
              in (await sources.changedInCode()).entries) {
            dvPurgeRenderedPages();
            await records.delete(dvStudioPagesTable,
                where: DVFilter.equals('route', changed.key));
            final Map<String, Object?>? document = changed.value;
            if (document == null) continue;
            await records.insert(dvStudioPagesTable, <String, Object?>{
              'route': changed.key,
              'title': document['title'],
              'document': jsonEncode(document),
            });
          }
        }
        final List<Map<String, Object?>> rows = await records.find(
          dvStudioPagesTable,
          fields: const <String>['route', 'title', 'document'],
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
        final Map<String, Object?> body = await _body(request);
        final Object? document = body['document'];
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
        // The project's file first: when code changed it, nothing is
        // stored, and Studio shows both.
        try {
          await sources?.write(route, document, force: body['force'] == true);
        } on DVStudioSourceConflict catch (conflict) {
          return _conflict(conflict);
        }
        await records.delete(dvStudioPagesTable,
            where: DVFilter.equals('route', route));
        await records.insert(dvStudioPagesTable, <String, Object?>{
          'route': route,
          'title': document['title'],
          'document': jsonEncode(document),
        });
        dvPurgeRenderedPages();
        return _reply(<String, Object?>{'route': route});
      case 'DELETE':
        final String? route = request.url.queryParameters['route'];
        if (route == null || route.isEmpty) {
          throw _StudioRefusal(400, 'bad_route', 'Name the route to remove.');
        }
        try {
          await sources?.remove(route,
              force: request.url.queryParameters['force'] == 'true');
        } on DVStudioSourceConflict catch (conflict) {
          return _conflict(conflict);
        }
        await records.delete(dvStudioPagesTable,
            where: DVFilter.equals('route', route));
        dvPurgeRenderedPages();
        return _reply(<String, Object?>{'deleted': route});
    }
    _notAllowed();
  }

  // ---- functions ---------------------------------------------------------

  /// The frontend and backend functions built in Studio.
  ///
  /// Kept beside the pages rather than in the browser: the builder runs in a
  /// browser, which has no database, and a function is the project's, not
  /// that browser's.
  Future<Response> _functions(Request request, String method) async {
    final DVRecordAdapter records = DVRecordAdapter.over(_database);
    await records.ensure(dvStudioFunctionsShape);
    switch (method) {
      case 'GET':
        final List<Map<String, Object?>> rows =
            await records.find(dvStudioFunctionsTable);
        final List<Map<String, Object?>> functions = <Map<String, Object?>>[
          for (final Map<String, Object?> row in rows)
            <String, Object?>{
              'name': '${row['name']}',
              'document': jsonDecode('${row['document']}'),
            },
        ]..sort((Map<String, Object?> a, Map<String, Object?> b) =>
            '${a['name']}'.compareTo('${b['name']}'));
        return _reply(<String, Object?>{'functions': functions});
      case 'PUT':
        final Object? document = (await _body(request))['document'];
        if (document is! Map || document['name'] is! String) {
          throw _StudioRefusal(
              400, 'bad_function', 'A function has to have a name.');
        }
        final String name = document['name']! as String;
        if (name.isEmpty) {
          throw _StudioRefusal(
              400, 'bad_function', 'A function has to have a name.');
        }
        await records.delete(dvStudioFunctionsTable,
            where: DVFilter.equals('name', name));
        await records.insert(dvStudioFunctionsTable, <String, Object?>{
          'name': name,
          'document': jsonEncode(document),
        });
        return _reply(<String, Object?>{'name': name});
      case 'DELETE':
        final String? name = request.url.queryParameters['name'];
        if (name == null || name.isEmpty) {
          throw _StudioRefusal(
              400, 'bad_function', 'Name the function to remove.');
        }
        await records.delete(dvStudioFunctionsTable,
            where: DVFilter.equals('name', name));
        return _reply(<String, Object?>{'deleted': name});
    }
    _notAllowed();
  }

  // ---- queues ------------------------------------------------------------

  static const DVQueues _jobs = DVQueues();

  Future<Response> _queuesAt(String method, List<String> path) async {
    if (path.isEmpty) {
      if (method != 'GET') _notAllowed();
      final List<String> names =
          <String>{'default', ..._queues()}.toList()..sort();
      return _reply(<String, Object?>{
        'queues': <Object?>[
          for (final String name in names) await _queue(name),
        ],
      });
    }
    // jobs/<id>/retry, jobs/<id>/discard
    if (path.length == 3 && path.first == 'jobs') {
      if (method != 'POST') _notAllowed();
      final String id = path[1];
      final bool applied;
      switch (path[2]) {
        case 'retry':
          applied = await _jobs.retry(id);
        case 'discard':
          applied = await _jobs.discard(id);
        default:
          throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
      }
      if (!applied) {
        // Reporting success for a job the adapter did not find would leave
        // an operator believing a dead letter was dealt with.
        throw _StudioRefusal(
            404, 'not_found', 'No dead-lettered job has the id $id.');
      }
      return _reply(<String, Object?>{path[2]: id});
    }
    throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
  }

  Future<Map<String, Object?>> _queue(String name) async {
    List<DVJobEnvelope<DVJobPayload>> pending;
    List<DVJobEnvelope<DVJobPayload>> dead;
    String? unreadable;
    try {
      pending = await _jobs.pending(name);
      dead = await _jobs.deadLetters(name);
    } on Object catch (error) {
      // A broker that cannot list (Kafka, Pub/Sub) still has the queue; it
      // says why nothing is shown rather than showing an empty one.
      pending = const <DVJobEnvelope<DVJobPayload>>[];
      dead = const <DVJobEnvelope<DVJobPayload>>[];
      unreadable = '$error';
    }
    return <String, Object?>{
      'name': name,
      'pending': <Object?>[for (final job in pending) _jobJson(job)],
      'deadLetters': <Object?>[for (final job in dead) _jobJson(job)],
      'unreadable': ?unreadable,
    };
  }

  static Map<String, Object?> _jobJson(DVJobEnvelope<DVJobPayload> job) =>
      <String, Object?>{
        'id': job.id,
        'type': '${job.payloadType}',
        'state': job.state.name,
        'attempts': job.attempts,
        'maxAttempts': job.maxAttempts,
        'priority': job.priority,
        'createdAt': job.createdAt.toUtc().toIso8601String(),
        'lastError': ?job.lastError,
        'tenant': ?job.tenant,
      };

  // ---- the signed-in person ----------------------------------------------

  /// Who this Studio is open to: the signed-in account and its address, so
  /// Studio can say whose it is beside the control that signs out.
  Future<Response> _me(Request request, String method) async {
    if (method != 'GET' && method != 'HEAD') _notAllowed();
    final String? userId = await _caller(request);
    return _reply(<String, Object?>{
      'userId': userId,
      if (userId != null)
        if (await _emailOf(_directory, userId) case final String email)
          'email': email,
    });
  }

  // ---- project graph -----------------------------------------------------

  /// The project graph the build wrote beside the server: what Studio's
  /// Routes, Functions, Tasks and Modules sections list. Read through the API,
  /// behind the grant, like everything else Studio shows; it is the shape of
  /// the whole project and never a file served under the mount. An empty
  /// object when the build wrote none.
  Response _graph(String method) {
    if (method != 'GET' && method != 'HEAD') _notAllowed();
    final String? directory = root;
    Object? graph;
    if (directory != null) {
      try {
        // Through the source for Studio's data: the pack a web-server binary
        // carries, or the directory a build wrote.
        final DVAssetFile? file = DVAssetSources.at(directory).file('graph.json');
        graph = file == null ? null : jsonDecode(utf8.decode(file.bytes()));
      } on FormatException {
        graph = null;
      }
    }
    return _reply(graph is Map
        ? graph.cast<String, Object?>()
        : const <String, Object?>{});
  }

  // ---- cache -------------------------------------------------------------

  Future<Response> _cacheAt(String method, List<String> path) async {
    const DVCacheTags tags = DVCacheTags();
    if (path.length == 1 && path.first == 'tags') {
      if (method != 'GET') _notAllowed();
      final List<String> names = tags.tags.toList()..sort();
      return _reply(<String, Object?>{
        'tags': <Object?>[
          for (final String tag in names)
            <String, Object?>{
              'tag': tag,
              'keys': tags.keysForTag(tag).toList()..sort(),
            },
        ],
      });
    }
    if (path.length == 3 && path.first == 'tags' && path[2] == 'revalidate') {
      if (method != 'POST') _notAllowed();
      final List<String> dropped = tags.revalidateTag(path[1]).toList()..sort();
      return _reply(<String, Object?>{'tag': path[1], 'dropped': dropped});
    }
    throw _StudioRefusal(404, 'not_found', 'No such Studio endpoint.');
  }

  // ---- grants ------------------------------------------------------------

  DVAccountDirectory? get _directory =>
      _accounts ?? DVAuthEndpoints.accountDirectory;

  Future<Response> _grantsAt(Request request, String method) async {
    switch (method) {
      case 'GET':
        return _grants(request);
      case 'POST':
        return _grant(request);
      case 'DELETE':
        return _revoke(request);
    }
    _notAllowed();
  }

  Future<Response> _grants(Request request) async {
    final List<DVStudioGrant> grants = await DVStudioGrants(_database).list();
    final String? you = await _caller(request);
    final DVAccountDirectory? directory = _directory;
    return _reply(<String, Object?>{
      'grants': <Object?>[
        for (final DVStudioGrant grant in grants)
          <String, Object?>{
            'userId': grant.userId,
            if (await _emailOf(directory, grant.userId) case final String email)
              'email': email,
            'tenant': grant.tenant,
            'grantedAt': grant.grantedAt.toIso8601String(),
            if (grant.userId == you) 'you': true,
          },
      ],
    });
  }

  static Future<String?> _emailOf(
      DVAccountDirectory? directory, String userId) async {
    if (directory == null) return null;
    try {
      return (await directory.userById(userId))?.email;
    } on Object {
      // Listed by id when the provider cannot say.
      return null;
    }
  }

  /// Grants the account the body names, by address or by id.
  Future<Response> _grant(Request request) async {
    final Map<String, Object?> body = await _body(request);
    final String account = '${body['account'] ?? ''}'.trim();
    if (account.isEmpty) {
      throw _StudioRefusal(
          400, 'bad_account', 'Name the account by its address or its id.');
    }
    final String tenant = _tenantOf(body['tenant']);
    final DVAccountDirectory? directory = _directory;
    final String userId;
    String? email;
    if (account.contains('@')) {
      // By address only where somebody can say whose address it is: a grant
      // to a string that is no account's id opens Studio to nobody, and
      // looks as if it had worked.
      if (directory is! DVAccountLookup) {
        throw _StudioRefusal(
          400,
          'no_lookup',
          'This application\'s accounts cannot be found by address. Grant '
              'the account id instead.',
        );
      }
      final AuthUser? user =
          await (directory as DVAccountLookup).userByEmail(account);
      if (user == null) {
        throw _StudioRefusal(
          404,
          'no_account',
          'Nobody has signed up with $account. They sign up to the '
              'application first, then are granted.',
        );
      }
      userId = user.id;
      email = user.email;
    } else {
      if (directory != null) {
        final AuthUser? user = await directory.userById(account);
        if (user == null) {
          throw _StudioRefusal(
              404, 'no_account', 'No account has the id $account.');
        }
        email = user.email;
      }
      userId = account;
    }
    final DVStudioGrants grants = DVStudioGrants(_database);
    await grants.grant(userId, tenant: tenant);
    return _reply(<String, Object?>{
      'userId': userId,
      'email': ?email,
      'tenant': tenant,
    }, status: 201);
  }

  /// Takes a grant away. Revoking your own, or the last one on a tenant, is
  /// refused until the request confirms it: either can leave the person
  /// doing it, or everybody, unable to open Studio again except from the
  /// command line.
  Future<Response> _revoke(Request request) async {
    final Map<String, String> query = request.url.queryParameters;
    final String userId = (query['userId'] ?? '').trim();
    if (userId.isEmpty) {
      throw _StudioRefusal(400, 'bad_account', 'Name the userId to revoke.');
    }
    final String tenant = _tenantOf(query['tenant']);
    final bool confirmed = query['confirm'] == 'true';
    final DVStudioGrants grants = DVStudioGrants(_database);
    if (!await grants.isGranted(userId, tenant: tenant)) {
      throw _StudioRefusal(
          404, 'not_found', '$userId holds no grant on tenant $tenant.');
    }
    if (!confirmed) {
      final int onTenant = (await grants.list())
          .where((DVStudioGrant g) => g.tenant == tenant)
          .length;
      if (onTenant <= 1) {
        throw _StudioRefusal(
          409,
          'confirm_last',
          'This is the last grant on tenant $tenant. Once it is revoked '
              'nobody can open Studio there until somebody runs dartvel '
              'admin grant.',
        );
      }
      if (userId == await _caller(request)) {
        throw _StudioRefusal(
          409,
          'confirm_self',
          'This is your own grant. Once it is revoked you cannot open '
              'Studio again unless somebody grants you.',
        );
      }
    }
    await grants.revoke(userId, tenant: tenant);
    return _reply(<String, Object?>{'revoked': userId, 'tenant': tenant});
  }

  static String _tenantOf(Object? value) {
    final String named = '${value ?? ''}'.trim();
    return named.isEmpty ? const DVTenants().currentTenant : named;
  }
}
