// `dartvel preview create | list | destroy | sweep`.
//
// Run against a project on disk and an in-memory adapter, because what the
// command gets wrong is the glue: which branch it names, which secret values
// it reads, which models it reports as holding sensitive fields, what exit
// code a CI step sees, and whether the file it keeps can be committed.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/preview_command.dart';
import 'package:dartvel_cli/src/preview/preview_cli.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class MemoryAdapter implements DVPreviewAdapter {
  MemoryAdapter({this.canHostPreviews = true});

  @override
  final String name = 'memory';
  @override
  final bool canHostPreviews;
  @override
  final bool canBranchDatabases = true;

  final Set<String> databases = <String>{'shop'};
  final Set<String> buckets = <String>{};
  final Map<String, DVPreviewDeployment> deployments =
      <String, DVPreviewDeployment>{};
  final List<String> calls = <String>[];

  @override
  Future<DVPreviewProduction> production() async => const DVPreviewProduction(
        database: 'shop',
        bucket: 'shop-uploads',
        host: 'shop',
        queueNamespace: 'default',
      );

  @override
  Future<void> createDatabase(String database) async {
    calls.add('createDatabase');
    databases.add(database);
  }

  @override
  Future<void> branchDatabase(String database, {required String from}) async {
    calls.add('branchDatabase');
    databases.add(database);
  }

  @override
  Future<Set<String>> valueDigests(String database, String table, String column) async =>
      <String>{};

  @override
  Future<void> createBucket(String bucket) async => buckets.add(bucket);

  @override
  Future<String> deploy(DVPreviewDeployment deployment) async {
    calls.add('deploy');
    deployments[deployment.identity.hostLabel] = deployment;
    return 'https://${deployment.identity.hostLabel}.preview.example.dev';
  }

  @override
  Future<void> suspend(DVPreviewIdentity identity) async {}

  @override
  Future<void> wake(DVPreviewIdentity identity) async {}

  @override
  Future<void> destroyDeployment(DVPreviewIdentity identity) async =>
      deployments.remove(identity.hostLabel);

  /// Reports success and leaves the database where it is.
  bool databaseDestroyLies = false;

  @override
  Future<void> destroyDatabase(String database) async {
    if (!databaseDestroyLies) databases.remove(database);
  }

  @override
  Future<void> destroyBucket(String bucket) async => buckets.remove(bucket);

  @override
  Future<bool> exists(DVPreviewResource kind, String name) async => switch (kind) {
        DVPreviewResource.deployment => deployments.containsKey(name),
        DVPreviewResource.database => databases.contains(name),
        DVPreviewResource.bucket => buckets.contains(name),
      };
}

const String pubspec = '''
name: shop
dartvel:
  preview:
    visibility: link
    ttl: 3d
  secrets:
    PAYSTACK_SECRET:
      scope: backend
      required: [production]
''';

const String userModel = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String id;
  @DVModel.sensitiveField()
  final String email;
  final String name;
  const _User(this.id, this.email, this.name);
}
''';

void main() {
  late Directory previous;
  late Directory root;
  late MemoryAdapter adapter;
  late List<String> out;
  late Map<String, String> environment;
  late List<List<String>> gitCalls;
  late String currentBranch;
  late String remoteHeads;
  DateTime now = DateTime.utc(2026, 9, 1, 12);

  setUp(() {
    previous = Directory.current;
    root = Directory.systemTemp.createTempSync('dartvel_preview_cli_');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'user.dart')).writeAsStringSync(userModel);
    Directory.current = root;
    adapter = MemoryAdapter();
    out = <String>[];
    environment = <String, String>{'PREVIEW_PAYSTACK_SECRET': 'sk_test_preview'};
    gitCalls = <List<String>>[];
    currentBranch = 'feature/cart';
    remoteHeads = '';
    now = DateTime.utc(2026, 9, 1, 12);
    exitCode = 0;
    DVSecrets.reset();
  });

  tearDown(() {
    Directory.current = previous;
    root.deleteSync(recursive: true);
    exitCode = 0;
    DVSecrets.reset();
  });

  Future<int> run(
    List<String> args, {
    DVPreviewHost? Function(String root)? host,
  }) async {
    exitCode = 0;
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(PreviewCommand(
        previewHost: host ??
            (String root) => DVPreviewHost(
                  adapter: adapter,
                  registry: DVFilePreviewRegistry(root),
                ),
        git: (List<String> gitArgs) async {
          gitCalls.add(gitArgs);
          if (gitArgs.first == 'rev-parse') return '$currentBranch\n';
          if (gitArgs.first == 'ls-remote') return remoteHeads;
          throw StateError('unexpected git ${gitArgs.join(' ')}');
        },
        clock: () => now,
        out: out.add,
        environment: environment,
      ));
    await runner.run(<String>['preview', ...args]);
    return exitCode;
  }

  test('--help is a successful exit, not a usage error', () async {
    // The serve options moved to a parser of their own when the verbs
    // arrived, and that parser did not know --help: asking for help exited
    // 64, which a script reads as having called the command wrongly.
    expect(await run(<String>['--help']), 0);
  });

  test('with no adapter that can host previews, create is DV-PREVIEW-010 and fails the step',
      () async {
    final int code = await run(<String>['create'], host: (_) => null);
    expect(code, 1);
    expect(out.join('\n'), contains('DV-PREVIEW-010'));
    expect(Directory(p.join(root.path, '.dartvel', 'previews')).existsSync(), isFalse);
  });

  test('create names the current branch, deploys preview values, and prints the URL last',
      () async {
    final int code = await run(<String>['create']);
    expect(code, 0, reason: out.join('\n'));

    final DVPreviewIdentity id =
        DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
    final DVPreviewDeployment deployed = adapter.deployments[id.hostLabel]!;
    expect(deployed.variables['PAYSTACK_SECRET'], 'sk_test_preview');
    expect(deployed.visibility, DVPreviewVisibility.link);
    expect(out.join('\n'), contains('DV-PREVIEW-001'));

    // The last line is the URL alone, so a workflow can comment it.
    expect(out.last, startsWith('https://${id.hostLabel}.preview.example.dev'));
    expect(out.last, contains('dv_preview='));
  });

  test('the registry keeps link tokens and cannot be committed', () async {
    await run(<String>['create']);
    final Directory dir = Directory(p.join(root.path, '.dartvel', 'previews'));
    final File ignore = File(p.join(dir.path, '.gitignore'));
    expect(ignore.existsSync(), isTrue);
    expect(ignore.readAsLinesSync(), contains('*'));
    final Map<String, Object?> json = jsonDecode(
        File(p.join(dir.path, 'registry.json')).readAsStringSync()) as Map<String, Object?>;
    expect((json['previews']! as List<Object?>), hasLength(1));
  });

  test('a preview value may come from .env.preview', () async {
    environment = <String, String>{};
    File(p.join(root.path, '.env.preview'))
        .writeAsStringSync('PAYSTACK_SECRET=sk_test_from_file\n');
    final int code = await run(<String>['create']);
    expect(code, 0, reason: out.join('\n'));
    expect(adapter.deployments.values.single.variables['PAYSTACK_SECRET'],
        'sk_test_from_file');
  });

  test('production\'s value is never deployed, even when it is all there is',
      () async {
    environment = <String, String>{};
    DVSecrets.configure(<String, String>{'PAYSTACK_SECRET': 'sk_live_production'});
    final int code = await run(<String>['create']);
    expect(code, 1);
    expect(out.join('\n'), contains('DV-PREVIEW-002'));
    expect(out.join('\n'), isNot(contains('sk_live')));
    expect(adapter.calls, isEmpty);
  });

  test('a preview value copied from production is refused', () async {
    environment = <String, String>{'PREVIEW_PAYSTACK_SECRET': 'sk_live_production'};
    DVSecrets.configure(<String, String>{'PAYSTACK_SECRET': 'sk_live_production'});
    final int code = await run(<String>['create']);
    expect(code, 1);
    expect(out.join('\n'), contains('DV-PREVIEW-002'));
    expect(adapter.deployments, isEmpty);
    // The comparison read production's value and put the state back.
    expect(const DVSecrets().maybeGet('PAYSTACK_SECRET'), 'sk_live_production');
  });

  test('--from-pr takes the branch CI names and records the pull request', () async {
    environment['GITHUB_HEAD_REF'] = 'fix/login';
    final int code = await run(<String>['create', '--from-pr', '412']);
    expect(code, 0, reason: out.join('\n'));
    final List<DVPreviewRecord> records =
        await DVFilePreviewRegistry(root.path).all();
    expect(records.single.identity.branch, 'fix/login');
    expect(records.single.pullRequest, 412);
    expect(gitCalls, isEmpty, reason: 'the branch came from CI, not the checkout');
  });

  test('branching a database whose models hold sensitive fields names them in DV-PREVIEW-003',
      () async {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec.replaceFirst(
      '    visibility: link\n',
      '    visibility: link\n    database: branch\n    sanitize: lib/dev/sanitize.dart\n',
    ));
    final int code = await run(<String>['create']);
    expect(code, 1);
    expect(out.join('\n'), contains('DV-PREVIEW-003'));
    expect(out.join('\n'), contains('users.email'));
    expect(out.join('\n'), isNot(contains('users.name')));
    expect(adapter.calls, isEmpty);
  });

  test('a preview is not created from inside one', () async {
    environment['DARTVEL_ENVIRONMENT'] = 'preview';
    final int code = await run(<String>['create']);
    expect(code, 1);
    expect(adapter.calls, isEmpty);
  });

  test('an unreadable dartvel.preview fails before anything is created', () async {
    File(p.join(root.path, 'pubspec.yaml'))
        .writeAsStringSync(pubspec.replaceFirst('visibility: link', 'visibility: everyone'));
    final int code = await run(<String>['create']);
    expect(code, 1);
    expect(out.join('\n'), contains('dartvel.preview.visibility'));
    expect(adapter.calls, isEmpty);
  });

  test('list, then destroy takes the preview and its resources', () async {
    await run(<String>['create']);
    out.clear();
    await run(<String>['list']);
    final DVPreviewIdentity id =
        DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
    expect(out.join('\n'), contains(id.name));
    expect(out.join('\n'), contains('feature/cart'));

    out.clear();
    final int code = await run(<String>['destroy']);
    expect(code, 0, reason: out.join('\n'));
    expect(out.join('\n'), contains('DV-PREVIEW-009'));
    expect(adapter.databases, <String>{'shop'});
    expect(await DVFilePreviewRegistry(root.path).all(), isEmpty);
  });

  test('sweep destroys a preview whose branch is gone from the remote', () async {
    await run(<String>['create']);
    currentBranch = 'feature/other';
    await run(<String>['create']);
    remoteHeads = 'abc123\trefs/heads/feature/other\n';
    out.clear();
    final int code = await run(<String>['sweep']);
    expect(code, 0, reason: out.join('\n'));
    final List<DVPreviewRecord> left = await DVFilePreviewRegistry(root.path).all();
    expect(left.map((DVPreviewRecord r) => r.identity.branch), <String>['feature/other']);
  });

  test('a remote that lists nothing is not read as every branch having merged',
      () async {
    await run(<String>['create']);
    now = now.add(const Duration(days: 3, minutes: 1));
    currentBranch = 'feature/fresh';
    await run(<String>['create']);
    remoteHeads = '';
    out.clear();

    final int code = await run(<String>['sweep']);

    expect(code, 0, reason: out.join('\n'));
    expect(out.join('\n'), contains('Branches were not checked'));
    final List<DVPreviewRecord> left = await DVFilePreviewRegistry(root.path).all();
    // feature/cart is past its ttl; feature/fresh was deployed a minute ago
    // and its branch was never shown to be gone.
    expect(left.map((DVPreviewRecord r) => r.identity.branch), <String>['feature/fresh']);
  });

  test('a sweep whose teardown did not finish fails the step', () async {
    await run(<String>['create']);
    adapter.databaseDestroyLies = true;
    now = now.add(const Duration(days: 4));
    out.clear();
    final int expired = await run(<String>['sweep']);
    expect(expired, 1, reason: out.join('\n'));
    expect(out.join('\n'), contains('not destroyed'));
    expect((await DVFilePreviewRegistry(root.path).all()).single.state,
        DVPreviewState.destroying);
  });
}
