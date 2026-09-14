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
import '../preview/preview_server.dart' show DVPreviewServer;
import '../scheduling/scheduler.dart'
    show DVDatabaseScheduleLease, DVScheduleLease;
import '../secrets/secrets.dart' show DVSecrets;
import 'process_configuration.dart';

/// What this process shares with the other processes of its deployment.
final class DVProcessStores {
  DVProcessStores._({this.connection, this.database});

  /// The connection the shared store is on, or null without one.
  final DVDatabaseConnection? connection;

  /// The shared database, or null when this process shares none.
  final DVDatabaseAdapter? database;

  /// Installs the shared stores into this process and says what they are.
  ///
  /// Outside a preview the store is `DATABASE_URL` alone, on a connection of
  /// its own. `DV.Database` is left untouched -- production's database is the
  /// application's to configure -- and `DARTVEL_DATABASE` is ignored: it is a
  /// preview's variable, and a production deploy copied from a preview's
  /// settings would otherwise put its jobs on the preview's database.
  ///
  /// In a preview, `DVPreviewServer.start` has already chosen the preview's
  /// own database and configured `DV.Database` with it; that adapter is the
  /// store, rather than a second connection opened beside it.
  ///
  /// `DVQueues` is put on the store unless an adapter was already configured,
  /// because an application that chose its queue chose it. Without a store
  /// nothing is installed.
  ///
  /// [read] looks a setting up; `DV.Secrets` by default. Throws
  /// [DVProcessConfigurationError] for a `DATABASE_URL` it cannot read,
  /// without repeating the URL, which carries a password.
  static DVProcessStores install({String? Function(String key)? read}) {
    final DVDatabaseConnection? connection;
    final DVDatabaseAdapter? database;
    final DVPreviewServer? preview = DVPreviewServer.current;
    if (preview != null) {
      connection = preview.connection;
      database =
          connection == null ? null : const DVDatabase().configuredAdapter;
    } else {
      final String? Function(String) lookup =
          read ?? const DVSecrets().maybeGet;
      final String? url = lookup('DATABASE_URL')?.trim();
      if (url == null || url.isEmpty) return DVProcessStores._();
      try {
        connection = DVDatabaseConnection.parse(url);
      } on FormatException catch (error) {
        throw DVProcessConfigurationError(
          'DATABASE_URL cannot be read: ${error.message}. It is the store '
          "this deployment's processes share, and the backend does not start "
          'on a process-local one instead.',
        );
      }
      database = connection.open();
    }
    if (database == null) return DVProcessStores._();

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
