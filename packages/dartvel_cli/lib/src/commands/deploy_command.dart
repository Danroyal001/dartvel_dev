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

    Logger.log('🚀 Deploying Dartvel project...');

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
