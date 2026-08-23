import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/utils/toolchain.dart';
import 'package:test/test.dart';

void main() {
  visualStudioDetectionTests();
  fuchsiaInstallTests();
  group('toolRequirementsFor', () {
    test('web needs nothing beyond Flutter itself', () {
      expect(toolRequirementsFor('web'), isEmpty);
    });

    test('vscode requires npm for extension host compilation', () {
      final executables =
          toolRequirementsFor('vscode').map((r) => r.executable).toList();
      expect(executables, <String>['npm']);
    });

    test('each embedded target requires its vendor embedder', () {
      expect(
        toolRequirementsFor('tizen').map((r) => r.executable),
        contains('flutter-tizen'),
      );
      expect(
        toolRequirementsFor('sony-elinux').map((r) => r.executable),
        contains('flutter-elinux'),
      );
      expect(
        toolRequirementsFor('webos').map((r) => r.executable),
        contains('flutter-webos'),
      );
      expect(
        toolRequirementsFor('tvos').map((r) => r.executable),
        containsAll(<String>['flutter-tvos', 'xcodebuild']),
      );
    });

    test('embedders install from the Dartvel forks', () {
      final tizen = toolRequirementsFor('tizen', home: '/home/u')
          .firstWhere((r) => r.executable == 'flutter-tizen');
      expect(tizen.method, InstallMethod.automatic);
      expect(
        tizen.installCommand,
        contains('https://github.com/Danroyal001/dartvel_tizen.git'),
      );
      expect(tizen.pathHint, '/home/u/.dartvel/toolchains/dartvel_tizen/bin');
    });

    test('vendor SDKs are manual, never auto-installed', () {
      // Licence-gated or multi-gigabyte vendor installers must stay the
      // user's decision.
      final manual = <String, String>{
        'tizen': 'tizen',
        'android': 'sdkmanager',
        'ios': 'xcodebuild',
        'macos': 'xcodebuild',
        'tvos': 'xcodebuild',
        'windows': 'cl',
      };
      manual.forEach((platform, executable) {
        final requirement = toolRequirementsFor(platform)
            .firstWhere((r) => r.executable == executable);
        expect(requirement.method, InstallMethod.manual,
            reason: '$platform/$executable must not auto-install');
        expect(requirement.installHint, isNotEmpty);
      });
    });

    test('linux desktop requires its native build dependencies', () {
      final executables =
          toolRequirementsFor('linux').map((r) => r.executable).toList();
      expect(executables, containsAll(<String>['clang', 'cmake', 'ninja']));
    });

    test('webOS also requires the ares packaging CLI', () {
      final ares = toolRequirementsFor('webos')
          .firstWhere((r) => r.executable == 'ares');
      expect(ares.method, InstallMethod.automatic);
      expect(ares.installCommand, contains('@webos-tools/cli'));
    });
  });

  group('missingRequirements', () {
    test('reports only what is absent', () {
      final missing = missingRequirements(
        'webos',
        isInstalled: (executable) => executable == 'flutter-webos',
      );
      expect(missing.map((r) => r.executable), <String>['ares']);
    });

    test('is empty when everything is present', () {
      expect(
        missingRequirements('tizen', isInstalled: (_) => true),
        isEmpty,
      );
    });
  });

  group('isCiEnvironment', () {
    test('detects the CI convention', () {
      expect(isCiEnvironment({'CI': 'true'}), isTrue);
      expect(isCiEnvironment({'CI': '1'}), isTrue);
      expect(isCiEnvironment({'CI': 'false'}), isFalse);
    });

    test('detects providers that do not set CI', () {
      expect(isCiEnvironment({'GITHUB_ACTIONS': 'true'}), isTrue);
      expect(isCiEnvironment({'BUILDKITE': 'true'}), isTrue);
    });

    test('a plain developer shell is not CI', () {
      expect(
          isCiEnvironment({'HOME': '/home/dev', 'PATH': '/usr/bin'}), isFalse);
    });
  });

  group('decideAutoInstall', () {
    test('does nothing when the toolchain is complete', () {
      expect(
        decideAutoInstall(hasMissing: false, isCi: true),
        AutoInstallDecision.nothingToDo,
      );
    });

    test('prompts an interactive developer', () {
      expect(
        decideAutoInstall(hasMissing: true, isCi: false),
        AutoInstallDecision.prompt,
      );
    });

    test('installs unattended in CI rather than hanging on a prompt', () {
      expect(
        decideAutoInstall(hasMissing: true, isCi: true),
        AutoInstallDecision.installWithoutPrompting,
      );
    });

    test('--auto-install skips the prompt outside CI', () {
      expect(
        decideAutoInstall(hasMissing: true, isCi: false, autoInstallFlag: true),
        AutoInstallDecision.installWithoutPrompting,
      );
    });

    test('--no-auto-install wins even in CI', () {
      // A pipeline may deliberately require a pre-provisioned image and want
      // a missing tool to fail loudly rather than be installed mid-build.
      expect(
        decideAutoInstall(hasMissing: true, isCi: true, autoInstallFlag: false),
        AutoInstallDecision.declined,
      );
    });
  });

  group('terminal toolchain', () {
    test('a terminal target requires the flt fork and can fetch it', () {
      final requirements =
          toolRequirementsFor('linux-cli', home: '/home/dev');

      expect(requirements, isNotEmpty,
          reason: 'with no requirement, preflight finds nothing missing and '
              'never offers to install the embedder — the target just skips '
              'forever with no way forward');
      final embedder = requirements.single;
      expect(embedder.installCommand!.join(' '),
          contains('https://github.com/Danroyal001/dartvel_flt'));
      expect(embedder.method, InstallMethod.automatic,
          reason: 'an embedder fork is fetchable unattended; only the '
              'licence-gated vendor SDKs are not');
    });

    test('the executable is where Dartvel installs it, not a bare name', () {
      // The Fuchsia lesson: a plan naming a bare command that nothing ever
      // installs is unbuildable and looks fine. Dartvel-managed toolchains
      // live under ~/.dartvel/toolchains, so that is the path to check.
      final embedder =
          toolRequirementsFor('linux-cli', home: '/home/dev').single;
      expect(embedder.executable, startsWith('/home/dev/.dartvel/toolchains/'));
      expect(embedder.executable, contains('dartvel-flt'));
    });

    test('every terminal target names the same embedder', () {
      // -cli and -tui are one target under two names, and macos-cli must not
      // quietly require something different from linux-cli.
      final executables = <String>{
        for (final target in terminalBuildTargets)
          toolRequirementsFor(target, home: '/home/dev').single.executable,
      };
      expect(executables, hasLength(1));
    });

    test('the build runs exactly what this checks', () {
      // The invariant the embedder targets are held to, applied here before
      // this target grows the same defect.
      for (final target in terminalBuildTargets) {
        final plan = terminalBuildPlan(
          normalizeBuildTarget(target).platform,
          toolchainHome: '/home/dev',
        );
        final checked = toolRequirementsFor(target, home: '/home/dev')
            .map((ToolRequirement r) => r.executable);
        expect(checked, contains(plan.toolchain),
            reason: '$target would build with "${plan.toolchain}" while '
                'preflight checks something else');
      }
    });
  });

  group('fuchsia toolchain', () {
    test('requires the forked embedder checkout', () {
      final requirements = toolRequirementsFor('fuchsia', home: '/home/dev');

      expect(requirements, hasLength(1));
      final embedder = requirements.single;
      // A checkout, not a binary on PATH: the embedder is driven by scripts
      // inside its own tree.
      //
      // Specifically the script the build runs. This asserted bootstrap.sh,
      // which is the installation step — so preflight was answering "was this
      // checkout set up" when the question is "can it build". Both files
      // happen to exist in the fork, so nothing was broken; the check was
      // simply weaker than it read, in exactly the way that let a Fuchsia plan
      // name an executable nothing installs and stay green for weeks.
      expect(embedder.executable,
          '/home/dev/.dartvel/toolchains/dartvel_fuchsia/$fuchsiaAppBuildScript');
      expect(embedder.postInstall?.join(' '), contains('bootstrap.sh'),
          reason: 'bootstrap.sh is still how the checkout is prepared — it '
              'unshallows the submodules the clone deliberately skipped — but '
              'it runs after installation rather than being the thing whose '
              'absence blocks a build');
      expect(embedder.installCommand, isNotNull);
      expect(embedder.installCommand!.join(' '),
          contains('https://github.com/Danroyal001/dartvel_fuchsia.git'));
      expect(embedder.method, InstallMethod.automatic);
    });

    test('an absolute requirement is checked as a path, not a PATH lookup', () {
      // `which /some/path` answers a different question from "is it there".
      expect(isExecutableOnPath('/definitely/not/here/bootstrap.sh'), isFalse);
    });
  });
}

// Windows was reported as missing the C++ build tools on a runner that has
// them. `cl` is only on PATH inside a Developer Command Prompt, so probing for
// it there is a false negative — and a false negative here does not fail the
// build, it silently *skips* the target, which is worse.
//
// Flutter locates Visual Studio through vswhere.exe at a fixed path rather
// than through PATH, and so should this.
void visualStudioDetectionTests() {
  group('Visual Studio detection', () {
    test('an installation path means the tools are present', () {
      expect(
        visualStudioFoundIn(
          r'C:\Program Files\Microsoft Visual Studio\2022\Enterprise',
        ),
        isTrue,
      );
    });

    test('no output means no qualifying installation', () {
      // vswhere exits 0 and prints nothing when nothing matches the query,
      // so the exit code alone cannot be the answer.
      expect(visualStudioFoundIn(''), isFalse);
      expect(visualStudioFoundIn('   \r\n  \n'), isFalse);
    });

    test('several installations still count as found', () {
      expect(
        visualStudioFoundIn(
          'C:\\VS\\2022\\Community\r\nC:\\VS\\2019\\Professional\r\n',
        ),
        isTrue,
      );
    });

    test('the requirement probes vswhere rather than PATH', () {
      // The regression that matters: reverting to a PATH lookup for `cl`
      // brings back a skip on machines that can build.
      final windows = toolRequirementsFor('windows');
      expect(windows, hasLength(1));
      expect(windows.single.probe, isNotNull,
          reason: 'Visual Studio is not found on PATH');
    });

    test('a probe decides the requirement, not the PATH lookup', () {
      // isInstalled must not be consulted for a requirement that knows how to
      // answer for itself, or the false negative returns through the back door.
      final missing = missingRequirements(
        'windows',
        isInstalled: (String executable) => false,
        probeOverride: (ToolRequirement r) => true,
      );
      expect(missing, isEmpty);
    });

    test('a requirement without a probe still uses PATH', () {
      // Everything else — flutter-tizen, ares, cbindgen — is a real PATH
      // lookup and must keep working exactly as before.
      final missing = missingRequirements(
        'webos',
        isInstalled: (String executable) => false,
      );
      expect(missing, isNotEmpty);
    });
  });
}

// The Fuchsia embedder is a Bazel workspace, not a binary. Cloning it is not
// installing it: without submodules and a Bazel bootstrap there is no
// tools/bazel, so a build reaches the last step and dies on
// "./tools/bazel: No such file or directory" having already done all its work.
void fuchsiaInstallTests() {
  group('installing the Fuchsia embedder', () {
    ToolRequirement fuchsia() =>
        toolRequirementsFor('fuchsia', home: '/home/dev').single;

    test('does not shallow-clone submodules, which cannot work', () {
      // The requirement is that submodules end up initialised — bootstrap.sh
      // does that with `git submodule update --recursive --init`, unshallowed.
      //
      // Asking git for both --depth 1 and --recurse-submodules fails: a
      // shallow submodule fetch only gets the tip, and googletest is pinned to
      // a commit that is not it. "Fetched in submodule path
      // 'third_party/googletest', but it did not contain 7b0ac59d". This test
      // originally asserted --recurse-submodules, which was the wrong
      // mechanism for the right requirement.
      final command = fuchsia().installCommand!;
      expect(
        command.contains('--depth') && command.contains('--recurse-submodules'),
        isFalse,
        reason: 'a shallow clone cannot recurse submodules pinned off-tip',
      );
    });

    test('runs the bootstrap, because a clone is not an install', () {
      // Every other embedder is a binary on PATH and cloning is enough. This
      // one has to be prepared.
      expect(fuchsia().postInstall, isNotNull,
          reason: 'cloning a Bazel workspace does not make it buildable');
      expect(fuchsia().postInstall!.join(' '), contains('bootstrap.sh'));
    });

    test('the bootstrap is told where the workspace is', () {
      // Its scripts locate themselves through FUCHSIA_EMBEDDER_DIR and refuse
      // to run without it — the same variable the build invocation already
      // sets. Dartvel chose the directory, so it knows the answer; asking a
      // developer to export it for a directory we created is the wrong half of
      // the bargain.
      expect(
        fuchsia().postInstallEnvironment?['FUCHSIA_EMBEDDER_DIR'],
        '/home/dev/.dartvel/toolchains/dartvel_fuchsia',
      );
    });

    test('bootstraps for a build, not for a device', () {
      // The full bootstrap downloads a multi-gigabyte emulator image, makes
      // SSH keys and installs git hooks — all of it for running on hardware
      // that CI does not have.
      expect(fuchsia().postInstall, contains('--build-only'));
    });
  });
}
