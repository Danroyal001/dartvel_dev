/// Reporting metered usage to the billing provider, and reconciling the two.
///
/// The provider's invoice is the customer-facing figure. Dartvel's records are
/// the evidence behind it, and this is where one becomes the other: once per
/// closed period, under a key that makes a repeated report the same report,
/// with every failure kept until it goes through.
library dartvel_core.metering.reporting;

import 'dart:async';

import '../../dartvel.dart' show DVBillingProvider, DVUsageMeter;
import '../billing/subscription_lifecycle.dart';
import '../database/adapter.dart';
import '../database/framework_tables.dart';
import '../observability/observability.dart';
import 'meters.dart';

/// What became of one period's report.
enum DVMeterReportStatus {
  /// The provider has it.
  reported,

  /// It could not be sent and is kept for [DVMeterReporter.retryPending].
  queued,

  /// The meter has no price on the tenant's plan: counted, not billed.
  notBilled,

  /// Nothing was used in the period, so there was nothing to send.
  nothingToReport,
}

/// One tenant's usage of one meter over one period, as sent or to be sent.
class DVMeterReport {
  const DVMeterReport({
    required this.tenant,
    required this.meter,
    required this.period,
    required this.quantity,
    required this.idempotencyKey,
    required this.status,
    this.codes = const <String>[],
    this.error,
  });

  final String tenant;
  final String meter;
  final DVMeterPeriod period;

  /// What is billed: a whole number, rounded up from the meter's figure.
  final int quantity;

  /// The same for every attempt at this period's report, so a provider that
  /// received a report whose response was lost counts the retry once.
  final String idempotencyKey;

  final DVMeterReportStatus status;
  final List<String> codes;

  /// Why the last attempt did not go through, for a queued report.
  final String? error;

  DVMeterReport _as(
    DVMeterReportStatus status, {
    List<String> codes = const <String>[],
    String? error,
  }) =>
      DVMeterReport(
        tenant: tenant,
        meter: meter,
        period: period,
        quantity: quantity,
        idempotencyKey: idempotencyKey,
        status: status,
        codes: codes,
        error: error,
      );
}

/// A tenant and meter whose figures disagree for a period.
class DVMeterDifference {
  const DVMeterDifference({
    required this.tenant,
    required this.meter,
    required this.period,
    required this.ours,
    required this.theirs,
  });

  final String tenant;
  final String meter;
  final DVMeterPeriod period;

  /// Dartvel's figure, from its own records.
  final num ours;

  /// The provider's figure.
  final num theirs;

  num get difference => ours - theirs;
}

/// Where reports that could not be sent wait.
abstract class DVMeterReportQueue {
  /// Keeps [report], replacing any earlier entry under the same key.
  Future<void> put(DVMeterReport report);

  Future<void> remove(String idempotencyKey);

  /// Every waiting report, oldest first.
  Future<List<DVMeterReport>> pending();
}

/// Waiting reports held in this process.
///
/// Lost with the process, so a deployment that cannot afford that — which is
/// any deployment that bills — uses [DVDatabaseMeterReportQueue].
class DVMemoryMeterReportQueue implements DVMeterReportQueue {
  final Map<String, DVMeterReport> _pending = <String, DVMeterReport>{};

  @override
  Future<void> put(DVMeterReport report) async {
    _pending.remove(report.idempotencyKey);
    _pending[report.idempotencyKey] = report;
  }

  @override
  Future<void> remove(String idempotencyKey) async =>
      _pending.remove(idempotencyKey);

  @override
  Future<List<DVMeterReport>> pending() async =>
      List<DVMeterReport>.of(_pending.values);
}

/// Waiting reports in the application's database, so a restart or another
/// instance finds them.
class DVDatabaseMeterReportQueue implements DVMeterReportQueue {
  DVDatabaseMeterReportQueue({this.table = 'dv_meter_reports'});

  final String table;
  Future<void>? _ready;

  static const DVDatabase _db = DVDatabase();

  Future<void> _ensureTable() => _ready ??= dvEnsureFrameworkTable(
        _db.adapter,
        'CREATE TABLE IF NOT EXISTS $table (idempotency_key TEXT NOT NULL, '
        'dv_tenant TEXT NOT NULL, meter TEXT NOT NULL, '
        'period_start_us BIGINT NOT NULL, period_end_us BIGINT NOT NULL, '
        'quantity BIGINT NOT NULL, last_error TEXT, '
        'queued_at_us BIGINT NOT NULL)',
      );

  @override
  Future<void> put(DVMeterReport report) async {
    await _ensureTable();
    await _db.execute(
      'DELETE FROM $table WHERE idempotency_key = ?',
      <Object?>[report.idempotencyKey],
    );
    await _db.execute(
      'INSERT INTO $table (idempotency_key, dv_tenant, meter, period_start_us, '
      'period_end_us, quantity, last_error, queued_at_us) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        report.idempotencyKey,
        report.tenant,
        report.meter,
        report.period.start.microsecondsSinceEpoch,
        report.period.end.microsecondsSinceEpoch,
        report.quantity,
        report.error,
        DateTime.now().toUtc().microsecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> remove(String idempotencyKey) async {
    await _ensureTable();
    await _db.execute(
      'DELETE FROM $table WHERE idempotency_key = ?',
      <Object?>[idempotencyKey],
    );
  }

  @override
  Future<List<DVMeterReport>> pending() async {
    await _ensureTable();
    final List<Map<String, Object?>> rows = await _db.query(
      'SELECT idempotency_key, dv_tenant, meter, period_start_us, '
      'period_end_us, quantity, last_error FROM $table '
      'ORDER BY queued_at_us ASC',
    );
    return <DVMeterReport>[
      for (final Map<String, Object?> row in rows)
        DVMeterReport(
          tenant: '${row['dv_tenant']}',
          meter: '${row['meter']}',
          period: DVMeterPeriod(
            DateTime.fromMicrosecondsSinceEpoch(
                (row['period_start_us']! as num).toInt(),
                isUtc: true),
            DateTime.fromMicrosecondsSinceEpoch(
                (row['period_end_us']! as num).toInt(),
                isUtc: true),
          ),
          quantity: (row['quantity']! as num).toInt(),
          idempotencyKey: '${row['idempotency_key']}',
          status: DVMeterReportStatus.queued,
          error: row['last_error'] as String?,
        ),
    ];
  }
}

/// The billing customer a tenant is invoiced as, or null when it has none.
typedef DVBillingCustomerResolver = FutureOr<Object?> Function(String tenant);

/// Whether [meter] has a price on [tenant]'s plan.
typedef DVMeterPriceResolver = FutureOr<bool> Function(
    String tenant, DVMeterDefinition meter);

/// The provider's figure for [tenant]'s use of [meter] in the period being
/// reconciled.
typedef DVProviderFigure = FutureOr<num> Function(
    String tenant, DVMeterDefinition meter);

/// Each tenant's billing period, read from its subscription at the provider.
///
/// Pass as `DVMeters(periods: DVProviderBillingPeriods(...).call)`.
///
/// A recording must not cost a provider call, so each tenant's periods are
/// remembered: the current one until it ends, and the few before it so a
/// late record finds the period it belongs to. A tenant with no subscription,
/// a provider that names no period start, or a provider that cannot be
/// reached answers null, which falls back to the calendar month with
/// DV-METER-010; that answer is remembered for [retryAfter], so an outage is
/// not a provider call per request either.
class DVProviderBillingPeriods {
  DVProviderBillingPeriods(
    this.provider, {
    required this.customerFor,
    this.retryAfter = const Duration(minutes: 5),
    this.remembered = 3,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DVSubscriptionLifecycle provider;
  final DVBillingCustomerResolver customerFor;

  /// How long a tenant with no readable period is not asked about again.
  final Duration retryAfter;

  /// How many periods per tenant are kept, newest first.
  final int remembered;

  final DateTime Function() _clock;
  final Map<String, List<DVMeterPeriod>> _periods =
      <String, List<DVMeterPeriod>>{};
  final Map<String, DateTime> _unknownUntil = <String, DateTime>{};

  /// The billing period of [tenant] containing [at], or null.
  Future<DVMeterPeriod?> call(String tenant, DateTime at) async {
    final List<DVMeterPeriod> known = _periods[tenant] ?? <DVMeterPeriod>[];
    for (final DVMeterPeriod period in known) {
      if (period.contains(at)) return period;
    }
    // Only the provider's current period can be read. An instant before
    // every remembered period is one this process never saw.
    if (known.isNotEmpty && at.isBefore(known.first.end)) return null;
    final DateTime now = _clock().toUtc();
    final DateTime? wait = _unknownUntil[tenant];
    if (wait != null && now.isBefore(wait)) return null;

    final DVMeterPeriod? current = await _read(tenant);
    if (current == null) {
      _unknownUntil[tenant] = now.add(retryAfter);
      return null;
    }
    _unknownUntil.remove(tenant);
    if (!known.contains(current)) {
      _periods[tenant] = <DVMeterPeriod>[current, ...known]
          .take(remembered)
          .toList();
    }
    if (current.contains(at)) return current;
    // A period that has already ended is a provider that has not rolled the
    // subscription over yet: remembered as unknown, like no period at all.
    if (!at.isBefore(current.end)) _unknownUntil[tenant] = now.add(retryAfter);
    return null;
  }

  Future<DVMeterPeriod?> _read(String tenant) async {
    try {
      final Object? customer = await customerFor(tenant);
      if (customer == null) return null;
      final DVSubscriptionStatus status =
          await provider.subscriptionStatus(customer: customer);
      final DateTime? start = status.currentPeriodStart;
      final DateTime? end = status.currentPeriodEnd;
      if (start == null || end == null || !start.isBefore(end)) return null;
      return DVMeterPeriod(start.toUtc(), end.toUtc());
    } on Object catch (error) {
      DVObservability.logger.warn(
        'The billing period for tenant "$tenant" could not be read from the '
        'provider: $error',
        context: <String, Object?>{'tenant': tenant},
      );
      return null;
    }
  }
}

/// Sends closed periods' usage to the billing provider.
class DVMeterReporter {
  DVMeterReporter({
    required this.meters,
    required this.provider,
    required this.customerFor,
    required this.isPriced,
    DVMeterReportQueue? queue,
  }) : queue = queue ?? DVMemoryMeterReportQueue();

  final DVMeters meters;
  final DVBillingProvider provider;
  final DVBillingCustomerResolver customerFor;
  final DVMeterPriceResolver isPriced;
  final DVMeterReportQueue queue;

  /// Reports [tenant]'s use of [meter] in [period].
  ///
  /// Refused while the period can still receive usage — before it ends, or
  /// within the grace after it that accepts late records — because a report
  /// sent then under-bills by whatever arrives late, every period, silently.
  Future<DVMeterReport> report(
    DVMeterDefinition meter, {
    required String tenant,
    required DVMeterPeriod period,
  }) async {
    final DateTime closesAt = period.end.add(meter.grace ?? meters.grace);
    if (meters.now.isBefore(closesAt)) {
      throw StateError(
        '${meter.name} for $tenant cannot be reported for $period until '
        '${closesAt.toIso8601String()}: late usage can still be accepted into '
        'it, and a report sent now would leave that out.',
      );
    }

    final num usage =
        await meters.usage(meter, tenant: tenant, period: period);
    final DVMeterReport draft = DVMeterReport(
      tenant: tenant,
      meter: meter.name,
      period: period,
      quantity: usage.ceil(),
      idempotencyKey:
          'dv-meter:$tenant:${meter.name}:${period.start.toIso8601String()}',
      status: DVMeterReportStatus.queued,
    );

    if (draft.quantity <= 0) {
      return draft._as(DVMeterReportStatus.nothingToReport);
    }
    if (!await isPriced(tenant, meter)) {
      DVObservability.logger.warn(
        'DV-METER-009: ${meter.name} has no price on the plan for $tenant; '
        'usage is counted and not billed',
        context: <String, Object?>{
          'code': 'DV-METER-009',
          'meter': meter.name,
          'tenant': tenant,
          'quantity': draft.quantity,
        },
      );
      return draft._as(DVMeterReportStatus.notBilled,
          codes: const <String>['DV-METER-009']);
    }
    return _send(draft);
  }

  /// Sends every queued report again. Returns the ones that went through;
  /// the rest stay queued.
  Future<List<DVMeterReport>> retryPending() async {
    final List<DVMeterReport> sent = <DVMeterReport>[];
    for (final DVMeterReport waiting in await queue.pending()) {
      final DVMeterReport result = await _send(waiting);
      if (result.status == DVMeterReportStatus.reported) sent.add(result);
    }
    return sent;
  }

  /// Where Dartvel's figures and the provider's disagree, per tenant per
  /// meter. Nothing is corrected: a difference between two systems of record
  /// is something a person decides about.
  Future<List<DVMeterDifference>> reconcile({
    required DVMeterPeriod period,
    required List<String> tenants,
    required List<DVMeterDefinition> meters,
    required DVProviderFigure providerFigure,
  }) async {
    final List<DVMeterDifference> differences = <DVMeterDifference>[];
    for (final String tenant in tenants) {
      for (final DVMeterDefinition meter in meters) {
        final num ours =
            await this.meters.usage(meter, tenant: tenant, period: period);
        final num theirs = await providerFigure(tenant, meter);
        if (ours != theirs) {
          differences.add(DVMeterDifference(
            tenant: tenant,
            meter: meter.name,
            period: period,
            ours: ours,
            theirs: theirs,
          ));
        }
      }
    }
    return differences;
  }

  Future<DVMeterReport> _send(DVMeterReport report) async {
    final Object? customer = await customerFor(report.tenant);
    if (customer == null) {
      return _keep(report, 'no billing customer for tenant ${report.tenant}');
    }
    try {
      await provider.recordUsage(
        customer: customer,
        meter: DVUsageMeter(report.meter),
        quantity: report.quantity,
        idempotencyKey: report.idempotencyKey,
        // Inside the period, so a provider that places usage by timestamp
        // bills it in the period it was counted in.
        at: report.period.start,
      );
    } on Object catch (error) {
      return _keep(report, '$error');
    }
    await queue.remove(report.idempotencyKey);
    return report._as(DVMeterReportStatus.reported);
  }

  Future<DVMeterReport> _keep(DVMeterReport report, String reason) async {
    final DVMeterReport queued = report._as(DVMeterReportStatus.queued,
        codes: const <String>['DV-METER-006'], error: reason);
    await queue.put(queued);
    DVObservability.logger.error(
      'DV-METER-006: usage could not be reported to the billing provider; it '
      'is queued, not dropped',
      context: <String, Object?>{
        'code': 'DV-METER-006',
        'meter': report.meter,
        'tenant': report.tenant,
        'quantity': report.quantity,
        'reason': reason,
      },
    );
    return queued;
  }
}
