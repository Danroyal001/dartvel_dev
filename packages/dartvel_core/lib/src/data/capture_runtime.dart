/// Change capture as the generated server runs it, from `dartvel.capture`.
///
/// `@DVModel(capture: true)` on a data model and the destinations in
/// pubspec.yaml are all an application writes. This is everything else: the
/// log over the application's database with the declared retention, a
/// consumer and a destination per declared destination, delivery and
/// backfill on the job queue with its retries, a backfill for a destination
/// or a data model it has never copied, the lag gauges and `DV-CDC-003`, the
/// log's retention, and the erasure adapter that takes an erased record out
/// of every destination at once.
///
/// It is the framework's, and not in the barrel an application imports.
library dartvel_core.data.capture_runtime;

import 'dart:async';

import '../../dartvel.dart' show DVJobEnvelope, DVJobPayload, DVQueues;
import '../admin/studio_api.dart' show DVStudioFieldSpec, DVStudioModelSpec;
import '../analytics/analytics_runtime.dart' show DVPrivacyRuntime;
import '../database/adapter.dart';
import '../database/connection.dart';
import '../observability/logging.dart' show DVLogLevel;
import '../observability/observability.dart' show DVObservability;
import '../schema/generated_schema.dart' show dvTenantColumn;
import '../secrets/secrets.dart' show DVSecrets;
import '../tenancy/tenants.dart';
import 'capture_config.dart';
import 'change_capture.dart';
import 'record_history.dart';

/// The change capture runtime of this process.
abstract final class DVCaptureRuntime {
  /// The queue a destination's jobs go on is this, then its name, so each
  /// destination retries on its own and one that is down holds up no other.
  static const String queuePrefix = 'dartvel-capture-';

  /// How often a delivery is tried before the queue gives up on it. The next
  /// tick dispatches another, so giving up loses nothing: the changes stay in
  /// the log until the destination takes them or retention passes.
  static const int maxAttempts = 10;

  /// How long the queue waits before trying a refused delivery again.
  static const Duration backoff = Duration(seconds: 30);

  /// How often the log is pruned to its retention.
  static const Duration pruneEvery = Duration(hours: 1);

  static _Runtime? _runtime;

  /// Whether this process configured change capture.
  static bool get isConfigured => _runtime != null;

  /// The log this process writes to, or null when none is configured.
  static DVCapture? get log => _runtime?.log;

  /// The queues this process's destinations' jobs are on, for a worker to
  /// work beside its own.
  static List<String> get queues => <String>[
        for (final DVCaptureConsumer c in _runtime?.consumers ?? const [])
          '$queuePrefix${c.name}',
      ];

  /// The declared destinations this process could not reach, with the code
  /// that says why.
  static Map<String, String> get skipped =>
      Map<String, String>.unmodifiable(_runtime?.skipped ?? const {});

  /// The lag each destination had at the last tick.
  static Map<String, DVCaptureLag> get lag =>
      Map<String, DVCaptureLag>.unmodifiable(_runtime?.lag ?? const {});

  /// Configures change capture from [config] over [database], the
  /// application's own.
  ///
  /// [models] are the data models' specs as the generator wrote them; the
  /// captured ones are recorded to the log, and a destination takes those it
  /// names. [secret] reads a destination's connection by name -- `DV.Secrets`
  /// when null -- and [open] opens it, by default as a database connection.
  /// A destination whose connection is not set is skipped, and said with
  /// `DV-CDC-009`: its changes wait in the log.
  ///
  /// Throws [DVCaptureConfigError] (`DV-CDC-008`) for a destination naming a
  /// data model that is not captured.
  static void configure({
    required DVCaptureConfig config,
    required DVDatabaseAdapter database,
    required List<DVStudioModelSpec> models,
    String? Function(String name)? secret,
    DVDatabaseAdapter Function(String connection)? open,
    DateTime Function()? clock,
  }) {
    final Map<String, DVStudioModelSpec> captured = <String, DVStudioModelSpec>{
      for (final DVStudioModelSpec spec in models)
        if (spec.capture) spec.id: spec,
    };
    config.checkModels(captured.keys.toSet());

    final DVCapture log = DVCapture(
      database: database,
      retention: config.retention,
      clock: clock,
    );
    final Map<String, DVRecordTable> tables = <String, DVRecordTable>{
      for (final MapEntry<String, DVStudioModelSpec> e in captured.entries)
        e.key: _table(e.value, log, database),
    };
    for (final DVRecordTable table in tables.values) {
      log.track(table);
    }

    final String? Function(String) read = secret ?? const DVSecrets().maybeGet;
    final DVDatabaseAdapter Function(String) opening =
        open ?? (String url) => DVDatabaseConnection.parse(url).open();
    final Map<String, String> skipped = <String, String>{};
    final List<DVCaptureConsumer> consumers = <DVCaptureConsumer>[];
    final Map<String, List<DVRecordTable>> takes =
        <String, List<DVRecordTable>>{};
    for (final DVCaptureDestination destination in config.destinations) {
      final String? connection = read(destination.connection)?.trim();
      DVDatabaseAdapter? store;
      String? why;
      if (connection == null || connection.isEmpty) {
        why = '${destination.connection} is not set';
      } else {
        try {
          store = opening(connection);
        } on FormatException catch (error) {
          // Not the value: it carries credentials.
          why = '${destination.connection} cannot be read: ${error.message}';
        }
      }
      if (store == null) {
        skipped[destination.name] = 'DV-CDC-009';
        DVObservability.log(
          'Change capture destination ${destination.name} is not delivered '
          'to: $why. Its changes wait in the log for '
          '${config.retention.inHours} hours; set it before then, or the '
          'destination is backfilled when it comes back.',
          level: DVLogLevel.warn,
          code: 'DV-CDC-009',
        );
        continue;
      }
      final List<DVRecordTable> chosen = <DVRecordTable>[
        for (final MapEntry<String, DVRecordTable> e in tables.entries)
          if (destination.models == null ||
              destination.models!.contains(e.key))
            e.value,
      ];
      takes[destination.name] = chosen;
      consumers.add(log.consumer(
        destination.name,
        sink: DVWarehouseSink(database: store, name: destination.name),
        models: <String>{for (final DVRecordTable t in chosen) t.table},
        lagThreshold: destination.lagThreshold,
      ));
    }

    DVCapture.configure(log);
    // An erasure takes the erased records out of every destination now,
    // rather than at the next delivery, and is incomplete when one of them
    // cannot be reached.
    DVPrivacyRuntime.installAdapters(<DVCapturePrivacyAdapter>[
      DVCapturePrivacyAdapter(
        capture: log,
        sinks: <DVCaptureSink>[
          for (final DVCaptureConsumer c in consumers) c.sink,
        ],
      ),
    ]);
    _runtime = _Runtime(
      log: log,
      consumers: consumers,
      takes: takes,
      skipped: skipped,
    );
  }

  /// Makes the log's collections and registers delivery and backfill on
  /// [queues], in every process that configured capture: the one that
  /// dispatches and the worker that runs them both need the codecs.
  ///
  /// Returns false, doing nothing, where capture is not configured.
  static Future<bool> start({DVQueues queues = const DVQueues()}) async {
    final _Runtime? runtime = _runtime;
    if (runtime == null) return false;
    await runtime.log.ensureSchema();
    runtime.log.registerJobs(queues);
    runtime.queues = queues;
    // A change published here is sent on now rather than at the next tick.
    runtime.log.onPublished = (int _) => unawaited(_dispatchDeliveries());
    return true;
  }

  /// One pass of everything capture does on a schedule: changes a crash
  /// left staged are published, a destination or a data model that has
  /// never been copied is backfilled, pending changes are dispatched for
  /// delivery, lag is measured, and the log is pruned to its retention.
  ///
  /// With [work], this process also runs the jobs it dispatched: it is the
  /// whole deployment, with no worker to run them.
  static Future<void> tick({
    DVQueues queues = const DVQueues(),
    bool work = false,
  }) async {
    final _Runtime? runtime = _runtime;
    if (runtime == null || runtime.ticking) return;
    runtime.ticking = true;
    runtime.queues = queues;
    runtime.works = work;
    try {
      await runtime.log.publishStranded();
      for (final DVCaptureConsumer consumer in runtime.consumers) {
        await _backfillWhatIsMissing(runtime, consumer, queues);
      }
      await _dispatchDeliveries();
      if (work) await _work(runtime, queues);
      for (final DVCaptureConsumer consumer in runtime.consumers) {
        if (await consumer.position() == null) continue;
        runtime.lag[consumer.name] = await consumer.lag();
      }
      final DateTime now = DateTime.now();
      final DateTime? pruned = runtime.prunedAt;
      if (pruned == null || now.difference(pruned) >= pruneEvery) {
        runtime.prunedAt = now;
        await runtime.log.prune();
      }
    } on Object catch (error) {
      DVObservability.log(
        'Change capture could not complete its scheduled pass: $error',
        level: DVLogLevel.warn,
      );
    } finally {
      runtime.ticking = false;
    }
  }

  /// [tick] every [every]. The generated server starts it in the process
  /// that ticks the application's schedules; with [work], that process is
  /// the whole deployment and runs the jobs too.
  static Timer? startSchedules({
    Duration every = const Duration(seconds: 20),
    DVQueues queues = const DVQueues(),
    bool work = false,
  }) {
    final _Runtime? runtime = _runtime;
    if (runtime == null) return null;
    runtime.works = work;
    unawaited(tick(queues: queues, work: work));
    return Timer.periodic(
      every,
      (Timer _) => unawaited(tick(queues: queues, work: work)),
    );
  }

  /// Forgets the configuration, for tests.
  static void resetForTest() {
    final _Runtime? runtime = _runtime;
    if (runtime != null) runtime.log.onPublished = null;
    _runtime = null;
    DVCapture.unconfigure();
  }

  static DVRecordTable _table(
    DVStudioModelSpec spec,
    DVCapture log,
    DVDatabaseAdapter database,
  ) =>
      DVRecordTable(
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
        versioned: spec.versioned,
        softDelete: spec.softDelete,
        capture: log,
        scope: spec.tenantScoped
            ? DVRecordScope(dvTenantColumn, const DVTenants().currentTenant)
            : null,
        database: spec.resolvedDatabase(database),
      );

  static Future<List<DVJobEnvelope<DVJobPayload>>> _pending(
    DVQueues queues,
    String consumer,
    Type type,
  ) async =>
      <DVJobEnvelope<DVJobPayload>>[
        for (final DVJobEnvelope<DVJobPayload> job
            in await queues.pending('$queuePrefix$consumer'))
          if (job.payloadType == type) job,
      ];

  static Future<void> _backfillWhatIsMissing(
    _Runtime runtime,
    DVCaptureConsumer consumer,
    DVQueues queues,
  ) async {
    if ((await _pending(queues, consumer.name, DVCaptureBackfillJob))
        .isNotEmpty) {
      return;
    }
    // Down for longer than the log keeps changes: what it missed is gone
    // from the log, so every table it takes is copied again.
    final bool behind = await consumer.behindRetention();
    for (final DVRecordTable table
        in runtime.takes[consumer.name] ?? const <DVRecordTable>[]) {
      final DVCaptureBackfillProgress? progress =
          await consumer.backfillProgress(table.table);
      // Never copied -- a destination or a data model the destination has
      // not had before -- or a copy that stopped part of the way.
      if (!behind && progress != null && progress.done) continue;
      await runtime.log.dispatchBackfill(
        DVCaptureBackfillJob(
          consumer: consumer.name,
          model: table.table,
          queue: '$queuePrefix${consumer.name}',
        ),
        queues: queues,
      );
    }
  }

  static Future<void> _dispatchDeliveries() async {
    final _Runtime? runtime = _runtime;
    if (runtime == null) return;
    final DVQueues queues = runtime.queues;
    try {
      final int head = await runtime.log.head();
      for (final DVCaptureConsumer consumer in runtime.consumers) {
        final int? at = await consumer.position();
        // Nothing to send, or a destination whose first copy has not begun:
        // delivering from the start of the log would only redo the copy.
        if (at == null || at >= head) continue;
        if ((await _pending(queues, consumer.name, DVCaptureDeliveryJob))
            .isNotEmpty) {
          continue;
        }
        await queues.dispatch<DVCaptureDeliveryJob>(
          DVCaptureDeliveryJob(consumer.name),
          queue: '$queuePrefix${consumer.name}',
          maxAttempts: maxAttempts,
          backoff: backoff,
        );
      }
      if (runtime.works && !runtime.ticking) {
        await _work(runtime, queues);
      }
    } on Object catch (error) {
      DVObservability.log(
        'Captured changes could not be dispatched for delivery; the next '
        'scheduled pass does it: $error',
        level: DVLogLevel.warn,
      );
    }
  }

  /// Runs what is on each destination's queue, a bounded number of jobs so
  /// one pass cannot hold the process. A refused delivery goes back on the
  /// queue with its backoff, which is the retry.
  ///
  /// A pass takes what is queued when it looks, so a refused delivery that
  /// went straight back on an in-process queue is not tried again in the
  /// same pass; a backfill's next chunk is taken while every job completes,
  /// for up to [workFor].
  static Future<void> _work(_Runtime runtime, DVQueues queues) async {
    final Stopwatch clock = Stopwatch()..start();
    for (final DVCaptureConsumer consumer in runtime.consumers) {
      final String queue = '$queuePrefix${consumer.name}';
      while (clock.elapsed < workFor) {
        final int queued = (await queues.pending(queue)).length;
        if (queued == 0) break;
        final int done = await queues.work(queue: queue, maxJobs: queued);
        if (done < queued) break;
      }
    }
  }

  /// How long one pass may spend running jobs in a process with no worker.
  static const Duration workFor = Duration(seconds: 5);
}

final class _Runtime {
  _Runtime({
    required this.log,
    required this.consumers,
    required this.takes,
    required this.skipped,
  });

  final DVCapture log;
  final List<DVCaptureConsumer> consumers;

  /// The captured tables each destination takes.
  final Map<String, List<DVRecordTable>> takes;
  final Map<String, String> skipped;
  final Map<String, DVCaptureLag> lag = <String, DVCaptureLag>{};

  DVQueues queues = const DVQueues();
  bool works = false;
  bool ticking = false;
  DateTime? prunedAt;
}
