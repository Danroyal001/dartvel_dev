/// The stores the processes of one deployment share, from its configuration.
///
/// A generated backend runs as web, worker and cron processes, and they share
/// nothing unless something gives them a store in common. Without one a web
/// process dispatches to its own process-local queue, which the worker never
/// sees, and each cron process fires every schedule.
///
/// The store is the database `DATABASE_URL` names -- the secret
/// `dartvel infra` already declares and delivers to every unit -- read the
/// way `DV.Secrets` reads anything: the process environment, then the
/// supervisor's credentials, then `.env`. The queue goes on it through
/// `DVDatabaseQueueAdapter`, and schedule occurrences are claimed in it
/// through `DVDatabaseScheduleLease`.
library;

import '../../dartvel.dart' show DVDatabaseQueueAdapter, DVQueues;
import '../database/adapter.dart' show DVDatabase, DVDatabaseAdapter;
import '../database/connection.dart' show DVDatabaseConnection;
import '../scheduling/scheduler.dart'
    show DVDatabaseScheduleLease, DVScheduleLease;
import '../secrets/secrets.dart' show DVSecrets;
import 'process_configuration.dart';

/// What this process shares with the other processes of its deployment.
final class DVProcessStores {
  DVProcessStores._({this.connection, this.database});

  /// The connection `DATABASE_URL` resolved to, or null without one.
  final DVDatabaseConnection? connection;

  /// The shared database, or null when this process shares none.
  final DVDatabaseAdapter? database;

  /// Installs the shared stores into this process and says what they are.
  ///
  /// With `DATABASE_URL` set: `DV.Database` is configured from it unless
  /// something already configured it -- a preview does, before anything else
  /// runs, and that adapter is reused rather than a second connection opened
  /// beside it -- and `DVQueues` is put on that database unless an adapter
  /// was already configured, because an application that chose its queue
  /// chose it. Without `DATABASE_URL` nothing is installed.
  ///
  /// [read] looks a setting up; `DV.Secrets` by default. Throws
  /// [DVProcessConfigurationError] for a `DATABASE_URL` it cannot read,
  /// without repeating the URL, which carries a password.
  static DVProcessStores install({String? Function(String key)? read}) {
    final String? Function(String) lookup = read ?? const DVSecrets().maybeGet;
    final Map<String, String> environment = <String, String>{
      for (final String key in const <String>[
        'DATABASE_URL',
        'DARTVEL_DATABASE',
      ])
        if (lookup(key) case final String value) key: value,
    };
    final DVDatabaseConnection? connection;
    try {
      connection = DVDatabaseConnection.fromEnvironment(environment);
    } on FormatException catch (error) {
      throw DVProcessConfigurationError(
        'DATABASE_URL cannot be read: ${error.message}. It is the store this '
        "deployment's processes share, and the backend does not start on a "
        'process-local one instead.',
      );
    }
    if (connection == null) return DVProcessStores._();

    const DVDatabase facade = DVDatabase();
    DVDatabaseAdapter? database = facade.configuredAdapter;
    if (database == null) {
      database = connection.open();
      facade.configure(database);
    }
    const DVQueues queues = DVQueues();
    if (!queues.adapterConfigured) {
      queues.useAdapter(DVDatabaseQueueAdapter(database));
    }
    return DVProcessStores._(connection: connection, database: database);
  }

  /// The lease [process] claims each schedule occurrence through, or null
  /// when it claims none.
  ///
  /// A process that ticks no schedule claims nothing, and neither does one
  /// told `DARTVEL_SCHEDULE_LEASE=none`. A ticking process on a shared
  /// database claims in it -- a process given no role too, since a whole
  /// deployment scaled to two instances is two tickers. A process given no
  /// role and no shared database runs unguarded: it is the deployment, with
  /// no second process to race.
  ///
  /// A declared cron process with no shared store refuses to start, throwing
  /// [DVProcessConfigurationError]. Nothing in the process can tell whether
  /// it is the only cron process: `dartvel infra` writes one cron unit per
  /// host, and a container platform scales whatever it is told to. A second
  /// one does not fail -- it fires every schedule again, which is the invoice
  /// run happening twice -- so a warning in a log nobody reads is not enough.
  /// Saying it is the only one is one variable.
  DVScheduleLease? scheduleLeaseFor(DVProcessConfiguration process) {
    if (!process.ticksSchedules || process.scheduleLeaseWaived) return null;
    final DVDatabaseAdapter? database = this.database;
    if (database != null) return DVDatabaseScheduleLease(database);
    if (process.role == DVProcessRole.cron) {
      throw const DVProcessConfigurationError(
        'DARTVEL_ROLE=cron and nothing is shared with the other processes: '
        'DATABASE_URL is not set, so a schedule occurrence cannot be claimed '
        'anywhere another cron process would see it, and two cron processes '
        'would each fire every schedule. Set DATABASE_URL; or, if this is the '
        'only process ticking the schedules, say so with '
        'DARTVEL_SCHEDULE_LEASE=none.',
      );
    }
    return null;
  }
}
