import 'dart:io';

import '../generators/annotation_args.dart';
import '../utils/logger.dart';
import 'db_command.dart' show dvDatabaseSettings;
import 'package:dartvel_core/dartvel.dart'
    show
        DVDatabaseAdapter,
        DVDatabaseConnection,
        DVStudioGrant,
        DVStudioGrants,
        DVTenants,
        SqliteDVDatabaseAdapter;
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

class AdminCommand extends Command<void> {
  @override
  final String name = 'admin';

  @override
  String get description =>
      'Generate Dartvel admin surfaces, and say who may open Studio.';

  /// [root] is the project; null reads the working directory when the command
  /// runs. A test passes its own, because that directory is one value shared
  /// by every suite in the process. [environment], [out] and [setExitCode]
  /// are the process's own when null.
  AdminCommand({
    String? root,
    Map<String, String>? environment,
    void Function(String line)? out,
    void Function(int code)? setExitCode,
  }) {
    final _AdminIo io = _AdminIo(
      root: root,
      environment: environment ?? Platform.environment,
      out: out ?? Logger.log,
      setExitCode: setExitCode ?? ((int code) => exitCode = code),
    );
    addSubcommand(AdminGenerateCommand(root: root));
    addSubcommand(_AdminGrantCommand(io));
    addSubcommand(_AdminRevokeCommand(io));
    addSubcommand(_AdminListCommand(io));
  }
}

class _AdminIo {
  _AdminIo({
    required this._root,
    required this.environment,
    required this.out,
    required this.setExitCode,
  });

  final String? _root;
  final Map<String, String> environment;
  final void Function(String line) out;
  final void Function(int code) setExitCode;

  String get root => _root ?? Directory.current.path;

  void fail(String message) {
    out(message);
    setExitCode(1);
  }
}

/// What `grant`, `revoke` and `list` share: the database the grants live in.
///
/// Studio opens on a deployed application only for a person granted
/// `Studio.access`, and the running backend reads those grants from its own
/// database. So these write to that database and nowhere else: `--database`
/// names a SQLite file (a web-server binary keeps its own in
/// `dartvel_data/data.db` beside itself), else `DATABASE_URL`, else the
/// SQLite file `dartvel.database` names. A file that does not exist is
/// refused rather than created, because a grant written into a new empty
/// database is one no server reads, reported as done.
abstract class _AdminGrantsCommand extends Command<void> {
  _AdminGrantsCommand(this.io, {bool takesTenant = true}) {
    argParser.addOption('database',
        help: 'The SQLite file the application uses, such as '
            'dartvel_data/data.db beside a web-server binary. Defaults to '
            'DATABASE_URL, then dartvel.database.');
    // list shows every tenant's grants, so it takes none.
    if (takesTenant) {
      argParser.addOption('tenant',
          defaultsTo: DVTenants.defaultTenant,
          help: 'The tenant the account signs in on.');
    }
  }

  final _AdminIo io;

  DVDatabaseAdapter? openDatabase() {
    final String? declared = argResults?['database'] as String?;
    if (declared != null && declared.trim().isNotEmpty) {
      final String file =
          p.isAbsolute(declared) ? declared : p.join(io.root, declared);
      if (!File(file).existsSync()) {
        io.fail('No database exists at $file. Point --database at the SQLite '
            'file the application runs with.');
        return null;
      }
      return SqliteDVDatabaseAdapter.file(file);
    }
    final DVDatabaseConnection? connection;
    try {
      connection = DVDatabaseConnection.fromEnvironment(io.environment);
    } on Object catch (error) {
      io.fail('DATABASE_URL cannot be read: $error');
      return null;
    }
    if (connection != null) return connection.open();
    final ({String provider, String path}) settings =
        dvDatabaseSettings(io.root);
    if (settings.provider != 'sqlite') {
      io.fail('dartvel.database uses ${settings.provider}, and DATABASE_URL is '
          'not set, so there is no connection to it. Set DATABASE_URL.');
      return null;
    }
    final String file = p.isAbsolute(settings.path)
        ? settings.path
        : p.join(io.root, settings.path);
    if (!File(file).existsSync()) {
      io.fail('No database exists at $file. Set --database or DATABASE_URL '
          'to the database the application runs with.');
      return null;
    }
    return SqliteDVDatabaseAdapter.file(file);
  }

  String get tenant => '${argResults?['tenant'] ?? DVTenants.defaultTenant}';

  /// The one account the command names, or null having said why.
  String? account() {
    final List<String> rest = argResults?.rest ?? const <String>[];
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      io.fail('Name one account: dartvel admin $name <user-id>. The id is the '
          'one the application signs the person in as.');
      return null;
    }
    return rest.single.trim();
  }
}

class _AdminGrantCommand extends _AdminGrantsCommand {
  _AdminGrantCommand(super.io);

  @override
  final String name = 'grant';

  @override
  String get description =>
      'Let an account open Studio (Studio.access) on a deployed application.';

  @override
  Future<void> run() async {
    final String? user = account();
    if (user == null) return;
    final DVDatabaseAdapter? database = openDatabase();
    if (database == null) return;
    await DVStudioGrants(database).grant(user, tenant: tenant);
    io.out('$user may open Studio on tenant $tenant.');
  }
}

class _AdminRevokeCommand extends _AdminGrantsCommand {
  _AdminRevokeCommand(super.io);

  @override
  final String name = 'revoke';

  @override
  String get description => 'Take an account\'s Studio access away.';

  @override
  Future<void> run() async {
    final String? user = account();
    if (user == null) return;
    final DVDatabaseAdapter? database = openDatabase();
    if (database == null) return;
    if (!await DVStudioGrants(database).revoke(user, tenant: tenant)) {
      io.fail('$user holds no Studio grant on tenant $tenant, so nothing was '
          'revoked.');
      return;
    }
    io.out('$user may no longer open Studio on tenant $tenant.');
  }
}

class _AdminListCommand extends _AdminGrantsCommand {
  _AdminListCommand(super.io) : super(takesTenant: false);

  @override
  final String name = 'list';

  @override
  String get description => 'List the accounts that may open Studio.';

  @override
  Future<void> run() async {
    final DVDatabaseAdapter? database = openDatabase();
    if (database == null) return;
    final List<DVStudioGrant> grants = await DVStudioGrants(database).list();
    if (grants.isEmpty) {
      io.out('Nobody may open Studio. Grant an account with '
          'dartvel admin grant <user-id>.');
      return;
    }
    for (final DVStudioGrant grant in grants) {
      io.out('${grant.userId}  tenant ${grant.tenant}  granted '
          '${grant.grantedAt.toIso8601String()}');
    }
  }
}

class AdminGenerateCommand extends Command<void> {
  @override
  final String name = 'generate';

  @override
  String get description => 'Generate Dartvel admin and devtools pages.';

  AdminGenerateCommand({this._root}) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      defaultsTo: false,
      help: 'Overwrite generated admin files.',
    );
  }

  final String? _root;

  @override
  void run() {
    final String root = _root ?? Directory.current.path;
    final result = DartvelAdminGenerator.generate(
      root: Directory(root),
      force: argResults?['force'] == true,
    );
    for (final file in result.writtenFiles) {
      stdout.writeln('generated ${p.relative(file.path, from: root)}');
    }
    if (result.skippedFiles.isNotEmpty) {
      for (final file in result.skippedFiles) {
        stdout.writeln('exists ${p.relative(file.path, from: root)}');
      }
    }
  }
}

class DevtoolsCommand extends Command<void> {
  @override
  final String name = 'devtools';

  @override
  String get description =>
      'Generate and open Dartvel devtools metadata pages.';

  DevtoolsCommand({this._root}) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      defaultsTo: false,
      help: 'Overwrite generated devtools files.',
    );
  }

  final String? _root;

  @override
  void run() {
    final result = DartvelAdminGenerator.generate(
      root: Directory(_root ?? Directory.current.path),
      force: argResults?['force'] == true,
    );
    stdout.writeln('Dartvel devtools generated at /_dartvel_admin');
    stdout.writeln('Run dartvel dev and open /_dartvel_admin in the app.');
    stdout.writeln(
        'files=${result.writtenFiles.length}, skipped=${result.skippedFiles.length}');
  }
}

class DartvelAdminGenerationResult {
  final List<File> writtenFiles;
  final List<File> skippedFiles;

  const DartvelAdminGenerationResult({
    required this.writtenFiles,
    required this.skippedFiles,
  });
}

class DartvelAdminGenerator {
  const DartvelAdminGenerator._();

  static DartvelAdminGenerationResult generate({
    required Directory root,
    required bool force,
  }) {
    final adminDir =
        Directory(p.join(root.path, 'lib', 'pages', '_dartvel_admin'))
          ..createSync(recursive: true);
    final files = <String, String>{
      'index.page.dart': _indexPage,
      'queues.page.dart': _queuesPage,
      'cache.page.dart': _cachePage,
      'routes.page.dart': _routesPage,
      'studio.page.dart': _studioPage,
      'models.page.dart': _modelsPage(_discoverModels(root)),
      'outbox.page.dart': _outboxPage,
      'policies.page.dart': _policiesPage,
      'telemetry.page.dart': _telemetryPage,
    };
    final written = <File>[];
    final skipped = <File>[];
    for (final entry in files.entries) {
      final file = File(p.join(adminDir.path, entry.key));
      if (file.existsSync() && !force) {
        skipped.add(file);
        continue;
      }
      file.writeAsStringSync(entry.value);
      written.add(file);
    }
    return DartvelAdminGenerationResult(
      writtenFiles: List<File>.unmodifiable(written),
      skippedFiles: List<File>.unmodifiable(skipped),
    );
  }

  /// The models an application declared, read the same way the model
  /// generator reads them.
  ///
  /// Scanned rather than configured: an admin that had to be told which
  /// models exist would silently omit every model added afterwards.
  static List<String> _discoverModels(Directory root) {
    final modelsDir = Directory(p.join(root.path, 'lib', 'models'));
    if (!modelsDir.existsSync()) return const <String>[];
    final pattern = RegExp(
      r'@DVModel\s*\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*class\s+_([A-Za-z0-9_]+)\b',
      dotAll: true,
    );
    final names = <String>{};
    for (final entity in modelsDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Blanked annotation arguments, because `[^)]*` stops at the first
    // close parenthesis and a string argument can contain one. The model
    // generator masks the same way, and a model this misses while the
    // generator finds it is a table in the database with no row here.
      for (final match in pattern.allMatches(
        dvMaskAnnotationArgs(entity.readAsStringSync(), 'DVModel'),
      )) {
        names.add(match.group(1)!);
      }
    }
    return names.toList(growable: false)..sort();
  }

  /// The model CRUD page, one section per declared model.
  static String _modelsPage(List<String> models) {
    final buffer = StringBuffer()
      ..writeln("import '../../dartvel_client/dartvel_client.dart';")
      ..writeln("import 'package:flutter/widgets.dart';")
      ..writeln()
      ..writeln("@DVPage(title: 'Dartvel Models', path: '/_dartvel_admin/models', policy: DVPolicies.viewAdmin)")
      ..writeln("@pragma('vm:entry-point')")
      ..writeln('Widget _dartvelAdminModelsPage(BuildContext context) => '
          'buildDartvelAdminModelsPage(context);')
      ..writeln()
      ..writeln('Widget buildDartvelAdminModelsPage(BuildContext context) => '
          'DVBox.list([');
    buffer.writeln("    const DVText('Models').modifier(");
    buffer.writeln('      const DVModifier().fontSize(24)'
        '.fontWeight(FontWeight.bold),');
    buffer.writeln('    ),');
    if (models.isEmpty) {
      // An app with no models is a real state, and an empty page with no
      // explanation reads as a broken one.
      buffer.writeln("    const DVText('No @DVModel classes found in "
          "lib/models.'),");
    }
    for (final model in models) {
      buffer.writeln('    $model.Admin(),');
    }
    buffer.writeln('  ]).modifier(const DVModifier().padding(24));');
    return buffer.toString();
  }

  static const String _indexPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Admin', path: '/_dartvel_admin', policy: DVPolicies.viewAdmin)
@pragma('vm:entry-point')
Widget _dartvelAdminIndexPage(BuildContext context) => buildDartvelAdminIndexPage(context);

Widget buildDartvelAdminIndexPage(BuildContext context) => DVBox.list([
    const DVText('Dartvel Admin').modifier(
      const DVModifier().fontSize(28).fontWeight(FontWeight.bold),
    ),
    DVText('Generated model, route, queue, cache, policy, and notification tools.'),
    DVBox.grid([
      dartvelAdminCard(context, 'Studio', '/_dartvel_admin/studio'),
      dartvelAdminCard(context, 'Models', '/_dartvel_admin/models'),
      dartvelAdminCard(context, 'Queues and Jobs', '/_dartvel_admin/queues'),
      dartvelAdminCard(context, 'Cache Tags', '/_dartvel_admin/cache'),
      dartvelAdminCard(context, 'Routes and Pages', '/_dartvel_admin/routes'),
      dartvelAdminCard(context, 'Outbox', '/_dartvel_admin/outbox'),
      dartvelAdminCard(context, 'Policies and Sync', '/_dartvel_admin/policies'),
      dartvelAdminCard(context, 'Entitlements and Events', '/_dartvel_admin/telemetry'),
    ], columns: 2),
  ]).modifier(const DVModifier().padding(24));

/// A card that opens the surface it names. Cards that named a page without
/// going to it left the admin unnavigable.
Widget dartvelAdminCard(BuildContext context, String label, String path) =>
    DVBox(DVText(label)).modifier(
      const DVModifier().card().padding(16).semanticButton().onTap(
        () => context.navigateToPage(DVRouteTarget(path)),
      ),
    );
''';

  static const String _outboxPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Outbox', path: '/_dartvel_admin/outbox', policy: DVPolicies.viewAdmin)
@pragma('vm:entry-point')
Widget _dartvelAdminOutboxPage(BuildContext context) => buildDartvelAdminOutboxPage(context);

/// Only an in-memory provider keeps a record a local admin can read; a remote
/// provider sends from its own infrastructure. Point these at the providers
/// the application configured.
DVMemoryMailProvider? dartvelAdminMailOutbox;
DVMemoryNotificationProvider? dartvelAdminNotificationOutbox;

Widget buildDartvelAdminOutboxPage(BuildContext context) => DVBox(
      DVOutboxAdmin(
        mail: dartvelAdminMailOutbox,
        notifications: dartvelAdminNotificationOutbox,
      ),
    ).modifier(const DVModifier().padding(24));
''';

  static const String _policiesPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Policies', path: '/_dartvel_admin/policies', policy: DVPolicies.viewAdmin)
@pragma('vm:entry-point')
Widget _dartvelAdminPoliciesPage(BuildContext context) => buildDartvelAdminPoliciesPage(context);

Widget buildDartvelAdminPoliciesPage(BuildContext context) =>
    const DVBox(DVPolicyAdmin()).modifier(const DVModifier().padding(24));
''';

  static const String _telemetryPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Telemetry', path: '/_dartvel_admin/telemetry', policy: DVPolicies.viewAdmin)
@pragma('vm:entry-point')
Widget _dartvelAdminTelemetryPage(BuildContext context) => buildDartvelAdminTelemetryPage(context);

/// Only local providers keep records this admin can read; a hosted billing or
/// analytics provider keeps them on its own infrastructure. Point these at
/// the providers the application configured.
DVLocalBillingProvider? dartvelAdminBilling;
LocalAnalyticsProvider? dartvelAdminAnalytics;

Widget buildDartvelAdminTelemetryPage(BuildContext context) => DVBox(
      DVTelemetryAdmin(
        billing: dartvelAdminBilling,
        analytics: dartvelAdminAnalytics,
      ),
    ).modifier(const DVModifier().padding(24));
''';

  static const String _studioPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Studio', path: '/_dartvel_admin/studio', policy: DVPolicies.viewAdmin)
@pragma('vm:entry-point')
Widget _dartvelAdminStudioPage(BuildContext context) => buildDartvelAdminStudioPage(context);

/// The page builder itself. DVStudioScreen is a tested widget in
/// dartvel_flutter rather than source emitted here, so what the generator
/// writes cannot drift from the editor it opens.
Widget buildDartvelAdminStudioPage(BuildContext context) => const DVStudioScreen();
''';

  static const String _queuesPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Queues', path: '/_dartvel_admin/queues', policy: DVPolicies.viewAdmin)
@pragma('vm:entry-point')
Widget _dartvelAdminQueuesPage(BuildContext context) => buildDartvelAdminQueuesPage(context);

/// Jobs are stored per queue and nothing enumerates the names, so an
/// application lists the queues it dispatches to here.
const List<String> dartvelAdminQueues = <String>['default'];

Widget buildDartvelAdminQueuesPage(BuildContext context) =>
    const DVBox(DVQueueAdmin(queues: dartvelAdminQueues))
        .modifier(const DVModifier().padding(24));
'''; 

  static const String _cachePage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Cache', path: '/_dartvel_admin/cache', policy: DVPolicies.viewAdmin)
@pragma('vm:entry-point')
Widget _dartvelAdminCachePage(BuildContext context) => buildDartvelAdminCachePage(context);

Widget buildDartvelAdminCachePage(BuildContext context) =>
    const DVBox(DVCacheAdmin()).modifier(const DVModifier().padding(24));
''';

  static const String _routesPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Routes', path: '/_dartvel_admin/routes', policy: DVPolicies.viewAdmin)
@pragma('vm:entry-point')
Widget _dartvelAdminRoutesPage(BuildContext context) => buildDartvelAdminRoutesPage(context);

/// Reads the generated manifest rather than a hand-kept list, so a page added
/// later shows up here without anyone remembering to register it.
Widget buildDartvelAdminRoutesPage(BuildContext context) =>
    const DVBox(DVRouteAdmin(routes: dartvelRouteManifest))
        .modifier(const DVModifier().padding(24));
''';
}

/// The pages `dartvel admin` writes, by the file each is written to.
///
/// Exposed so that what the scaffold generates can be asserted rather than
/// described. The eight of these shipped with no guard, no policy and no
/// role between them and anybody who could load the application -- and one
/// of them is the page builder, whose documents the router prefers over the
/// pages the application shipped with.
Map<String, String> dvAdminScaffoldPages() => <String, String>{
      'index.page.dart': DartvelAdminGenerator._indexPage,
      'queues.page.dart': DartvelAdminGenerator._queuesPage,
      'cache.page.dart': DartvelAdminGenerator._cachePage,
      'routes.page.dart': DartvelAdminGenerator._routesPage,
      'studio.page.dart': DartvelAdminGenerator._studioPage,
      'models.page.dart': DartvelAdminGenerator._modelsPage(const <String>[]),
      'outbox.page.dart': DartvelAdminGenerator._outboxPage,
      'policies.page.dart': DartvelAdminGenerator._policiesPage,
      'telemetry.page.dart': DartvelAdminGenerator._telemetryPage,
    };
