import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/build_runner.dart';
import '../utils/logger.dart';
import '../utils/toolchain.dart';

typedef BuildPreflight = Future<bool> Function(
  String platform, {
  bool? autoInstall,
});

typedef BuildProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

typedef BuildRunnerDependencyCheck = bool Function(String root);

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

/// Extension-host platforms built through host-specific Flutter embedders.
const extensionBuildPlatforms = <String>[
  'vscode',
];

/// The set built by `--platform all`. Distribution-image formats
/// (`sony-elinux-iso`/`sony-elinux-img`) are intentionally excluded; they are
/// explicit packaging targets, not part of a general build.
const allBuildPlatforms = <String>[
  ...flutterBuildPlatforms,
  ...embeddedBuildPlatforms,
  ...extensionBuildPlatforms,
];

/// Everything `dartvel build <platform>` accepts, positionally or via
/// `--platform`. Includes the distribution-image and alias target names, which
/// [normalizeBuildTarget] resolves to a base platform.
const buildPlatformArguments = <String>[
  ...allBuildPlatforms,
  'tpk',
  'sony-elinux-iso',
  'sony-elinux-img',
  'all',
];

/// Resolves which platform to build from the positional argument and the
/// `--platform` option.
///
/// The documented surface is positional (`dartvel build web`,
/// `dartvel build tizen`), so a positional argument wins. `--platform` remains
/// supported, and giving both is an error rather than a silent preference —
/// picking one would build something the user did not ask for.
///
/// Throws [FormatException] on an unknown or ambiguous request.
String resolveRequestedPlatform({
  required List<String> positional,
  required String optionValue,
  required bool optionWasParsed,
}) {
  if (positional.length > 1) {
    throw FormatException(
      'Expected at most one platform, got: ${positional.join(', ')}. '
      'Build one platform at a time, or use "all".',
    );
  }

  if (positional.isEmpty) return optionValue;

  final requested = positional.first;
  if (!buildPlatformArguments.contains(requested)) {
    throw FormatException(
      '"$requested" is not a known build platform. '
      'Allowed: ${buildPlatformArguments.join(', ')}.',
    );
  }

  if (optionWasParsed && optionValue != requested) {
    throw FormatException(
      'Conflicting platforms: "$requested" and --platform=$optionValue. '
      'Pass only one.',
    );
  }

  return requested;
}

/// Whether [platform] can be built from a [hostOs] (a `Platform.operatingSystem`
/// value such as `linux`, `macos`, or `windows`).
///
/// Flutter has no cross-compilation for desktop targets: a Windows desktop
/// build needs Windows and Visual Studio, a Linux desktop build needs Linux
/// with clang and GTK, and the Apple targets need macOS. Claiming otherwise
/// does not enable a build — it turns an unbuildable target into a hard
/// failure instead of a clean skip.
///
/// Web is host-independent. Android and its `fireos` variant are treated as
/// available everywhere because they depend on the Android SDK rather than the
/// host OS; a missing SDK surfaces as Flutter's own diagnostic.
bool isPlatformAvailableOn(String platform, String hostOs) {
  switch (platform) {
    case 'web':
    case 'android':
    case 'fireos':
      return true;
    case 'ios':
    case 'macos':
    case 'tvos':
      return hostOs == 'macos';
    case 'windows':
      return hostOs == 'windows';
    case 'linux':
      return hostOs == 'linux';
    default:
      return false;
  }
}

class BuildCommand extends Command<void> {
  @override
  final String name = 'build';

  @override
  String get description =>
      'Build for production. Pass a platform (dartvel build web) or omit it to '
      'build every available platform.';

  @override
  String get invocation => 'dartvel build [platform]';

  BuildCommand({
    BuildPreflight? preflight,
    BuildProcessRun? processRun,
    BuildRunnerDependencyCheck? hasBuildRunner,
  })  : _preflightOverride = preflight,
        _processRun = processRun ?? _defaultProcessRun,
        _hasBuildRunner = hasBuildRunner ?? hasBuildRunnerDependency {
    argParser
      ..addOption('platform',
          abbr: 'p',
          allowed: buildPlatformArguments,
          defaultsTo: 'all',
          help: 'Target platform (or pass it positionally)')
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
      ..addFlag('tree-shake-icons', defaultsTo: true, help: 'Tree shake icons')
      ..addFlag('auto-install',
          defaultsTo: null,
          help: 'Install missing build tools without prompting. Defaults to '
              'prompting when interactive, and to installing in CI. Use '
              '--no-auto-install to require a pre-provisioned toolchain.');
  }

  final BuildPreflight? _preflightOverride;
  final BuildProcessRun _processRun;
  final BuildRunnerDependencyCheck _hasBuildRunner;

  static Future<ProcessResult> _defaultProcessRun(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }

  @override
  Future<void> run() async {
    final root = Directory.current.path;

    final String rawPlatform;
    try {
      rawPlatform = resolveRequestedPlatform(
        positional: argResults?.rest ?? const <String>[],
        optionValue: argResults?['platform'] as String,
        optionWasParsed: argResults?.wasParsed('platform') ?? false,
      );
    } on FormatException catch (error) {
      Logger.log('❌ ${error.message}');
      exit(64); // EX_USAGE
    }

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
    final autoInstall = argResults?['auto-install'] as bool?;

    // A distribution-target name (`sony-elinux-iso`) resolves to a base
    // platform plus a format; an explicit `--format` overrides the default.
    final normalized = normalizeBuildTarget(rawPlatform);
    final platforms = normalized.platform == 'all'
        ? allBuildPlatforms
        : [normalized.platform];
    final format = formatFlag ?? normalized.format;

    Logger.log('🔨 Building Dartvel project...');
    Logger.log('');

    var skipped = 0;
    final buildablePlatforms = <String>[];
    final preflight = _preflightOverride ?? _preflight;
    for (final platform in platforms) {
      if (await preflight(platform, autoInstall: autoInstall)) {
        buildablePlatforms.add(platform);
      } else {
        skipped += 1;
      }
    }

    if (buildablePlatforms.isEmpty) {
      Logger.log('');
      Logger.log('✅ Build complete with $skipped skipped target(s).');
      return;
    }

    // Generate Dartvel routes/client/backend artifacts before optional user
    // build_runner builders so they can consume the generated client barrel.
    Logger.log('📝 Generating routes...');
    final routesResult = await _processRun(
      'dart',
      ['run', 'dartvel_cli:dartvel', 'routes'],
      workingDirectory: root,
      runInShell: true,
    );

    if (routesResult.exitCode != 0) {
      Logger.log('❌ Route generation failed');
      exit(1);
    }

    if (_hasBuildRunner(root)) {
      Logger.log('📦 Running build_runner...');
      final buildRunnerResult = await _processRun(
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

    final buildMode =
        isProfile ? '--profile' : (isRelease ? '--release' : '--debug');

    var failures = 0;
    for (final p in buildablePlatforms) {
      final result = embeddedBuildPlatforms.contains(p)
          ? await _buildEmbedded(
              p,
              buildMode,
              format: p == 'sony-elinux' ? (format ?? 'bundle') : null,
              deviceProfile: deviceProfile,
              arch: arch,
              target: target,
            )
          : extensionBuildPlatforms.contains(p)
              ? await _buildVSCodeExtension(root)
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
      environment: _buildEnvironment,
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
    final label =
        format == null || format == 'bundle' ? platform : '$platform ($format)';
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
      environment: _buildEnvironment,
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

  Future<_PlatformBuildResult> _buildVSCodeExtension(String root) async {
    Logger.log('');
    Logger.log('🔨 Building for vscode...');

    if (!hasPubDependency(root, 'flutter_vscode')) {
      Logger.log(
        '❌ vscode build requires a flutter_vscode dependency in pubspec.yaml.',
      );
      Logger.log(
        '   Add flutter_vscode, then run `dartvel build vscode` again.',
      );
      return _PlatformBuildResult.failed;
    }

    final commands = <({String executable, List<String> arguments})>[
      (
        executable: 'dart',
        arguments: <String>['run', 'flutter_vscode:generate_vscode_extension'],
      ),
      (executable: 'flutter', arguments: <String>['pub', 'get']),
      (executable: 'npm', arguments: <String>['install']),
      (executable: 'npm', arguments: <String>['run', 'compile']),
    ];

    for (final command in commands) {
      Logger.log(
        '   ${command.executable} ${command.arguments.join(' ')}',
      );
      final result = await _processRun(
        command.executable,
        command.arguments,
        workingDirectory: root,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        Logger.log('❌ vscode build failed');
        stdout.write(result.stdout);
        stderr.write(result.stderr);
        return _PlatformBuildResult.failed;
      }
    }

    final artifacts = validateVSCodeArtifacts(root);
    if (!artifacts.isValid) {
      Logger.log('❌ vscode build did not produce required artifacts.');
      for (final missing in artifacts.missing) {
        Logger.log('   Missing: $missing');
      }
      return _PlatformBuildResult.failed;
    }

    Logger.log('✅ vscode extension build successful');
    return _PlatformBuildResult.succeeded;
  }

  Future<bool> _isPlatformAvailable(String platform) async =>
      isPlatformAvailableOn(platform, Platform.operatingSystem);

  /// Directories added to PATH by an auto-install during this run.
  ///
  /// A tool installed a moment ago is not on the PATH this process inherited,
  /// so without this the build would install a toolchain and then immediately
  /// report it as missing.
  final _installedToolPaths = <String>[];

  /// The environment child processes should see, including anything installed
  /// during this run. Null when nothing was installed, so the child simply
  /// inherits.
  Map<String, String>? get _buildEnvironment {
    if (_installedToolPaths.isEmpty) return null;
    final separator = Platform.isWindows ? ';' : ':';
    final existing = Platform.environment['PATH'] ?? '';
    return <String, String>{
      ...Platform.environment,
      'PATH': <String>[..._installedToolPaths, existing].join(separator),
    };
  }

  /// Checks that this host can build [platform] and that its toolchain is
  /// present, installing what it can.
  ///
  /// Returns false when the target should be skipped. Ordering matters: host
  /// support is checked first, because offering to install Xcode on Linux
  /// would be nonsense.
  Future<bool> _preflight(String platform, {bool? autoInstall}) async {
    if (!isPlatformAvailableOn(platform, Platform.operatingSystem) &&
        !embeddedBuildPlatforms.contains(platform) &&
        !extensionBuildPlatforms.contains(platform)) {
      Logger.log('');
      Logger.log('🔨 Checking $platform...');
      Logger.log(
        '⚠️  ${Platform.operatingSystem} cannot build $platform. Skipping...',
      );
      return false;
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    var missing = missingRequirements(
      platform,
      isInstalled: isExecutableOnPath,
      home: home,
    );
    if (missing.isEmpty) return true;

    Logger.log('');
    Logger.log('🔎 $platform is missing ${missing.length} required tool(s):');
    for (final requirement in missing) {
      Logger.log('   • ${requirement.name} (${requirement.executable})');
    }

    final isCi = isCiEnvironment(Platform.environment);
    final decision = decideAutoInstall(
      hasMissing: true,
      isCi: isCi,
      autoInstallFlag: autoInstall,
    );

    var shouldInstall = false;
    switch (decision) {
      case AutoInstallDecision.nothingToDo:
        return true;
      case AutoInstallDecision.installWithoutPrompting:
        if (isCi && autoInstall == null) {
          Logger.log('🤖 CI detected; installing without prompting.');
        }
        shouldInstall = true;
      case AutoInstallDecision.prompt:
        shouldInstall = promptForInstall(missing);
      case AutoInstallDecision.declined:
        shouldInstall = false;
    }

    if (shouldInstall) {
      final installed = missing.toList();
      missing = await installRequirements(missing);
      // Make anything installed usable immediately, without a shell restart.
      for (final requirement in installed) {
        if (!missing.contains(requirement) && requirement.pathHint != null) {
          _installedToolPaths.add(requirement.pathHint!);
        }
      }
      if (missing.isEmpty) {
        Logger.log('✅ $platform toolchain ready.');
        return true;
      }
    }

    reportUnresolved(platform, missing);
    Logger.log('⚠️  Skipping $platform.');
    return false;
  }

  Future<bool> _isExecutableAvailable(String executable) async {
    try {
      final locator = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(locator, [executable],
          runInShell: true, environment: _buildEnvironment);
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

class VSCodeArtifactValidation {
  const VSCodeArtifactValidation({
    required this.hasExtensionHostOutput,
    required this.hasFlutterBootstrap,
    required this.hasFlutterAssets,
  });

  final bool hasExtensionHostOutput;
  final bool hasFlutterBootstrap;
  final bool hasFlutterAssets;

  bool get isValid =>
      hasExtensionHostOutput && hasFlutterBootstrap && hasFlutterAssets;

  List<String> get missing {
    final missing = <String>[];
    if (!hasExtensionHostOutput) {
      missing.add('compiled extension host JavaScript under out/ or dist/');
    }
    if (!hasFlutterBootstrap) {
      missing.add('build/web/flutter_bootstrap.js');
    }
    if (!hasFlutterAssets) {
      missing.add('build/web/assets/');
    }
    return List<String>.unmodifiable(missing);
  }
}

VSCodeArtifactValidation validateVSCodeArtifacts(String root) {
  return VSCodeArtifactValidation(
    hasExtensionHostOutput: _containsJavaScriptFile(
          Directory(p.join(root, 'out')),
        ) ||
        _containsJavaScriptFile(Directory(p.join(root, 'dist'))),
    hasFlutterBootstrap:
        File(p.join(root, 'build', 'web', 'flutter_bootstrap.js')).existsSync(),
    hasFlutterAssets:
        Directory(p.join(root, 'build', 'web', 'assets')).existsSync(),
  );
}

bool _containsJavaScriptFile(Directory directory) {
  if (!directory.existsSync()) return false;
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .any((file) => file.path.endsWith('.js'));
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
      return EmbeddedBuildPlan(
          'flutter-tizen', List<String>.unmodifiable(args));
    case 'sony-elinux':
      final args = <String>[
        'build',
        'elinux',
        buildMode,
        '--target-arch',
        arch
      ];
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
