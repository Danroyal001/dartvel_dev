/// A preview's server, started from the environment its deployment wrote.
///
/// The preview runtime -- capture, access, schedules -- is only a preview if
/// something installs it, and a process that starts without it starts as
/// production: it mails real people, answers crawlers, reserves production's
/// queues and queries whatever database it was handed. So the server's
/// startup calls [DVPreviewServer.start] before anything else, and a preview
/// that cannot establish what it is refuses to start at all.
///
/// In every other environment [DVPreviewServer.start] returns null having
/// touched nothing.
library;

import 'dart:async';

import '../../dartvel.dart' show DVDatabase, DVDatabaseConnection, DVQueues;
import '../http/wintercg.dart';
import 'preview_access.dart';
import 'preview_database_guard.dart';
import 'preview_outbound.dart';
import 'preview_secrets.dart';

/// Why a process deployed as a preview did not start.
final class DVPreviewStartupException implements Exception {
  const DVPreviewStartupException(this.message);

  final String message;

  @override
  String toString() => 'DVPreviewStartupException: $message';
}

/// The preview this process is serving.
final class DVPreviewServer {
  DVPreviewServer._({
    required this.runtime,
    required this.access,
    required this.queueNamespace,
    required this.database,
    required this.connection,
  });

  final DVPreviewRuntime runtime;

  /// The gate every response passes through.
  final DVPreviewAccess access;

  /// What every queue of this process is under.
  final String queueNamespace;

  /// The preview's database, as its identity names it.
  final String database;

  /// The connection `DATABASE_URL` resolved to, aimed at [database]; null
  /// when the deployment supplied no URL.
  final DVDatabaseConnection? connection;

  static DVPreviewServer? _current;

  /// The preview started in this process, or null.
  static DVPreviewServer? get current => _current;

  /// Installs the preview [environment] describes, or does nothing when it
  /// describes none.
  ///
  /// In order: capture is switched on first, before any check that can
  /// refuse, so a caller that catches the refusal still sends nothing. Then
  /// the queue namespace must be this preview's own, its database must carry
  /// this preview's name and must not be production's, `DATABASE_URL` must be
  /// readable, and a members preview needs [membership]. Only once every
  /// check has passed are the queues namespaced and `DV.Database` pointed at
  /// the preview's database.
  ///
  /// Starting again returns the preview already started.
  static DVPreviewServer? start(
    Map<String, String> environment, {
    DVPreviewMembership? membership,
    String signInPath = '/sign-in',
    Set<String> openPaths = const <String>{},
    void Function(DVPreviewFinding finding)? onFinding,
  }) {
    if (environment['DARTVEL_ENVIRONMENT'] != dvPreviewEnvironment) return null;
    final DVPreviewServer? running = _current;
    if (running != null) return running;

    final DVPreviewRuntime runtime;
    try {
      runtime = DVPreviewRuntime.fromEnvironment(environment)!;
    } on FormatException catch (error) {
      throw DVPreviewStartupException(
        'DARTVEL_ENVIRONMENT is preview and the preview\'s settings cannot be '
        'read: ${error.message}. The process is not started, rather than '
        'started as production.',
      );
    }

    DVPreviewOutbound.activate(runtime, onFinding: onFinding);

    final String ownNamespace = 'preview-${runtime.name}';
    final String? namespace = environment['DARTVEL_QUEUE_NAMESPACE'];
    if (namespace != ownNamespace) {
      throw DVPreviewStartupException(
        'DARTVEL_QUEUE_NAMESPACE is '
        '${namespace == null ? 'not set' : '"$namespace"'}, and preview '
        '${runtime.name}\'s queues are "$ownNamespace". On any other '
        'namespace it would consume jobs that are not its own.',
      );
    }

    final String? database = environment['DARTVEL_DATABASE'];
    if (database == null || database.isEmpty) {
      throw DVPreviewStartupException(
        'DARTVEL_DATABASE names no database for preview ${runtime.name}, so '
        'nothing says which database is its own.',
      );
    }
    final String digest = runtime.name.substring(
      runtime.name.lastIndexOf('-') + 1,
    );
    if (!database.endsWith('_$digest')) {
      throw DVPreviewStartupException(
        'DARTVEL_DATABASE is "$database", which is not preview '
        '${runtime.name}\'s database: every database a preview owns carries '
        'its name\'s digest, $digest.',
      );
    }
    final String? production = environment['DARTVEL_PRODUCTION_DATABASE'];
    if (production != null && database == production) {
      throw DVPreviewStartupException(
        'DARTVEL_DATABASE is "$database", which is production\'s database. A '
        'preview migrated, seeded or sanitized against it would change real '
        'people\'s rows.',
      );
    }

    final DVDatabaseConnection? connection;
    try {
      connection = DVDatabaseConnection.fromEnvironment(environment);
    } on FormatException catch (error) {
      throw DVPreviewStartupException(
        'DATABASE_URL cannot be read: ${error.message}.',
      );
    }

    final DVPreviewAccess access;
    try {
      access = DVPreviewAccess(
        runtime,
        membership: membership,
        signInPath: signInPath,
        openPaths: openPaths,
      );
    } on ArgumentError {
      throw DVPreviewStartupException(
        'preview ${runtime.name} is visible to members and no membership check '
        'was supplied, so it could only admit everybody or nobody. Pass '
        'previewMembership to startBackend, or deploy with visibility link.',
      );
    }

    const DVQueues().useNamespace(namespace);
    DVPreviewDatabaseGuard.restrict(database: database, production: production);
    if (connection != null) const DVDatabase().configure(connection.open());

    return _current = DVPreviewServer._(
      runtime: runtime,
      access: access,
      queueNamespace: namespace!,
      database: database,
      connection: connection,
    );
  }

  /// [handler] behind this preview's gate.
  Future<Response> Function(Request request) wrap(
    FutureOr<Response> Function(Request request) handler,
  ) =>
      (Request request) => access.handle(request, handler);

  /// Forgets the started preview and everything it installed. For tests.
  static void reset() {
    _current = null;
    DVPreviewOutbound.deactivate();
    const DVQueues().useNamespace(null);
    DVPreviewDatabaseGuard.release();
  }
}
