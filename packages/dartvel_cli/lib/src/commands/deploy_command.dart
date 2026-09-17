import 'package:path/path.dart' as p;
import '../graph/project_graph.dart';
import '../deploy/function_deploy.dart';
import '../secrets/secrets_analysis.dart';
import 'dart:io';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import '../cloud/cloud_build.dart';
import '../publish/store_deploy.dart';
import '../utils/logger.dart';

typedef DeployProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

class DeployCommand extends Command<void> {
  /// [root] and [cloud] are for the store form; null reads the working
  /// directory and reaches the real Dartvel Cloud.
  DeployCommand({
    DeployProcessRun? processRun,
    String? root,
    DVCloudBuilder? cloud,
  })  : _processRun = processRun ?? Process.run,
        _store = DVStoreDeploy(
          // The upload runs in the project, which is the working directory
          // this command already runs everything else in.
          processRun: processRun == null
              ? null
              : (String executable, List<String> arguments,
                      {String? workingDirectory, bool runInShell = false}) =>
                  processRun(executable, arguments, runInShell: runInShell),
          root: root,
          cloud: cloud,
        ) {
    argParser
      ..addOption('target',
          abbr: 't',
          allowed: ['web', 'server', 'all'],
          defaultsTo: 'all',
          help: 'Deployment target')
      ..addOption('provider',
          // Checked in run() rather than by `allowed`, so a bare firebase is
          // answered with the two things it could mean instead of the
          // parser's "not an allowed value".
          valueHelp: _providers.join('|'),
          help: 'Where the web build or the server is hosted: '
              'firebase-hosting (Firebase Hosting, with the firebase CLI), '
              'vercel, netlify, cloudflare (Cloudflare Pages, with wrangler), '
              'or custom to build only and deploy from build/ yourself.')
      ..addOption('environment',
          abbr: 'e',
          defaultsTo: 'production',
          help: 'Environment to deploy to. Declared secrets required for it '
              'must resolve before anything ships.')
      ..addFlag('functions',
          negatable: false,
          help: 'Function mode: write a deployment artifact per backend '
              'function instead of deploying the whole build.')
      ..addOption('function-target',
          help: 'Where the functions go: '
              '${dvFunctionDeployTargets.join(', ')}.',
          defaultsTo: 'container')
      ..addFlag('build', defaultsTo: true, help: 'Build before deploying')
      ..addFlag('verify', defaultsTo: true, help: 'Verify deployment')
      ..addOption('store',
          allowed: dvDeployStores.keys,
          allowedHelp: {
            'play': 'Google Play, to the track dartvel.publish.play names.',
            'appstore': 'App Store Connect.',
            'testflight': 'TestFlight.',
            'firebase-app-distribution':
                'Firebase App Distribution, to its tester groups.',
          },
          help: 'Deploy a built application to a store or a tester group '
              'instead of a web build or a server. Declared under '
              'dartvel.publish in pubspec.yaml; build it first with '
              'dartvel build. Takes none of --target, --provider, --functions '
              'or --function-target.')
      ..addFlag('dry-run',
          defaultsTo: false,
          negatable: false,
          help: 'With --store: print the upload that would run, and run '
              'nothing.')
      ..addOption('artifact',
          help: 'With --store: the file to upload, when it is not where the '
              'build puts it.')
      ..addFlag('cloud',
          defaultsTo: false,
          negatable: false,
          help: 'With --store: build and deploy on Dartvel Cloud, with the '
              'credentials kept there by dartvel key cloud. With --dry-run '
              'the worker prints the upload instead of making it. Play gets '
              'an App Bundle and App Store Connect a signed IPA, both built '
              'in release. Needs a paid Dartvel Cloud plan.')
      ..addOption('cloud-token',
          help: 'The Dartvel Cloud token for --cloud. Defaults to '
              'DARTVEL_CLOUD_TOKEN, which keeps it out of shell history.');
  }

  final DeployProcessRun _processRun;
  final DVStoreDeploy _store;

  /// The options that only mean something with --store, and the ones that
  /// mean something only without it.
  static const List<String> _providers = <String>[
    'firebase-hosting',
    'vercel',
    'netlify',
    'cloudflare',
    'custom',
  ];

  static const List<String> _storeOnly = <String>[
    'dry-run',
    'artifact',
    'cloud',
    'cloud-token',
  ];
  static const List<String> _hostOnly = <String>[
    'target',
    'provider',
    'functions',
    'function-target',
  ];

  @override
  final String name = 'deploy';

  @override
  String get description =>
      'Deploy to production: a web build or a server (--provider), or an '
      'application to a store (--store).';

  @override
  Future<void> run() async {
    final ArgResults args = argResults!;
    final String? store = args['store'] as String?;
    // Refused rather than ignored: a --dry-run that a web deploy did not
    // honour would ship while the person thought they were looking.
    final List<String> misplaced = <String>[
      for (final String option in store == null ? _storeOnly : _hostOnly)
        if (args.wasParsed(option)) '--$option',
    ];
    final String? provider = args['provider'] as String?;
    if (provider == 'firebase') {
      usageException('--provider firebase could mean two things. Use '
          '--provider firebase-hosting for Firebase Hosting, or '
          '--store firebase-app-distribution for Firebase App Distribution.');
    }
    if (provider != null && !_providers.contains(provider)) {
      usageException('"$provider" is not a provider. The providers are '
          '${_providers.join(', ')}.');
    }
    if (misplaced.isNotEmpty) {
      usageException(store == null
          ? '${misplaced.join(', ')} only applies with --store.'
          : '--store deploys an application to a store, so '
              '${misplaced.join(', ')} does not apply to it.');
    }
    if (store != null) {
      // No production build and no secrets gate: a store artifact is built
      // by dartvel build for its target, and the secrets a server resolves at
      // runtime are not in the binary a store receives.
      exitCode = await _store.run(
        store: store,
        dryRun: args['dry-run'] == true,
        artifact: args['artifact'] as String?,
        cloud: args['cloud'] == true,
        cloudToken: args['cloud-token'] as String?,
      );
      return;
    }

    final target = argResults?['target'] as String;
    final shouldBuild = argResults?['build'] as bool;
    final verify = argResults?['verify'] as bool;

    final environment = argResults?['environment'] as String? ?? 'production';

    Logger.log('🚀 Deploying Dartvel project...');

    // Before the build, because a build that succeeds and a deploy that then
    // ships without a secret is worse than stopping early. The spec states
    // this as a guarantee: a secret forgotten in a new environment fails the
    // deploy rather than the first request that needs it.
    if (!_secretsResolve(environment)) {
      exitCode = 1;
      return;
    }

    if (argResults?['functions'] == true) {
      await _writeFunctionPlan(
        target: argResults?['function-target'] as String? ?? 'container',
      );
      return;
    }

    if (shouldBuild) {
      Logger.log('📦 Building for production...');
      final buildResult = await _processRun(
        'dart',
        [
          'run',
          'dartvel_cli:dartvel',
          'build',
          '--platform',
          // The server is the web-server build, which writes the backend
          // executable. There is no build platform named server.
          target == 'server' ? 'web-server' : target,
        ],
        runInShell: true,
      );

      if (buildResult.exitCode != 0) {
        Logger.log('❌ Build failed');
        exitCode = buildResult.exitCode;
        return;
      }
    }

    bool deployed = false;
    switch (provider) {
      case 'firebase-hosting':
        deployed = await _deployFirebase(target);
        break;
      case 'vercel':
        deployed = await _deployVercel(target);
        break;
      case 'netlify':
        deployed = await _deployNetlify(target);
        break;
      case 'cloudflare':
        deployed = await _deployCloudflare(target);
        break;
      default:
        Logger.log('ℹ️  No provider specified. Build completed.');
        Logger.log('   Deploy manually from build/ directory');
        deployed = false;
    }

    if (verify && deployed) {
      Logger.log('✅ Deployment complete!');
    }
  }

  /// Writes one deployment artifact per backend function.
  ///
  /// Calling a cloud needs credentials this command does not have. Producing
  /// the artifacts does not, and that is the part that is wrong or right
  /// regardless of who runs it -- a handler name a provider rejects, a port
  /// the container never listens on, a manifest missing a function.
  Future<void> _writeFunctionPlan({required String target}) async {
    final root = Directory.current.path;
    final graph = await DartvelProjectGraph.build(
      root: root,
      pkgName: _packageName(root) ?? 'dartvel-app',
    );

    if (graph.functions.isEmpty) {
      Logger.log('No backend functions found. Nothing to deploy in function '
          'mode.');
      return;
    }

    final pubspec = File(p.join(root, 'pubspec.yaml'));
    final declared = pubspec.existsSync()
        ? dvParseSecretDeclarations(pubspec.readAsStringSync())
        : const <String, DVSecretDeclaration>{};

    final DVFunctionDeployPlan plan;
    try {
      plan = dvFunctionDeployPlan(
        functions: <DVDeployableFunction>[
          for (final fn in graph.functions)
            DVDeployableFunction(
              name: fn.name,
              method: fn.method,
              path: fn.path,
              source: fn.source,
            ),
        ],
        target: target,
        appName: _packageName(root) ?? 'dartvel-app',
        secretNames: declared.keys.toSet(),
      );
    } on ArgumentError catch (error) {
      Logger.error('   ${error.message}');
      exitCode = 1;
      return;
    }

    final outDir = Directory(p.join(root, 'build', 'deploy'))
      ..createSync(recursive: true);
    for (final entry in plan.files.entries) {
      File(p.join(outDir.path, entry.key)).writeAsStringSync(entry.value);
    }

    Logger.log('   ${plan.units.length} function(s) for $target:');
    for (final unit in plan.units) {
      Logger.log('     ${unit.function.method.padRight(6)} '
          '${unit.function.path}  →  ${unit.remoteName}');
    }
    Logger.log('   Wrote ${plan.files.length} file(s) to build/deploy/');
  }

  String? _packageName(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final match = RegExp(r'^name:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec.readAsStringSync());
    return match?.group(1);
  }

  /// Whether every secret this environment requires actually resolves.
  ///
  /// Asked of DVSecrets rather than answered here, so the gate and the
  /// process it gates cannot disagree about what counts as set. A value
  /// nothing supplies is one the deployed application would fail on at its
  /// first request.
  bool _secretsResolve(String environment) {
    final pubspec = File('pubspec.yaml');
    if (!pubspec.existsSync()) return true;

    final declared = dvParseSecretDeclarations(pubspec.readAsStringSync());
    if (declared.isEmpty) return true;

    final resolved = dvResolveSecrets(declared.keys);

    final problems = dvValidateEnvironment(
      declared: declared,
      environment: environment,
      resolved: resolved,
    );
    if (problems.isEmpty) return true;

    Logger.log('❌ $environment is missing ${problems.length} required '
        'secret(s):');
    for (final problem in problems) {
      Logger.error('   $problem');
    }
    return false;
  }

  Future<bool> _deployFirebase(String target) async {
    Logger.log('🔥 Deploying to Firebase...');

    final version =
        await _processRun('firebase', ['--version'], runInShell: true);
    if (version.exitCode != 0) {
      Logger.log(
        '❌ Firebase CLI not found. Install: npm install -g firebase-tools',
      );
      exitCode = version.exitCode;
      return false;
    }

    final result = await _processRun(
      'firebase',
      ['deploy', '--only', target == 'web' ? 'hosting' : 'functions'],
      runInShell: true,
    );
    _writeProcessResult(result);
    if (result.exitCode != 0) {
      Logger.log('❌ Firebase deployment failed');
      exitCode = result.exitCode;
      return false;
    }
    return true;
  }

  Future<bool> _deployVercel(String target) async {
    Logger.log('▲ Deploying to Vercel...');

    final result = await _processRun(
      'vercel',
      ['--prod'],
      runInShell: true,
    );
    _writeProcessResult(result);
    if (result.exitCode != 0) {
      Logger.log('❌ Vercel deployment failed');
      exitCode = result.exitCode;
      return false;
    }
    return true;
  }

  Future<bool> _deployNetlify(String target) async {
    Logger.log('🦙 Deploying to Netlify...');

    final result = await _processRun(
      'netlify',
      ['deploy', '--prod', '--dir=build/web'],
      runInShell: true,
    );
    _writeProcessResult(result);
    if (result.exitCode != 0) {
      Logger.log('❌ Netlify deployment failed');
      exitCode = result.exitCode;
      return false;
    }
    return true;
  }

  Future<bool> _deployCloudflare(String target) async {
    Logger.log('☁️  Deploying to Cloudflare Pages...');

    final result = await _processRun(
      'wrangler',
      ['pages', 'publish', 'build/web'],
      runInShell: true,
    );
    _writeProcessResult(result);
    if (result.exitCode != 0) {
      Logger.log('❌ Cloudflare Pages deployment failed');
      exitCode = result.exitCode;
      return false;
    }
    return true;
  }

  void _writeProcessResult(ProcessResult result) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  }
}
