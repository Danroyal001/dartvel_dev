import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../build/browser_extension.dart';
import '../build/elinux_bundle.dart';
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
  'fireos',
];

/// The Fuchsia embedder's script for building an arbitrary Flutter package.
///

/// Embedded/television platforms built through dedicated Flutter embedders:
/// `flutter-tizen` (Samsung), `flutter-elinux` (Sony), `flutter-webos` (LG),
/// `flutter-tvos` (community, Apple TV), and Fuchsia's out-of-tree embedder.
///
/// tvOS lives here and not in [flutterBuildPlatforms]: Apple ships no tvOS
/// Flutter embedder, and `flutter build ios` produces an iPhone app whatever
/// the caller names it.
const embeddedBuildPlatforms = <String>[
  'tizen',
  'sony-elinux',
  'webos',
  'tvos',
  'fuchsia',
];

/// Extension-host platforms built through host-specific Flutter embedders.
const extensionBuildPlatforms = <String>[
  'vscode',
];

/// Browser extension bundles. These are Flutter web output plus a generated
/// manifest and background script, not a separate embedder.
const browserExtensionBuildPlatforms = <String>[
  'chrome-extension',
  'firefox-extension',
];

/// The set built by `--platform all`. Distribution-image formats
/// (`sony-elinux-iso`/`sony-elinux-img`) are intentionally excluded; they are
/// explicit packaging targets, not part of a general build.
const allBuildPlatforms = <String>[
  ...flutterBuildPlatforms,
  ...embeddedBuildPlatforms,
  ...extensionBuildPlatforms,
  ...browserExtensionBuildPlatforms,
];

/// Everything `dartvel build <platform>` accepts, positionally or via
/// `--platform`. Includes the distribution-image and alias target names, which
/// [normalizeBuildTarget] resolves to a base platform.
const buildPlatformArguments = <String>[
  ...allBuildPlatforms,
  'tpk',
  'sony-elinux-iso',
  'sony-elinux-img',
  ...terminalBuildTargets,
  'all',
];

/// Targets that can render into a terminal.
///
/// Desktop platforms and Fuchsia. The suffix is refused elsewhere rather than
/// accepted and ignored, because building something other than what the name
/// promises is worse than refusing the name.
///
/// Android is refused for a reason worth writing down, since the obvious
/// objection is that Termux exists. It does, but a `linux-cli` binary cannot
/// run in it: Termux is Android userland, so it uses bionic rather than glibc
/// and has no `/lib/ld-linux-aarch64.so.1` to load a `linux-gnu` binary with.
/// Supporting it would need an Android-triple build and a Flutter engine that
/// runs without an Activity — a project, not a suffix.
const terminalCapablePlatforms = <String>[
  'linux',
  'windows',
  'macos',
  'fuchsia',
];

/// `linux-cli`, `linux-tui`, and the same for every terminal-capable platform.
///
/// `-tui` says what it does and `-cli` says where it runs; they resolve
/// identically.
const terminalBuildTargets = <String>[
  'linux-cli', 'linux-tui',
  'windows-cli', 'windows-tui',
  'macos-cli', 'macos-tui',
  'fuchsia-cli', 'fuchsia-tui',
];

/// How a terminal build is actually produced.
///
/// This exists because `dartvel build linux-cli` resolved its target
/// correctly, printed "Rendering: terminal only", then ran
/// `flutter build linux` and reported success — shipping a GUI binary under a
/// name that promises no GUI. The resolution tests all passed throughout,
/// because they asserted what the target was called rather than what building
/// it did.
///
/// `flt` is not a Flutter CLI wrapper like `flutter-tizen` or `flutter-webos`.
/// It uses Flutter's Custom Embedder API from Rust and renders through the
/// Kitty graphics protocol, so no combination of flags to `flutter build`
/// produces a terminal binary. There is no fallback to degrade to.
class TerminalBuildPlan {
  const TerminalBuildPlan({
    required this.platform,
    required this.toolchain,
    required this.arguments,
  });

  /// The base platform this renders on — `linux`, not `linux-cli`.
  final String platform;

  /// The executable that performs the build, looked up on PATH.
  final String toolchain;

  final List<String> arguments;

  /// Whether this plan would run a GUI desktop build.
  ///
  /// Computed from the command rather than declared, so that an implementation
  /// which later resolves to `flutter build linux` fails the assertion instead
  /// of satisfying it by construction.
  bool get usesFlutterDesktopBuild =>
      toolchain == 'flutter' &&
      arguments.length >= 2 &&
      arguments.first == 'build' &&
      const <String>{'linux', 'windows', 'macos'}.contains(arguments[1]);
}

/// The plan for rendering [platform] into a terminal.
///
/// [platform] is the base platform, so `linux` rather than `linux-cli`.
TerminalBuildPlan terminalBuildPlan(
  String platform, {
  String? buildMode,
  String? toolchainHome,
}) {
  final root = dartvelToolchainRoot(toolchainHome ?? resolveToolchainHome());
  return TerminalBuildPlan(
    platform: platform,
    // The fork, not upstream: upstream `flt` runs an app in development and
    // does not produce a distributable binary, and supplying that is the
    // fork's reason to exist.
    //
    // An absolute path under the toolchain root rather than a bare name,
    // because that is where Dartvel installs it — and a plan naming something
    // nothing installs is the Fuchsia defect.
    toolchain: '$root/dartvel_flt/bin/dartvel-flt',
    arguments: <String>[
      'build',
      platform,
      if (buildMode != null) buildMode,
    ],
  );
}

/// Whether a terminal build can proceed, and what to say when it cannot.
class TerminalBuildOutcome {
  const TerminalBuildOutcome({required this.shouldRun, required this.message});

  final bool shouldRun;
  final String message;
}

/// Decides what to do about a terminal build for [plan].
///
/// Separated from the loop that runs it so the decision can be asserted on
/// without spawning a build. The rule it implements is the Build Toolchain
/// Rule: check tooling before doing work, and skip cleanly rather than start
/// something that cannot finish.
///
/// It deliberately does not name `flutter build` as an alternative. That is
/// what the code used to do silently, and suggesting it would be recommending
/// the bug.
TerminalBuildOutcome terminalBuildOutcome(
  TerminalBuildPlan plan, {
  required bool toolchainPresent,
}) {
  if (toolchainPresent) {
    return TerminalBuildOutcome(
      shouldRun: true,
      message: 'Building ${plan.platform} for the terminal with '
          '${plan.toolchain}.',
    );
  }
  return TerminalBuildOutcome(
    shouldRun: false,
    message: 'Skipping ${plan.platform}-cli: ${plan.toolchain} is not '
        'installed. Terminal rendering uses the dartvel_flt embedder, which '
        'renders through the Kitty graphics protocol from Rust — there is no '
        'way to produce a terminal binary from the desktop toolchain, so this '
        'target is skipped rather than substituted.',
  );
}

/// A rendering backend linked into a build.
///
/// Which of these a binary contains is decided at build time and never at
/// startup: resolving it on launch would mean every application shipped every
/// backend, and paid for modes most of them never use.
enum DVRenderBackend { gui, terminal }

/// Whether `pubspec.yaml` opts this application into terminal rendering.
///
/// `dartvel.terminal: true`, and nothing else. An application that says
/// nothing gets no terminal backend, which is the rule the whole feature rests
/// on: a rendering backend costs binary size for every user who never reaches
/// it.
///
/// A value that is neither boolean is refused rather than guessed. `yes`, `1`
/// and a nested map are all plausible things to write and all ambiguous;
/// guessing one way links a backend nobody asked for, and guessing the other
/// silently ignores a request that was made.
bool readTerminalOptIn(YamlMap? pubspec) {
  final dartvel = pubspec?['dartvel'];
  if (dartvel is! YamlMap) return false;
  if (!dartvel.containsKey('terminal')) return false;

  final value = dartvel['terminal'];
  if (value is bool) return value;
  throw FormatException(
    'dartvel.terminal must be true or false, not "$value". Terminal '
    'rendering is linked into a build or it is not; there is no third state.',
  );
}

/// The backends a build links, from the target's format and the application's
/// opt-in.
///
/// The whole rule, and both halves of it are exclusions:
///
/// | build | gui | terminal |
/// |---|---|---|
/// | plain desktop | yes | no |
/// | desktop + `dartvel.terminal: true` | yes | yes |
/// | `-cli` / `-tui` | no | yes |
///
/// A terminal build contains no GUI backend at all — not a window that stays
/// closed. A plain desktop build contains no terminal code. Nothing gives an
/// application a backend it did not ask for.
Set<DVRenderBackend> resolveRenderBackends({
  required String? format,
  required bool terminalOptIn,
}) {
  // Asking for a terminal build is the stronger statement: the pubspec key
  // enables a mode, it does not add one back.
  if (format == 'tui') return const <DVRenderBackend>{DVRenderBackend.terminal};
  return terminalOptIn
      ? const <DVRenderBackend>{DVRenderBackend.gui, DVRenderBackend.terminal}
      : const <DVRenderBackend>{DVRenderBackend.gui};
}

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
/// The host OS an embedded target's embedder requires, or null when it runs
/// anywhere.
///
/// Separate from [isPlatformAvailableOn], which answers whether plain
/// `flutter build` can serve a target — embedded targets never can. An
/// embedder can still be host-constrained: Fuchsia's states it builds on Linux
/// only, not macOS or Windows natively.
String? embeddedHostRequirement(String platform) => switch (platform) {
      'fuchsia' => 'linux',
      _ => null,
    };

bool isPlatformAvailableOn(String platform, String hostOs) {
  switch (platform) {
    case 'web':
    case 'android':
    case 'fireos':
      return true;
    // A browser extension is web output; any host that can build web can
    // build it.
    case 'chrome-extension':
    case 'firefox-extension':
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
    bool Function(String)? onPath,
  })  : _preflightOverride = preflight,
        _onPathOverride = onPath,
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
      ..addOption('build-timeout',
          help: 'Minutes before a stalled build is killed (0 disables). '
              'A build that stops producing output is the failure mode worth '
              'guarding: it looks identical to a slow one and costs far more.')
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
  final bool Function(String)? _onPathOverride;

  /// Overridable so a test never depends on what is installed on the machine
  /// running it — the mistake that let a Fuchsia test assert an executable
  /// name for weeks while nothing by that name was ever present.
  bool _isOnPath(String executable) =>
      (_onPathOverride ?? isExecutableOnPath)(executable);
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
    final archExplicit = argResults?.wasParsed('arch') ?? false;
    final splitPerAbi = argResults?['split-per-abi'] as bool;
    final buildNumber = argResults?['build-number'] as String?;
    final buildName = argResults?['build-name'] as String?;
    final obfuscate = argResults?['obfuscate'] as bool;
    final treeShakeIcons = argResults?['tree-shake-icons'] as bool;
    final autoInstall = argResults?['auto-install'] as bool?;
    final buildTimeout =
        parseBuildTimeout(argResults?['build-timeout'] as String?);

    // A distribution-target name (`sony-elinux-iso`) resolves to a base
    // platform plus a format; an explicit `--format` overrides the default.
    final normalized = normalizeBuildTarget(rawPlatform);
    final platforms = normalized.platform == 'all'
        ? allBuildPlatforms
        : [normalized.platform];
    final format = formatFlag ?? normalized.format;

    // Resolved once, before any target runs, so a mistyped opt-in is reported
    // before minutes of generation rather than after.
    final Set<DVRenderBackend> renderBackends;
    try {
      renderBackends = resolveRenderBackends(
        format: format,
        terminalOptIn: readTerminalOptIn(readPubspecYaml(root)),
      );
    } on FormatException catch (error) {
      Logger.log('❌ ${error.message}');
      exit(78); // EX_CONFIG
    }

    Logger.log('🔨 Building Dartvel project...');
    if (renderBackends.contains(DVRenderBackend.terminal)) {
      Logger.log(
        renderBackends.contains(DVRenderBackend.gui)
            ? '   Rendering: GUI and terminal.'
            : '   Rendering: terminal only.',
      );
    }
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
    Logger.log('📝 Generating Dartvel artifacts...');
    final routesResult = await _processRun(
      'dart',
      ['run', 'dartvel_cli:dartvel', 'routes'],
      workingDirectory: root,
      runInShell: true,
    );

    if (routesResult.exitCode != 0) {
      Logger.log('❌ Dartvel artifact generation failed');
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

    // A terminal-only build must not reach the desktop branch below. It used
    // to, which is how `dartvel build linux-cli` produced a GUI binary and
    // called it a success.
    final terminalOnly = renderBackends.contains(DVRenderBackend.terminal) &&
        !renderBackends.contains(DVRenderBackend.gui);

    var failures = 0;
    for (final p in buildablePlatforms) {
      if (terminalOnly) {
        final plan = terminalBuildPlan(p, buildMode: buildMode);
        final outcome = terminalBuildOutcome(
          plan,
          toolchainPresent: _isOnPath(plan.toolchain),
        );
        Logger.log(outcome.shouldRun
            ? '🔨 ${outcome.message}'
            : '⏭️  ${outcome.message}');
        if (!outcome.shouldRun) {
          skipped += 1;
          continue;
        }
        final result = await _buildTerminal(plan, timeout: buildTimeout);
        switch (result) {
          case _PlatformBuildResult.succeeded:
            break;
          case _PlatformBuildResult.skipped:
            skipped += 1;
          case _PlatformBuildResult.failed:
            failures += 1;
        }
        continue;
      }

      if (p == 'sony-elinux') {
        final result = await _buildELinuxBundle(
          root: root,
          arch: resolveEmbeddedArch(p, arch, explicit: archExplicit),
          isRelease: isRelease,
          buildMode: buildMode,
          timeout: buildTimeout,
          target: target,
        );
        switch (result) {
          case _PlatformBuildResult.succeeded:
            break;
          case _PlatformBuildResult.skipped:
            skipped += 1;
          case _PlatformBuildResult.failed:
            failures += 1;
        }
        continue;
      }

      final result = embeddedBuildPlatforms.contains(p)
          ? await _buildEmbedded(
              p,
              buildMode,
              timeout: buildTimeout,
              format: p == 'sony-elinux' ? (format ?? 'bundle') : null,
              deviceProfile: deviceProfile,
              arch: resolveEmbeddedArch(p, arch, explicit: archExplicit),
              target: target,
            )
          : browserExtensionBuildPlatforms.contains(p)
              ? await _buildBrowserExtension(p, buildMode, root, target: target)
              : extensionBuildPlatforms.contains(p)
                  ? await _buildVSCodeExtension(root)
                  : await _buildPlatform(
                      p,
                      buildMode,
                      timeout: buildTimeout,
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
    Duration? timeout,
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

    // Printed before starting, so a log that ends here says exactly what was
    // invoked. A macOS build once stopped at this point and produced nothing
    // for 41 minutes; the log could not even show the command.
    Logger.log('   flutter ${args.join(' ')}');

    final proc = await Process.start(
      'flutter',
      args,
      runInShell: true,
      environment: _buildEnvironment,
    );

    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));

    final exitCode = await _awaitBuild(
      proc,
      timeout: timeout,
      description: 'flutter build $platform',
    );
    if (exitCode == null) return _PlatformBuildResult.failed;

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
  Future<_PlatformBuildResult> _buildTerminal(
    TerminalBuildPlan plan, {
    required Duration? timeout,
  }) async {
    final command = '${plan.toolchain} ${plan.arguments.join(' ')}';
    Logger.log('   $command');
    final process = await Process.start(
      plan.toolchain,
      plan.arguments,
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode =
        await _awaitBuild(process, timeout: timeout, description: command);
    if (exitCode == null) return _PlatformBuildResult.failed;
    if (exitCode != 0) {
      Logger.log('❌ ${plan.platform} terminal build failed (exit $exitCode)');
      return _PlatformBuildResult.failed;
    }
    Logger.log('✅ ${plan.platform} terminal build successful');
    return _PlatformBuildResult.succeeded;
  }

  /// Assembles an eLinux release bundle from the desktop release build.
  ///
  /// See build/elinux_bundle.dart for why this does not go through
  /// flutter-elinux: that tool is pinned to Flutter 3.29.3, fifteen minor
  /// versions behind Dartvel's floor, and a release bundle does not need it.
  Future<_PlatformBuildResult> _buildELinuxBundle({
    required String root,
    required String arch,
    required bool isRelease,
    required String buildMode,
    required Duration? timeout,
    required String? target,
  }) async {
    if (!isRelease) {
      // Refused rather than approximated. A debug desktop bundle carries
      // kernel_blob.bin and no libapp.so, and the only engine obtainable
      // without building one is the release build, which has no interpreter to
      // run kernel with — so the result would look complete and never start.
      Logger.log('⏭️  Skipping sony-elinux: only release bundles can be '
          'assembled. Debug and profile need an engine built for those modes, '
          'which is not published as a standalone embedder artifact.');
      return _PlatformBuildResult.skipped;
    }

    final artifacts =
        '${dartvelToolchainRoot(resolveToolchainHome())}/dartvel_elinux/artifacts';
    final backend = ELinuxBackend.wayland;
    if (!File('$artifacts/${backend.executable}').existsSync()) {
      Logger.log('⏭️  Skipping sony-elinux: the embedder artifacts are not '
          'installed at $artifacts. Build them with the "Embedder artifacts" '
          'workflow and unpack the result there.');
      return _PlatformBuildResult.skipped;
    }

    // The desktop build supplies the app, the assets and the AOT library.
    Logger.log('🔨 Building the host bundle sony-elinux assembles from...');
    final desktop = await _buildPlatform(
      'linux',
      buildMode,
      timeout: timeout,
      target: target,
      splitPerAbi: false,
      buildNumber: null,
      buildName: null,
      obfuscate: false,
      treeShakeIcons: true,
    );
    if (desktop != _PlatformBuildResult.succeeded) {
      Logger.log('❌ sony-elinux: the host build it assembles from failed');
      return _PlatformBuildResult.failed;
    }

    // The desktop build is host-native, so the bundle architecture is the
    // host's. Requesting another is refused rather than assembled from a
    // directory that will not exist.
    final String bundleArch;
    try {
      bundleArch = elinuxAssemblyArch(
        requested: arch,
        host: _hostArchitecture(),
      );
    } on UnsupportedError catch (error) {
      Logger.log('❌ sony-elinux: ${error.message}');
      return _PlatformBuildResult.failed;
    }

    final desktopBundle = '$root/build/linux/$bundleArch/release/bundle';
    final outDir = '$root/build/elinux/$bundleArch/release/bundle';

    final List<ELinuxCopy> plan;
    try {
      plan = elinuxAssemblyPlan(
        desktopBundle: desktopBundle,
        artifacts: artifacts,
        backend: backend,
        mode: ELinuxMode.release,
      );
    } on UnsupportedError catch (error) {
      Logger.log('❌ sony-elinux: ${error.message}');
      return _PlatformBuildResult.failed;
    }

    Directory(outDir).createSync(recursive: true);
    for (final copy in plan) {
      final destination = '$outDir/${copy.to}';
      Directory(p.dirname(destination)).createSync(recursive: true);
      final source = Directory(copy.from);
      if (source.existsSync()) {
        _copyDirectory(source, Directory(destination));
        continue;
      }
      final file = File(copy.from);
      if (!file.existsSync()) {
        // Naming the missing piece, because an incomplete bundle is still a
        // directory and fails on the device instead of here.
        Logger.log('❌ sony-elinux: ${copy.from} is missing');
        return _PlatformBuildResult.failed;
      }
      file.copySync(destination);
    }

    Logger.log('✅ sony-elinux bundle assembled at $outDir');
    Logger.log('   ${backend.executable} + engine + libapp.so, no GUI stack');
    return _PlatformBuildResult.succeeded;
  }

  /// The architecture this machine builds natively for.
  String _hostArchitecture() {
    final version = Platform.version;
    if (version.contains('arm64') || version.contains('aarch64')) return 'arm64';
    return 'x64';
  }

  void _copyDirectory(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync()) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entity is Directory) {
        _copyDirectory(entity, Directory('${to.path}/$name'));
      } else if (entity is File) {
        entity.copySync('${to.path}/$name');
      }
    }
  }

  Future<_PlatformBuildResult> _buildEmbedded(
    String platform,
    String buildMode, {
    String? format,
    String? deviceProfile,
    required String arch,
    String? target,
    Duration? timeout,
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
      // The project being built. The Fuchsia embedder takes a package path
      // rather than a name, because it builds apps from outside its workspace.
      appPath: Directory.current.path,
    );
    if (plan == null) {
      Logger.log('❌ Unsupported embedded platform: $platform');
      return _PlatformBuildResult.failed;
    }

    if (!await _isExecutableAvailable(plan.executable)) {
      Logger.log(
        p.isAbsolute(plan.executable)
            ? '⚠️  ${plan.executable} does not exist. '
                'Install the $platform embedder to build this target. Skipping...'
            : '⚠️  ${plan.executable} not found on PATH. '
                'Install the $platform embedder to build this target. Skipping...',
      );
      return _PlatformBuildResult.skipped;
    }

    // These embedders refuse a project with no platform directory. That
    // directory is generated output, so Dartvel generates it rather than
    // failing with the vendor's "not configured" message and a manual step.
    final scaffoldDir = plan.scaffoldDirectory;
    if (scaffoldDir != null &&
        !Directory(p.join(Directory.current.path, scaffoldDir)).existsSync()) {
      Logger.log('   No $scaffoldDir/ scaffold; generating it...');
      // Started the same way as the build below, with [_buildEnvironment]: an
      // embedder auto-installed moments ago lives on a PATH this process was
      // not started with, so a plain run would not find the executable the
      // availability check just resolved.
      final scaffold = await Process.start(
        plan.executable,
        plan.scaffoldArguments,
        workingDirectory: Directory.current.path,
        runInShell: true,
        environment: _buildEnvironment,
      );
      scaffold.stdout.listen((data) => stdout.add(data));
      scaffold.stderr.listen((data) => stderr.add(data));
      // Scaffold generation shells out to the vendor CLI, which is exactly
      // the kind of process that has hung before. Bounded at a share of the
      // build's allowance: generating a platform directory is quick, and one
      // that is not quick is stuck.
      final scaffoldCode = await _awaitBuild(
        scaffold,
        timeout: timeout == null
            ? null
            : Duration(minutes: (timeout.inMinutes ~/ 3).clamp(1, 10)),
        description: 'generating the $scaffoldDir/ scaffold',
      );
      if (scaffoldCode == null) return _PlatformBuildResult.failed;
      final generated = Directory(p.join(Directory.current.path, scaffoldDir));
      if (scaffoldCode != 0 || !generated.existsSync()) {
        // A vendor `create` that fails partway still leaves the directory
        // behind. Left in place it would satisfy the check above on the next
        // run, so the build would proceed against a half-written scaffold and
        // fail somewhere less obvious.
        if (generated.existsSync()) {
          generated.deleteSync(recursive: true);
          Logger.log('   Removed the partial $scaffoldDir/ scaffold.');
        }
        Logger.log('❌ Could not generate the $scaffoldDir/ scaffold.');
        return _PlatformBuildResult.failed;
      }
      Logger.log('   Generated $scaffoldDir/.');
    }

    final proc = await Process.start(
      plan.executable,
      plan.arguments,
      runInShell: true,
      environment: _environmentFor(plan),
    );
    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));
    final exitCode = await _awaitBuild(
      proc,
      timeout: timeout,
      description: '$label build',
    );
    if (exitCode == null) return _PlatformBuildResult.failed;

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

  /// Builds a Chromium or Firefox extension bundle.
  ///
  /// This is Flutter web output plus a generated manifest and background
  /// script. Two build flags are load-bearing rather than stylistic:
  /// `--csp`, because manifest V3 forbids `eval`, and `--pwa-strategy=none`,
  /// because Flutter's service worker fights the extension's own.
  Future<_PlatformBuildResult> _buildBrowserExtension(
    String platform,
    String buildMode,
    String root, {
    String? target,
  }) async {
    final extensionTarget = BrowserExtensionTarget.forTarget(platform);
    if (extensionTarget == null) {
      Logger.log('❌ Unknown browser extension target "$platform".');
      return _PlatformBuildResult.failed;
    }

    Logger.log('');
    Logger.log('🔨 Building for $platform...');

    final pubspec = readPubspecYaml(root);
    if (pubspec == null) {
      Logger.log('❌ No readable pubspec.yaml at $root.');
      return _PlatformBuildResult.failed;
    }
    final config = BrowserExtensionConfig.fromPubspec(pubspec);

    final arguments = <String>[
      'build',
      'web',
      buildMode,
      '--csp',
      '--pwa-strategy=none',
      if (target != null) ...<String>['-t', target],
    ];
    Logger.log('   flutter ${arguments.join(' ')}');
    final result = await _processRun(
      'flutter',
      arguments,
      workingDirectory: root,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      Logger.log('❌ $platform build failed');
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      return _PlatformBuildResult.failed;
    }

    final outputDir = p.join(root, 'build', platform);
    try {
      assembleExtensionBundle(
        webBuildDir: p.join(root, 'build', 'web'),
        outputDir: outputDir,
        config: config,
        target: extensionTarget,
      );
    } on FileSystemException catch (error) {
      Logger.log('❌ Could not assemble the extension bundle: ${error.message}');
      return _PlatformBuildResult.failed;
    }

    final artifacts = validateExtensionArtifacts(outputDir);
    if (!artifacts.isValid) {
      Logger.log('❌ $platform build did not produce a loadable extension.');
      for (final missing in artifacts.missing) {
        Logger.log('   Missing: $missing');
      }
      return _PlatformBuildResult.failed;
    }

    Logger.log(
      '✅ ${extensionTarget.label} extension built at build/$platform '
      '(${config.name} ${config.version})',
    );
    return _PlatformBuildResult.succeeded;
  }

  Future<_PlatformBuildResult> _buildVSCodeExtension(String root) async {
    Logger.log('');
    Logger.log('🔨 Building for vscode...');
    final buildStartedAt = DateTime.now();

    if (!hasPubDependency(root, 'flutter_vscode')) {
      Logger.log(
        '❌ vscode build requires a flutter_vscode dependency in pubspec.yaml.',
      );
      Logger.log(
        '   Add flutter_vscode, then run `dartvel build vscode` again.',
      );
      return _PlatformBuildResult.failed;
    }

    if (!_hasBuildRunner(root)) {
      Logger.log(
        '❌ vscode build requires build_runner to generate controller bindings.',
      );
      Logger.log(
        '   Add build_runner to dev_dependencies, then run `dartvel build vscode` again.',
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

    final artifacts = validateVSCodeArtifacts(root, since: buildStartedAt);
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

  /// Waits for [proc], killing it if it stops making progress.
  ///
  /// Returns null when the build was killed, having already reported why. A
  /// build that hangs is worse than one that fails: it is indistinguishable
  /// from a slow one, so it runs to whatever cap it was given — a silent
  /// `flutter build macos` once burned 41 minutes and reported nothing.
  Future<int?> _awaitBuild(
    Process proc, {
    required Duration? timeout,
    required String description,
  }) async {
    if (timeout == null) return proc.exitCode;
    try {
      return await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      // SIGKILL rather than SIGTERM: a process wedged on a lock or a pipe is
      // often not responsive to a polite signal, and this one has already had
      // its full allowance.
      proc.kill(ProcessSignal.sigkill);
      Logger.log('');
      Logger.log(
        '❌ $description produced no result within '
        '${timeout.inMinutes} minute(s) and was killed.',
      );
      Logger.log(
        '   Raise or remove the limit with --build-timeout <minutes> '
        '(0 disables it).',
      );
      return null;
    }
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

  /// [_buildEnvironment] plus whatever the embedder itself requires.
  ///
  /// Null only when there is nothing to add, so the child inherits normally.
  Map<String, String>? _environmentFor(EmbeddedBuildPlan plan) {
    if (plan.environment.isEmpty) return _buildEnvironment;
    return <String, String>{
      ...(_buildEnvironment ?? Platform.environment),
      ...plan.environment,
    };
  }

  /// Checks that this host can build [platform] and that its toolchain is
  /// present, installing what it can.
  ///
  /// Returns false when the target should be skipped. Ordering matters: host
  /// support is checked first, because offering to install Xcode on Linux
  /// would be nonsense.
  Future<bool> _preflight(String platform, {bool? autoInstall}) async {
    // An embedder that only runs on one host is still unavailable elsewhere,
    // even though embedded targets are otherwise exempt from the host check.
    final embedderHost = embeddedHostRequirement(platform);
    if (embedderHost != null && embedderHost != Platform.operatingSystem) {
      Logger.log('');
      Logger.log('🔨 Checking $platform...');
      Logger.log(
        '⚠️  The $platform embedder builds on $embedderHost only, not '
        '${Platform.operatingSystem}. Skipping...',
      );
      return false;
    }

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

    final home = resolveToolchainHome();
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
    // An absolute path is not a PATH lookup. Fuchsia's embedder is a script
    // inside its own checkout rather than an installed binary, so asking
    // `which` about it is the wrong question — and on Windows `where` answers
    // a different one entirely.
    if (p.isAbsolute(executable)) {
      return File(executable).existsSync();
    }
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
  for (final suffix in const <String>['-cli', '-tui']) {
    if (!target.endsWith(suffix)) continue;
    final base = target.substring(0, target.length - suffix.length);
    if (!terminalCapablePlatforms.contains(base)) {
      throw FormatException(
        '$base cannot render in a terminal. Terminal builds are available for '
        '${terminalCapablePlatforms.join(', ')}.',
        target,
      );
    }
    return (platform: base, format: 'tui');
  }
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
  const EmbeddedBuildPlan(
    this.executable,
    this.arguments, {
    this.scaffoldDirectory,
    this.scaffoldArguments = const <String>[],
    this.environment = const <String, String>{},
  });

  final String executable;
  final List<String> arguments;

  /// Variables the embedder requires beyond an inherited environment.
  ///
  /// Vendor embedders are ordinarily configured by being on PATH. Fuchsia's is
  /// not: its scripts locate their own workspace through
  /// `FUCHSIA_EMBEDDER_DIR`, and refuse to run without it. Dartvel installed
  /// that checkout and therefore knows the value, so it sets it rather than
  /// telling the developer to edit a shell profile.
  final Map<String, String> environment;

  /// The platform directory the embedder requires, the way an Android build
  /// requires `android/`. Null when the embedder needs no scaffold.
  final String? scaffoldDirectory;

  /// Generates [scaffoldDirectory] when it is absent.
  final List<String> scaffoldArguments;
}

/// Attaches [platform]'s scaffold requirement to a plan.
EmbeddedBuildPlan _withScaffold(
  String platform,
  String executable,
  List<String> arguments,
) {
  final scaffold = embeddedScaffoldFor(platform);
  return EmbeddedBuildPlan(
    executable,
    arguments,
    scaffoldDirectory: scaffold?.directory,
    scaffoldArguments: scaffold?.arguments ?? const <String>[],
  );
}

/// The embedder scaffold [platform] needs, or null when it needs none.
///
/// These embedders refuse to build a project that has no platform directory —
/// `This project is not configured for <platform>` — and the directory is
/// generated output, not application code, so Dartvel generates it rather
/// than making every developer run the vendor's `create` by hand. The vendor
/// `create` commands write only files that do not already exist, so an
/// existing `pubspec.yaml` or `lib/main.dart` is never clobbered.
({String directory, List<String> arguments})? embeddedScaffoldFor(
  String platform,
) =>
    switch (platform) {
      'tizen' => (
          directory: 'tizen',
          // The default scaffold is C#/.NET; cpp matches the native toolchain.
          arguments: <String>[
            'create',
            '--platforms',
            'tizen',
            '--tizen-language',
            'cpp',
            '.',
          ],
        ),
      'sony-elinux' => (
          directory: 'elinux',
          arguments: <String>['create', '--platforms', 'elinux', '.'],
        ),
      'webos' => (
          directory: 'webos',
          arguments: <String>['create', '--platforms', 'webos', '.'],
        ),
      'tvos' => (
          directory: 'tvos',
          arguments: <String>['create', '--platforms=tvos', '.'],
        ),
      _ => null,
    };

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

VSCodeArtifactValidation validateVSCodeArtifacts(String root,
    {DateTime? since}) {
  return VSCodeArtifactValidation(
    hasExtensionHostOutput: _containsJavaScriptFile(
          Directory(p.join(root, 'out')),
          since: since,
        ) ||
        _containsJavaScriptFile(Directory(p.join(root, 'dist')), since: since),
    hasFlutterBootstrap: _existsAndIsFresh(
      File(p.join(root, 'build', 'web', 'flutter_bootstrap.js')),
      since: since,
    ),
    hasFlutterAssets: _directoryExistsAndIsFresh(
      Directory(p.join(root, 'build', 'web', 'assets')),
      since: since,
    ),
  );
}

bool _containsJavaScriptFile(Directory directory, {DateTime? since}) {
  if (!directory.existsSync()) return false;
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .any((file) => file.path.endsWith('.js') && _isFresh(file, since));
}

bool _directoryExistsAndIsFresh(Directory directory, {DateTime? since}) {
  if (!directory.existsSync()) return false;
  if (since == null) return true;
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .any((file) => _isFresh(file, since));
}

bool _existsAndIsFresh(File file, {DateTime? since}) {
  return file.existsSync() && _isFresh(file, since);
}

/// How far below the build's start time an artifact's timestamp may sit and
/// still count as produced by that build.
///
/// The build start is a `DateTime.now()` carrying microseconds; a file's mtime
/// is whatever the filesystem chose to record, which is second-granular on
/// several and two-second-granular on FAT. So an artifact written a moment
/// after the build began can carry a timestamp numerically below it, and a
/// strict comparison reports a file that is right there as missing.
///
/// Two seconds covers the coarsest granularity in use. It does not weaken what
/// the check is for: a leftover from an earlier build is minutes or hours old,
/// not two seconds.
const _timestampGranularitySlack = Duration(seconds: 2);

bool _isFresh(FileSystemEntity entity, DateTime? since) {
  if (since == null) return true;
  final floor = since.subtract(_timestampGranularitySlack);
  return !entity.statSync().modified.isBefore(floor);
}

/// Embedded targets whose default architecture is not the global one.
///
/// `--arch` defaults to arm64, which is right for TVs and embedded boards.
/// Fuchsia's embedder ships an x64 prebuilt engine only, so inheriting that
/// default asks it for an engine that does not exist — and a `dartvel build
/// all` would ask for it without anyone having chosen arm64 at all.
const embeddedArchDefaults = <String, String>{'fuchsia': 'x64'};

/// [arch] unless [platform] defaults differently and the caller did not ask.
///
/// An explicit `--arch` always wins: a developer who has built an arm64
/// Fuchsia engine should be able to use it, and the embedder's own error is
/// clear if they have not.
String resolveEmbeddedArch(String platform, String arch,
        {bool explicit = false}) =>
    explicit ? arch : (embeddedArchDefaults[platform] ?? arch);

/// How long a build may run before it is treated as stalled.
///
/// Null means no limit. The default is deliberately generous — a clean
/// release build of a large app on a cold cache is genuinely slow — but it is
/// finite, because a build that hangs looks exactly like a slow one and keeps
/// costing until something else stops it.
Duration? parseBuildTimeout(String? minutes) {
  if (minutes == null || minutes.trim().isEmpty) {
    return const Duration(minutes: 45);
  }
  final parsed = int.tryParse(minutes.trim());
  if (parsed == null || parsed < 0) {
    throw FormatException(
      'A --build-timeout is a whole number of minutes, or 0 to disable it.',
      minutes,
    );
  }
  return parsed == 0 ? null : Duration(minutes: parsed);
}

/// The directory Dartvel-managed toolchains are installed under.
String resolveToolchainHome() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

/// Resolves the embedder invocation for an embedded platform, or `null` if the
/// platform is not an embedded target. `iso`/`img` packaging builds the same
/// bundle; the packaging step is handled separately by the caller.
EmbeddedBuildPlan? resolveEmbeddedBuildPlan({
  required String platform,
  required String buildMode,
  required String arch,
  String? deviceProfile,
  String? target,
  String? appPath,
  String? toolchainHome,
}) {
  switch (platform) {
    case 'tizen':
      final args = <String>['build', 'tpk', buildMode];
      if (target != null) args.addAll(<String>['--target', target]);
      if (deviceProfile != null) {
        args.addAll(<String>['--device-profile', deviceProfile]);
      }
      return _withScaffold(
          'tizen', 'flutter-tizen', List<String>.unmodifiable(args));
    case 'sony-elinux':
      // No external embedder command any more.
      //
      // flutter-elinux is pinned to Flutter 3.29.3 and upstream has not
      // committed since 2025-07-09, so driving the build through it makes the
      // target permanently unbuildable at Dartvel's floor. A release bundle is
      // assembled instead: the desktop release build supplies the app, the
      // assets and the AOT library, and Sony's artifacts supply the embedder
      // and the engine. See build/elinux_bundle.dart.
      return null;
    case 'webos':
      final args = <String>['build', 'webos', buildMode];
      if (target != null) args.addAll(<String>['--target', target]);
      if (deviceProfile != null) {
        args.addAll(<String>['--device-profile', deviceProfile]);
      }
      return _withScaffold(
          'webos', 'flutter-webos', List<String>.unmodifiable(args));
    case 'tvos':
      // Device builds are AOT and require a configured Xcode signing team.
      // `simulator` (via --device-profile simulator) is the unsigned path,
      // and the embedder accepts it only with a debug build.
      final simulator = deviceProfile == 'simulator';
      final args = <String>[
        'build',
        'tvos',
        simulator ? '--debug' : buildMode,
        if (simulator) '--simulator',
      ];
      if (target != null) args.addAll(<String>['--target', target]);
      return _withScaffold(
          'tvos', 'flutter-tvos', List<String>.unmodifiable(args));
    case 'fuchsia':
      // Unlike the other three, Fuchsia's embedder is not a Flutter CLI
      // wrapper — there is no embedder binary at all. It is a Bazel workspace,
      // and its build script takes the path of a Flutter package to stage in
      // and build.
      //
      // So the executable is the script's absolute path inside the checkout,
      // not a bare name. A bare name is looked up on PATH, and nothing named
      // `dartvel_fuchsia` is ever installed there — which is exactly how this
      // target reported "not found on PATH" and skipped on a runner that had
      // just installed the embedder successfully.
      final root =
          dartvelToolchainRoot(toolchainHome ?? resolveToolchainHome());
      final args = <String>[
        appPath ?? '.',
        '--cpu',
        arch == 'arm64' ? 'arm64' : 'x64',
        // Build the package and stop. Without this the fork's script hands off
        // to build_and_run_example.sh, which starts a package server and
        // bazel-runs the component through ffx — so the build does all its work
        // and then fails at the last step on any machine with no device.
        // `dartvel build` produces artifacts; running is a different verb.
        '--build-only',
      ];
      if (target != null) args.addAll(<String>['--target', target]);
      return EmbeddedBuildPlan(
        '$root/dartvel_fuchsia/$fuchsiaAppBuildScript',
        List<String>.unmodifiable(args),
        environment: Map<String, String>.unmodifiable(<String, String>{
          'FUCHSIA_EMBEDDER_DIR': '$root/dartvel_fuchsia',
        }),
      );
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
  if (platform == 'ios') {
    args.add('--no-codesign');
  }

  return List<String>.unmodifiable(args);
}
