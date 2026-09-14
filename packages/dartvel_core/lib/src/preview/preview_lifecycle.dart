/// A preview's life: created from a branch, suspended when nobody is looking,
/// destroyed when the branch is done with it.
///
/// Driven by a `now` the caller passes, the way a rollout is, so a CLI step, a
/// scheduled sweep and a test all make the same decision on the same clock.
///
/// Every resource a preview owns is recorded before it is created and removed
/// from the record only once the adapter confirms it is gone. The failure this
/// is arranged around is quiet: a teardown that reported success while a
/// database kept running, or a create that died half-way and left resources
/// nothing lists -- both of which cost money every hour and show up only on
/// an invoice.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'preview_config.dart';
import 'preview_identity.dart';
import 'preview_secrets.dart';

/// A kind of resource a preview owns.
enum DVPreviewResource { deployment, database, bucket }

/// The names production's resources go by, so a preview's can be checked
/// against them before anything is created.
final class DVPreviewProduction {
  const DVPreviewProduction({
    required this.database,
    required this.bucket,
    required this.host,
    required this.queueNamespace,
  });

  final String database;
  final String bucket;
  final String host;
  final String queueNamespace;

  Set<String> get names => <String>{database, bucket, host, queueNamespace};
}

/// What the adapter deploys.
final class DVPreviewDeployment {
  const DVPreviewDeployment({
    required this.identity,
    required this.visibility,
    required this.secrets,
    this.linkDigest,
    this.productionOrigin,
    this.productionDatabase,
    this.schedules = const <String>{},
  });

  final DVPreviewIdentity identity;
  final DVPreviewVisibility visibility;

  /// Preview values only. See [dvPlanPreviewSecrets].
  final Map<String, String> secrets;

  /// SHA-256 of the link token, for `visibility: link`. The token itself is
  /// never part of a deployment: platform environment variables are readable
  /// by everybody who can read the deployment's settings.
  final String? linkDigest;

  /// Where the canonical link of every preview page points.
  final String? productionOrigin;

  /// Production's database name -- a name, not a credential -- so the
  /// running preview can refuse to start on it.
  final String? productionDatabase;

  final Set<String> schedules;

  /// The process environment the preview runs with. The Dartvel names are
  /// written after the secrets, so a secret declared under one of them cannot
  /// move the preview onto production's environment.
  Map<String, String> get variables => <String, String>{
        ...secrets,
        'DARTVEL_ENVIRONMENT': dvPreviewEnvironment,
        'DARTVEL_PREVIEW': identity.name,
        'DARTVEL_PREVIEW_VISIBILITY': visibility.name,
        'DARTVEL_DATABASE': identity.database,
        'DARTVEL_STORAGE_BUCKET': identity.bucket,
        'DARTVEL_QUEUE_NAMESPACE': identity.queueNamespace,
        if (linkDigest != null) 'DARTVEL_PREVIEW_LINK_DIGEST': linkDigest!,
        if (productionOrigin != null)
          'DARTVEL_PRODUCTION_ORIGIN': productionOrigin!,
        if (productionDatabase != null)
          'DARTVEL_PRODUCTION_DATABASE': productionDatabase!,
        'DARTVEL_PREVIEW_SCHEDULES': (schedules.toList()..sort()).join(','),
      };
}

/// What a deployment platform must do to host previews.
///
/// Whether it can at all is the adapter's answer, the same way traffic
/// weighting is in Backend Release Management. An adapter that cannot
/// create an isolated environment on demand says so through
/// [canHostPreviews] rather than implementing something that shares
/// production's database.
abstract interface class DVPreviewAdapter {
  String get name;

  bool get canHostPreviews;

  /// Whether the provider can branch a database (Neon, PlanetScale).
  bool get canBranchDatabases;

  Future<DVPreviewProduction> production();

  /// Creates an empty database. Throws when one of that name exists.
  Future<void> createDatabase(String database);

  /// Branches [from] into a new database named [database].
  Future<void> branchDatabase(String database, {required String from});

  /// SHA-256 digests, as lowercase hex, of every non-null value of
  /// [table].[column] in [database]. Used to prove a sanitization step left
  /// no production value behind, without either side's values leaving the
  /// provider.
  Future<Set<String>> valueDigests(String database, String table, String column);

  Future<void> createBucket(String bucket);

  /// Deploys, or redeploys, and returns the preview's URL.
  Future<String> deploy(DVPreviewDeployment deployment);

  Future<void> suspend(DVPreviewIdentity identity);

  Future<void> wake(DVPreviewIdentity identity);

  Future<void> destroyDeployment(DVPreviewIdentity identity);

  Future<void> destroyDatabase(String database);

  Future<void> destroyBucket(String bucket);

  /// Whether the resource still exists, asked of the platform rather than
  /// remembered: a destroy call returning is not the resource being gone.
  /// A deployment is named by its identity's host label.
  Future<bool> exists(DVPreviewResource kind, String name);
}

/// Where a preview is.
enum DVPreviewState { creating, running, suspended, destroying }

/// One preview, as the registry keeps it.
final class DVPreviewRecord {
  const DVPreviewRecord({
    required this.identity,
    required this.state,
    required this.visibility,
    required this.createdAt,
    required this.lastRequestAt,
    this.deployedAt,
    this.pullRequest,
    this.url,
    this.linkToken,
    this.remaining = const <DVPreviewResource>{},
  });

  final DVPreviewIdentity identity;
  final DVPreviewState state;
  final DVPreviewVisibility visibility;
  final DateTime createdAt;
  final DateTime? deployedAt;
  final DateTime lastRequestAt;
  final int? pullRequest;
  final String? url;

  /// The token of a `visibility: link` preview. Kept by whoever created the
  /// preview so the link can be printed again; never deployed.
  final String? linkToken;

  /// Resources this preview owns that have not been confirmed gone.
  final Set<DVPreviewResource> remaining;

  DVPreviewRecord copyWith({
    DVPreviewState? state,
    DateTime? deployedAt,
    DateTime? lastRequestAt,
    String? url,
    Set<DVPreviewResource>? remaining,
  }) =>
      DVPreviewRecord(
        identity: identity,
        state: state ?? this.state,
        visibility: visibility,
        createdAt: createdAt,
        deployedAt: deployedAt ?? this.deployedAt,
        lastRequestAt: lastRequestAt ?? this.lastRequestAt,
        pullRequest: pullRequest,
        url: url ?? this.url,
        linkToken: linkToken,
        remaining: remaining ?? this.remaining,
      );

  /// The URL to hand a reviewer: the link token included where there is one.
  String? get openUrl {
    final String? base = url;
    if (base == null) return null;
    final String? token = linkToken;
    if (token == null) return base;
    return Uri.parse(base).replace(queryParameters: <String, String>{
      dvPreviewLinkParameter: token,
    }).toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'identity': identity.toJson(),
        'state': state.name,
        'visibility': visibility.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'deployedAt': deployedAt?.toUtc().toIso8601String(),
        'lastRequestAt': lastRequestAt.toUtc().toIso8601String(),
        'pullRequest': pullRequest,
        'url': url,
        'linkToken': linkToken,
        'remaining': <String>[
          for (final DVPreviewResource r in remaining) r.name,
        ]..sort(),
      };

  factory DVPreviewRecord.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> id =
        (json['identity']! as Map<Object?, Object?>).cast<String, Object?>();
    DateTime? date(Object? raw) => raw == null ? null : DateTime.parse('$raw');
    return DVPreviewRecord(
      identity: DVPreviewIdentity.fromJson(id),
      state: DVPreviewState.values.byName('${json['state']}'),
      visibility: DVPreviewVisibility.values.byName('${json['visibility']}'),
      createdAt: date(json['createdAt'])!,
      deployedAt: date(json['deployedAt']),
      lastRequestAt: date(json['lastRequestAt'])!,
      pullRequest: json['pullRequest'] as int?,
      url: json['url'] as String?,
      linkToken: json['linkToken'] as String?,
      remaining: <DVPreviewResource>{
        for (final Object? r in (json['remaining'] as List<Object?>? ?? <Object?>[]))
          DVPreviewResource.values.byName('$r'),
      },
    );
  }
}

/// The query parameter a `visibility: link` preview reads its token from.
const String dvPreviewLinkParameter = 'dv_preview';

/// Where previews are recorded.
abstract interface class DVPreviewRegistry {
  Future<List<DVPreviewRecord>> all();
  Future<DVPreviewRecord?> find(String name);
  Future<void> put(DVPreviewRecord record);
  Future<void> remove(String name);
}

/// A registry held in memory. For tests and for a single process.
final class DVMemoryPreviewRegistry implements DVPreviewRegistry {
  final Map<String, DVPreviewRecord> _records = <String, DVPreviewRecord>{};

  @override
  Future<List<DVPreviewRecord>> all() async =>
      List<DVPreviewRecord>.unmodifiable(_records.values);

  @override
  Future<DVPreviewRecord?> find(String name) async => _records[name];

  @override
  Future<void> put(DVPreviewRecord record) async =>
      _records[record.identity.name] = record;

  @override
  Future<void> remove(String name) async => _records.remove(name);
}

/// The database a migration, seed or sanitization step runs against.
final class DVPreviewTarget {
  const DVPreviewTarget({required this.identity});

  final DVPreviewIdentity identity;

  String get database => identity.database;
}

typedef DVPreviewStep = FutureOr<void> Function(DVPreviewTarget target);

/// What a create or destroy did.
final class DVPreviewOutcome {
  const DVPreviewOutcome({
    this.record,
    this.findings = const <DVPreviewFinding>[],
    this.errors = const <String>[],
  });

  final DVPreviewRecord? record;
  final List<DVPreviewFinding> findings;

  /// Failures the specification gives no code: a failed migration, a name
  /// that collides with production's, a teardown that did not finish.
  final List<String> errors;

  /// False whenever the step should fail a CI check.
  bool get ok =>
      errors.isEmpty && !findings.any((DVPreviewFinding f) => f.isError);

  String? get openUrl => record?.openUrl;
}

/// The previews of one application on one adapter.
final class DVPreviews {
  DVPreviews({
    required this.app,
    required this.adapter,
    required this.registry,
    this.config = const DVPreviewConfig(),
    this.currentEnvironment,
    Random? random,
  }) : _random = random ?? Random.secure();

  final String app;
  final DVPreviewAdapter adapter;
  final DVPreviewRegistry registry;
  final DVPreviewConfig config;

  /// The environment the calling process runs as. A preview asking for a
  /// preview is refused: a branch gets one environment.
  final String? currentEnvironment;

  final Random _random;

  Future<List<DVPreviewRecord>> list() => registry.all();

  /// Creates the branch's preview, or redeploys the one it has.
  ///
  /// [sensitiveColumns] is table to `@DVModel.sensitiveField()` columns.
  /// [migrate] runs the project's migration plan against the preview's
  /// database, [seed] its seeds -- on a fresh database only, and once --
  /// and [sanitize] the declared sanitization step over a branch.
  Future<DVPreviewOutcome> create({
    required String branch,
    required DateTime now,
    required DVPreviewSecretPlan secrets,
    int? pullRequest,
    Map<String, Set<String>> sensitiveColumns = const <String, Set<String>>{},
    DVPreviewStep? migrate,
    DVPreviewStep? seed,
    DVPreviewStep? sanitize,
    String? productionOrigin,
  }) async {
    if (!adapter.canHostPreviews) {
      // DV-PREVIEW-010 is a warning in the registry, because an adapter that
      // cannot host previews is a fact about the target rather than a mistake.
      // A create that produced nothing is still a failed step, so the outcome
      // carries an error as well: a CI check that went green here would leave
      // the last run's link on the pull request, pointing at nothing.
      return DVPreviewOutcome(
        findings: <DVPreviewFinding>[
          DVPreviewFinding(
            'DV-PREVIEW-010',
            '${adapter.name} cannot create an isolated environment on demand, so '
            'dartvel preview is unavailable on it. Nothing was created.',
          ),
        ],
        errors: <String>['no preview was created on ${adapter.name}'],
      );
    }
    if (currentEnvironment == dvPreviewEnvironment) {
      return const DVPreviewOutcome(errors: <String>[
        'this process runs as a preview, and a preview of a preview is not '
            'created: a branch gets one environment.',
      ]);
    }

    final DVPreviewIdentity identity =
        DVPreviewIdentity.forBranch(app: app, branch: branch);

    // Plan-time refusals, in the order a developer fixes them. Nothing below
    // has touched the platform.
    if (!secrets.deployable) {
      return DVPreviewOutcome(findings: secrets.findings);
    }

    final bool branching = config.database == DVPreviewDatabase.branch;
    final List<String> sensitive = <String>[
      for (final MapEntry<String, Set<String>> table in sensitiveColumns.entries)
        for (final String column in table.value) '${table.key}.$column',
    ]..sort();
    if (branching && sensitive.isNotEmpty &&
        (config.sanitize == null || sanitize == null)) {
      return DVPreviewOutcome(findings: <DVPreviewFinding>[
        DVPreviewFinding(
          'DV-PREVIEW-003',
          'database: branch copies production rows, and ${sensitive.join(', ')} '
          'hold${sensitive.length == 1 ? 's' : ''} @DVModel.sensitiveField() values. '
          '${config.sanitize == null ? 'Declare dartvel.preview.sanitize' : 'The declared step ${config.sanitize} was not supplied to run'}; '
          'nothing was branched.',
        ),
      ]);
    }
    if (branching && !adapter.canBranchDatabases) {
      return DVPreviewOutcome(errors: <String>[
        'dartvel.preview.database is branch and ${adapter.name} cannot branch '
            'a database. Nothing was copied another way; declare database: '
            'fresh to use the project\'s seeds.',
      ]);
    }

    final DVPreviewProduction production = await adapter.production();
    final Set<String> collisions =
        identity.resourceNames.intersection(production.names);
    if (collisions.isNotEmpty) {
      return DVPreviewOutcome(errors: <String>[
        'the preview of $branch would use ${collisions.join(', ')}, which '
            '${collisions.length == 1 ? 'is' : 'are'} production\'s. Nothing was '
            'created.',
      ]);
    }

    final DVPreviewRecord? existing = await registry.find(identity.name);
    if (existing != null) {
      return _redeploy(existing, now, secrets, migrate, productionOrigin);
    }

    final List<DVPreviewFinding> findings = <DVPreviewFinding>[];

    // The cap counts running previews. Suspending one frees the machine the
    // cap exists to limit; the record, the database and the URL stay.
    final List<DVPreviewRecord> running = <DVPreviewRecord>[
      for (final DVPreviewRecord r in await registry.all())
        if (r.state == DVPreviewState.running) r,
    ]..sort((DVPreviewRecord a, DVPreviewRecord b) =>
        a.lastRequestAt.compareTo(b.lastRequestAt));
    if (running.length >= config.max) {
      final DVPreviewRecord oldest = running.first;
      try {
        await adapter.suspend(oldest.identity);
      } catch (error) {
        return DVPreviewOutcome(errors: <String>[
          '${config.max} previews are running, the cap, and suspending the '
              'oldest idle one (${oldest.identity.name}) failed: $error. '
              'Nothing was created.',
        ]);
      }
      await registry.put(oldest.copyWith(state: DVPreviewState.suspended));
      findings.add(DVPreviewFinding(
        'DV-PREVIEW-004',
        '${config.max} previews were running; ${oldest.identity.name} '
        '(${oldest.identity.branch}), idle since '
        '${oldest.lastRequestAt.toUtc().toIso8601String()}, was suspended to '
        'make room. Its next request wakes it.',
      ));
    }

    final String? linkToken = config.visibility == DVPreviewVisibility.link
        ? base64Url.encode(List<int>.generate(32, (_) => _random.nextInt(256)))
            .replaceAll('=', '')
        : null;

    // Recorded before the first resource exists, with every resource it may
    // come to own, so a process that dies part-way leaves something a sweep
    // can find and take down.
    DVPreviewRecord record = DVPreviewRecord(
      identity: identity,
      state: DVPreviewState.creating,
      visibility: config.visibility,
      createdAt: now,
      lastRequestAt: now,
      pullRequest: pullRequest,
      linkToken: linkToken,
      remaining: DVPreviewResource.values.toSet(),
    );
    await registry.put(record);

    final DVPreviewTarget target = DVPreviewTarget(identity: identity);
    try {
      if (branching) {
        await adapter.branchDatabase(identity.database, from: production.database);
        if (migrate != null) await migrate(target);
        if (sensitive.isNotEmpty) {
          await sanitize!(target);
          final DVPreviewFinding? leak =
              await _productionValuesLeft(sensitiveColumns, production, identity);
          if (leak != null) {
            final DVPreviewOutcome teardown = await _teardown(record, now);
            return DVPreviewOutcome(
              findings: <DVPreviewFinding>[leak],
              errors: teardown.errors,
            );
          }
        }
      } else {
        await adapter.createDatabase(identity.database);
        if (migrate != null) await migrate(target);
        if (seed != null) await seed(target);
      }
      await adapter.createBucket(identity.bucket);
      final String url = await adapter.deploy(DVPreviewDeployment(
        identity: identity,
        visibility: config.visibility,
        secrets: secrets.values,
        linkDigest: linkToken == null ? null : _digest(linkToken),
        productionOrigin: productionOrigin,
        productionDatabase: production.database,
        schedules: config.schedules,
      ));
      record = record.copyWith(
        state: DVPreviewState.running,
        deployedAt: now,
        url: url,
      );
      await registry.put(record);
    } catch (error) {
      final DVPreviewOutcome teardown = await _teardown(record, now);
      return DVPreviewOutcome(errors: <String>[
        'the preview of $branch was not deployed: $error',
        ...teardown.errors,
      ]);
    }

    findings.add(DVPreviewFinding(
      'DV-PREVIEW-001',
      'preview ${identity.name} of $branch created at ${record.url}; it is '
      'destroyed when the branch merges'
      '${pullRequest == null ? '' : ' or pull request #$pullRequest closes'}, '
      'or ${_describe(config.ttl)} after its last deploy.',
    ));
    if (config.visibility == DVPreviewVisibility.public) {
      findings.add(DVPreviewFinding(
        'DV-PREVIEW-007',
        'preview ${identity.name} is declared public: anyone with the URL can '
        'open it. It is still excluded from indexing.',
      ));
    }
    return DVPreviewOutcome(record: record, findings: findings);
  }

  Future<DVPreviewOutcome> _redeploy(
    DVPreviewRecord existing,
    DateTime now,
    DVPreviewSecretPlan secrets,
    DVPreviewStep? migrate,
    String? productionOrigin,
  ) async {
    if (existing.state == DVPreviewState.destroying ||
        existing.state == DVPreviewState.creating) {
      return DVPreviewOutcome(record: existing, errors: <String>[
        'preview ${existing.identity.name} is ${existing.state.name}; run '
            'dartvel preview sweep before creating it again.',
      ]);
    }
    try {
      if (migrate != null) {
        await migrate(DVPreviewTarget(identity: existing.identity));
      }
      final DVPreviewProduction production = await adapter.production();
      final String url = await adapter.deploy(DVPreviewDeployment(
        identity: existing.identity,
        productionDatabase: production.database,
        visibility: existing.visibility,
        secrets: secrets.values,
        linkDigest:
            existing.linkToken == null ? null : _digest(existing.linkToken!),
        productionOrigin: productionOrigin,
        schedules: config.schedules,
      ));
      final DVPreviewRecord record = existing.copyWith(
        state: DVPreviewState.running,
        deployedAt: now,
        lastRequestAt: now,
        url: url,
      );
      await registry.put(record);
      return DVPreviewOutcome(record: record);
    } catch (error) {
      return DVPreviewOutcome(record: existing, errors: <String>[
        'preview ${existing.identity.name} was not redeployed: $error',
      ]);
    }
  }

  /// The finding when any sensitive column of the branch still holds a value
  /// production holds, or null.
  Future<DVPreviewFinding?> _productionValuesLeft(
    Map<String, Set<String>> sensitiveColumns,
    DVPreviewProduction production,
    DVPreviewIdentity identity,
  ) async {
    final List<String> leaks = <String>[];
    final List<String> tables = sensitiveColumns.keys.toList()..sort();
    for (final String table in tables) {
      final List<String> columns = sensitiveColumns[table]!.toList()..sort();
      for (final String column in columns) {
        final Set<String> source =
            await adapter.valueDigests(production.database, table, column);
        final Set<String> branch =
            await adapter.valueDigests(identity.database, table, column);
        final int left = source.intersection(branch).length;
        if (left > 0) leaks.add('$table.$column ($left value${left == 1 ? '' : 's'})');
      }
    }
    if (leaks.isEmpty) return null;
    return DVPreviewFinding(
      'DV-PREVIEW-003',
      'the sanitization step ${config.sanitize} ran and production values '
      'remain in ${leaks.join(', ')}. The branch was destroyed and nothing '
      'was deployed.',
    );
  }

  /// Destroys the preview named [name]: its deployment, database and bucket.
  Future<DVPreviewOutcome> destroy(String name, {required DateTime now}) async {
    final DVPreviewRecord? record = await registry.find(name);
    if (record == null) {
      return DVPreviewOutcome(errors: <String>['there is no preview named $name']);
    }
    return _teardown(record, now);
  }

  Future<DVPreviewOutcome> _teardown(DVPreviewRecord record, DateTime now) async {
    final DVPreviewIdentity id = record.identity;
    DVPreviewRecord current = record.copyWith(
      state: DVPreviewState.destroying,
      remaining: DVPreviewResource.values.toSet(),
    );
    await registry.put(current);

    final List<String> errors = <String>[];
    Future<void> attempt(String what, Future<void> Function() call) async {
      try {
        await call();
      } catch (error) {
        errors.add('destroying the $what of ${id.name} failed: $error');
      }
    }

    // The deployment first: once it is gone nothing is writing to the
    // database or the bucket while they are taken down.
    await attempt('deployment', () => adapter.destroyDeployment(id));
    await attempt('database', () => adapter.destroyDatabase(id.database));
    await attempt('bucket', () => adapter.destroyBucket(id.bucket));

    final Set<DVPreviewResource> remaining = <DVPreviewResource>{};
    for (final DVPreviewResource kind in DVPreviewResource.values) {
      final String resource = switch (kind) {
        DVPreviewResource.deployment => id.hostLabel,
        DVPreviewResource.database => id.database,
        DVPreviewResource.bucket => id.bucket,
      };
      bool exists;
      try {
        exists = await adapter.exists(kind, resource);
      } catch (error) {
        // Unknown is not gone.
        errors.add('could not confirm the $resource ${kind.name} of ${id.name} '
            'is gone: $error');
        exists = true;
      }
      if (exists) remaining.add(kind);
    }

    if (remaining.isNotEmpty) {
      current = current.copyWith(remaining: remaining);
      await registry.put(current);
      return DVPreviewOutcome(record: current, errors: <String>[
        ...errors,
        'preview ${id.name} is not destroyed: its '
            '${(remaining.map((DVPreviewResource r) => r.name).toList()..sort()).join(', ')} '
            'still exist${remaining.length == 1 ? 's' : ''}. The record is kept, '
            'and dartvel preview sweep tries again.',
      ]);
    }

    await registry.remove(id.name);
    return DVPreviewOutcome(findings: <DVPreviewFinding>[
      DVPreviewFinding(
        'DV-PREVIEW-009',
        'preview ${id.name} of ${id.branch} destroyed; its database '
        '${id.database} and bucket ${id.bucket} went with it.',
      ),
    ]);
  }

  /// Destroys what is over and suspends what is idle, as of [now].
  ///
  /// [liveBranches], when given, is every branch that still exists: a
  /// preview whose branch is not among them has merged or been deleted.
  /// [closedPullRequests] are pull requests that closed.
  Future<List<DVPreviewFinding>> sweep({
    required DateTime now,
    Set<String>? liveBranches,
    Set<int> closedPullRequests = const <int>{},
  }) async {
    final List<DVPreviewFinding> findings = <DVPreviewFinding>[];
    for (final DVPreviewRecord record in await registry.all()) {
      final bool over = record.state == DVPreviewState.destroying ||
          // A create that is still `creating` after an idle interval is not
          // still creating: the process that started it has gone.
          (record.state == DVPreviewState.creating &&
              !now.isBefore(record.createdAt.add(config.idle))) ||
          (liveBranches != null && !liveBranches.contains(record.identity.branch)) ||
          (record.pullRequest != null &&
              closedPullRequests.contains(record.pullRequest)) ||
          (record.state != DVPreviewState.creating &&
              !now.isBefore((record.deployedAt ?? record.createdAt).add(config.ttl)));
      if (over) {
        findings.addAll((await _teardown(record, now)).findings);
        continue;
      }
      if (record.state == DVPreviewState.running &&
          !now.isBefore(record.lastRequestAt.add(config.idle))) {
        try {
          await adapter.suspend(record.identity);
        } catch (_) {
          continue;
        }
        await registry.put(record.copyWith(state: DVPreviewState.suspended));
        findings.add(DVPreviewFinding(
          'DV-PREVIEW-005',
          'preview ${record.identity.name} suspended: no request for '
          '${_describe(config.idle)}. Its next request wakes it.',
        ));
      }
    }
    return findings;
  }

  /// Records a request to the preview named [name], waking it if suspended.
  Future<DVPreviewRecord?> touch(String name, {required DateTime now}) async {
    final DVPreviewRecord? record = await registry.find(name);
    if (record == null) return null;
    if (record.state == DVPreviewState.suspended) {
      await adapter.wake(record.identity);
    } else if (record.state != DVPreviewState.running) {
      return record;
    }
    final DVPreviewRecord updated =
        record.copyWith(state: DVPreviewState.running, lastRequestAt: now);
    await registry.put(updated);
    return updated;
  }

  static String _digest(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  static String _describe(Duration d) {
    if (d.inDays > 0 && d == Duration(days: d.inDays)) return '${d.inDays}d';
    if (d.inHours > 0 && d == Duration(hours: d.inHours)) return '${d.inHours}h';
    if (d.inMinutes > 0 && d == Duration(minutes: d.inMinutes)) {
      return '${d.inMinutes}m';
    }
    return '${d.inSeconds}s';
  }
}
