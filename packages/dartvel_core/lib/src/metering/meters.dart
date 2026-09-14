/// Usage metering and quotas: what is counted, whose it is, and what happens
/// when a tenant reaches a limit.
///
/// The recording layer is here: meters, the period a record belongs to, the
/// idempotency that stops a retry from billing twice, and the enforcement of
/// a declared limit. The billing provider's invoice stays the customer-facing
/// figure; this is the evidence behind it.
library dartvel_core.metering.meters;

import 'dart:async';

import '../database/adapter.dart';
import '../observability/observability.dart';
import '../tenancy/tenants.dart';

/// Whether a meter accumulates or samples.
enum DVMeterKind {
  /// Events adding up over a period: API calls, tokens, messages sent.
  counter,

  /// The current value at a sample: gigabytes stored, connections open.
  /// "Gigabytes stored" is not a number you add up, so a gauge is billed on
  /// its [DVGaugeBilling] instead.
  gauge,
}

/// How a gauge's samples become one number for the period.
enum DVGaugeBilling { average, peak }

/// What happens to a recording that would take a tenant past its limit.
///
/// There is no default. Each is somebody's correct answer, and a deployment
/// that got one silently finds out which during an incident.
enum DVQuota {
  /// Refused, and not counted. The call does not proceed.
  block,

  /// Counted, and the call proceeds slowly enough to notice.
  throttle,

  /// Counted, the call proceeds, and the amount past the limit is billed.
  allowAndBill,
}

/// Where a meter's limit comes from.
class DVLimit {
  const DVLimit._({this.value});

  /// A fixed quantity, the same for every tenant.
  const DVLimit.fixed(num value) : this._(value: value);

  /// The tenant's plan decides, read through [DVMeters.limits].
  static const DVLimit entitlement = DVLimit._();

  /// The fixed quantity, or null when the plan decides.
  final num? value;

  bool get fromEntitlement => value == null;

  @override
  String toString() =>
      fromEntitlement ? 'DVLimit.entitlement' : 'DVLimit.fixed($value)';
}

/// A meter: the name usage is counted under, and what bounds it.
///
/// Built once per meter, normally by the generated client from an
/// `@DVMeter` declaration.
class DVMeterDefinition {
  DVMeterDefinition(
    this.name, {
    required this.unit,
    this.kind = DVMeterKind.counter,
    this.limit,
    this.atLimit,
    this.notifyAt = const <double>[],
    this.grace,
    this.gaugeBilling = DVGaugeBilling.average,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'a meter needs a name');
    }
    if (limit != null && atLimit == null) {
      throw ArgumentError(
        'DV-METER-005: meter "$name" declares a limit and no behaviour at '
        'the limit. Pass atLimit: DVQuota.block, DVQuota.throttle or '
        'DVQuota.allowAndBill -- there is no default, because each is '
        "somebody's correct answer and picking one silently is how a "
        'deployment finds out which it got.',
      );
    }
    final num? fixed = limit?.value;
    if (fixed != null && !(fixed >= 0)) {
      throw ArgumentError.value(fixed, 'limit', 'a limit cannot be negative');
    }
    if (notifyAt.isNotEmpty && limit == null) {
      throw ArgumentError(
        'meter "$name" declares notifyAt with no limit to be a fraction of',
      );
    }
    for (final double fraction in notifyAt) {
      if (!(fraction > 0) || fraction.isInfinite) {
        throw ArgumentError.value(
            fraction, 'notifyAt', 'a threshold is a positive fraction');
      }
    }
  }

  final String name;
  final String unit;
  final DVMeterKind kind;
  final DVLimit? limit;
  final DVQuota? atLimit;

  /// Fractions of the limit announced when a recording crosses them.
  final List<double> notifyAt;

  /// How long after its period closes a late record is still accepted into
  /// it. Null takes [DVMeters.grace].
  final Duration? grace;

  final DVGaugeBilling gaugeBilling;

  /// Records [amount] through the configured [DVMeters].
  Future<DVMeterOutcome> record(
    num amount, {
    String? idempotencyKey,
    DateTime? at,
  }) =>
      DVMeters.current
          .record(this, amount, idempotencyKey: idempotencyKey, at: at);

  @override
  String toString() => 'DVMeterDefinition($name)';
}

/// A half-open span of time: [start] is inside it, [end] is the next one's
/// start. Half-open so that a record on the boundary belongs to exactly one.
class DVMeterPeriod {
  const DVMeterPeriod(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime at) => !at.isBefore(start) && at.isBefore(end);

  /// The calendar month containing [at], in UTC.
  factory DVMeterPeriod.calendarMonth(DateTime at) {
    final DateTime utc = at.toUtc();
    return DVMeterPeriod(
      DateTime.utc(utc.year, utc.month),
      DateTime.utc(utc.year, utc.month + 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DVMeterPeriod &&
      other.start.isAtSameMomentAs(start) &&
      other.end.isAtSameMomentAs(end);

  @override
  int get hashCode => Object.hash(
      start.microsecondsSinceEpoch, end.microsecondsSinceEpoch);

  @override
  String toString() =>
      'DVMeterPeriod(${start.toIso8601String()}, ${end.toIso8601String()})';
}

/// One stored recording.
class DVMeterRecord {
  const DVMeterRecord({
    required this.tenant,
    required this.meter,
    required this.idempotencyKey,
    required this.amount,
    required this.at,
    required this.period,
  });

  final String tenant;
  final String meter;
  final String idempotencyKey;
  final num amount;

  /// When the usage happened.
  final DateTime at;

  /// The period it was counted in, which for a late record can be a
  /// different one from the period [at] falls in.
  final DVMeterPeriod period;
}

/// A threshold a recording crossed.
class DVMeterThreshold {
  const DVMeterThreshold({
    required this.meter,
    required this.tenant,
    required this.fraction,
    required this.total,
    required this.limit,
    required this.period,
  });

  final DVMeterDefinition meter;
  final String tenant;
  final double fraction;
  final num total;
  final num limit;
  final DVMeterPeriod period;
}

/// What happened to one recording, or one level check.
class DVMeterOutcome {
  const DVMeterOutcome({
    required this.recorded,
    required this.admitted,
    required this.total,
    required this.period,
    this.applied,
    this.limit,
    this.overage = 0,
    this.codes = const <String>[],
    this.crossed = const <double>[],
  });

  /// Whether a record was stored. False for a duplicate and for a block.
  final bool recorded;

  /// Whether the call the recording was for may proceed.
  final bool admitted;

  /// The behaviour applied at the limit, or null when under it.
  final DVQuota? applied;

  /// Usage in [period] after this recording.
  final num total;

  final num? limit;

  /// The amount past the limit that will be billed, under
  /// [DVQuota.allowAndBill].
  final num overage;

  final DVMeterPeriod period;

  /// The diagnostic codes this recording raised, in the order raised.
  final List<String> codes;

  /// The notification thresholds this recording crossed.
  final List<double> crossed;
}

/// A limit on a level: how many of something exist right now.
///
/// Seats, projects, connected devices. Counted when asked, never recorded --
/// a level already has an authoritative answer, and a counter kept beside it
/// drifts the first time a row is removed by a cascade or a restore.
class DVLevelLimit {
  const DVLevelLimit(
    this.name, {
    required this.count,
    required this.limit,
    required this.atLimit,
  });

  final String name;
  final FutureOr<num> Function(String tenant) count;

  /// The tenant's limit, or null when its plan sets none.
  final FutureOr<num?> Function(String tenant) limit;
  final DVQuota atLimit;
}

/// Where meter records are kept.
abstract class DVMeterStore {
  /// Whether a record with [key] exists for [tenant] and [meter] in any of
  /// [periods].
  Future<bool> hasKey({
    required String tenant,
    required String meter,
    required String key,
    required Iterable<DVMeterPeriod> periods,
  });

  /// Stores [record]. Returns false when the store itself refused it as a
  /// duplicate, which a database does when two instances race.
  Future<bool> add(DVMeterRecord record);

  /// The records counted in [period] for [tenant] and [meter].
  Future<List<DVMeterRecord>> recordsIn({
    required String tenant,
    required String meter,
    required DVMeterPeriod period,
  });
}

/// Records held in this process. Tests and single-instance development.
class DVMemoryMeterStore implements DVMeterStore {
  final List<DVMeterRecord> _records = <DVMeterRecord>[];

  int get recordCount => _records.length;

  @override
  Future<bool> hasKey({
    required String tenant,
    required String meter,
    required String key,
    required Iterable<DVMeterPeriod> periods,
  }) async {
    final Set<DVMeterPeriod> within = periods.toSet();
    return _records.any((DVMeterRecord r) =>
        r.tenant == tenant &&
        r.meter == meter &&
        r.idempotencyKey == key &&
        within.contains(r.period));
  }

  @override
  Future<bool> add(DVMeterRecord record) async {
    _records.add(record);
    return true;
  }

  @override
  Future<List<DVMeterRecord>> recordsIn({
    required String tenant,
    required String meter,
    required DVMeterPeriod period,
  }) async =>
      <DVMeterRecord>[
        for (final DVMeterRecord r in _records)
          if (r.tenant == tenant && r.meter == meter && r.period == period) r,
      ];
}

/// Records in the application's own database, through `DV.Database`.
///
/// Instances share it, which is what makes a tenant's total one number
/// rather than one per process. On a database that enforces constraints, a
/// retry racing its original onto two instances is refused by the unique key
/// rather than counted twice.
class DVDatabaseMeterStore implements DVMeterStore {
  DVDatabaseMeterStore({this.table = 'dv_meter_records'});

  final String table;
  Future<void>? _ready;

  static const DVDatabase _db = DVDatabase();

  Future<void> _ensureTable() => _ready ??= _create();

  Future<void> _create() async {
    const String columns = 'dv_tenant TEXT NOT NULL, meter TEXT NOT NULL, '
        'idempotency_key TEXT NOT NULL, amount REAL NOT NULL, '
        'at_us INTEGER NOT NULL, period_start_us INTEGER NOT NULL, '
        'period_end_us INTEGER NOT NULL';
    try {
      await _db.execute(
        'CREATE TABLE IF NOT EXISTS $table ($columns, '
        'UNIQUE (dv_tenant, meter, period_start_us, idempotency_key))',
      );
    } on ArgumentError {
      // An adapter that cannot express the constraint still stores records;
      // the in-process check in DVMeters is then the only guard.
      await _db.execute('CREATE TABLE IF NOT EXISTS $table ($columns)');
    }
  }

  @override
  Future<bool> hasKey({
    required String tenant,
    required String meter,
    required String key,
    required Iterable<DVMeterPeriod> periods,
  }) async {
    await _ensureTable();
    for (final DVMeterPeriod period in periods.toSet()) {
      final List<Map<String, Object?>> rows = await _db.query(
        'SELECT COUNT(*) AS n FROM $table WHERE dv_tenant = ? AND meter = ? '
        'AND idempotency_key = ? AND period_start_us = ?',
        <Object?>[tenant, meter, key, period.start.microsecondsSinceEpoch],
      );
      if (rows.isNotEmpty && ((rows.first['n'] as num?) ?? 0) > 0) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> add(DVMeterRecord record) async {
    await _ensureTable();
    try {
      await _db.execute(
        'INSERT INTO $table (dv_tenant, meter, idempotency_key, amount, at_us, '
        'period_start_us, period_end_us) VALUES (?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          record.tenant,
          record.meter,
          record.idempotencyKey,
          record.amount,
          record.at.microsecondsSinceEpoch,
          record.period.start.microsecondsSinceEpoch,
          record.period.end.microsecondsSinceEpoch,
        ],
      );
      return true;
    } on Object catch (error) {
      if ('$error'.toUpperCase().contains('UNIQUE')) return false;
      rethrow;
    }
  }

  @override
  Future<List<DVMeterRecord>> recordsIn({
    required String tenant,
    required String meter,
    required DVMeterPeriod period,
  }) async {
    await _ensureTable();
    final List<Map<String, Object?>> rows = await _db.query(
      'SELECT idempotency_key, amount, at_us FROM $table WHERE dv_tenant = ? '
      'AND meter = ? AND period_start_us = ? AND period_end_us = ?',
      <Object?>[
        tenant,
        meter,
        period.start.microsecondsSinceEpoch,
        period.end.microsecondsSinceEpoch,
      ],
    );
    return <DVMeterRecord>[
      for (final Map<String, Object?> row in rows)
        DVMeterRecord(
          tenant: tenant,
          meter: meter,
          idempotencyKey: '${row['idempotency_key']}',
          amount: row['amount']! as num,
          at: DateTime.fromMicrosecondsSinceEpoch(
              (row['at_us']! as num).toInt(),
              isUtc: true),
          period: period,
        ),
    ];
  }
}

/// The tenant's billing period containing [at], or null when it has none.
typedef DVBillingPeriodResolver = FutureOr<DVMeterPeriod?> Function(
    String tenant, DateTime at);

/// The tenant's limit for [meter] under its plan, or null when the plan sets
/// none.
typedef DVMeterLimitResolver = FutureOr<num?> Function(
    String tenant, DVMeterDefinition meter);

typedef DVMeterThresholdHandler = FutureOr<void> Function(
    DVMeterThreshold threshold);

/// Records usage, places it in its period, and applies limits.
class DVMeters {
  DVMeters({
    required this.store,
    DateTime Function()? clock,
    this.periods,
    this.limits,
    this.onThreshold,
    this.grace = Duration.zero,
    DVLogger? logger,
  })  : _clock = clock ?? (() => DateTime.now().toUtc()),
        _logger = logger;

  final DVMeterStore store;
  final DVBillingPeriodResolver? periods;
  final DVMeterLimitResolver? limits;

  /// Called for each notification threshold a recording crosses. This is the
  /// seam Notifications sends through.
  final DVMeterThresholdHandler? onThreshold;

  /// The deployment's grace for late records, when a meter declares none.
  final Duration grace;

  final DateTime Function() _clock;
  final DVLogger? _logger;

  DVLogger get _log => _logger ?? DVObservability.logger;

  /// The time these meters consider current, in UTC.
  ///
  /// Public so that what reports and reconciles usage decides "is this period
  /// closed" by the same clock that placed the records in it.
  DateTime get now => _clock().toUtc();

  static DVMeters? _current;

  /// Sets the meters [DVMeterDefinition.record] records through.
  static void configure(DVMeters meters) => _current = meters;

  static void unconfigure() => _current = null;

  static DVMeters get current {
    final DVMeters? meters = _current;
    if (meters == null) {
      throw StateError(
        'No meters are configured. Call DVMeters.configure(DVMeters(store: '
        '...)) before recording; a recording with nowhere to go is not a '
        'usage number.',
      );
    }
    return meters;
  }

  static const Symbol _zoneKey = #dartvelMeterIdempotencyKey;

  /// Runs [body] with [key] as the idempotency key for recordings that do not
  /// pass one: the request id for a backend call, the job id for a job, so a
  /// retry of either counts once however many attempts it took.
  static R withIdempotencyKey<R>(String key, R Function() body) =>
      runZoned(body, zoneValues: <Object?, Object?>{_zoneKey: key});

  static String? get currentIdempotencyKey => Zone.current[_zoneKey] as String?;

  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  /// The queue a tenant's meter is serialised on. One function, because a
  /// check and a recording on two spellings of it do not wait for each other.
  static String _queueKey(String tenant, String meter) => '$tenant\u0000$meter';

  /// Runs [body] after every earlier body for [key] has finished.
  ///
  /// Enforcement is a read and a write; without this, every request in the
  /// same instant reads "two of three" and all of them proceed.
  Future<T> _serialised<T>(String key, Future<T> Function() body) async {
    // Registered before the first await, so a call made in the same instant
    // queues behind this one rather than reading the same "before".
    final Future<void> previous = _tails[key] ?? Future<void>.value();
    final Completer<void> done = Completer<void>();
    _tails[key] = done.future;
    try {
      await previous;
      return await body();
    } finally {
      done.complete();
      if (identical(_tails[key], done.future)) unawaited(_tails.remove(key));
    }
  }

  /// Records [amount] against [meter] for the current tenant.
  Future<DVMeterOutcome> record(
    DVMeterDefinition meter,
    num amount, {
    String? idempotencyKey,
    DateTime? at,
  }) {
    final bool valid = amount.isFinite &&
        (meter.kind == DVMeterKind.counter ? amount > 0 : amount >= 0);
    if (!valid) {
      throw ArgumentError.value(
        amount,
        'amount',
        meter.kind == DVMeterKind.counter
            ? 'a counter records a positive, finite amount'
            : 'a gauge samples a non-negative, finite value',
      );
    }
    final String? key = (idempotencyKey ?? currentIdempotencyKey)?.trim();
    if (key == null || key.isEmpty) {
      return Future<DVMeterOutcome>.error(StateError(
        'Meter "${meter.name}" was recorded with no idempotency key and no '
        'DVMeters.withIdempotencyKey scope. A generated key would differ on '
        'the retry, which is the double count the key exists to prevent.',
      ));
    }
    final String tenant = const DVTenants().currentTenant;
    final DateTime now = _clock().toUtc();
    final DateTime when = (at ?? now).toUtc();
    return _serialised(_queueKey(tenant, meter.name),
        () => _record(meter, amount, key, tenant, now, when));
  }

  Future<DVMeterOutcome> _record(
    DVMeterDefinition meter,
    num amount,
    String key,
    String tenant,
    DateTime now,
    DateTime at,
  ) async {
    final Set<String> codes = <String>{};
    final DVMeterPeriod open = await _periodFor(tenant, now, codes);
    final DVMeterPeriod belongs =
        open.contains(at) ? open : await _periodFor(tenant, at, codes);

    final DVMeterPeriod placement;
    if (!at.isBefore(open.start)) {
      placement = belongs;
    } else if (now.isBefore(belongs.end.add(meter.grace ?? grace))) {
      placement = belongs;
      _emit(codes, 'DV-METER-007', meter, tenant);
    } else {
      placement = open;
      _emit(codes, 'DV-METER-008', meter, tenant);
    }

    final List<num> existing = <num>[
      for (final DVMeterRecord r in await store.recordsIn(
          tenant: tenant, meter: meter.name, period: placement))
        r.amount,
    ];
    final num before = _aggregate(meter, existing);

    if (await store.hasKey(
      tenant: tenant,
      meter: meter.name,
      key: key,
      periods: <DVMeterPeriod>[placement, belongs],
    )) {
      return _duplicate(codes, meter, tenant, before, placement);
    }

    final num? limit = await _limitFor(meter, tenant);
    final num after = _aggregate(meter, <num>[...existing, amount]);

    DVQuota? applied;
    num overage = 0;
    if (limit != null && after > limit) {
      applied = meter.atLimit!;
      _emit(codes, 'DV-METER-004', meter, tenant,
          extra: <String, Object?>{'behaviour': applied.name, 'limit': limit});
      if (applied == DVQuota.block) {
        return DVMeterOutcome(
          recorded: false,
          admitted: false,
          applied: applied,
          total: before,
          limit: limit,
          period: placement,
          codes: codes.toList(),
        );
      }
      if (applied == DVQuota.allowAndBill) {
        overage = meter.kind == DVMeterKind.counter
            ? after - (before > limit ? before : limit)
            : after - limit;
      }
    }

    final bool added = await store.add(DVMeterRecord(
      tenant: tenant,
      meter: meter.name,
      idempotencyKey: key,
      amount: amount,
      at: at,
      period: placement,
    ));
    if (!added) return _duplicate(codes, meter, tenant, before, placement);

    final List<double> crossed = <double>[
      if (limit != null && limit > 0)
        for (final double fraction in (meter.notifyAt.toList()..sort()))
          if (before < fraction * limit && after >= fraction * limit) fraction,
    ];
    if (crossed.isNotEmpty) {
      _emit(codes, 'DV-METER-003', meter, tenant,
          extra: <String, Object?>{'thresholds': crossed});
      final DVMeterThresholdHandler? handler = onThreshold;
      if (handler != null) {
        for (final double fraction in crossed) {
          await handler(DVMeterThreshold(
            meter: meter,
            tenant: tenant,
            fraction: fraction,
            total: after,
            limit: limit!,
            period: placement,
          ));
        }
      }
    }

    return DVMeterOutcome(
      recorded: true,
      admitted: true,
      applied: applied,
      total: after,
      limit: limit,
      overage: overage,
      period: placement,
      codes: codes.toList(),
      crossed: crossed,
    );
  }

  DVMeterOutcome _duplicate(Set<String> codes, DVMeterDefinition meter,
      String tenant, num total, DVMeterPeriod period) {
    _emit(codes, 'DV-METER-002', meter, tenant);
    // Admitted: the call being retried was counted, so it was admitted once
    // already, and refusing the retry would break the call it repeats.
    return DVMeterOutcome(
      recorded: false,
      admitted: true,
      total: total,
      period: period,
      codes: codes.toList(),
    );
  }

  /// Whether recording [amount] against [meter] for the current tenant would
  /// be admitted, without recording anything.
  ///
  /// For a caller that has to decide before it spends: an AI feature about
  /// to call a provider cannot use [record], which counts the amount as it
  /// checks it. Recording the worst case up front bills tokens nobody used,
  /// and recording afterwards checks a budget that has already been spent.
  ///
  /// The answer is for this instant. Nothing is reserved, so a concurrent
  /// recording can take the room between this check and the [record] that
  /// follows the call.
  Future<DVMeterOutcome> admits(DVMeterDefinition meter, num amount) {
    final bool valid = amount.isFinite &&
        (meter.kind == DVMeterKind.counter ? amount > 0 : amount >= 0);
    if (!valid) {
      throw ArgumentError.value(amount, 'amount',
          'a meter is asked about a positive, finite amount');
    }
    final String tenant = const DVTenants().currentTenant;
    final DateTime now = _clock().toUtc();
    return _serialised(_queueKey(tenant, meter.name), () async {
      final DVMeterPeriod period = await _periodFor(tenant, now, <String>{});
      final List<num> existing = <num>[
        for (final DVMeterRecord r in await store.recordsIn(
            tenant: tenant, meter: meter.name, period: period))
          r.amount,
      ];
      final num before = _aggregate(meter, existing);
      final num? limit = await _limitFor(meter, tenant);
      final num after = _aggregate(meter, <num>[...existing, amount]);
      if (limit == null || after <= limit) {
        return DVMeterOutcome(
          recorded: false,
          admitted: true,
          total: before,
          limit: limit,
          period: period,
        );
      }
      return DVMeterOutcome(
        recorded: false,
        admitted: meter.atLimit != DVQuota.block,
        applied: meter.atLimit,
        total: before,
        limit: limit,
        period: period,
      );
    });
  }

  /// Usage of [meter] by [tenant] in [period], defaulting to the open one.
  Future<num> usage(
    DVMeterDefinition meter, {
    required String tenant,
    DVMeterPeriod? period,
  }) async {
    final DVMeterPeriod within =
        period ?? await _periodFor(tenant, _clock().toUtc(), <String>{});
    return _aggregate(meter, <num>[
      for (final DVMeterRecord r in await store.recordsIn(
          tenant: tenant, meter: meter.name, period: within))
        r.amount,
    ]);
  }

  /// Checks [level] for the current tenant, as if [adding] more existed.
  ///
  /// Nothing is recorded: a level is counted when asked.
  Future<DVMeterOutcome> admitLevel(DVLevelLimit level, {num adding = 1}) async {
    final String tenant = const DVTenants().currentTenant;
    final DVMeterPeriod period =
        await _periodFor(tenant, _clock().toUtc(), <String>{});
    final num current = await level.count(tenant);
    final num? limit = await level.limit(tenant);
    if (limit == null || current + adding <= limit) {
      return DVMeterOutcome(
        recorded: false,
        admitted: true,
        total: current,
        limit: limit,
        period: period,
      );
    }
    final Set<String> codes = <String>{};
    _log.warn(
      'DV-METER-004: level "${level.name}" reached its limit; '
      '${level.atLimit.name} was applied',
      context: <String, Object?>{
        'code': 'DV-METER-004',
        'level': level.name,
        'tenant': tenant,
        'limit': limit,
      },
    );
    codes.add('DV-METER-004');
    return DVMeterOutcome(
      recorded: false,
      admitted: level.atLimit != DVQuota.block,
      applied: level.atLimit,
      total: current,
      limit: limit,
      period: period,
      codes: codes.toList(),
    );
  }

  Future<DVMeterPeriod> _periodFor(
      String tenant, DateTime at, Set<String> codes) async {
    final DVBillingPeriodResolver? resolve = periods;
    final DVMeterPeriod? billing =
        resolve == null ? null : await resolve(tenant, at);
    if (billing != null) {
      if (!billing.contains(at)) {
        throw StateError(
          'The billing period resolver answered $billing for $at, which does '
          'not contain it. Usage placed in that period would be billed in the '
          'wrong one.',
        );
      }
      return billing;
    }
    if (codes.add('DV-METER-010')) {
      _log.info(
        'DV-METER-010: tenant "$tenant" has no billing period; the '
        "deployment's calendar period was used",
        context: <String, Object?>{'code': 'DV-METER-010', 'tenant': tenant},
      );
    }
    return DVMeterPeriod.calendarMonth(at);
  }

  Future<num?> _limitFor(DVMeterDefinition meter, String tenant) async {
    final DVLimit? limit = meter.limit;
    if (limit == null) return null;
    final num? fixed = limit.value;
    if (fixed != null) return fixed;
    final DVMeterLimitResolver? resolve = limits;
    if (resolve == null) {
      throw StateError(
        'Meter "${meter.name}" takes its limit from the plan, and no limit '
        'resolver is configured. Treating that as unlimited would admit every '
        'tenant forever; pass DVMeters(limits: ...).',
      );
    }
    return resolve(tenant, meter);
  }

  num _aggregate(DVMeterDefinition meter, List<num> amounts) {
    if (amounts.isEmpty) return 0;
    if (meter.kind == DVMeterKind.counter) {
      return amounts.fold<num>(0, (num sum, num a) => sum + a);
    }
    return switch (meter.gaugeBilling) {
      DVGaugeBilling.peak =>
        amounts.reduce((num a, num b) => a > b ? a : b),
      DVGaugeBilling.average =>
        amounts.fold<num>(0, (num sum, num a) => sum + a) / amounts.length,
    };
  }

  void _emit(Set<String> codes, String code, DVMeterDefinition meter,
      String tenant,
      {Map<String, Object?> extra = const <String, Object?>{}}) {
    if (!codes.add(code)) return;
    final Map<String, Object?> context = <String, Object?>{
      'code': code,
      'meter': meter.name,
      'tenant': tenant,
      ...extra,
    };
    switch (code) {
      case 'DV-METER-002':
        _log.debug('$code: a duplicate recording of "${meter.name}" was '
            'discarded by its idempotency key', context: context);
      case 'DV-METER-007':
        _log.info('$code: a late record of "${meter.name}" was accepted into '
            'its closed period under the grace', context: context);
      default:
        _log.warn('$code: meter "${meter.name}"', context: context);
    }
  }
}
