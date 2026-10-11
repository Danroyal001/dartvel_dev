/// Build targets that are not compiled into this package.
///
/// The free targets -- Android, iOS, web and web-server, the desktops,
/// embedded Linux and the television platforms -- are built by
/// `BuildCommand` itself. Every other target is a [DVBuildTarget] that a
/// separate package implements and registers, and the CLI knows it only by
/// this interface. `dartvel build <name>` for a target nobody registered
/// prints [dvTargetRefusal] and exits; it never fails with a stack trace.
///
/// A target package is an ordinary Dart package with
///
/// - a `dartvel_targets.yaml` at its root naming the targets it provides and
///   the executable that provides them, and
/// - that executable, which registers its targets and runs the CLI:
///
/// ```dart
/// import 'package:dartvel_cli/build_targets.dart';
///
/// Future<void> main(List<String> arguments) =>
///     dvRunWithTargets(arguments, <DVBuildTarget>[MyTarget()]);
/// ```
///
/// A project that depends on the package (a dev dependency is enough) gets
/// its targets: `dartvel build <name>` finds the manifest through the
/// project's `.dart_tool/package_config.json` and runs the build through the
/// package's executable. Nothing is downloaded, nothing phones home, and
/// nothing about the target package reaches a built application.
library;

import 'dart:async';
import 'dart:io';

import '../utils/toolchain.dart' show ToolRequirement;
import 'render_backends.dart' show DVRenderBackend;

/// How a target build ended.
enum DVBuildTargetResult { succeeded, failed, skipped }

/// A step of a free platform's pipeline that a [DVPlatformVariant] can leave
/// out. Leaving one out takes back out whatever an earlier build of the
/// platform wrote for it, so the variant's build never carries it.
enum DVPlatformStep {
  /// The lock-task launcher and its device-admin receiver (`dartvel.kiosk`).
  kiosk,

  /// Home-screen widget providers (`@DVHomeWidget`).
  homeWidgets,

  /// The store billing library and bridge (`dartvel.purchases`).
  purchases,

  /// The pairing a development build carries for `dartvel dev`.
  devClient,
}

/// A free platform's pipeline, adjusted for a target that rides on it.
///
/// A target built from the Android or iOS project is still that project: the
/// splash, launcher identity, deep links, release signing and every other
/// writer prepare it exactly as they do for the free build. A variant adds to
/// that rather than repeating it.
class DVPlatformVariant {
  const DVPlatformVariant({
    required this.name,
    this.flutterArguments = const <String>[],
    this.leaveOut = const <DVPlatformStep, String>{},
    this.prepare,
    this.finish,
  });

  /// The target's name, used wherever the build reports what it is building.
  final String name;

  /// Appended to the free platform's `flutter build` arguments.
  final List<String> flutterArguments;

  /// Steps this target does not carry, each with the reason printed when the
  /// project declares it.
  final Map<DVPlatformStep, String> leaveOut;

  /// Runs after Dartvel's own writers have prepared the native project and
  /// before `flutter build`. Returning false fails the build.
  final FutureOr<bool> Function(DVBuildTargetContext context)? prepare;

  /// Runs once the Flutter build has ended, whether or not it succeeded, when
  /// [prepare] ran. [built] says whether it did. Returning false fails a build
  /// that had succeeded; the return value is ignored when [built] is false.
  final FutureOr<bool> Function(DVBuildTargetContext context,
      {required bool built})? finish;
}

/// The options `dartvel build` was given.
class DVBuildOptions {
  const DVBuildOptions({
    required this.buildMode,
    required this.profile,
    this.entryPoint,
    this.simulator = false,
    this.arch = 'arm64',
    this.archExplicit = false,
    this.format,
    this.buildNumber,
    this.buildName,
    this.obfuscate = false,
    this.treeShakeIcons = true,
    this.splitPerAbi = false,
    this.deviceProfile,
    this.timeout,
    this.codesign = true,
    this.exportOptionsPlist,
    this.autoInstall,
  });

  /// Flutter's mode flag: `--release`, `--profile` or `--debug`.
  final String buildMode;

  /// `release`, `profile` or `development`.
  final String profile;

  /// `--target`: the entry point, or null for Flutter's default.
  final String? entryPoint;
  final bool simulator;
  final String arch;
  final bool archExplicit;
  final String? format;
  final String? buildNumber;
  final String? buildName;

  /// Already false outside a release build.
  final bool obfuscate;
  final bool treeShakeIcons;
  final bool splitPerAbi;
  final String? deviceProfile;

  /// When a build that stops making progress is killed; null never.
  final Duration? timeout;
  final bool codesign;
  final String? exportOptionsPlist;
  final bool? autoInstall;

  bool get isRelease => buildMode == '--release';

  DVBuildOptions copyWith({
    bool? splitPerAbi,
    String? Function()? format,
    bool? simulator,
    bool? obfuscate,
  }) =>
      DVBuildOptions(
        buildMode: buildMode,
        profile: profile,
        entryPoint: entryPoint,
        simulator: simulator ?? this.simulator,
        arch: arch,
        archExplicit: archExplicit,
        format: format == null ? this.format : format(),
        buildNumber: buildNumber,
        buildName: buildName,
        obfuscate: obfuscate ?? this.obfuscate,
        treeShakeIcons: treeShakeIcons,
        splitPerAbi: splitPerAbi ?? this.splitPerAbi,
        deviceProfile: deviceProfile,
        timeout: timeout,
        codesign: codesign,
        exportOptionsPlist: exportOptionsPlist,
        autoInstall: autoInstall,
      );
}

/// What a [DVBuildTarget] is handed: the project, the options, and the parts
/// of the CLI's own pipeline it may use.
abstract interface class DVBuildTargetContext {
  /// The project being built.
  String get projectRoot;

  DVBuildOptions get options;

  /// `Platform.operatingSystem` of the machine building.
  String get hostOs;

  /// The home directory Dartvel-managed toolchains are installed under, as
  /// `<home>/.dartvel/toolchains`.
  String get toolchainHome;

  /// The `dartvel:` section of the project's pubspec.yaml, or empty.
  Map<Object?, Object?> get dartvelSection;

  /// The environment child processes should get: the inherited one plus any
  /// toolchain installed during this run. Null when nothing was added.
  Map<String, String>? get environment;

  void log(String line);

  /// Runs [executable] to completion and returns what it printed.
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  /// Starts [executable] with its output passed through and waits for it,
  /// killing it when it exceeds [DVBuildOptions.timeout]. Returns its exit
  /// code, or null when it was killed (having said so).
  Future<int?> stream(
    String executable,
    List<String> arguments, {
    required String description,
    String? workingDirectory,
    Map<String, String>? environment,
  });

  /// Whether [executable] resolves on PATH (or exists, when absolute).
  bool isOnPath(String executable);

  /// Whether pubspec.yaml declares [package] in any dependency section.
  bool hasDependency(String package);

  /// Generates the platform directory (`web/`, `android/`, ...) when the
  /// project has none. False, having said why, when that failed.
  Future<bool> ensureScaffold(String platform);

  /// Runs the free [platform]'s pipeline -- `android`, `ios`, `web` and the
  /// rest -- with [variant] applied, and [options] in place of the ones the
  /// command was given.
  Future<DVBuildTargetResult> buildPlatform(
    String platform, {
    DVPlatformVariant? variant,
    DVBuildOptions? options,
  });
}

/// A build target provided by a package rather than by the CLI.
abstract class DVBuildTarget {
  const DVBuildTarget();

  /// What follows `dartvel build`.
  String get name;

  /// Other names the target answers to.
  List<String> get aliases => const <String>[];

  /// One line for `dartvel targets`.
  String get summary;

  /// Whether a [hostOs] machine can build this target at all. Asked before
  /// tooling, so nothing is offered for install on a host that cannot use it.
  bool availableOn(String hostOs);

  /// The free platform this target's pipeline rides on, whose tools it needs
  /// too, or null for a target that builds itself.
  String? get basePlatform => null;

  /// What has to be installed, beyond [basePlatform]'s tools. Dartvel offers
  /// to install the automatic ones exactly as it does for a free target.
  List<ToolRequirement> requirements({
    required String home,
    required String hostOs,
  }) =>
      const <ToolRequirement>[];

  /// Whether `dartvel build all` builds this target. False for a target that
  /// is another presentation of one `all` already builds.
  bool get buildsWithAll => true;

  /// The rendering backends this target links, or null for the ones the
  /// project's pubspec asks for.
  Set<DVRenderBackend>? get renderBackends => null;

  /// Why `--format` and the signing options cannot build this target, or null
  /// to leave the question to the CLI's own rules.
  String? packageFormatProblem({
    String? format,
    bool simulator = false,
  }) =>
      null;

  /// Builds the target. Generation has already run.
  Future<DVBuildTargetResult> build(DVBuildTargetContext context);

  /// The Flutter device `dartvel dev <name>` runs on, or null when the target
  /// has no development loop of its own.
  String? get devDevice => null;

  /// Prepares the project for `dartvel dev <name>`, before Flutter runs.
  /// Returning false stops the command. Only asked when [devDevice] is set.
  Future<bool> prepareDev(DVBuildTargetContext context) async => true;

  /// `dartvel doctor --target <name>`: report what the build needs, with the
  /// `[+]`/`[!]`/`[i]` prefixes the rest of doctor uses.
  Future<void> doctor(DVBuildTargetContext context) async {}
}

/// The targets registered in this process.
abstract final class DVBuildTargets {
  static final Map<String, DVBuildTarget> _byName = <String, DVBuildTarget>{};
  static final List<DVBuildTarget> _targets = <DVBuildTarget>[];

  /// Makes [target] buildable under its name and every alias. A free target's
  /// name is refused: it is built by the CLI, and a package that replaced it
  /// would change what a free build does.
  static void register(DVBuildTarget target) {
    for (final String name in <String>[target.name, ...target.aliases]) {
      if (dvFreeTargetNames.contains(name)) {
        throw ArgumentError.value(name, 'target.name',
            'is a free target the CLI builds itself');
      }
      _byName[name] = target;
    }
    _targets.add(target);
  }

  /// The target registered under [name], or null.
  static DVBuildTarget? lookup(String name) => _byName[name];

  /// Every registered target, in registration order.
  static List<DVBuildTarget> get all =>
      List<DVBuildTarget>.unmodifiable(_targets);

  /// Every name and alias registered.
  static Set<String> get names => _byName.keys.toSet();

  /// Forgets every registration. For tests.
  static void clear() {
    _byName.clear();
    _targets.clear();
  }
}

/// Every target name the CLI builds itself.
///
/// Kept beside the paid list rather than derived from the build command so
/// that the two can be read side by side, and so a target package cannot
/// register over one.
const Set<String> dvFreeTargetNames = <String>{
  'web', 'web-server', 'android', 'fireos', 'ios', 'macos',
  'windows', 'linux', 'tizen', 'tpk', 'sony-elinux', 'sony-elinux-iso',
  'sony-elinux-img', 'webos', 'tvos', 'all',
};

/// Targets that need a paid Dartvel Cloud plan, each with what it builds.
///
/// They are built by the `dartvel_targets_pro` package, which comes with any
/// Cloud plan; the CLI knows only their names, so that asking for one on a
/// free install says what it is and how to get it instead of "not a known
/// platform". Releases 0.11.5 and earlier built them in the open and remain
/// MIT licensed.
const Map<String, String> dvPaidTargets = <String, String>{
  'visionos': 'Apple Vision Pro, as the iPad build "Designed for iPad"',
  'horizon': 'Meta Horizon OS (Quest) panel app',
  'chrome-extension': 'Chromium browser extension (Chrome, Edge, Brave)',
  'firefox-extension': 'Firefox browser extension',
  'vscode': 'VS Code extension',
  'linux-cli': 'Linux, rendered in a terminal (alias linux-tui)',
  'linux-tui': 'Linux, rendered in a terminal',
  'macos-cli': 'macOS, rendered in a terminal (alias macos-tui)',
  'macos-tui': 'macOS, rendered in a terminal',
  'windows-cli': 'Windows, rendered in a terminal (alias windows-tui)',
  'windows-tui': 'Windows, rendered in a terminal',
  'fuchsia': 'Fuchsia, through the out-of-tree embedder',
  'fuchsia-cli': 'Fuchsia, rendered in a terminal (alias fuchsia-tui)',
  'fuchsia-tui': 'Fuchsia, rendered in a terminal',
  'telegram': 'Telegram Mini App, the web build inside Telegram',
};

/// The package that implements [dvPaidTargets].
const String dvTargetsProPackage = 'dartvel_targets_pro';

/// What `dartvel build <target>` says when [target] is a paid target and no
/// package that provides it is installed.
String dvTargetRefusal(String target) {
  final String? what = dvPaidTargets[target];
  return <String>[
    '$target${what == null ? '' : ' ($what)'} is a paid target: it is '
        'included in every Dartvel Cloud plan and is not part of the free '
        'install.',
    '',
    '  Build it on Dartvel Cloud:   dartvel build $target --cloud',
    '  Or build it on this machine: dartvel targets add pro',
    '    which adds the $dvTargetsProPackage package to this project. It is '
        'private, so it needs the access that comes with a Cloud plan.',
    '',
    '  Free targets: android, fireos, ios, web, web-server, macos, '
        'windows, linux, sony-elinux, tizen, webos, tvos.',
    '  Dartvel 0.11.5 and earlier still build $target under the MIT licence.',
  ].join('\n');
}

/// Whether [name] is a paid target or one a package registered.
bool dvIsPackageTarget(String name) =>
    dvPaidTargets.containsKey(name) || DVBuildTargets.lookup(name) != null;

/// The second name of each paid target that has one, and the name Dartvel
/// Cloud knows it by. `-tui` says what a terminal build does and `-cli` where
/// it runs; they are one target.
const Map<String, String> dvPaidTargetAliases = <String, String>{
  'linux-tui': 'linux-cli',
  'macos-tui': 'macos-cli',
  'windows-tui': 'windows-cli',
  'fuchsia-tui': 'fuchsia-cli',
};
