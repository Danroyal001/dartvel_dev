import 'package:path/path.dart' as p;
import '../graph/project_graph.dart';
import '../deploy/function_deploy.dart';
import '../secrets/secrets_analysis.dart';
import 'dart:io';
import 'package:args/command_runner.dart';
import '../utils/logger.dart';

typedef DeployProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

class DeployCommand extends Command<void> {
  DeployCommand({DeployProcessRun? processRun})
      : _processRun = processRun ?? Process.run {
    argParser
      ..addOption('target',
          abbr: 't',
          allowed: ['web', 'server', 'all'],
          defaultsTo: 'all',
          help: 'Deployment target')
      ..addOption('provider',
          allowed: ['firebase', 'vercel', 'netlify', 'cloudflare', 'custom'],
          help: 'Cloud provider')
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
      ..addFlag('verify', defaultsTo: true, help: 'Verify deployment');
  }

  final DeployProcessRun _processRun;

  @override
  final String name = 'deploy';

  @override
  String get description => 'Deploy to production (web/server).';

  @override
  Future<void> run() async {
    final target = argResults?['target'] as String;
    final provider = argResults?['provider'] as String?;
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
        ['run', 'dartvel_cli:dartvel', 'build', '--platform', target],
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
      case 'firebase':
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
  /// Resolution is the same order the runtime uses: the process environment,
  /// then .env for local development. A value present in neither is one the
  /// deployed application would fail on at its first request.
  bool _secretsResolve(String environment) {
    final pubspec = File('pubspec.yaml');
    if (!pubspec.existsSync()) return true;

    final declared = dvParseSecretDeclarations(pubspec.readAsStringSync());
    if (declared.isEmpty) return true;

    final resolved = <String>{
      for (final name in declared.keys)
        if (_resolves(name)) name,
    };

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

  bool _resolves(String name) {
    final fromEnvironment = Platform.environment[name];
    if (fromEnvironment != null && fromEnvironment.isNotEmpty) return true;

    final envFile = File('.env');
    if (!envFile.existsSync()) return false;
    for (final line in envFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;
      if (trimmed.substring(0, separator).trim() != name) continue;
      // An empty assignment is not a value. Treating `KEY=` as resolved is
      // how a deploy ships with a blank credential.
      return trimmed.substring(separator + 1).trim().isNotEmpty;
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
