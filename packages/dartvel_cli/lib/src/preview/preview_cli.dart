/// `dartvel preview create | list | open | destroy | sweep`: the lifecycle
/// half of `dartvel preview`, over a deployment adapter.
///
/// The command decides the things only a project checkout knows -- the
/// branch, the declared secrets and their preview values, the models that
/// hold sensitive fields -- and hands everything else to [DVPreviews] in
/// dartvel_core, so the refusals a CI step fails on are the runtime's own.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../graph/project_graph.dart';
import '../secrets/secrets_analysis.dart';

/// What hosts a project's previews: the adapter, where previews are
/// recorded, and the project steps that run against a preview's database.
///
/// The steps come from the host rather than from the CLI because nothing in
/// core reads a database connection from the environment: a migration or
/// seed program the CLI started itself would open whichever database that
/// program was written to open, and on a developer's machine or a CI runner
/// that is not reliably the preview's.
final class DVPreviewHost {
  const DVPreviewHost({
    required this.adapter,
    required this.registry,
    this.migrate,
    this.seed,
    this.sanitize,
    this.productionOrigin,
  });

  final DVPreviewAdapter adapter;
  final DVPreviewRegistry registry;
  final DVPreviewStep? migrate;
  final DVPreviewStep? seed;
  final DVPreviewStep? sanitize;
  final String? productionOrigin;
}

/// Resolves the host for the project at [root], or null when none is
/// configured.
typedef DVPreviewHostResolver = FutureOr<DVPreviewHost?> Function(String root);

/// Runs git with [args] in the project and returns its standard output.
typedef DVPreviewGit = Future<String> Function(List<String> args);

/// No preview adapter ships with Dartvel yet; this is what the CLI uses
/// until one is configured, so `create` reports `DV-PREVIEW-010` rather than
/// building something called a preview on a target that cannot isolate one.
DVPreviewHost? dvNoPreviewHost(String root) => null;

Future<String> dvRunGit(List<String> args) async {
  final ProcessResult result = await Process.run('git', args);
  if (result.exitCode != 0) {
    throw ProcessException('git', args, '${result.stderr}'.trim(), result.exitCode);
  }
  return '${result.stdout}';
}

/// The verbs `dartvel preview` dispatches to the lifecycle.
const Set<String> dvPreviewVerbs = <String>{
  'create',
  'list',
  'open',
  'destroy',
  'sweep',
};

final class _UnavailableAdapter implements DVPreviewAdapter {
  const _UnavailableAdapter();

  @override
  String get name => 'the configured deployment (no preview adapter)';
  @override
  bool get canHostPreviews => false;
  @override
  bool get canBranchDatabases => false;

  Never _no() => throw UnsupportedError('no preview adapter is configured');

  @override
  Future<DVPreviewProduction> production() async => _no();
  @override
  Future<void> createDatabase(String database) async => _no();
  @override
  Future<void> branchDatabase(String database, {required String from}) async => _no();
  @override
  Future<Set<String>> valueDigests(String database, String table, String column) async =>
      _no();
  @override
  Future<void> createBucket(String bucket) async => _no();
  @override
  Future<String> deploy(DVPreviewDeployment deployment) async => _no();
  @override
  Future<void> suspend(DVPreviewIdentity identity) async => _no();
  @override
  Future<void> wake(DVPreviewIdentity identity) async => _no();
  @override
  Future<void> destroyDeployment(DVPreviewIdentity identity) async => _no();
  @override
  Future<void> destroyDatabase(String database) async => _no();
  @override
  Future<void> destroyBucket(String bucket) async => _no();
  @override
  Future<bool> exists(DVPreviewResource kind, String name) async => _no();
}

/// Previews recorded in `.dartvel/previews/registry.json`.
///
/// The directory carries its own `.gitignore` of `*`: the file holds link
/// tokens, and a project scaffolded before `.dartvel/` was ignored would
/// otherwise commit every link to a public repository.
final class DVFilePreviewRegistry implements DVPreviewRegistry {
  DVFilePreviewRegistry(String root)
      : _dir = Directory(p.join(root, '.dartvel', 'previews'));

  final Directory _dir;

  File get _file => File(p.join(_dir.path, 'registry.json'));

  @override
  Future<List<DVPreviewRecord>> all() async {
    if (!_file.existsSync()) return const <DVPreviewRecord>[];
    final Object? json = jsonDecode(await _file.readAsString());
    final List<Object?> previews =
        json is Map && json['previews'] is List ? json['previews'] as List<Object?> : <Object?>[];
    return <DVPreviewRecord>[
      for (final Object? record in previews)
        DVPreviewRecord.fromJson((record! as Map<Object?, Object?>).cast<String, Object?>()),
    ];
  }

  @override
  Future<DVPreviewRecord?> find(String name) async {
    for (final DVPreviewRecord record in await all()) {
      if (record.identity.name == name) return record;
    }
    return null;
  }

  @override
  Future<void> put(DVPreviewRecord record) async {
    final List<DVPreviewRecord> records = <DVPreviewRecord>[
      for (final DVPreviewRecord r in await all())
        if (r.identity.name != record.identity.name) r,
      record,
    ];
    await _write(records);
  }

  @override
  Future<void> remove(String name) async {
    await _write(<DVPreviewRecord>[
      for (final DVPreviewRecord r in await all())
        if (r.identity.name != name) r,
    ]);
  }

  Future<void> _write(List<DVPreviewRecord> records) async {
    _dir.createSync(recursive: true);
    final File ignore = File(p.join(_dir.path, '.gitignore'));
    if (!ignore.existsSync()) {
      ignore.writeAsStringSync('# Link tokens. Never committed.\n*\n');
    }
    final File temp = File('${_file.path}.tmp');
    await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'previews': <Object?>[for (final DVPreviewRecord r in records) r.toJson()],
    }));
    await temp.rename(_file.path);
  }
}

/// Table to `@DVModel.sensitiveField()` columns, named as the model
/// generator names them: the public class lowercased with an `s`, and the
/// field's own name.
Map<String, Set<String>> dvPreviewSensitiveColumns(DartvelProjectGraph graph) {
  final Map<String, Set<String>> out = <String, Set<String>>{};
  for (final DVGraphModel model in graph.models) {
    final Set<String> columns = <String>{
      for (final DVGraphField field in model.fields)
        if (field.sensitive) field.name,
    };
    if (columns.isNotEmpty) out['${model.name.toLowerCase()}s'] = columns;
  }
  return out;
}

/// A preview's secret plan for the project at [root].
///
/// Preview values are `PREVIEW_<NAME>` in [environment], then `<NAME>` in
/// `.env.preview`. Production's value is resolved through [DVSecrets] only
/// to compare, and the secrets state is put back afterwards, so the value
/// is not left loaded in a process that goes on to call a deployment API.
DVPreviewSecretPlan dvPreviewSecretPlanFor(
  String root,
  Map<String, String> environment,
) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  final Map<String, DVSecretDeclaration> declared = pubspec.existsSync()
      ? dvParseSecretDeclarations(pubspec.readAsStringSync())
      : const <String, DVSecretDeclaration>{};
  final File file = File(p.join(root, '.env.preview'));
  final Map<String, String> fromFile = file.existsSync()
      ? dvParseEnvContents(file.readAsStringSync())
      : const <String, String>{};

  final DVSecretsState before = DVSecrets.captureState();
  try {
    return dvPlanPreviewSecrets(
      required: <String, Set<String>>{
        for (final DVSecretDeclaration d in declared.values) d.name: d.required,
      },
      previewValue: (String name) => environment['PREVIEW_$name'] ?? fromFile[name],
      productionValue: (String name) => const DVSecrets().maybeGet(name),
    );
  } finally {
    DVSecrets.reset();
    DVSecrets.restoreState(before);
  }
}

/// Runs a lifecycle verb and returns the exit code.
Future<int> dvRunPreviewLifecycle(
  List<String> args, {
  required String root,
  required DVPreviewHostResolver host,
  required DVPreviewGit git,
  required DateTime Function() clock,
  required void Function(String line) out,
  required Map<String, String> environment,
}) async {
  final _Context context = _Context(
    root: root,
    host: host,
    git: git,
    clock: clock,
    out: out,
    environment: environment,
  );
  final CommandRunner<int> runner = CommandRunner<int>(
    'dartvel preview',
    'A branch\'s own deployment, for as long as somebody is looking at it.',
  )
    ..addCommand(_Create(context))
    ..addCommand(_List(context))
    ..addCommand(_Open(context))
    ..addCommand(_Destroy(context))
    ..addCommand(_Sweep(context));
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (error) {
    out(error.message);
    out(error.usage);
    return 64;
  }
}

final class _Context {
  _Context({
    required this.root,
    required this.host,
    required this.git,
    required this.clock,
    required this.out,
    required this.environment,
  });

  final String root;
  final DVPreviewHostResolver host;
  final DVPreviewGit git;
  final DateTime Function() clock;
  final void Function(String line) out;
  final Map<String, String> environment;

  Map<Object?, Object?>? _dartvel() {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw const FormatException('no pubspec.yaml here; run dartvel preview from the project');
    }
    final Object? document = loadYaml(pubspec.readAsStringSync());
    final Object? dartvel = document is Map ? document['dartvel'] : null;
    return dartvel is Map ? dartvel.cast<Object?, Object?>() : null;
  }

  String appName() {
    final Object? document =
        loadYaml(File(p.join(root, 'pubspec.yaml')).readAsStringSync());
    final Object? name = document is Map ? document['name'] : null;
    return name is String && name.isNotEmpty ? name : 'dartvel-app';
  }

  DVPreviewConfig config() {
    final Object? preview = _dartvel()?['preview'];
    if (preview != null && preview is! Map) {
      throw FormatException('dartvel.preview must be a map, got $preview');
    }
    return DVPreviewConfig.fromConfig(
      preview == null ? null : (preview as Map).cast<Object?, Object?>(),
    );
  }

  Future<DVPreviews> previews(DVPreviewConfig config) async {
    final DVPreviewHost resolved = await host(root) ??
        DVPreviewHost(
          adapter: const _UnavailableAdapter(),
          registry: DVMemoryPreviewRegistry(),
        );
    _resolved = resolved;
    return DVPreviews(
      app: appName(),
      adapter: resolved.adapter,
      registry: resolved.registry,
      config: config,
      currentEnvironment: environment['DARTVEL_ENVIRONMENT'],
    );
  }

  DVPreviewHost? _resolved;
  DVPreviewHost? get resolved => _resolved;

  /// The branch: `--branch`, then the pull request's head branch CI names,
  /// then the checkout.
  Future<String> branch(String? given) async {
    if (given != null && given.trim().isNotEmpty) return given.trim();
    final String? ci = environment['GITHUB_HEAD_REF'];
    if (ci != null && ci.trim().isNotEmpty) return ci.trim();
    final String head = (await git(<String>['rev-parse', '--abbrev-ref', 'HEAD'])).trim();
    if (head.isEmpty || head == 'HEAD') {
      throw const FormatException(
        'the checkout is not on a branch; pass --branch',
      );
    }
    return head;
  }

  int report(DVPreviewOutcome outcome) {
    for (final DVPreviewFinding finding in outcome.findings) {
      out(finding.toString());
    }
    for (final String error in outcome.errors) {
      out('error: $error');
    }
    return outcome.ok ? 0 : 1;
  }
}

abstract class _Verb extends Command<int> {
  _Verb(this.context);

  final _Context context;

  @override
  Future<int> run() async {
    try {
      return await verb();
    } on FormatException catch (error) {
      context.out('error: ${error.message}');
      return 1;
    }
  }

  Future<int> verb();
}

final class _Create extends _Verb {
  _Create(super.context) {
    argParser
      ..addOption('branch', help: 'The branch to preview. Defaults to CI\'s head branch, then the checkout.')
      ..addOption('from-pr', help: 'The pull request this preview is for. It is destroyed when that closes.');
  }

  @override
  String get name => 'create';

  @override
  String get description =>
      'Create or redeploy the preview of a branch, and print its URL.';

  @override
  Future<int> verb() async {
    final DVPreviewConfig config = context.config();
    final String? rawPr = argResults?['from-pr'] as String?;
    final int? pr = rawPr == null ? null : int.tryParse(rawPr);
    if (rawPr != null && (pr == null || pr < 1)) {
      throw FormatException('--from-pr must be a pull request number, got $rawPr');
    }
    final String branch = await context.branch(argResults?['branch'] as String?);
    final DVPreviews previews = await context.previews(config);
    final DVPreviewSecretPlan secrets =
        dvPreviewSecretPlanFor(context.root, context.environment);

    Map<String, Set<String>> sensitive = const <String, Set<String>>{};
    if (config.database == DVPreviewDatabase.branch) {
      sensitive = dvPreviewSensitiveColumns(await DartvelProjectGraph.build(
        root: context.root,
        pkgName: context.appName(),
      ));
    }

    final DVPreviewHost host = context.resolved!;
    final DVPreviewOutcome outcome = await previews.create(
      branch: branch,
      now: context.clock(),
      secrets: secrets,
      pullRequest: pr,
      sensitiveColumns: sensitive,
      migrate: host.migrate,
      seed: host.seed,
      sanitize: host.sanitize,
      productionOrigin: host.productionOrigin,
    );
    final int code = context.report(outcome);
    // Last and alone, so a workflow can take the final line as the link.
    if (code == 0 && outcome.openUrl != null) context.out(outcome.openUrl!);
    return code;
  }
}

final class _List extends _Verb {
  _List(super.context);

  @override
  String get name => 'list';

  @override
  String get description => 'List this project\'s previews.';

  @override
  Future<int> verb() async {
    final DVPreviews previews = await context.previews(context.config());
    final List<DVPreviewRecord> records = await previews.list();
    if (records.isEmpty) {
      context.out('No previews.');
      return 0;
    }
    for (final DVPreviewRecord r in records) {
      context.out(<String>[
        r.identity.name,
        r.identity.branch,
        r.state.name,
        if (r.pullRequest != null) '#${r.pullRequest}',
        r.url ?? '-',
        'deployed ${r.deployedAt?.toUtc().toIso8601String() ?? '-'}',
      ].join('  '));
    }
    return 0;
  }
}

final class _Open extends _Verb {
  _Open(super.context) {
    argParser.addOption('branch', help: 'The branch whose preview to open.');
  }

  @override
  String get name => 'open';

  @override
  String get description => 'Print the URL of a branch\'s preview, link token included.';

  @override
  Future<int> verb() async {
    final String branch = await context.branch(argResults?['branch'] as String?);
    final DVPreviews previews = await context.previews(context.config());
    final DVPreviewRecord? record = await previews.registry
        .find(DVPreviewIdentity.forBranch(app: context.appName(), branch: branch).name);
    final String? url = record?.openUrl;
    if (url == null) {
      context.out('error: $branch has no deployed preview');
      return 1;
    }
    context.out(url);
    return 0;
  }
}

final class _Destroy extends _Verb {
  _Destroy(super.context) {
    argParser.addOption('branch', help: 'The branch whose preview to destroy.');
  }

  @override
  String get name => 'destroy';

  @override
  String get description =>
      'Destroy a branch\'s preview: its deployment, database and storage.';

  @override
  Future<int> verb() async {
    final String branch = await context.branch(argResults?['branch'] as String?);
    final DVPreviews previews = await context.previews(context.config());
    final DVPreviewOutcome outcome = await previews.destroy(
      DVPreviewIdentity.forBranch(app: context.appName(), branch: branch).name,
      now: context.clock(),
    );
    return context.report(outcome);
  }
}

final class _Sweep extends _Verb {
  _Sweep(super.context) {
    argParser.addMultiOption('closed-pr',
        help: 'A pull request that closed; its preview is destroyed.');
  }

  @override
  String get name => 'sweep';

  @override
  String get description =>
      'Destroy previews whose branch is gone, whose pull request closed or whose ttl passed; suspend idle ones.';

  @override
  Future<int> verb() async {
    final DVPreviews previews = await context.previews(context.config());

    Set<String>? live;
    try {
      final String heads = await context.git(<String>['ls-remote', '--heads', 'origin']);
      final Set<String> branches = <String>{
        for (final String line in const LineSplitter().convert(heads))
          if (line.contains('\trefs/heads/')) line.split('\trefs/heads/').last.trim(),
      };
      // An empty answer is treated as no answer. A remote with no branches
      // at all is not a thing a project has; a remote that could not be
      // listed and printed nothing is, and reading that as every branch
      // having merged would destroy every preview at once.
      live = branches.isEmpty ? null : branches;
    } catch (_) {
      live = null;
    }
    if (live == null) {
      context.out('Branches were not checked: the remote could not be listed. '
          'Previews are still expired by ttl and closed pull request.');
    }

    final Set<int> closed = <int>{};
    for (final String raw in (argResults?['closed-pr'] as List<String>? ?? const <String>[])) {
      final int? n = int.tryParse(raw);
      if (n == null) throw FormatException('--closed-pr must be a number, got $raw');
      closed.add(n);
    }

    final List<DVPreviewFinding> findings = await previews.sweep(
      now: context.clock(),
      liveBranches: live,
      closedPullRequests: closed,
    );
    for (final DVPreviewFinding f in findings) {
      context.out(f.toString());
    }
    // A teardown that did not finish leaves its record in `destroying`.
    final List<DVPreviewRecord> stuck = <DVPreviewRecord>[
      for (final DVPreviewRecord r in await previews.list())
        if (r.state == DVPreviewState.destroying) r,
    ];
    for (final DVPreviewRecord r in stuck) {
      context.out('error: preview ${r.identity.name} is not destroyed; '
          '${r.remaining.map((DVPreviewResource x) => x.name).join(', ')} remain');
    }
    return stuck.isEmpty ? 0 : 1;
  }
}
