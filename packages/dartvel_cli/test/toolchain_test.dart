import 'package:dartvel_cli/src/utils/toolchain.dart';
import 'package:test/test.dart';

void main() {
  visualStudioDetectionTests();
  group('toolRequirementsFor', () {
    test('web needs nothing beyond Flutter itself', () {
      expect(toolRequirementsFor('web'), isEmpty);
    });

    test('each embedded target requires its vendor embedder', () {
      expect(
        toolRequirementsFor('tizen').map((r) => r.executable),
        contains('flutter-tizen'),
      );
      // sony-elinux deliberately absent: it no longer uses a vendor embedder
      // command. Its own group below covers what it requires instead.
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

    test('an Android SDK is found where Flutter finds it', () {
      // The check was `sdkmanager` on PATH, and an Android SDK usually has
      // it somewhere else: a runner ships one and does not put it on PATH,
      // and Android Studio installs one that only its own shell knows about.
      // So `dartvel build android` refused on machines that build Android
      // perfectly well, which is a refusal nobody can act on -- the hint
      // says install the SDK, and the SDK is installed.
      //
      // ANDROID_HOME and ANDROID_SDK_ROOT are where Flutter looks, so they
      // are where this looks.
      final ToolRequirement sdk = toolRequirementsFor('android')
          .firstWhere((ToolRequirement r) => r.name == 'Android SDK');

      expect(sdk.probe, isNotNull,
          reason: 'PATH alone does not answer whether an SDK is installed');
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

  group('sony eLinux toolchain', () {
    test('it needs the embedder artifacts, not the flutter-elinux tool', () {
      // The tool is pinned to Flutter 3.29.3 and upstream has not committed
      // since 2025-07-09, so requiring it makes the target permanently
      // unbuildable at Dartvel's floor. A release bundle does not need it: the
      // desktop build supplies the app and assets, and these artifacts supply
      // the embedder and engine.
      final requirements =
          toolRequirementsFor('sony-elinux', home: '/home/dev');

      expect(requirements, isNotEmpty);
      final artifact = requirements.first;
      expect(artifact.executable, contains('flutter-client'),
          reason: 'what has to be present is Sony\'s embedder executable, '
              'which is what the bundle actually runs');
      expect(artifact.executable, startsWith('/home/dev/.dartvel/toolchains/'));
    });

    test('it does not require flutter-elinux at all', () {
      final executables = toolRequirementsFor('sony-elinux', home: '/home/dev')
          .map((ToolRequirement r) => r.executable);
      expect(executables, isNot(contains('flutter-elinux')));
    });
  });

  group('absolute requirements', () {

    test('an absolute requirement is checked as a path, not a PATH lookup', () {
      // `which /some/path` answers a different question from "is it there".
      expect(isExecutableOnPath('/definitely/not/here/bootstrap.sh'), isFalse);
    });

    test('a path is a path on Windows too, whichever slash it uses', () {
      // Toolchain paths are built with '/', and the check used to ask for
      // Platform.pathSeparator -- '\' on Windows -- so there an installed
      // embedder's absolute path went to `where`, which answered no.
      expect(namesALocation('C:/Users/dev/.dartvel/toolchains/x/bin/a.exe'),
          isTrue);
      expect(namesALocation(r'C:\Users\dev\bin\a.exe'), isTrue);
      expect(namesALocation('/home/dev/bin/a'), isTrue);
      expect(namesALocation('flutter'), isFalse);
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
