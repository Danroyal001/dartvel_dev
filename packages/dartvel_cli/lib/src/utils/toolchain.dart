import 'dart:io';

import 'logger.dart';

/// How a missing build tool can be obtained.
enum InstallMethod {
  /// Dartvel can fetch and install it unattended.
  automatic,

  /// A vendor installer, licence acceptance, or platform SDK that Dartvel must
  /// not install on the user's behalf. Dartvel explains, the user decides.
  manual,
}

/// A single tool a platform needs before `dartvel build <platform>` can work.
class ToolRequirement {
  const ToolRequirement({
    required this.executable,
    required this.name,
    required this.installHint,
    this.installCommand,
    this.postInstall,
    this.postInstallEnvironment,
    this.pathHint,
    this.probe,
  });

  /// The executable that must resolve on PATH for this requirement to be met.
  final String executable;

  /// Human-readable name used in messages.
  final String name;

  /// What the user should do if Dartvel cannot install this itself.
  final String installHint;

  /// The command Dartvel runs to install this, or null when it cannot.
  final List<String>? installCommand;

  /// Run after [installCommand] for tools where fetching is not installing.
  ///
  /// Every other embedder is a binary that works the moment it is on disk.
  /// Fuchsia's is a Bazel workspace: cloning it leaves no `tools/bazel`, so a
  /// build reaches its final step and dies on
  /// `./tools/bazel: No such file or directory` having already done all its
  /// work. Null wherever a clone or a package install is genuinely enough.
  final List<String>? postInstall;

  /// Variables [postInstall] needs beyond an inherited environment.
  ///
  /// The Fuchsia bootstrap locates its own workspace through
  /// `FUCHSIA_EMBEDDER_DIR` and refuses to run without it. Dartvel chose that
  /// directory, so it knows the answer — telling a developer to export a path
  /// we created would be the wrong half of the bargain, and the toolchain rule
  /// already says a tool installed during a run must reach the process that
  /// uses it.
  final Map<String, String>? postInstallEnvironment;

  /// Directory to add to PATH after an automatic install, when the tool does
  /// not land somewhere already on PATH.
  final String? pathHint;

  /// Answers whether this tool is present, for tools PATH cannot answer for.
  ///
  /// Most requirements are a binary on PATH and [executable] is the whole
  /// question. Visual Studio is not: `cl` exists only inside a Developer
  /// Command Prompt, so probing PATH reports a fully installed machine as
  /// missing it — and a false negative here does not fail a build, it silently
  /// skips the target, which is worse.
  final bool Function()? probe;

  InstallMethod get method =>
      installCommand == null ? InstallMethod.manual : InstallMethod.automatic;
}

/// Where Dartvel installs toolchains it manages itself.
String dartvelToolchainRoot(String home) => '$home/.dartvel/toolchains';

/// A Dartvel app is an ordinary Flutter package, so nothing Dartvel-specific
/// is handed to the embedder: this is the same entry point a plain
/// `flutter create` app uses, and the fork keeps it that way so it stays a
/// general embedder rather than a Dartvel one.
const String fuchsiaAppBuildScript = 'scripts/build_flutter_app.sh';


/// The tools [platform] needs, beyond a working Flutter SDK.
///
/// Repository names and executable names differ on purpose: the Dartvel forks
/// are `dartvel_tizen`, `dartvel_elinux`, `dartvel_webos`, `dartvel_tvos` and
/// `dartvel_fuchsia`, but the binaries inside them are upstream's own
/// `flutter-tizen`, `flutter-elinux`, `flutter-webos` and `flutter-tvos`.
/// Renaming those would mean patching every vendor script and would break
/// tracking upstream.
///
/// Host support is a separate question answered by `isPlatformAvailableOn`;
/// this describes what must be *installed*, assuming the host can build the
/// target at all.
List<ToolRequirement> toolRequirementsFor(String platform, {String home = ''}) {
  final root = dartvelToolchainRoot(home);

  switch (platform) {
    case 'web':
      // Flutter's own web toolchain; nothing extra to install.
      return const <ToolRequirement>[];

    case 'vscode':
      return const <ToolRequirement>[
        ToolRequirement(
          executable: 'npm',
          name: 'Node.js/npm',
          installHint:
              'Install Node.js with npm. Dartvel uses npm to install and '
              'compile the generated VS Code extension host package.',
        ),
      ];

    case 'android':
    case 'fireos':
      return const <ToolRequirement>[
        ToolRequirement(
          executable: 'sdkmanager',
          name: 'Android SDK',
          installHint:
              'Install the Android SDK (Android Studio, or the command-line '
              'tools) and set ANDROID_HOME. See '
              'https://developer.android.com/studio',
        ),
      ];

    case 'linux':
      return const <ToolRequirement>[
        ToolRequirement(
          executable: 'clang',
          name: 'Clang',
          installHint: 'sudo apt-get install clang',
          installCommand: <String>['sudo', 'apt-get', 'install', '-y', 'clang'],
        ),
        ToolRequirement(
          executable: 'cmake',
          name: 'CMake',
          installHint: 'sudo apt-get install cmake',
          installCommand: <String>['sudo', 'apt-get', 'install', '-y', 'cmake'],
        ),
        ToolRequirement(
          executable: 'ninja',
          name: 'Ninja',
          installHint: 'sudo apt-get install ninja-build',
          installCommand: <String>[
            'sudo',
            'apt-get',
            'install',
            '-y',
            'ninja-build',
          ],
        ),
        ToolRequirement(
          executable: 'pkg-config',
          name: 'pkg-config and GTK 3 headers',
          installHint: 'sudo apt-get install pkg-config libgtk-3-dev',
          installCommand: <String>[
            'sudo',
            'apt-get',
            'install',
            '-y',
            'pkg-config',
            'libgtk-3-dev',
          ],
        ),
      ];

    case 'windows':
      return const <ToolRequirement>[
        ToolRequirement(
          executable: 'cl',
          name: 'Visual Studio C++ build tools',
          installHint:
              'Install Visual Studio with the "Desktop development with C++" '
              'workload. See https://visualstudio.microsoft.com/downloads/',
          probe: isVisualStudioInstalled,
        ),
      ];

    case 'macos':
    case 'ios':
      return const <ToolRequirement>[
        ToolRequirement(
          executable: 'xcodebuild',
          name: 'Xcode',
          installHint: 'Install Xcode from the App Store, then run '
              '`sudo xcode-select --install`.',
        ),
      ];

    // Apple ships no tvOS Flutter embedder; the target rides the community
    // flutter-tvos CLI, which carries its own Flutter SDK and engine
    // artifacts. Xcode is still required — the embedder drives xcodebuild.
    case 'tvos':
      return <ToolRequirement>[
        ToolRequirement(
          executable: 'flutter-tvos',
          name: 'flutter-tvos embedder',
          installHint:
              'git clone https://github.com/Danroyal001/dartvel_tvos.git '
              'and add its bin/ to PATH.',
          installCommand: <String>[
            'git',
            'clone',
            '--depth',
            '1',
            'https://github.com/Danroyal001/dartvel_tvos.git',
            '$root/dartvel_tvos',
          ],
          pathHint: '$root/dartvel_tvos/bin',
        ),
        const ToolRequirement(
          executable: 'xcodebuild',
          name: 'Xcode',
          installHint: 'Install Xcode from the App Store, then run '
              '`sudo xcode-select --install`.',
        ),
      ];

    case 'tizen':
      return <ToolRequirement>[
        ToolRequirement(
          executable: 'flutter-tizen',
          name: 'flutter-tizen embedder',
          installHint:
              'git clone https://github.com/Danroyal001/dartvel_tizen.git '
              'and add its bin/ to PATH.',
          installCommand: <String>[
            'git',
            'clone',
            '--depth',
            '1',
            'https://github.com/Danroyal001/dartvel_tizen.git',
            '$root/dartvel_tizen',
          ],
          pathHint: '$root/dartvel_tizen/bin',
        ),
        const ToolRequirement(
          executable: 'tizen',
          name: 'Tizen Studio SDK',
          installHint:
              'Install the Tizen SDK (native CLI, the tizen-core "tz" tool, a '
              'GCC cross-toolchain, and a device rootstrap), then add '
              '<tizen-studio>/tools and <tizen-studio>/tools/ide/bin to PATH. '
              'A signing certificate is also required: '
              '`tizen certificate` followed by `tizen security-profiles add`.',
        ),
      ];

    case 'sony-elinux':
      return <ToolRequirement>[
        ToolRequirement(
          executable: 'flutter-elinux',
          name: 'flutter-elinux embedder',
          installHint:
              'git clone https://github.com/Danroyal001/dartvel_elinux.git '
              'and add its bin/ to PATH.',
          installCommand: <String>[
            'git',
            'clone',
            '--depth',
            '1',
            'https://github.com/Danroyal001/dartvel_elinux.git',
            '$root/dartvel_elinux',
          ],
          pathHint: '$root/dartvel_elinux/bin',
        ),
      ];

    case 'fuchsia':
      return <ToolRequirement>[
        ToolRequirement(
          // Not a PATH executable like the other embedders: the Fuchsia
          // embedder is a Bazel workspace driven by scripts inside its own
          // checkout, so what has to be present is the checkout itself.
          //
          // Specifically the script the *build* runs, not the one that sets
          // the checkout up. Checking bootstrap.sh passed for a checkout that
          // could not perform a build, which is the shape of "reports ready
          // and cannot build" that the Build Toolchain Rule exists to stop.
          // postInstall below still runs bootstrap.sh; it is an installation
          // step rather than the thing whose absence should block a build.
          executable: '$root/dartvel_fuchsia/$fuchsiaAppBuildScript',
          name: 'Fuchsia Flutter embedder',
          installHint:
              'git clone https://github.com/Danroyal001/dartvel_fuchsia.git '
              'and run its scripts/bootstrap.sh.',
          installCommand: <String>[
            'git',
            'clone',
            '--depth',
            '1',
            // Deliberately not --recurse-submodules: combined with --depth 1
            // it fails, because a shallow submodule fetch only gets the tip
            // and googletest is pinned off-tip. bootstrap.sh below initialises
            // them unshallowed, which is the mechanism that works.
            'https://github.com/Danroyal001/dartvel_fuchsia.git',
            '$root/dartvel_fuchsia',
          ],
          // A clone is not an install here. The bootstrap initialises the
          // submodules and produces tools/bazel; --build-only stops it before
          // the SSH keys, git hooks and the multi-gigabyte emulator image,
          // which exist for running on a device rather than producing one.
          postInstall: <String>[
            '$root/dartvel_fuchsia/scripts/bootstrap.sh',
            '--build-only',
          ],
          postInstallEnvironment: <String, String>{
            'FUCHSIA_EMBEDDER_DIR': '$root/dartvel_fuchsia',
          },
          pathHint: '$root/dartvel_fuchsia/tools',
        ),
      ];

    case 'webos':
      return <ToolRequirement>[
        ToolRequirement(
          executable: 'flutter-webos',
          name: 'flutter-webos embedder',
          installHint:
              'git clone https://github.com/Danroyal001/dartvel_webos.git '
              'and add its bin/ to PATH.',
          installCommand: <String>[
            'git',
            'clone',
            '--depth',
            '1',
            'https://github.com/Danroyal001/dartvel_webos.git',
            '$root/dartvel_webos',
          ],
          pathHint: '$root/dartvel_webos/bin',
        ),
        const ToolRequirement(
          executable: 'ares',
          name: 'webOS CLI (ares)',
          installHint: 'npm install -g @webos-tools/cli',
          installCommand: <String>[
            'npm',
            'install',
            '-g',
            '@webos-tools/cli',
          ],
        ),
      ];

    default:
      return const <ToolRequirement>[];
  }
}

/// The subset of [toolRequirementsFor] that is not currently installed.
///
/// [isInstalled] is injected so the decision is testable without touching the
/// host's real PATH.
List<ToolRequirement> missingRequirements(
  String platform, {
  required bool Function(String executable) isInstalled,
  String home = '',
  bool Function(ToolRequirement requirement)? probeOverride,
}) {
  return toolRequirementsFor(platform, home: home)
      .where((requirement) {
        // A requirement that knows how to answer for itself is asked; only
        // the rest fall back to PATH. Consulting PATH anyway would let the
        // false negative back in through the side door.
        final probe = requirement.probe;
        if (probe != null) {
          return !(probeOverride?.call(requirement) ?? probe());
        }
        return !isInstalled(requirement.executable);
      })
      .toList(growable: false);
}

/// Where the Visual Studio Installer puts `vswhere.exe`.
///
/// A fixed location by design: it is how a tool finds Visual Studio without
/// knowing which edition or year is installed.
String vswherePath(Map<String, String> environment) {
  final programFiles =
      environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
  return '$programFiles\\Microsoft Visual Studio\\Installer\\vswhere.exe';
}

/// Whether [output] from `vswhere` names at least one installation.
///
/// `vswhere` exits 0 and prints nothing when the query matches nothing, so the
/// exit code cannot be the answer — the output has to be read.
bool visualStudioFoundIn(String output) => output.trim().isNotEmpty;

/// Whether Visual Studio with the C++ toolset is installed.
///
/// Asks `vswhere` for an installation carrying the VC tools component, which
/// is what `flutter build windows` needs and what Flutter itself queries for.
/// Never true off Windows.
bool isVisualStudioInstalled() {
  if (!Platform.isWindows) return false;
  final vswhere = vswherePath(Platform.environment);
  if (!File(vswhere).existsSync()) return false;
  try {
    final result = Process.runSync(vswhere, <String>[
      '-latest',
      '-products',
      '*',
      '-requires',
      'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
      '-property',
      'installationPath',
    ]);
    return visualStudioFoundIn('${result.stdout}');
  } catch (_) {
    return false;
  }
}

/// Whether Dartvel is running unattended and must not wait on a prompt.
///
/// Honours the `CI` convention that every major CI provider sets, plus the
/// provider-specific variables for the ones that historically did not.
bool isCiEnvironment(Map<String, String> environment) {
  const truthy = <String>{'true', '1', 'yes'};
  if (truthy.contains((environment['CI'] ?? '').toLowerCase())) {
    return true;
  }
  const providerVariables = <String>[
    'GITHUB_ACTIONS',
    'GITLAB_CI',
    'BUILDKITE',
    'CIRCLECI',
    'TF_BUILD',
  ];
  return providerVariables.any((name) => environment.containsKey(name));
}

/// What to do about missing tools, before any prompting happens.
enum AutoInstallDecision {
  /// Nothing is missing.
  nothingToDo,

  /// Install without asking (CI, or an explicit --yes/--auto-install).
  installWithoutPrompting,

  /// Ask the user first.
  prompt,

  /// The user opted out; report and skip.
  declined,
}

/// Decides how to handle missing tools.
///
/// In CI, prompting would hang the job forever, so an unattended run installs
/// what it can. An explicit `--no-auto-install` always wins, including in CI,
/// so a pipeline can demand a pre-provisioned image.
AutoInstallDecision decideAutoInstall({
  required bool hasMissing,
  required bool isCi,
  bool? autoInstallFlag,
}) {
  if (!hasMissing) return AutoInstallDecision.nothingToDo;
  if (autoInstallFlag == false) return AutoInstallDecision.declined;
  if (autoInstallFlag == true || isCi) {
    return AutoInstallDecision.installWithoutPrompting;
  }
  return AutoInstallDecision.prompt;
}

/// Whether [executable] resolves on the current PATH.
bool isExecutableOnPath(String executable) {
  // An absolute path is a location, not a PATH lookup. The Fuchsia embedder is
  // a checkout rather than a binary on PATH, and asking `which` about a path
  // that does not exist yet answers a different question.
  if (executable.contains(Platform.pathSeparator)) {
    return File(executable).existsSync();
  }
  try {
    final locator = Platform.isWindows ? 'where' : 'which';
    final result =
        Process.runSync(locator, <String>[executable], runInShell: true);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Asks the user whether to install [missing]. Returns false when stdin cannot
/// be read, so a non-interactive shell never blocks.
bool promptForInstall(List<ToolRequirement> missing) {
  final installable =
      missing.where((r) => r.method == InstallMethod.automatic).toList();
  if (installable.isEmpty) return false;

  Logger.log('');
  Logger.log('Dartvel can install ${installable.length} of these for you:');
  for (final requirement in installable) {
    Logger.log('   • ${requirement.name}');
  }
  stdout.write('Install now? [Y/n] ');

  try {
    final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    return answer.isEmpty || answer == 'y' || answer == 'yes';
  } on StdinException {
    // No terminal attached; treat as declined rather than hanging.
    return false;
  } catch (_) {
    return false;
  }
}

/// Installs what it can and returns the requirements still missing afterwards.
Future<List<ToolRequirement>> installRequirements(
  List<ToolRequirement> missing,
) async {
  final stillMissing = <ToolRequirement>[];

  for (final requirement in missing) {
    final command = requirement.installCommand;
    if (command == null) {
      stillMissing.add(requirement);
      continue;
    }

    Logger.log('📥 Installing ${requirement.name}...');
    final result = await Process.run(
      command.first,
      command.sublist(1),
      runInShell: true,
    );

    if (result.exitCode == 0 && requirement.postInstall != null) {
      // Fetching is not always installing. A cloned Bazel workspace has no
      // tools/bazel until it is bootstrapped, and without this the build gets
      // all the way to its final step before discovering that.
      final prepare = requirement.postInstall!;
      Logger.log('🔧 Preparing ${requirement.name}...');
      final prepared = await Process.run(
        prepare.first,
        prepare.sublist(1),
        runInShell: true,
        environment: requirement.postInstallEnvironment,
      );
      if (prepared.exitCode != 0) {
        Logger.log('⚠️  Failed to prepare ${requirement.name}.');
        final text = (prepared.stderr as Object?)?.toString().trim() ?? '';
        if (text.isNotEmpty) Logger.log('   ${text.split('\n').last}');
        stillMissing.add(requirement);
        continue;
      }
    }

    if (result.exitCode != 0) {
      Logger.log('⚠️  Failed to install ${requirement.name}.');
      final stderrText = (result.stderr as Object?)?.toString().trim() ?? '';
      if (stderrText.isNotEmpty) {
        // The last lines, not the first. git's first stderr line is always
        // "Cloning into '...'", so reporting the first line hid every real
        // failure behind progress noise — including the submodule error that
        // this comment exists because of.
        final lines = stderrText
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        for (final line in lines.reversed.take(3).toList().reversed) {
          Logger.log('   $line');
        }
      }
      stillMissing.add(requirement);
      continue;
    }

    Logger.log('✅ Installed ${requirement.name}.');
    if (requirement.pathHint != null) {
      Logger.log('   Add to PATH: ${requirement.pathHint}');
    }
  }

  return stillMissing;
}

/// Prints what the user must do for anything Dartvel could not install.
void reportUnresolved(String platform, List<ToolRequirement> unresolved) {
  Logger.log('');
  Logger.log('⚠️  $platform needs tools Dartvel cannot install for you:');
  for (final requirement in unresolved) {
    Logger.log('   • ${requirement.name}');
    Logger.log('     ${requirement.installHint}');
  }
}
