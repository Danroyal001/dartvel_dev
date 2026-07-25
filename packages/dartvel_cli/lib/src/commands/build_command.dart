import 'dart:io';
import 'package:args/command_runner.dart';
import '../utils/build_runner.dart';
import '../utils/logger.dart';

/// Platforms built with the standard `flutter build` executable.
const flutterBuildPlatforms = <String>[
  'android',
  'ios',
  'web',
  'windows',
  'macos',
  'linux',
  'tvos',
  'fireos',
];

/// Embedded/television platforms built through dedicated Flutter embedders:
/// `flutter-tizen` (Samsung), `flutter-elinux` (Sony), and `flutter-webos`
/// (LG).
const embeddedBuildPlatforms = <String>[
  'tizen',
  'sony-elinux',
  'webos',
];

/// The set built by `--platform all`. Distribution-image formats
/// (`sony-elinux-iso`/`sony-elinux-img`) are intentionally excluded; they are
/// explicit packaging targets, not part of a general build.
const allBuildPlatforms = <String>[
  ...flutterBuildPlatforms,
  ...embeddedBuildPlatforms,
];

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
            ...flutterBuildPlatforms,
            ...embeddedBuildPlatforms,
            'tpk',
            'sony-elinux-iso',
            'sony-elinux-img',
            'all',
          ],
          defaultsTo: 'all',
          help: 'Target platform')
      ..addFlag('release', defaultsTo: true, help: 'Build in release mode')
      ..addFlag('profile', defaultsTo: false, help: 'Build in profile mode')
      ..addOption('target', abbr: 't', help: 'Target entry point')
      ..addOption('format',
          allowed: ['bundle', 'iso', 'img'],
          help: 'Sony eLinux output format (bundle | iso | img)')
      ..addOption('device-profile',
          help: 'Named embedded device profile from pubspec.yaml')
      ..addOption('arch',
          allowed: ['arm', 'arm64', 'x64'],
          defaultsTo: 'arm64',
          help: 'Target architecture for embedded builds')
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
    final rawPlatform = argResults?['platform'] as String;
    final isRelease = argResults?['release'] as bool;
    final isProfile = argResults?['profile'] as bool;
    final target = argResults?['target'] as String?;
    final formatFlag = argResults?['format'] as String?;
    final deviceProfile = argResults?['device-profile'] as String?;
    final arch = argResults?['arch'] as String;
    final splitPerAbi = argResults?['split-per-abi'] as bool;
    final buildNumber = argResults?['build-number'] as String?;
    final buildName = argResults?['build-name'] as String?;
    final obfuscate = argResults?['obfuscate'] as bool;
    final treeShakeIcons = argResults?['tree-shake-icons'] as bool;

    Logger.log('🔨 Building Dartvel project...');
    Logger.log('');

    // Run optional user-configured builders after Dartvel's own generation.
    if (hasBuildRunnerDependency(root)) {
      Logger.log('📦 Running build_runner...');
      final buildRunnerResult = await Process.run(
        'dart',
        ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
        workingDirectory: root,
        runInShell: true,
      );

      if (buildRunnerResult.exitCode != 0) {
        Logger.log('⚠️  build_runner failed');
      }
    } else {
      Logger.log('📦 No build_runner dependency declared; skipping build.');
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

    // A distribution-target name (`sony-elinux-iso`) resolves to a base
    // platform plus a format; an explicit `--format` overrides the default.
    final normalized = normalizeBuildTarget(rawPlatform);
    final platforms =
        normalized.platform == 'all' ? allBuildPlatforms : [normalized.platform];
    final format = formatFlag ?? normalized.format;

    var failures = 0;
    var skipped = 0;
    for (final p in platforms) {
      final result = embeddedBuildPlatforms.contains(p)
          ? await _buildEmbedded(
              p,
              buildMode,
              format: p == 'sony-elinux' ? (format ?? 'bundle') : null,
              deviceProfile: deviceProfile,
              arch: arch,
              target: target,
            )
          : await _buildPlatform(
              p,
              buildMode,
              target: target,
              splitPerAbi: splitPerAbi,
              buildNumber: buildNumber,
              buildName: buildName,
              obfuscate: obfuscate && isRelease,
              treeShakeIcons: treeShakeIcons,
            );
      switch (result) {
        case _PlatformBuildResult.succeeded:
          break;
        case _PlatformBuildResult.skipped:
          skipped += 1;
        case _PlatformBuildResult.failed:
          failures += 1;
      }
    }

    Logger.log('');
    if (failures > 0) {
      Logger.log(
        '❌ Build completed with $failures failed target(s) and $skipped skipped target(s).',
      );
      exitCode = 1;
      return;
    }
    if (skipped > 0) {
      Logger.log('✅ Build complete with $skipped skipped target(s).');
      return;
    }
    Logger.log('✅ Build complete!');
  }

  Future<_PlatformBuildResult> _buildPlatform(
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

    final args = resolveFlutterBuildArguments(
      platform: platform,
      buildMode: buildMode,
      target: target,
      splitPerAbi: splitPerAbi,
      buildNumber: buildNumber,
      buildName: buildName,
      obfuscate: obfuscate,
      treeShakeIcons: treeShakeIcons,
    );

    // Check if platform is available
    if (!await _isPlatformAvailable(platform)) {
      Logger.log(
          '⚠️  Platform $platform not available on this system. Skipping...');
      return _PlatformBuildResult.skipped;
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
      return _PlatformBuildResult.succeeded;
    } else {
      Logger.log('❌ $platform build failed');
      return _PlatformBuildResult.failed;
    }
  }

  /// Builds embedded/television targets through their dedicated Flutter
  /// embedders (`flutter-tizen`, `flutter-elinux`). The bundle is always built
  /// first; `iso`/`img` are distribution-packaging steps layered on top of the
  /// bundle and require the configured Sony eLinux image toolchain.
  Future<_PlatformBuildResult> _buildEmbedded(
    String platform,
    String buildMode, {
    String? format,
    String? deviceProfile,
    required String arch,
    String? target,
  }) async {
    final label = format == null || format == 'bundle'
        ? platform
        : '$platform ($format)';
    Logger.log('');
    Logger.log('🔨 Building for $label...');

    final plan = resolveEmbeddedBuildPlan(
      platform: platform,
      buildMode: buildMode,
      arch: arch,
      deviceProfile: deviceProfile,
      target: target,
    );
    if (plan == null) {
      Logger.log('❌ Unsupported embedded platform: $platform');
      return _PlatformBuildResult.failed;
    }

    if (!await _isExecutableAvailable(plan.executable)) {
      Logger.log(
        '⚠️  ${plan.executable} not found on PATH. '
        'Install the $platform embedder to build this target. Skipping...',
      );
      return _PlatformBuildResult.skipped;
    }

    final proc = await Process.start(
      plan.executable,
      plan.arguments,
      runInShell: true,
    );
    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));
    final exitCode = await proc.exitCode;

    if (exitCode != 0) {
      Logger.log('❌ $label build failed');
      return _PlatformBuildResult.failed;
    }
    Logger.log('✅ $platform bundle build successful');

    // Distribution-image packaging is a separate step. Dartvel does not bundle
    // a system-imaging toolchain, so report honestly instead of emitting a fake
    // artifact.
    if (format == 'iso' || format == 'img') {
      Logger.log(
        '⚠️  DV-ELINUX-IMG: $platform $format packaging requires the configured '
        'Sony eLinux image toolchain, which is not available in this '
        'environment. Bundle built; image assembly skipped.',
      );
      return _PlatformBuildResult.skipped;
    }
    return _PlatformBuildResult.succeeded;
  }

  Future<bool> _isPlatformAvailable(String platform) async {
    switch (platform) {
      case 'android':
      case 'fireos':
        return true; // Usually available
      case 'ios':
      case 'macos':
      case 'tvos':
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

  Future<bool> _isExecutableAvailable(String executable) async {
    try {
      final locator = Platform.isWindows ? 'where' : 'which';
      final result =
          await Process.run(locator, [executable], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

enum _PlatformBuildResult { succeeded, failed, skipped }

/// Splits a distribution-format target name into a base platform plus an output
/// format. Non-distribution targets pass through unchanged with a null format.
({String platform, String? format}) normalizeBuildTarget(String target) {
  return switch (target) {
    'sony-elinux-iso' => (platform: 'sony-elinux', format: 'iso'),
    'sony-elinux-img' => (platform: 'sony-elinux', format: 'img'),
    // `tpk` is Tizen's native package format; alias it to the tizen target.
    'tpk' => (platform: 'tizen', format: null),
    _ => (platform: target, format: null),
  };
}

/// Describes how an embedded/television platform is built: which embedder
/// executable to invoke and with which arguments.
class EmbeddedBuildPlan {
  const EmbeddedBuildPlan(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

/// Resolves the embedder invocation for an embedded platform, or `null` if the
/// platform is not an embedded target. `iso`/`img` packaging builds the same
/// bundle; the packaging step is handled separately by the caller.
EmbeddedBuildPlan? resolveEmbeddedBuildPlan({
  required String platform,
  required String buildMode,
  required String arch,
  String? deviceProfile,
  String? target,
}) {
  switch (platform) {
    case 'tizen':
      final args = <String>['build', 'tpk', buildMode];
      if (target != null) args.addAll(<String>['--target', target]);
      if (deviceProfile != null) {
        args.addAll(<String>['--device-profile', deviceProfile]);
      }
      return EmbeddedBuildPlan('flutter-tizen', List<String>.unmodifiable(args));
    case 'sony-elinux':
      final args = <String>['build', 'elinux', buildMode, '--target-arch', arch];
      if (target != null) args.addAll(<String>['--target', target]);
      if (deviceProfile != null) {
        args.addAll(<String>['--device-profile', deviceProfile]);
      }
      return EmbeddedBuildPlan(
          'flutter-elinux', List<String>.unmodifiable(args));
    case 'webos':
      final args = <String>['build', 'webos', buildMode];
      if (target != null) args.addAll(<String>['--target', target]);
      if (deviceProfile != null) {
        args.addAll(<String>['--device-profile', deviceProfile]);
      }
      return EmbeddedBuildPlan(
          'flutter-webos', List<String>.unmodifiable(args));
    default:
      return null;
  }
}

List<String> resolveFlutterBuildArguments({
  required String platform,
  required String buildMode,
  String? target,
  bool splitPerAbi = false,
  String? buildNumber,
  String? buildName,
  bool obfuscate = false,
  bool treeShakeIcons = false,
}) {
  final command = switch (platform) {
    'android' || 'fireos' => 'apk',
    'tvos' => 'ios',
    _ => platform,
  };
  final args = <String>['build', command, buildMode];

  if (target != null) {
    args.addAll(<String>['--target', target]);
  }

  if (buildNumber != null) {
    args.addAll(<String>['--build-number', buildNumber]);
  }

  if (buildName != null) {
    args.addAll(<String>['--build-name', buildName]);
  }

  if (obfuscate && command != 'web') {
    args.add('--obfuscate');
    args.addAll(<String>['--split-debug-info', 'build/debug-info']);
  }

  if (treeShakeIcons) {
    args.add('--tree-shake-icons');
  }

  if (platform == 'android' && splitPerAbi) {
    args.add('--split-per-abi');
  }
  if (platform == 'ios' || platform == 'tvos') {
    args.add('--no-codesign');
  }

  return List<String>.unmodifiable(args);
}
