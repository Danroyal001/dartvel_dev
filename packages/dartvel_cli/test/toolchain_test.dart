import 'package:dartvel_cli/src/utils/toolchain.dart';
import 'package:test/test.dart';

void main() {
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

  group('fuchsia toolchain', () {
    test('requires the forked embedder checkout', () {
      final requirements = toolRequirementsFor('fuchsia', home: '/home/dev');

      expect(requirements, hasLength(1));
      final embedder = requirements.single;
      // A checkout, not a binary on PATH: the embedder is driven by scripts
      // inside its own tree.
      expect(embedder.executable,
          '/home/dev/.dartvel/toolchains/dartvel_fuchsia/scripts/bootstrap.sh');
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
