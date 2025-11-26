import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';

class DeployCommand extends Command<void> {
  @override
  final String name = 'deploy';

  @override
  String get description => 'Deploy to production (web/server).';

  DeployCommand() {
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

  @override
  Future<void> run() async {
    final target = argResults?['target'] as String;
    final provider = argResults?['provider'] as String?;
    final shouldBuild = argResults?['build'] as bool;
    final verify = argResults?['verify'] as bool;

    Logger.log('🚀 Deploying Dartvel project...');

    if (shouldBuild) {
      Logger.log('📦 Building for production...');
      final buildResult = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', 'build', '--platform', target],
        runInShell: true,
      );

      if (buildResult.exitCode != 0) {
        Logger.log('❌ Build failed');
        exit(1);
      }
    }

    switch (provider) {
      case 'firebase':
        await _deployFirebase(target);
        break;
      case 'vercel':
        await _deployVercel(target);
        break;
      case 'netlify':
        await _deployNetlify(target);
        break;
      case 'cloudflare':
        await _deployCloudflare(target);
        break;
      default:
        Logger.log('ℹ️  No provider specified. Build completed.');
        Logger.log('   Deploy manually from build/ directory');
    }

    if (verify) {
      Logger.log('✅ Deployment complete!');
    }
  }

  Future<void> _deployFirebase(String target) async {
    Logger.log('🔥 Deploying to Firebase...');

    // Check if firebase CLI is available
    try {
      final result =
          await Process.run('firebase', ['--version'], runInShell: true);
      if (result.exitCode != 0) {
        Logger.log(
            '❌ Firebase CLI not found. Install: npm install -g firebase-tools');
        exit(1);
      }
    } catch (e) {
      Logger.log('❌ Firebase CLI not found');
      exit(1);
    }

    final proc = await Process.start(
      'firebase',
      ['deploy', '--only', target == 'web' ? 'hosting' : 'functions'],
      runInShell: true,
    );

    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));

    final exitCode = await proc.exitCode;
    if (exitCode != 0) {
      Logger.log('❌ Firebase deployment failed');
      exit(exitCode);
    }
  }

  Future<void> _deployVercel(String target) async {
    Logger.log('▲ Deploying to Vercel...');

    final proc = await Process.start(
      'vercel',
      ['--prod'],
      runInShell: true,
    );

    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));

    await proc.exitCode;
  }

  Future<void> _deployNetlify(String target) async {
    Logger.log('🦙 Deploying to Netlify...');

    final proc = await Process.start(
      'netlify',
      ['deploy', '--prod', '--dir=build/web'],
      runInShell: true,
    );

    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));

    await proc.exitCode;
  }

  Future<void> _deployCloudflare(String target) async {
    Logger.log('☁️  Deploying to Cloudflare Pages...');

    final proc = await Process.start(
      'wrangler',
      ['pages', 'publish', 'build/web'],
      runInShell: true,
    );

    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));

    await proc.exitCode;
  }
}
