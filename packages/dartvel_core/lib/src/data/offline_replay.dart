/// The one route that takes writes a device made while nobody was watching.
///
/// Everything about the request is somebody else's input: the model it
/// names, the key, the values, how many of them there are. The generated
/// backend authenticates the route like every other, and the model's own
/// policy decides each mutation through the remote's `authorize`. This is
/// what runs before either, and it decides whether the request is a request
/// at all.
///
/// Not in the barrel an application imports. An application declares
/// `@DVModel(offline:)` and the generated backend serves this; nothing else
/// should be able to hand a table a write from outside.
library;

import '../../dartvel.dart' show DVAuthAuthorization;
import '../admin/studio_api.dart';
import '../auth/backend_policy.dart';
import '../database/adapter.dart';
import '../observability/observability.dart';
import '../schema/generated_schema.dart' show dvTenantColumn;
import '../tenancy/tenants.dart';
import 'offline_store.dart';
import 'record_history.dart';

/// What the route answers.
///
/// Status and message are chosen here, and nothing from the request is ever
/// in the message: an error that echoes its input is how a probe learns what
/// exists.
class DVOfflineReplayResult {
  const DVOfflineReplayResult(this.status, this.message,
      {this.body = const <String, Object?>{}});

  final int status;
  final String message;
  final Map<String, Object?> body;
}

/// Applies a batch of replayed mutations to the models that declared they
/// work offline, and to no others.
class DVOfflineReplay {
  const DVOfflineReplay(this.remotes);

  /// By model name, as the generator wrote it. A name that is not a key here
  /// is a model nobody declared offline, and is refused: a registry that fell
  /// back to looking the table up would be an arbitrary-table write
  /// primitive reachable by anybody with a session.
  final Map<String, DVOfflineRemote> remotes;

  /// The most mutations one request may carry.
  ///
  /// A queue that has been filling for a week is replayed in batches, so the
  /// bound is generous; what it stops is a single request holding a
  /// connection and somebody else's database open for as long as the sender
  /// likes.
  static const int maxMutations = 500;

  /// The route the generated backend serves this on, under the API base path.
  static const String path = '/offline/replay';

  /// The registry the generated backend builds, from the specs it already
  /// has for Studio.
  ///
  /// Only the specs that declare a strategy. The backend cannot import
  /// models.g.dart -- that file imports Flutter -- so a remote is resolved
  /// from the spec's table, key, columns, sensitive fields, tenancy,
  /// versioning and soft delete rather than from the model class.
  factory DVOfflineReplay.forSpecs(
    List<DVStudioModelSpec> specs, {
    required DVDatabaseAdapter database,
  }) {
    final Map<String, DVOfflineRemote> remotes = <String, DVOfflineRemote>{};
    for (final DVStudioModelSpec spec in specs) {
      final DVConflict? strategy = spec.offline;
      if (strategy == null) continue;
      final String table;
      final DVDatabaseAdapter store;
      try {
        // Where this model's rows actually are: the tenant's schema where
        // that is the separation, the name the module's mount gave it, and
        // the module's own database where it owns one. Studio resolves a
        // spec the same way through the same two members, so the route that
        // takes a device's queue writes the rows Studio reads.
        table = spec.resolvedTable;
        store = spec.resolvedDatabase(database);
      } on StateError {
        // A module mounted remotely, or one whose own database nothing has
        // given it. Its rows are not this process's to write, so it is not
        // in the registry and a mutation naming it is refused like any other
        // model nobody declared offline -- rather than a batch that dies
        // with a server error, or one applied to the parent's tables.
        continue;
      }
      remotes[spec.id] = DVRecordTableRemote(
        DVRecordTable(
          table: table,
          key: spec.key,
          columns: <String>[
            if (spec.tenantScoped) dvTenantColumn,
            for (final DVStudioFieldSpec field in spec.fields) field.name,
          ],
          sensitive: <String>{
            for (final DVStudioFieldSpec field in spec.fields)
              if (field.sensitive) field.name,
          },
          // A generated model declares every field column TEXT, and so does
          // Studio. Declared here rather than left off because a table this
          // route created first would otherwise have untyped columns, which
          // in SQLite take whatever they are given.
          types: <String, String>{
            if (spec.tenantScoped) dvTenantColumn: 'TEXT',
            for (final DVStudioFieldSpec field in spec.fields)
              field.name: 'TEXT',
          },
          versioned: spec.versioned,
          softDelete: spec.softDelete,
          // The same scope every other read and write on this table carries.
          // The whole registry is built inside the request, so the tenant
          // read here is the one that asked.
          scope: spec.tenantScoped
              ? DVRecordScope(dvTenantColumn, const DVTenants().currentTenant)
              : null,
          database: store,
        ),
        strategy: strategy,
        authorize: (DVMutation mutation) => _authorized(spec, mutation, store),
      );
    }
    return DVOfflineReplay(remotes);
  }

  /// Whether the caller may make this change, asked of the model's policy.
  ///
  /// The server has no model class, so the policy is asked with the values.
  /// A policy written for the model's own type does not accept those and
  /// refuses, saying so once -- which is the same default-deny the rest of
  /// the generated server gives a policy it cannot reach, and is why a model
  /// that has to work offline needs its policy written against dartvel_core.
  static Future<bool> _authorized(
    DVStudioModelSpec spec,
    DVMutation mutation,
    DVDatabaseAdapter database,
  ) async {
    try {
      final DVRecord? stored = await DVRecordTable(
        table: spec.resolvedTable,
        key: spec.key,
        columns: <String>[
          for (final DVStudioFieldSpec field in spec.fields) field.name,
        ],
        types: <String, String>{
          for (final DVStudioFieldSpec field in spec.fields)
            field.name: 'TEXT',
        },
        database: database,
      ).read(mutation.key, withDeleted: true);
      final String action = mutation.isDelete
          ? '${spec.model}.delete'
          : stored == null
              ? '${spec.model}.create'
              : '${spec.model}.update';
      // Awaited inside the try, or the future escapes it and a policy that
      // throws asynchronously is an error on the way out rather than the
      // refusal the catch below is here to make it.
      return await const DVAuthAuthorization().canAction(
        DVBackendPolicy.callerFor(action),
        action,
        resource: stored?.values ?? mutation.values,
      );
    } catch (error) {
      // Default deny. A policy that could not be reached, or a read that
      // failed on the way to asking it, has not said yes.
      DVObservability.logger.warn(
        'Replay authorization for ${spec.model} could not decide, so it '
        'refused: $error',
      );
      return false;
    }
  }

  Future<DVOfflineReplayResult> handle(Object? body) async {
    if (body is! Map<Object?, Object?>) {
      return const DVOfflineReplayResult(400, 'not a replay request');
    }
    final Object? model = body['model'];
    final Object? mutations = body['mutations'];
    if (model is! String || model.isEmpty || mutations is! List<Object?>) {
      return const DVOfflineReplayResult(400, 'not a replay request');
    }
    if (mutations.length > maxMutations) {
      return const DVOfflineReplayResult(413, 'too many mutations at once');
    }

    final DVOfflineRemote? remote = remotes[model];
    if (remote == null) {
      // The same answer for a model that does not exist and one that exists
      // and is not offline. Telling them apart is telling a caller what this
      // application is made of.
      return const DVOfflineReplayResult(404, 'no such offline model');
    }

    // Decoded before any of it is applied, so a batch with one bad mutation
    // in the middle does not leave the ones before it written and the ones
    // after it not.
    final List<DVMutation> decoded = <DVMutation>[];
    for (final Object? entry in mutations) {
      final DVMutation? mutation = _decode(entry);
      if (mutation == null) {
        return const DVOfflineReplayResult(400, 'not a replay request');
      }
      decoded.add(mutation);
    }

    final List<Object?> outcomes = <Object?>[];
    for (final DVMutation mutation in decoded) {
      final DVRemoteOutcome outcome = await remote.apply(mutation);
      outcomes.add(<String, Object?>{
        'mutationId': mutation.mutationId,
        ...dvOutcomeToJson(outcome, sensitive: remote.sensitiveColumns),
      });
    }
    return DVOfflineReplayResult(200, 'applied',
        body: <String, Object?>{'outcomes': outcomes});
  }

  /// A mutation, or null when what arrived is not one.
  ///
  /// The key must be a scalar. A map or a list would reach the table as
  /// whatever it interpolates to -- a key nobody meant, and one no other
  /// writer will ever match, so the row it makes is invisible to everything
  /// except the device that sent it.
  static DVMutation? _decode(Object? entry) {
    if (entry is! Map<Object?, Object?>) return null;
    final Object? key = entry['key'];
    if (key is! String && key is! num) return null;
    final Object? op = entry['op'];
    if (op != DVMutation.opWrite && op != DVMutation.opDelete) return null;
    try {
      return DVMutation.fromJson(
        entry.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)),
      );
    } catch (_) {
      // Malformed is refused, not thrown at: a 500 here would report the
      // server as broken for a request that was never well formed.
      return null;
    }
  }
}
