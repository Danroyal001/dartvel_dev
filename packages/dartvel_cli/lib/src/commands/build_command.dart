import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../build/accessibility_audit.dart';
import '../build/browser_extension.dart';
import '../build/desktop_entry.dart';
import '../build/elinux_bundle.dart';
import '../build/capture_completeness.dart';
import '../build/declaration_check.dart';
import '../build/device_profile_check.dart';
import '../build/pwa_icons.dart';
import '../build/pwa_manifest.dart';
import '../secrets/secrets_analysis.dart';
import '../build/pwa_service_worker.dart';
import '../build/seo_head.dart';
import '../build/page_text.dart';
import '../build/semantic_html.dart';
import '../build/semantics_capture.dart';
import '../build/server_config.dart';
import '../build/structured_data.dart';
import '../build/supervisor_unit.dart';
import '../build/static_seo.dart';
import '../build/static_paths_runner.dart';
import '../build/static_generation.dart';
import '../build/web_server.dart';
import '../graph/module_mounts.dart';
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

/// Web output served by a Dartvel server rather than written to files.
///
/// The same pages from the same pieces, decided per request instead of at
/// build time -- which is the only way a model-backed page or a parameterised
/// route can be served correctly, because neither can be written to a file
/// ahead of being asked for.
const webServerBuildPlatforms = <String>[
  'web-server',
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
  // Not in allBuildPlatforms: `--platform all` should not produce both a
  // static web build and a server one, since they are two answers to the
  // same question and the second would overwrite the first.
  ...webServerBuildPlatforms,
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
    toolchain: '$root/dartvel_cli_flt/bin/dartvel-cli-flt',
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
        'installed. Terminal rendering uses the dartvel_cli_flt embedder, which '
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
    case 'web-server':
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
      ..addFlag('simulator',
          defaultsTo: false,
          negatable: false,
          help: 'Build for a simulator rather than a device (tvOS). Device '
              'builds are AOT and need a configured Xcode signing team, so '
              'this is the only unsigned path.')
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
    final simulator = argResults?['simulator'] as bool? ?? false;
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

    // What the project declares, before anything is generated. Never start a
    // build that cannot finish reads as being about tools -- the host, the
    // SDK, the embedder -- and a declaration the build cannot honour is the
    // same thing one layer up. Both were checked by `dartvel doctor` alone,
    // so a pipeline that runs a build and not a doctor shipped them.
    // And whether the device being built for can run what is being built.
    // The specification names device-profile compatibility among the things
    // a build validates before it starts; the decision existed in the module
    // manifest verifier and no caller ever passed it a target, so an image
    // built happily around a module that cannot run on it.
    final DVDeviceProfileCheck profileCheck =
        DVDeviceProfileCheck.run(root, profile: deviceProfile);
    if (!profileCheck.ok) {
      Logger.log('❌ DV-ELINUX-004: the selected device profile cannot run '
          'this application:');
      for (final String line in profileCheck.lines) {
        Logger.log(line);
      }
      exit(78); // EX_CONFIG
    }

    final DVDeclarationCheck declarations = DVDeclarationCheck.run(root);
    if (!declarations.ok) {
      Logger.log('❌ The project declares something this build cannot honour:');
      for (final String line in declarations.lines) {
        Logger.log(line);
      }
      Logger.log('   Run `dartvel doctor` for the whole picture.');
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
    _checkSecrets(root);

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
              simulator: simulator,
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
                      deviceProfile: deviceProfile,
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
    String? deviceProfile,
  }) async {
    Logger.log('');
    Logger.log('🔨 Building for $platform...');
    // Before Xcode packages the bundle: the document and URL types live in
    // its Info.plist.
    if (platform == 'macos') _writeMacosDesktopEntries(Directory.current.path);

    final args = resolveFlutterBuildArguments(
      platform: platform,
      buildMode: buildMode,
      target: target,
      splitPerAbi: splitPerAbi,
      buildNumber: buildNumber,
      buildName: buildName,
      obfuscate: obfuscate,
      treeShakeIcons: treeShakeIcons,
      deviceProfile: deviceProfile,
    );

    // Check if platform is available
    if (!await _isPlatformAvailable(platform)) {
      Logger.log(
          '⚠️  Platform $platform not available on this system. Skipping...');
      return _PlatformBuildResult.skipped;
    }

    // Before the build copies web/index.html into the output, so the built
    // page carries it whether or not it also goes through the SEO pass. A
    // page without one is laid out by a phone at a notional 980 CSS pixels
    // and scaled down, which makes every breakpoint report "desktop" on a
    // phone.
    if (platform == 'web' || platform == 'web-server') {
      if (dvEnsureProjectViewport(Directory.current.path)) {
        Logger.log('   Added a viewport meta to web/index.html.');
      }
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
      if (platform == 'web' || platform == 'web-server') {
        final root = Directory.current.path;
        // Before anything reads it. The crawler-visible HTML on every page
        // comes from these trees, and a build that skipped the capture would
        // publish whatever the last one produced -- including for a route
        // that has since stopped rendering.
        await _captureSemantics(root);
        _writePwaManifest(root);
        _writeSeoHead(root);
        if (platform == 'web-server') {
          _writeWebServerManifest(root);
        } else {
          await _writeStaticPages(root);
        }
      }
      if (platform == 'linux') _writeLinuxDesktopFiles(Directory.current.path);
      if (platform == 'windows') _writeWindowsDesktopFiles(Directory.current.path);
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

    // Boot-to-app: the declaration says the target's supervisor starts the
    // application, and on an eLinux image that supervisor is systemd. Without
    // the unit the image boots to a console.
    final DVSupervisorWrite supervisor = dvWriteSupervisorUnit(
      root,
      outDir,
      executable: backend.executable,
    );
    for (final String problem in supervisor.problems) {
      Logger.log('⚠️  $problem');
    }

    Logger.log('✅ sony-elinux bundle assembled at $outDir');
    Logger.log('   ${backend.executable} + engine + libapp.so, no GUI stack');
    if (supervisor.written.isNotEmpty) {
      Logger.log('   ${supervisor.written.join(', ')}: install under '
          '/etc/systemd/system and enable it.');
    }
    return _PlatformBuildResult.succeeded;
  }

  /// The architecture this machine builds natively for.
  /// The desktop entry and MIME info for file associations and app links,
  /// next to the binary. What a package installs into the system's
  /// applications and mime directories; what a developer copies there by
  /// hand to try an association.
  void _writeLinuxDesktopFiles(String root) {
    final String bundle = '$root/build/linux/${_hostArchitecture()}/release/bundle';
    if (!Directory(bundle).existsSync()) return;
    final DVDesktopWrite result = dvWriteLinuxDesktopFiles(root, bundle);
    for (final String problem in result.problems) {
      Logger.log('⚠️  $problem');
    }
    Logger.log('   Wrote ${result.written.join(', ')} under the bundle.');
  }

  /// The document and URL types into the macOS runner's Info.plist.
  void _writeMacosDesktopEntries(String root) {
    final DVDesktopWrite result = dvWriteMacosDesktopEntries(root);
    for (final String problem in result.problems) {
      Logger.log('⚠️  $problem');
    }
    if (result.written.isNotEmpty) Logger.log('   Wrote ${result.written.join(', ')}.');
  }

  /// The registry script for file associations and app links, beside the
  /// Windows binary. Only an installer or the person may write those keys.
  void _writeWindowsDesktopFiles(String root) {
    final String bundle = '$root/build/windows/x64/runner/Release';
    if (!Directory(bundle).existsSync()) return;
    final DVDesktopWrite result = dvWriteWindowsDesktopFiles(root, bundle);
    for (final String problem in result.problems) {
      Logger.log('⚠️  $problem');
    }
    if (result.written.isNotEmpty) Logger.log('   Wrote ${result.written.join(', ')} under the bundle.');
  }

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
    bool simulator = false,
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
      simulator: simulator,
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
  /// script. The build flags are load-bearing rather than stylistic and live
  /// in [browserExtensionBuildArguments], where they can be tested -- one of
  /// them was missing for as long as this target existed.
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

    final arguments =
        browserExtensionBuildArguments(buildMode: buildMode, target: target);
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

  /// Write the PWA manifest into a finished web build.
  ///
  /// `dartvel.pwa.enabled` was read out of pubspec.yaml and emitted as a
  /// generated constant for a long time with nothing consuming it. This is
  /// what consumes it.
  ///
  /// Installability problems are printed rather than failing the build: a
  /// manifest no browser will install is still a web app that runs, and a
  /// build that refuses to finish over an icon size would be worse than the
  /// warning.
  /// DV-SECRETS-001, before anything is generated or compiled.
  ///
  /// A secret compiled into a client bundle ships to every visitor, and the
  /// point of compiling both ends from one project is that this can be a
  /// build error rather than a code-review habit.
  ///
  /// Client-reachable means lib/ minus the backend directory. It is an
  /// approximation -- a value routed through an indirection this cannot
  /// follow is a false negative -- which is why the structural guarantee is
  /// elsewhere: only PUBLIC_ values reach the generated env.g.dart at all.
  void _checkSecrets(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return;

    final declared = dvParseSecretDeclarations(pubspec.readAsStringSync());
    if (declared.isEmpty) return;

    final problems = dvValidateDeclarations(declared);
    if (problems.isNotEmpty) {
      for (final problem in problems) {
        Logger.error('   $problem');
      }
      Logger.log('❌ dartvel.secrets is not valid');
      exit(1);
    }

    final backendDir = '${_dartvelSection(root)['backendDir'] ?? 'lib/backend'}';
    final lib = Directory(p.join(root, 'lib'));
    if (!lib.existsSync()) return;

    final clientFiles = <String, String>{};
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = p.relative(entity.path, from: root).replaceAll('\\', '/');
      // The backend is where a backend-scoped secret belongs, and the
      // generated client is written from the sources already checked.
      if (rel.startsWith(backendDir)) continue;
      if (rel.contains('/dartvel_client/')) continue;
      clientFiles[rel] = entity.readAsStringSync();
    }

    final findings = dvAnalyseSecrets(
      declared: declared,
      clientFiles: clientFiles,
    );
    if (findings.isEmpty) return;

    for (final finding in findings) {
      Logger.error('   ${finding.code} ${finding.file}: ${finding.message}');
    }
    Logger.log('❌ ${findings.length} secret problem(s)');
    exit(1);
  }

  void _writePwaManifest(String root) {
    final pwa = _dartvelSection(root)['pwa'];
    final settings = pwa is Map ? pwa : const <Object?, Object?>{};
    if (settings['enabled'] == false) return;

    final name = '${settings['name'] ?? _packageName(root) ?? 'Dartvel App'}';
    final result = dvPwaWrite(
      webBuildDir: p.join(root, 'build', 'web'),
      manifest: dvPwaManifest(
        name: name,
        shortName: settings['shortName'] as String?,
        display: '${settings['display'] ?? 'standalone'}',
        themeColor: '${settings['themeColor'] ?? '#000000'}',
        backgroundColor: '${settings['backgroundColor'] ?? '#FFFFFF'}',
        description: settings['description'] as String?,
      ),
    );

    if (!result.wrote) {
      Logger.log('   PWA manifest not written: ${result.problems.join(' ')}');
      return;
    }
    Logger.log('   PWA manifest written for "$name"'
        '${result.linked ? ' and linked from index.html' : ''}.');
    for (final problem in result.problems) {
      Logger.log('   ⚠ $problem');
    }

    _writePwaIcons(root, settings);
    _writeServiceWorker(root, name: name, settings: settings);
  }

  /// The hreflang set for [route], and its x-default, when the site is built
  /// for more than one language and has a siteUrl to build them on.
  ///
  /// Empty otherwise: a single-language site declaring itself as one
  /// alternate of itself reads as a misconfiguration. The locale declaration
  /// itself is validated, fatally, where the root head is written.
  (Map<String, String>, String?) _alternatesFor(String root, String route) {
    final dartvel = _dartvelSection(root);
    final seo = dartvel['seo'];
    final settings = seo is Map ? seo : const <Object?, Object?>{};
    final String? siteUrl = settings['siteUrl'] as String?;
    final DVI18nLocales locales = DVI18nLocales.parse(dartvel);
    if (siteUrl == null || siteUrl.isEmpty || !locales.multilingual) {
      return (const <String, String>{}, null);
    }
    final Map<String, String> alternates = dvSeoAlternatesFor(
      siteUrl: siteUrl,
      route: route,
      locales: locales.locales,
      defaultLocale: locales.defaultLocale,
    );
    return (alternates, alternates[locales.defaultLocale]);
  }

  /// Generates the four icons the manifest names, from the project's icon.
  ///
  /// The manifest pointed at files nothing produced, and Chrome refuses to
  /// install without them, so every fresh project was uninstallable until
  /// someone exported four PNGs by hand. Skipped, and said, when the project
  /// has no icon; fatal when it names one that cannot be read, because that is
  /// a mistake the developer can fix in a minute and would otherwise ship.
  void _writePwaIcons(String root, Map<Object?, Object?> settings) {
    final File? source;
    try {
      source = dvPwaIconSource(root, settings);
    } on DVPngError catch (error) {
      Logger.error('   ${error.message}');
      Logger.log('❌ PWA icon');
      exit(1);
    }
    if (source == null) {
      Logger.log('   No PWA icons generated: add web/icon.png (or set '
          'dartvel.pwa.icon) and the 192 and 512 sizes will be built from it.');
      return;
    }
    try {
      final List<String> written = dvGeneratePwaIcons(
        source: source,
        into: Directory(p.join(root, 'build', 'web')),
        background: dvHexToArgb('${settings['backgroundColor'] ?? '#FFFFFF'}'),
      );
      Logger.log('   PWA icons written from ${p.relative(source.path, from: root)}: '
          '${written.length}.');
    } on DVPngError catch (error) {
      Logger.error('   ${error.message}');
      Logger.log('❌ PWA icon');
      exit(1);
    }
  }

  /// Replace Flutter's service worker with one that knows the routes.
  ///
  /// Flutter's own caches the app shell and nothing Dartvel knows about, so a
  /// Dartvel site had no offline page, no cached routes, and no control over
  /// what a stale worker serves after a deploy.
  void _writeServiceWorker(
    String root, {
    required String name,
    required Map<Object?, Object?> settings,
  }) {
    if (settings['serviceWorker'] == false) return;

    final web = Directory(p.join(root, 'build', 'web'));
    if (!web.existsSync()) return;

    // The routes this build produced, which is what a Dartvel worker can
    // precache and Flutter's cannot know.
    final routes = <String>['/'];
    for (final entity in web.listSync()) {
      if (entity is! Directory) continue;
      final segment = p.basename(entity.path);
      if (segment.startsWith('.') ||
          segment == 'assets' ||
          segment == 'canvaskit' ||
          segment == 'icons') {
        continue;
      }
      if (File(p.join(entity.path, 'index.html')).existsSync()) {
        routes.add('/$segment');
      }
    }

    const offlinePath = '/offline.html';
    File(p.join(web.path, 'offline.html'))
        .writeAsStringSync(dvOfflinePage(title: name));

    // Written over flutter_service_worker.js, which index.html already
    // registers: adding a second worker would leave two competing for the
    // same scope, and which one wins is not something to leave to chance.
    File(p.join(web.path, 'flutter_service_worker.js')).writeAsStringSync(
      dvServiceWorker(
        buildId: DateTime.now().toUtc().toIso8601String(),
        precache: routes,
        offlinePath: offlinePath,
        // On unless the project says otherwise: a backend call made offline
        // is queued and replayed, which is the behaviour a PWA promises.
        backgroundSync: settings['backgroundSync'] != false,
      ),
    );

    Logger.log('   Service worker written: '
        '${routes.length} route(s) precached, with an offline page.');
  }

  /// Write the SEO head tags into a finished web build.
  ///
  /// Flutter's template leaves the title as the package name and ships no
  /// Open Graph tags, above a body that stays empty until JavaScript runs. A
  /// crawler and a link preview read exactly that, and neither runs the app --
  /// so the page is perfect in a browser and blank everywhere else.
  void _writeSeoHead(String root) {
    final dartvel = _dartvelSection(root);
    final seo = dartvel['seo'];
    final settings = seo is Map ? seo : const <Object?, Object?>{};
    final pwa = dartvel['pwa'];
    final pwaSettings = pwa is Map ? pwa : const <Object?, Object?>{};

    // The title falls back through what is already configured before reaching
    // the package name, which is the value that made this worth fixing.
    final title = dvSeoTitle(
      settings,
      '${pwaSettings['name'] ?? _packageName(root) ?? 'Dartvel'}',
    );
    final description = dvSeoDescription(settings) ??
        (pwaSettings['description'] == null
            ? null
            : '${pwaSettings['description']}');

    final index = File(p.join(root, 'build', 'web', 'index.html'));
    if (!index.existsSync()) return;

    // hreflang, when the site is built for more than one language. A default
    // locale the site does not have is refused rather than written, because
    // it sends x-default to a 404.
    final DVI18nLocales locales = DVI18nLocales.parse(dartvel);
    for (final String problem in locales.problems) {
      Logger.error('   $problem');
    }
    if (locales.problems.isNotEmpty) {
      Logger.log('❌ i18n locales');
      exit(1);
    }
    final (Map<String, String> rootAlternates, String? rootDefault) =
        _alternatesFor(root, '/');
    final head = dvSeoHead(
      title: title,
      description: description,
      siteUrl: settings['siteUrl'] as String?,
      image: settings['image'] as String?,
      siteName: settings['siteName'] as String? ?? title,
      alternates: rootAlternates,
      defaultAlternate: rootDefault,
    );
    // The site's own WebSite block, which belongs on the root and nowhere
    // else -- repeating it per page tells a crawler the site begins again at
    // each URL. The root is written here rather than by dvStaticPage, which
    // is why it had none while every inner page did.
    final rootJsonLd = dvStructuredData(
      route: '/',
      title: title,
      siteName: settings['siteName'] as String? ?? title,
      description: description,
      siteUrl: settings['siteUrl'] as String?,
      image: dvAbsoluteAsset(
          settings['image'] as String?, settings['siteUrl'] as String?),
    );

    final before = index.readAsStringSync();
    var after = dvSeoApply(
        before, rootJsonLd.isEmpty ? head : '$head\n$rootJsonLd');
    // The body is empty until JavaScript runs, so a crawler, a link preview
    // and a reader with scripting off all see nothing.
    //
    // From the semantics tree where there is one, which is the structure the
    // application declares. The root took the source-literal path while every
    // other route took the tree, so the home page alone shipped its eyebrow
    // as an <h1>, its sentences split across three paragraphs, and the string
    // 'RobotoMono' as a paragraph of its own.
    final String? semantics = _semanticHtmlFor(root, '/');
    after = semantics != null
        ? dvApplyPageHtml(after, semantics)
        : dvApplyPageText(after, _routeText(root)['/'] ?? const <String>[]);
    if (after == before) return;
    index.writeAsStringSync(after);
    Logger.log('   SEO head written for "$title".');
  }

  /// Write per-route HTML, a sitemap and robots.txt into a finished web build.
  ///
  /// Without this a static host serves one index.html for every route, which
  /// is `flutter build web` with extra steps: four URLs, one title, one
  /// description, one body. Prerendered text is used where `dartvel prerender`
  /// captured it, and a page still gets its own head tags where it did not.
  /// Every page this build should produce.
  ///
  /// The router's own routes, minus the templates -- `/posts/:slug` is a shape
  /// that matches at run time and is not a page, and writing it out makes a
  /// directory with a colon in its name that nothing requests -- plus the
  /// concrete paths those templates stand for, which only the application can
  /// enumerate because they come from its database.
  Future<List<String>> _pagesToGenerate(String root) async {
    final List<String> declared = _generatedRoutes(root);
    final List<String> concrete = dvConcreteRoutes(declared);
    final int templates = declared.length - concrete.length;

    if (templates == 0) return concrete;

    final List<String> resolved = await dvResolveStaticPaths(root);
    if (resolved.isEmpty) {
      Logger.log('   $templates parameterised route(s) resolved to no pages. '
          'A model page needs generatePublicPages or a publicPathsResolver.');
      return concrete;
    }

    // Only pages a declared route can serve. The manifest derives its route
    // from the model's name and nothing checked the router had one, so this
    // was generating /products/pro-kit for an application whose router has no
    // /products at all: a crawler follows the link, gets HTML, and the app
    // boots and renders its own not-found page.
    final List<String> served =
        dvServedStaticPaths(resolved, declared: declared);
    final int stranded = resolved.length - served.length;
    if (stranded > 0) {
      // generatePublicPages generates its own route, so what lands here is
      // a publicPathsResolver naming paths for a page the application has
      // not written. Saying which is the difference between a warning
      // someone can act on and one they cannot.
      Logger.log('   $stranded page(s) were not written: no route serves '
          'them. A publicPathsResolver names the paths for a page you write; '
          'if you meant Dartvel to write it, use generatePublicPages: true.');
    }
    if (served.isEmpty) return concrete;

    Logger.log('   $templates parameterised route(s) expanded to '
        '${served.length} page(s).');
    return <String>{...concrete, ...served}.toList()..sort();
  }

  /// Capture each route's semantics tree from the finished build.
  ///
  /// The crawler-visible HTML is built from these. Without the capture the
  /// pages fall back to reading string literals out of the page source, which
  /// cannot tell a heading from a sentence and produces no links at all.
  Future<void> _captureSemantics(String root) async {
    final web = Directory(p.join(root, 'build', 'web'));
    if (!web.existsSync()) return;
    final routes = await _pagesToGenerate(root);
    if (routes.isEmpty) return;

    Logger.log('   Reading the semantics tree for ${routes.length} routes...');
    final int captured = await dvCaptureSemantics(
      projectRoot: root,
      webRoot: web.path,
      routes: routes,
    );
    final verdict =
        dvVerifyCapture(captured: captured, expected: routes.length);
    if (verdict.ok) {
      Logger.log('   Captured $captured of ${routes.length}.');
      _auditAccessibility(root, routes);
      return;
    }

    // Fatal rather than a warning. A build that ships most of its SEO and
    // reports success hides the failure until someone checks a search result
    // weeks later, and the fix -- rerun it -- costs a minute.
    Logger.error('   ${verdict.message}');
    Logger.log('❌ semantics capture incomplete');
    exit(1);
  }

  /// Fails the build on an accessibility regression.
  ///
  /// The captured semantics tree is what a screen reader will actually be
  /// handed, so it is the right thing to judge -- better than the source, which
  /// only suggests what the tree might become.
  ///
  /// Fatal, for the same reason the capture itself is: an accessibility check
  /// that warns is a check that gets scrolled past, and nothing else in the
  /// pipeline fails a release on this.
  void _auditAccessibility(String root, List<String> routes) {
    final List<DVA11yFinding> findings = <DVA11yFinding>[];
    for (final String route in routes) {
      final File file = File(dvSemanticsPathFor(root, route));
      if (!file.existsSync()) continue;
      findings.addAll(dvAuditSemantics(
        route: route,
        nodes: DVSemanticNode.listFromJson(file.readAsStringSync()),
      ));
    }

    // A documented waiver sets a finding aside; a waiver with no reason, or
    // one naming a rule the audit does not have, is refused as configuration.
    final DVA11yWaivers waivers = DVA11yWaivers.parse(_dartvelSection(root));
    for (final String problem in waivers.problems) {
      Logger.error('   $problem');
    }
    if (waivers.problems.isNotEmpty) {
      Logger.log('❌ accessibility waivers');
      exit(1);
    }
    final DVA11yVerdict verdict = waivers.apply(findings);

    for (final DVA11yFinding finding in verdict.waived) {
      Logger.log('   waived: $finding');
    }
    for (final DVA11yWaiver waiver in verdict.unused) {
      // Either a typo or a finding since fixed; either way not for ever.
      Logger.log('   ⚠ waiver matched nothing: ${waiver.route} ${waiver.rule} '
          '(${waiver.reason})');
    }
    if (verdict.ok) {
      Logger.log('   Accessibility: ${routes.length} route(s), '
          '${verdict.waived.isEmpty ? 'nothing to fix' : '${verdict.waived.length} waived'}.');
      return;
    }

    for (final DVA11yFinding finding in verdict.failing) {
      Logger.error('   $finding');
    }
    Logger.log('❌ ${verdict.failing.length} accessibility finding(s)');
    exit(1);
  }

  /// The crawler-visible HTML for [route], from a semantics dump if the
  /// prerender step wrote one.
  ///
  /// `dartvel build web --prerender` drives a browser over each route and
  /// writes `.dart_tool/dartvel_semantics/<route>.json`. Absent that, this
  /// returns null and the caller falls back to the source-literal extractor,
  /// so a build with no browser still produces something rather than failing.
  String? _semanticHtmlFor(String root, String route) {
    final String name =
        route == '/' ? 'index' : route.replaceAll(RegExp(r'^/|/$'), '')
            .replaceAll('/', '_');
    final file = File(
        p.join(root, '.dart_tool', 'dartvel_semantics', '$name.json'));
    if (!file.existsSync()) return null;
    final String html =
        dvSemanticHtml(DVSemanticNode.listFromJson(file.readAsStringSync()));
    return html.trim().isEmpty ? null : html;
  }

  Future<void> _writeStaticPages(String root) async {
    final web = Directory(p.join(root, 'build', 'web'));
    final index = File(p.join(web.path, 'index.html'));
    if (!index.existsSync()) return;

    final dartvel = _dartvelSection(root);
    final seo = dartvel['seo'];
    final settings = seo is Map ? seo : const <Object?, Object?>{};
    final siteUrl = settings['siteUrl'] as String?;

    final routes = await _pagesToGenerate(root);
    if (routes.isEmpty) return;
    final routeText = _routeText(root);

    final baseTitle = dvSeoTitle(settings, _packageName(root) ?? 'Dartvel');
    // The template Flutter wrote, cleaned before anything is built from it:
    // its two developer-facing comments and its package-name iOS title
    // otherwise reach production on every page.
    final shell = dvCleanShell(
      index.readAsStringSync(),
      siteName: settings['siteName'] as String? ?? baseTitle,
    );
    // What each page calls itself, which is better than anything derivable
    // from the path.
    final declared = dvRouteTitles(_routerSource(root));
    var written = 0;

    for (final String route in routes) {
      final target = dvStaticRoutePath(route);
      // The root is already index.html and carries its head tags from
      // _writeSeoHead; rewriting it here would undo them.
      if (target == null || target == 'index.html') continue;

      final meta = _prerendered(web.path, route);
      final text = routeText[route] ?? const <String>[];
      final page = dvStaticPage(
        shell: shell,
        route: route,
        title: meta?.title ??
            declared[route] ??
            '${_routeLabel(route)} — $baseTitle',
        description: dvSeoDescription(settings),
        content: meta?.content,
        siteUrl: siteUrl,
        image: settings['image'] as String?,
        siteName: settings['siteName'] as String? ?? baseTitle,
        alternates: _alternatesFor(root, route).$1,
        defaultAlternate: _alternatesFor(root, route).$2,
      );

      // The semantics tree when there is one, the source-literal extractor
      // when there is not. The tree is the structure the application declares
      // -- headings, links, landmarks -- and the same one a screen reader is
      // given; the extractor can only see strings, so it cannot tell a
      // heading from a sentence and produces no links at all.
      final String? semantics = _semanticHtmlFor(root, route);
      File(p.join(web.path, target))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(semantics != null
            ? dvApplyPageHtml(page, semantics)
            : dvApplyPageText(page, text));
      written++;
    }

    if (siteUrl != null && siteUrl.isNotEmpty) {
      File(p.join(web.path, 'sitemap.xml'))
          .writeAsStringSync(dvSitemap(
            routes: routes,
            siteUrl: siteUrl,
            federated: dvFederatedRoutes(root).keys.toList(),
          ));
      File(p.join(web.path, 'robots.txt'))
          .writeAsStringSync(dvRobots(siteUrl: siteUrl));

      // The stylesheet the sitemap points at. A bare urlset renders as the
      // browser's XML tree view, which says nothing about the site; crawlers
      // ignore XSLT entirely. Written only when absent, so a project that
      // wants its own keeps it.
      final stylesheet = File(p.join(web.path, 'sitemap.xsl'));
      if (!File(p.join(root, 'web', 'sitemap.xsl')).existsSync()) {
        stylesheet.writeAsStringSync(dvSitemapStylesheet(
          siteName: settings['siteName'] as String? ?? baseTitle,
          tagline: dvSeoDescription(settings) ?? '',
          accent: settings['accent'] as String? ?? '#2563EB',
          ink: settings['ink'] as String? ?? '#0B1020',
        ));
      }

      // Path URLs need the server to answer index.html for a route with no
      // file behind it -- every parameterised route, and anything added since
      // the last build. The generated router's own comment claimed this was
      // written and nothing wrote it, so a build uploaded to Apache answered
      // the host's 404 page.
      final htaccess = File(p.join(web.path, '.htaccess'));
      // Overwritten every build: build/web is output, and "only when absent"
      // meant a fix to the generated file never reached anyone who had built
      // once -- which is how a bad cache rule survived being fixed. A project
      // supplies its own by putting the file in web/, which Flutter copies.
      if (!File(p.join(root, 'web', '.htaccess')).existsSync()) {
        htaccess.writeAsStringSync(dvApacheConfig());
      }
      Logger.log('   Wrote $written route pages, sitemap.xml and robots.txt.');
    } else {
      Logger.log('   Wrote $written route pages. Set dartvel.seo.siteUrl for '
          'a sitemap and robots.txt.');
    }
  }



  /// Write what a Dartvel server needs to build any page on request.
  ///
  /// No per-route HTML: the server writes those, which is the point of the
  /// target. The sitemap and robots stay files, because each is one document
  /// that does not vary by request and generating them per fetch would be
  /// work for nothing.
  void _writeWebServerManifest(String root) {
    final web = Directory(p.join(root, 'build', 'web'));
    if (!web.existsSync()) return;

    final settings = _dartvelSection(root)['seo'];
    final seo = settings is Map ? settings : const <Object?, Object?>{};
    final siteUrl = seo['siteUrl'] as String?;

    final routes = _generatedRoutes(root);
    if (routes.isEmpty) return;

    // A previous static build in this directory left a file per route, and a
    // server that falls through to a file would serve those instead of the
    // pages it renders. The stale copy shadows the live one, and the symptom
    // is a page that will not update however often it is deployed.
    final present = web
        .listSync(recursive: true)
        .whereType<File>()
        .map((File f) => p.relative(f.path, from: web.path))
        .toList();
    var removed = 0;
    for (final String stale in dvWebServerStaleFiles(present: present)) {
      File(p.join(web.path, stale)).deleteSync();
      removed++;
    }

    File(p.join(web.path, 'dartvel_routes.json')).writeAsStringSync(
      dvWebServerManifest(
        federated: dvFederatedRoutes(root),
        routes: routes,
        titles: dvRouteTitles(_routerSource(root)),
        text: _routeText(root),
        siteUrl: siteUrl,
        // dartvel.web.server: how page data is waited for, and whether the
        // head goes out ahead of the body.
        server: DVWebServerSettings.parse(
          (_dartvelSection(root)['web'] is Map ? (_dartvelSection(root)['web']! as Map)['server'] : null),
        ),
      ),
    );

    if (siteUrl != null && siteUrl.isNotEmpty) {
      File(p.join(web.path, 'sitemap.xml'))
          .writeAsStringSync(dvSitemap(
            routes: routes,
            siteUrl: siteUrl,
            federated: dvFederatedRoutes(root).keys.toList(),
          ));
      File(p.join(web.path, 'robots.txt'))
          .writeAsStringSync(dvRobots(siteUrl: siteUrl));

      // The stylesheet the sitemap points at. A bare urlset renders as the
      // browser's XML tree view, which says nothing about the site; crawlers
      // ignore XSLT entirely. Written only when absent, so a project that
      // wants its own keeps it.
      final stylesheet = File(p.join(web.path, 'sitemap.xsl'));
      if (!File(p.join(root, 'web', 'sitemap.xsl')).existsSync()) {
        stylesheet.writeAsStringSync(dvSitemapStylesheet(
          siteName: seo['siteName'] as String? ??
              dvSeoTitle(seo, _packageName(root) ?? 'Dartvel'),
          tagline: dvSeoDescription(seo) ?? '',
          accent: seo['accent'] as String? ?? '#2563EB',
          ink: seo['ink'] as String? ?? '#0B1020',
        ));
      }

      // Path URLs need the server to answer index.html for a route with no
      // file behind it -- every parameterised route, and anything added since
      // the last build. The generated router's own comment claimed this was
      // written and nothing wrote it, so a build uploaded to Apache answered
      // the host's 404 page.
      final htaccess = File(p.join(web.path, '.htaccess'));
      // Overwritten every build: build/web is output, and "only when absent"
      // meant a fix to the generated file never reached anyone who had built
      // once -- which is how a bad cache rule survived being fixed. A project
      // supplies its own by putting the file in web/, which Flutter copies.
      if (!File(p.join(root, 'web', '.htaccess')).existsSync()) {
        htaccess.writeAsStringSync(dvApacheConfig());
      }
    }
    Logger.log('   Wrote dartvel_routes.json for ${routes.length} routes; '
        'the server renders each page on request.');
    if (removed > 0) {
      Logger.log('   Removed $removed stale page(s) from an earlier static '
          'build, which would have shadowed the rendered ones.');
    }
  }

  /// The text each route's page contains, written by generation.
  ///
  /// Read rather than derived. An earlier version guessed the source file
  /// from the route name -- `/docs` to `docs.dart` -- and got `/docs` wrong
  /// and `/cloud` not at all, because a route name is not a filename. The
  /// generator has the source in hand and says what it found; generation runs
  /// as part of every build, so this cannot go stale behind a rebuild.
  Map<String, List<String>> _routeText(String root) {
    final file = File(p.join(root, '.dart_tool', 'dartvel_route_text.json'));
    if (!file.existsSync()) return const <String, List<String>>{};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const <String, List<String>>{};
      return decoded.map((Object? route, Object? lines) => MapEntry<String, List<String>>(
            '$route',
            (lines as List<Object?>).map((Object? l) => '$l').toList(),
          ));
    } on Object {
      // A half-written manifest is a page without its text, not a failed
      // build.
      return const <String, List<String>>{};
    }
  }

  /// What prerendering captured for a route, if it ran.
  DVPrerenderedMeta? _prerendered(String webDir, String route) {
    final clean = route == '/' ? 'index' : route.substring(1);
    final file = File(p.join(webDir, 'prerender', clean, 'meta.json'));
    if (!file.existsSync()) return null;
    return dvPrerenderedMeta(file.readAsStringSync());
  }

  /// A readable name for a route, for a title when nothing better exists.
  String _routeLabel(String route) {
    final parts = route.split('/').where((String s) => s.isNotEmpty);
    if (parts.isEmpty) return 'Home';
    final last = parts.last.replaceAll('-', ' ').replaceAll('_', ' ');
    return last[0].toUpperCase() + last.substring(1);
  }

  /// The generated router's source, or empty when there is none.
  String _routerSource(String root) {
    final router =
        File(p.join(root, 'lib', 'dartvel_client', 'router.g.dart'));
    return router.existsSync() ? router.readAsStringSync() : '';
  }

  /// The routes the generator emitted, read from the generated router.
  List<String> _generatedRoutes(String root) {
    final source = _routerSource(root);
    if (source.isEmpty) return const <String>[];
    final pattern = RegExp("path: '([^']+)'");
    return pattern
        .allMatches(source)
        .map((RegExpMatch m) => m.group(1)!)
        .where((String r) => r.startsWith('/'))
        .toSet()
        .toList()
      ..sort();
  }

  /// The `dartvel:` section of pubspec.yaml, or an empty map.
  Map<Object?, Object?> _dartvelSection(String root) {
    final file = File(p.join(root, 'pubspec.yaml'));
    if (!file.existsSync()) return const <Object?, Object?>{};
    try {
      final doc = loadYaml(file.readAsStringSync());
      final section = doc is Map ? doc['dartvel'] : null;
      return section is Map ? section : const <Object?, Object?>{};
    } on Object {
      return const <Object?, Object?>{};
    }
  }

  String? _packageName(String root) {
    final file = File(p.join(root, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    try {
      final doc = loadYaml(file.readAsStringSync());
      final name = doc is Map ? doc['name'] : null;
      return name is String ? name : null;
    } on Object {
      return null;
    }
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
  bool simulator = false,
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
      // --simulator is the unsigned path, and the embedder accepts it only
      // with a debug build.
      //
      // Its own flag rather than --device-profile simulator, which is what
      // it used to be: a device profile is a section of pubspec.yaml, and
      // overloading the option meant the check that a profile is declared
      // refused a tvOS build for a reason that read as a mistake in the
      // project rather than as two features sharing one flag.
      final args = <String>[
        'build',
        'tvos',
        simulator ? '--debug' : buildMode,
        if (simulator) '--simulator',
        // tvOS presents itself to Flutter as iOS — there is no
        // TargetPlatform.tvOS — so a running app reports `Platform: ios` and,
        // being a wide screen, `Device: tablet`. A screenshot from a tvOS
        // simulator showed exactly that.
        //
        // Nothing at run time can tell the difference, so the build states it.
        // DARTVEL_PLATFORM is the override DVPlatform already consults, and
        // getting this wrong is not cosmetic: an application branching on
        // deviceType takes the touch path on a device driven by a remote.
        '--dart-define=DARTVEL_PLATFORM=tvos',
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
  String? deviceProfile,
}) {
  final command = switch (platform) {
    'android' || 'fireos' => 'apk',
    // The same Flutter web build. What differs is what Dartvel writes beside
    // it afterwards: a manifest rather than a file per route.
    'web-server' => 'web',
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

  // The selected device profile, for DVDeviceProfiles.selected: display
  // names and the kiosk override are per profile, and nothing at run time
  // can tell which machine the build is on.
  if (deviceProfile != null && deviceProfile.isNotEmpty) {
    args.add('--dart-define=DARTVEL_DEVICE_PROFILE=$deviceProfile');
  }

  if (platform == 'android' && splitPerAbi) {
    args.add('--split-per-abi');
  }
  if (platform == 'ios') {
    args.add('--no-codesign');
  }

  return List<String>.unmodifiable(args);
}
