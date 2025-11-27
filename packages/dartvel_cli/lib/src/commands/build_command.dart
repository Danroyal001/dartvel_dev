import 'dart:io';
import 'package:args/command_runner.dart';
import '../utils/logger.dart';

class BuildCommand extends Command<void> {
  @override
  final String name = 'build';

  @override
  String get description => 'Build for production (all platforms).';

  BuildCommand() {
    argParser
      ..addOption('platform',
          abbr: 'p',
          allowed: [
            'android',
            'ios',
            'web',
            'windows',
            'macos',
            'linux',
            'all'
          ],
          defaultsTo: 'all',
          help: 'Target platform')
      ..addFlag('release', defaultsTo: true, help: 'Build in release mode')
      ..addFlag('profile', defaultsTo: false, help: 'Build in profile mode')
      ..addOption('target', abbr: 't', help: 'Target entry point')
      ..addFlag('split-per-abi',
          defaultsTo: false, help: 'Split APKs per ABI (Android)')
      ..addOption('build-number', help: 'Build number')
      ..addOption('build-name', help: 'Build name/version')
      ..addFlag('obfuscate',
          defaultsTo: true, help: 'Obfuscate code (release only)')
      ..addFlag('tree-shake-icons', defaultsTo: true, help: 'Tree shake icons');
  }

  @override
  Future<void> run() async {
    final root = Directory.current.path;
    final platform = argResults?['platform'] as String;
    final isRelease = argResults?['release'] as bool;
    final isProfile = argResults?['profile'] as bool;
    final target = argResults?['target'] as String?;
    final splitPerAbi = argResults?['split-per-abi'] as bool;
    final buildNumber = argResults?['build-number'] as String?;
    final buildName = argResults?['build-name'] as String?;
    final obfuscate = argResults?['obfuscate'] as bool;
    final treeShakeIcons = argResults?['tree-shake-icons'] as bool;

    Logger.log('🔨 Building Dartvel project...');
    Logger.log('');

    // Run build_runner first
    Logger.log('📦 Running build_runner...');
    final buildRunnerResult = await Process.run(
      'dart',
      ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
      workingDirectory: root,
      runInShell: true,
    );

    if (buildRunnerResult.exitCode != 0) {
      Logger.log(
          '⚠️  build_runner failed or not configured (continuing anyway)');
    }

    // Generate routes
    Logger.log('📝 Generating routes...');
    final routesResult = await Process.run(
      'dart',
      ['run', 'dartvel_cli:dartvel', 'routes'],
      workingDirectory: root,
      runInShell: true,
    );

    if (routesResult.exitCode != 0) {
      Logger.log('❌ Route generation failed');
      exit(1);
    }

    final buildMode =
        isProfile ? '--profile' : (isRelease ? '--release' : '--debug');

    final platforms = platform == 'all'
        ? ['android', 'ios', 'web', 'windows', 'macos', 'linux']
        : [platform];

    for (final p in platforms) {
      await _buildPlatform(
        p,
        buildMode,
        target: target,
        splitPerAbi: splitPerAbi,
        buildNumber: buildNumber,
        buildName: buildName,
        obfuscate: obfuscate && isRelease,
        treeShakeIcons: treeShakeIcons,
      );
    }

    Logger.log('');
    Logger.log('✅ Build complete!');
  }

  Future<void> _buildPlatform(
    String platform,
    String buildMode, {
    String? target,
    bool splitPerAbi = false,
    String? buildNumber,
    String? buildName,
    bool obfuscate = false,
    bool treeShakeIcons = false,
  }) async {
    Logger.log('');
    Logger.log('🔨 Building for $platform...');

    final args = ['build', platform, buildMode];

    if (target != null) {
      args.addAll(['--target', target]);
    }

    if (buildNumber != null) {
      args.addAll(['--build-number', buildNumber]);
    }

    if (buildName != null) {
      args.addAll(['--build-name', buildName]);
    }

    if (obfuscate) {
      args.add('--obfuscate');
      args.addAll(['--split-debug-info', 'build/debug-info']);
    }

    if (treeShakeIcons) {
      args.add('--tree-shake-icons');
    }

    // Platform-specific flags
    switch (platform) {
      case 'android':
        if (splitPerAbi) {
          args.add('--split-per-abi');
        }
        break;
      case 'web':
        args.addAll(['--web-renderer', 'canvaskit']);
        break;
      case 'ios':
        // IPA export
        args.add('--no-codesign'); // For CI/CD
        break;
    }

    // Check if platform is available
    if (!await _isPlatformAvailable(platform)) {
      Logger.log(
          '⚠️  Platform $platform not available on this system. Skipping...');
      return;
    }

    final proc = await Process.start(
      'flutter',
      args,
      runInShell: true,
    );

    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));

    final exitCode = await proc.exitCode;

    if (exitCode == 0) {
      Logger.log('✅ $platform build successful');
    } else {
      Logger.log('❌ $platform build failed');
    }
  }

  Future<bool> _isPlatformAvailable(String platform) async {
    switch (platform) {
      case 'android':
        return true; // Usually available
      case 'ios':
      case 'macos':
        return Platform.isMacOS;
      case 'windows':
        return Platform.isWindows || Platform.isLinux; // Cross-compile possible
      case 'linux':
        return Platform.isLinux || Platform.isMacOS;
      case 'web':
        return true;
      default:
        return false;
    }
  }
}
