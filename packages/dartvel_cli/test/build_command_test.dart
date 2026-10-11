import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/utils/toolchain.dart';
import 'package:dartvel_core/dartvel.dart' show DVImageVariants;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('resolveFlutterBuildArguments', () {
    test('an iOS simulator build asks Flutter for the simulator, unsigned', () {
      // A development build a simulator can install. --no-codesign is for
      // device builds; a simulator app is never signed.
      final args = resolveFlutterBuildArguments(
        platform: 'ios',
        buildMode: '--debug',
        simulator: true,
      );
      expect(args, containsAllInOrder(<String>['build', 'ios', '--debug']));
      expect(args, contains('--simulator'));
      expect(args, isNot(contains('--no-codesign')));

      final device = resolveFlutterBuildArguments(
        platform: 'ios',
        buildMode: '--debug',
      );
      expect(device, isNot(contains('--simulator')));
      expect(device, contains('--no-codesign'));
    });

    test('uses supported web flags for current Flutter SDKs', () {
      final args = resolveFlutterBuildArguments(
        platform: 'web',
        buildMode: '--release',
        obfuscate: true,
        treeShakeIcons: true,
      );

      expect(args, <String>[
        'build',
        'web',
        '--release',
        '--tree-shake-icons',
      ]);
      expect(args, isNot(contains('--obfuscate')));
      expect(args, isNot(contains('--web-renderer')));
    });

    test('a web-server build tells the app its own server signs accounts in', () {
      // The page cannot tell what served it. Without this the development
      // auth provider an app configures checked passwords in the browser tab
      // and a real account on the binary could not sign in through /login.
      final server = resolveFlutterBuildArguments(
        platform: 'web-server',
        buildMode: '--release',
      );
      expect(server, contains('--dart-define=DARTVEL_WEB_SERVER=true'));

      final web = resolveFlutterBuildArguments(platform: 'web', buildMode: '--release');
      expect(web.where((String a) => a.contains('DARTVEL_WEB_SERVER')), isEmpty);
    });

    test('only a web-server build that serves Studio compiles Studio in', () {
      // Studio is routes of the application behind a compile-time define.
      // The web-server binary guards it; a static export has no server to
      // guard it with, so it never carries Studio, whatever it is asked.
      final studio = resolveFlutterBuildArguments(
        platform: 'web-server',
        buildMode: '--release',
        studio: true,
      );
      expect(studio, contains('--dart-define=dartvel.studio=true'));

      final noStudio = resolveFlutterBuildArguments(
          platform: 'web-server', buildMode: '--release');
      expect(noStudio.where((String a) => a.contains('dartvel.studio')), isEmpty);

      for (final String platform in <String>['web', 'android', 'linux']) {
        final args = resolveFlutterBuildArguments(
            platform: platform, buildMode: '--release', studio: true);
        expect(args.where((String a) => a.contains('dartvel.studio')), isEmpty,
            reason: platform);
      }
    });

    test('--device-profile reaches the app as DARTVEL_DEVICE_PROFILE', () {
      // Nothing at run time can tell which machine a desktop build is on;
      // the build states it, and DVDeviceProfiles.selected reads it.
      final args = resolveFlutterBuildArguments(
        platform: 'linux',
        buildMode: '--release',
        deviceProfile: 'frontDesk',
      );
      expect(args, contains('--dart-define=DARTVEL_DEVICE_PROFILE=frontDesk'));

      final plain = resolveFlutterBuildArguments(platform: 'linux', buildMode: '--release');
      expect(plain.where((String a) => a.contains('DARTVEL_DEVICE_PROFILE')), isEmpty);
    });

    test('image variants reach a web build as DARTVEL_IMAGES, and only a web build', () {
      // What the build wrote and whether a server resizes: DVImageView cannot
      // find out either at run time, and asking for a variant nobody wrote
      // is a 404 for every image on the page.
      const variants = DVImageVariants(
        assetWidths: <String, int>{'assets/assets/hero.png': 1600},
      );
      for (final String platform in <String>['web', 'web-server']) {
        expect(
          resolveFlutterBuildArguments(
            platform: platform,
            buildMode: '--release',
            imageVariants: variants,
          ),
          contains('--dart-define=DARTVEL_IMAGES=${variants.toDartDefine()}'),
          reason: platform,
        );
      }

      final linux = resolveFlutterBuildArguments(
        platform: 'linux',
        buildMode: '--release',
        imageVariants: variants,
      );
      expect(linux.where((String a) => a.contains('DARTVEL_IMAGES')), isEmpty,
          reason: 'variants are files a web host serves');

      final none = resolveFlutterBuildArguments(
        platform: 'web',
        buildMode: '--release',
        imageVariants: const DVImageVariants(),
      );
      expect(none.where((String a) => a.contains('DARTVEL_IMAGES')), isEmpty,
          reason: 'nothing built, nothing handed over');
    });

    test('maps Android-family platforms to apk builds', () {
      expect(
        resolveFlutterBuildArguments(
          platform: 'android',
          buildMode: '--release',
          splitPerAbi: true,
          obfuscate: true,
        ),
        <String>[
          'build',
          'apk',
          '--release',
          '--obfuscate',
          '--split-debug-info',
          'build/debug-info',
          '--split-per-abi',
        ],
      );

      expect(
        resolveFlutterBuildArguments(
          platform: 'fireos',
          buildMode: '--release',
        ),
        <String>['build', 'apk', '--release'],
      );
    });

    test('tvOS is not a Flutter build platform in disguise', () {
      // `flutter build ios` produces an iPhone app whatever the caller names
      // it; tvOS belongs to the flutter-tvos embedder.
      expect(flutterBuildPlatforms, isNot(contains('tvos')));
      expect(embeddedBuildPlatforms, contains('tvos'));
    });
  });

  group('normalizeBuildTarget', () {
    test('splits Sony eLinux distribution targets into platform + format', () {
      expect(
        normalizeBuildTarget('sony-elinux-iso'),
        (platform: 'sony-elinux', format: 'iso'),
      );
      expect(
        normalizeBuildTarget('sony-elinux-img'),
        (platform: 'sony-elinux', format: 'img'),
      );
    });

    test('passes non-distribution targets through with a null format', () {
      expect(
        normalizeBuildTarget('sony-elinux'),
        (platform: 'sony-elinux', format: null),
      );
      expect(
        normalizeBuildTarget('all'),
        (platform: 'all', format: null),
      );
    });

    test('aliases tpk to the tizen target', () {
      expect(
        normalizeBuildTarget('tpk'),
        (platform: 'tizen', format: null),
      );
    });
  });

  group('resolveEmbeddedBuildPlan', () {
    test('builds Tizen through flutter-tizen', () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'tizen',
        buildMode: '--release',
        arch: 'arm64',
        deviceProfile: 'lobby-display',
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-tizen');
      expect(plan.arguments, <String>[
        'build',
        'tpk',
        '--release',
        '--device-profile',
        'lobby-display',
      ]);
    });

    test('Sony eLinux has no external embedder command', () {
      // It used to return a `flutter-elinux build elinux` plan. That tool is
      // pinned to Flutter 3.29.3 with no upstream commit since 2025-07-09, so
      // a plan naming it describes a build that cannot run at Dartvel's floor.
      // The release bundle is assembled instead — see build/elinux_bundle.dart
      // and its tests, which cover what replaced this.
      final plan = resolveEmbeddedBuildPlan(
        platform: 'sony-elinux',
        buildMode: '--release',
        arch: 'arm64',
      );
      expect(plan, isNull);
    });

    test('builds webOS through flutter-webos (LG embedder)', () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'webos',
        buildMode: '--release',
        arch: 'arm64',
        deviceProfile: 'lg-tv',
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-webos');
      expect(plan.arguments, <String>[
        'build',
        'webos',
        '--release',
        '--device-profile',
        'lg-tv',
      ]);
    });

    test('builds tvOS through flutter-tvos (community embedder)', () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'tvos',
        buildMode: '--release',
        arch: 'arm64',
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-tvos');
      // The define is part of the command, not incidental: tvOS reports
      // itself to Flutter as iOS, so the build has to say otherwise.
      expect(plan.arguments,
          <String>['build', 'tvos', '--release',
              '--dart-define=DARTVEL_PLATFORM=tvos']);
    });

    test('tvOS simulator builds are debug: the only unsigned path is JIT', () {
      // A release/profile device build requires a configured Xcode signing
      // team; the embedder accepts --simulator only with a debug build.
      final plan = resolveEmbeddedBuildPlan(
        platform: 'tvos',
        buildMode: '--release',
        arch: 'arm64',
        simulator: true,
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-tvos');
      expect(plan.arguments, <String>[
        'build',
        'tvos',
        '--debug',
        '--simulator',
        '--dart-define=DARTVEL_PLATFORM=tvos',
      ]);
    });

    test('a device profile is not how a simulator is asked for', () {
      // They were the same flag: --device-profile simulator meant the
      // unsigned tvOS path. Two things sharing one option is how the check
      // that a profile is declared came to refuse a tvOS build -- "simulator"
      // is not a profile and never was, and the build that had been passing
      // it was refused for a reason that read as a mistake in the project.
      final plan = resolveEmbeddedBuildPlan(
        platform: 'tvos',
        buildMode: '--release',
        arch: 'arm64',
        deviceProfile: 'simulator',
      );

      expect(plan!.arguments, isNot(contains('--simulator')));
      expect(plan.arguments, contains('--release'));
    });

    test('embedders that need a platform directory carry how to make one', () {
      // Each of these refuses to build a project with no platform directory
      // ("This project is not configured for <platform>"). The directory is
      // generated output, so the plan carries the command that generates it.
      // sony-elinux is deliberately absent. It needed an `elinux/` directory
      // because flutter-elinux read one; the assembled release bundle is built
      // from the desktop build instead, which uses `linux/` — a directory the
      // project already has.
      final expected = <String, String>{
        'tizen': 'tizen',
        'webos': 'webos',
        'tvos': 'tvos',
      };
      expected.forEach((platform, directory) {
        final plan = resolveEmbeddedBuildPlan(
          platform: platform,
          buildMode: '--release',
          arch: 'arm64',
        );
        expect(plan!.scaffoldDirectory, directory,
            reason: '$platform needs $directory/');
        expect(plan.scaffoldArguments.first, 'create',
            reason: '$platform scaffold must be generated by the embedder');
      });
    });

    test('tvOS tells the app it is a television', () {
      // The tvOS simulator presents itself to Flutter as iOS — there is no
      // TargetPlatform.tvOS — so without this the running app reports
      // `Platform: ios` and `Device: tablet`. A screenshot from a tvOS
      // simulator showed exactly that.
      //
      // DARTVEL_PLATFORM is the override DVPlatform already consults, so the
      // build states what the runtime cannot infer.
      final plan = resolveEmbeddedBuildPlan(
        platform: 'tvos',
        buildMode: '--release',
        arch: 'arm64',
      );

      expect(plan!.arguments, contains('--dart-define=DARTVEL_PLATFORM=tvos'));
    });

    test('the other embedders do not get the tvOS define', () {
      // It exists to correct a platform that lies about itself. Setting it
      // elsewhere would override a value those platforms report correctly.
      for (final platform in <String>['tizen', 'webos', 'sony-elinux']) {
        final plan = resolveEmbeddedBuildPlan(
          platform: platform,
          buildMode: '--release',
          arch: 'arm64',
        );
        if (plan == null) continue;
        expect(
          plan.arguments.where((String a) => a.contains('DARTVEL_PLATFORM')),
          isEmpty,
          reason: '$platform reports itself correctly',
        );
      }
    });

    test('returns null for non-embedded platforms', () {
      expect(
        resolveEmbeddedBuildPlan(
          platform: 'android',
          buildMode: '--release',
          arch: 'arm64',
        ),
        isNull,
      );
    });
  });

  group('allBuildPlatforms', () {
    test('includes embedded/TV embedders but not distribution images', () {
      expect(allBuildPlatforms, contains('tizen'));
      expect(allBuildPlatforms, contains('sony-elinux'));
      expect(allBuildPlatforms, contains('webos'));
      // A paid target is never part of a free 'all'.
      expect(allBuildPlatforms, isNot(contains('vscode')));
      expect(allBuildPlatforms, isNot(contains('sony-elinux-iso')));
      expect(allBuildPlatforms, isNot(contains('sony-elinux-img')));
    });

    test('routes webOS through the embedded embedder, not flutter build web',
        () {
      expect(flutterBuildPlatforms, isNot(contains('webos')));
      expect(embeddedBuildPlatforms, contains('webos'));
    });
  });

  group('resolveRequestedPlatform', () {
    String resolve(List<String> positional,
            {String option = 'all', bool wasParsed = false}) =>
        resolveRequestedPlatform(
          positional: positional,
          optionValue: option,
          optionWasParsed: wasParsed,
        );

    test('honours the documented positional form', () {
      // Regression: `dartvel build web` used to ignore the argument entirely
      // and build every platform.
      expect(resolve(['web']), 'web');
      expect(resolve(['tizen']), 'tizen');
      expect(resolve(['webos']), 'webos');
      expect(resolve(['sony-elinux']), 'sony-elinux');
      expect(resolve(['vscode']), 'vscode');
    });

    test('accepts alias and distribution target names positionally', () {
      expect(resolve(['tpk']), 'tpk');
      expect(resolve(['sony-elinux-iso']), 'sony-elinux-iso');
      expect(resolve(['sony-elinux-img']), 'sony-elinux-img');
    });

    test('falls back to the option when nothing is positional', () {
      expect(resolve([]), 'all');
      expect(resolve([], option: 'android', wasParsed: true), 'android');
    });

    test('allows the positional and option forms to agree', () {
      expect(resolve(['web'], option: 'web', wasParsed: true), 'web');
    });

    test('rejects an unknown platform instead of building everything', () {
      expect(() => resolve(['wbe']), throwsFormatException);
    });

    test('rejects conflicting positional and option platforms', () {
      expect(
        () => resolve(['web'], option: 'android', wasParsed: true),
        throwsFormatException,
      );
    });

    test('rejects more than one positional platform', () {
      expect(() => resolve(['web', 'android']), throwsFormatException);
    });
  });

  group('isPlatformAvailableOn', () {
    test('does not claim desktop targets cross-compile', () {
      // Regression: `windows` claimed availability on Linux, so
      // `dartvel build windows` hard-failed there instead of skipping.
      expect(isPlatformAvailableOn('windows', 'linux'), isFalse);
      expect(isPlatformAvailableOn('windows', 'macos'), isFalse);
      expect(isPlatformAvailableOn('linux', 'macos'), isFalse);
      expect(isPlatformAvailableOn('linux', 'windows'), isFalse);
    });

    test('builds each desktop target on its own host', () {
      expect(isPlatformAvailableOn('windows', 'windows'), isTrue);
      expect(isPlatformAvailableOn('linux', 'linux'), isTrue);
      expect(isPlatformAvailableOn('macos', 'macos'), isTrue);
    });

    test('gates the Apple targets on macOS', () {
      for (final platform in ['ios', 'macos', 'tvos']) {
        expect(isPlatformAvailableOn(platform, 'macos'), isTrue);
        expect(isPlatformAvailableOn(platform, 'linux'), isFalse);
        expect(isPlatformAvailableOn(platform, 'windows'), isFalse);
      }
    });

    test('treats web and the Android family as host-independent', () {
      for (final host in ['linux', 'macos', 'windows']) {
        expect(isPlatformAvailableOn('web', host), isTrue);
        expect(isPlatformAvailableOn('android', host), isTrue);
        expect(isPlatformAvailableOn('fireos', host), isTrue);
      }
    });

    test('reports embedder targets as unavailable to the Flutter path', () {
      // Embedded targets route through _buildEmbedded, which checks for the
      // embedder executable instead.
      for (final platform in embeddedBuildPlatforms) {
        expect(isPlatformAvailableOn(platform, 'linux'), isFalse);
      }
    });

  });

  group('BuildCommand', () {

    test('skips generation when target preflight skips every platform',
        () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_build_test_');
      final processInvocations = <String>[];
      final preflightPlatforms = <String>[];
      final command = BuildCommand(
        root: temp.path,
        preflight: (String platform, {bool? autoInstall}) async {
          preflightPlatforms.add(platform);
          return false;
        },
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          processInvocations.add(<String>[executable, ...arguments].join(' '));
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => true,
      );
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(command);

      try {
        await runner.run(<String>['build', 'windows']);
      } finally {
        temp.deleteSync(recursive: true);
      }

      expect(preflightPlatforms, <String>['windows']);
      expect(processInvocations, isEmpty);
    });

    test('generates routes before running build_runner', () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_build_test_');
      final processInvocations = <String>[];
      final command = BuildCommand(
        root: temp.path,
        preflight: (String platform, {bool? autoInstall}) async => true,
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          processInvocations.add(<String>[executable, ...arguments].join(' '));
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => true,
      );
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(command);

      try {
        await runner.run(<String>['build', 'windows']);
      } finally {
        temp.deleteSync(recursive: true);
      }

      expect(processInvocations, <String>[
        'dart run dartvel_cli:dartvel routes --render gui',
        'dart run build_runner build --delete-conflicting-outputs',
      ]);
    });

  });

  buildTimeoutTests();
  planMatchesPreflightTests();
  terminalRenderingTests();
  terminalOptInTests();
  everyBuildPathIsBoundedTests();

  group('resolveEmbeddedArch', () {
    test('sony-elinux defaults to the host, the one arch it can assemble', () {
      // The bundle is assembled from the host's own desktop build, which does
      // not cross-compile, so the arm64 default refused every plain
      // `dartvel build sony-elinux` on an x64 machine -- including a Dartvel
      // Cloud worker, which has no --arch to pass.
      expect(resolveEmbeddedArch('sony-elinux', 'arm64', host: 'x64'), 'x64');
      expect(resolveEmbeddedArch('sony-elinux', 'x64', host: 'arm64'), 'arm64');
      expect(
          resolveEmbeddedArch('sony-elinux', 'arm64', explicit: true, host: 'x64'),
          'arm64');
      expect(resolveEmbeddedArch('tizen', 'arm64', host: 'x64'), 'arm64');
    });

    test('the TV and embedded targets keep the arm64 default', () {
      expect(resolveEmbeddedArch('tizen', 'arm64'), 'arm64');
      expect(resolveEmbeddedArch('sony-elinux', 'arm64'), 'arm64');
    });
  });
}

// Appended: a build that hangs is worse than one that fails, because it is
// indistinguishable from a slow one and keeps costing until something else
// stops it. A macOS build once ran 41 minutes producing nothing at all.
void buildTimeoutTests() {
  group('build timeout', () {
    test('defaults to a generous but finite limit', () {
      // Generous because a clean release build on a cold cache is genuinely
      // slow; finite because nothing else here notices a stall.
      expect(parseBuildTimeout(null), const Duration(minutes: 45));
      expect(parseBuildTimeout(''), const Duration(minutes: 45));
      expect(parseBuildTimeout('   '), const Duration(minutes: 45));
    });

    test('an explicit number of minutes is honoured', () {
      expect(parseBuildTimeout('90'), const Duration(minutes: 90));
      expect(parseBuildTimeout(' 5 '), const Duration(minutes: 5));
    });

    test('zero disables the limit rather than meaning instantly', () {
      // The obvious wrong reading of 0 would kill every build immediately.
      expect(parseBuildTimeout('0'), isNull);
    });

    test('a value that is not minutes is refused, not silently defaulted', () {
      // Silently falling back would turn a typo into a limit nobody chose.
      expect(() => parseBuildTimeout('soon'), throwsFormatException);
      expect(() => parseBuildTimeout('-1'), throwsFormatException);
      expect(() => parseBuildTimeout('1.5'), throwsFormatException);
    });
  });
}

// Written before the fix. Every path that starts a long-running child process
// must be bounded, not just the Flutter one: an embedded build that wedges is
// indistinguishable from a slow one and runs to whatever cap it was given.
// Two Windows attempts burned 257 and 226 minutes producing no output.
void everyBuildPathIsBoundedTests() {
  group('every build path is bounded', () {
    test('the embedded build path awaits its child through the same guard',
        () {
      // Asserting on behaviour is not possible without spawning a real
      // embedder, so this asserts the structural property that makes the
      // behaviour possible: no build path may await a raw exitCode.
      final source = File('lib/src/commands/build_command.dart')
          .readAsStringSync();

      // The guard itself is where exitCode is legitimately awaited, so its
      // own body is excluded — everything else awaiting a raw exitCode is a
      // path that can hang forever.
      final guardStart = source.indexOf('Future<int?> _awaitBuild(');
      expect(guardStart, greaterThan(0), reason: 'the guard must exist');
      // From the body, not the declaration: the parameter list closes with
      // `}) async {`, which also matches a method-closing brace.
      final guardBody = source.indexOf('async {', guardStart);
      final guardEnd = source.indexOf('\n  }', guardBody);
      final outsideGuard =
          source.substring(0, guardStart) + source.substring(guardEnd);

      final unguarded = RegExp(r'await\s+[A-Za-z_][A-Za-z0-9_]*\.exitCode\b')
          .allMatches(outsideGuard)
          .map((m) => m.group(0))
          .toList();
      expect(
        unguarded,
        isEmpty,
        reason: 'a child process awaited directly cannot be timed out; '
            'route it through _awaitBuild',
      );
    });

    test('the scaffold generation step is bounded too', () {
      // Generating an embedder scaffold shells out to the vendor CLI, which
      // is exactly the kind of process that has hung before.
      final source = File('lib/src/commands/build_command.dart')
          .readAsStringSync();
      final scaffoldSection = source.substring(
        source.indexOf('Could not generate the'),
      );
      expect(
        scaffoldSection.contains('.exitCode.timeout') ||
            source.contains('_awaitBuild'),
        isTrue,
        reason: 'scaffold generation must not be able to hang indefinitely',
      );
    });
  });
}

// Terminal rendering, step one: resolving the target and refusing to link a
// backend nobody asked for. Written against the spec's table, before any of it
// exists.
//
// | dartvel build linux                    | GUI yes | terminal no  |
// | dartvel build linux + dartvel.terminal | GUI yes | terminal yes |
// | dartvel build linux-cli / linux-tui    | GUI no  | terminal yes |
/// The defect this repository has now shipped twice: a plan that names a
/// command, and a test that agrees the name is spelled correctly while nothing
/// establishes the command can run.
///
/// First `expect(plan.executable, 'dartvel_fuchsia')`, green for weeks against
/// a target that could never build. Then the terminal targets, green while
/// `dartvel build linux-cli` produced a GUI binary.
///
/// The invariant underneath both: whatever a build plan is about to execute is
/// what preflight must have checked for. Checking a *different* file is a
/// weaker guarantee than it appears — it passes for a toolchain that is
/// present but cannot perform the build, which is the case the Build Toolchain
/// Rule exists to prevent.
void planMatchesPreflightTests() {
  group('a build plan runs what preflight checked', () {
    for (final platform in embeddedBuildPlatforms) {
      test(platform, () {
        final plan = resolveEmbeddedBuildPlan(
          platform: platform,
          buildMode: '--release',
          arch: 'arm64',
          appPath: '/work/app',
          toolchainHome: '/home/dev',
        );
        final checked = toolRequirementsFor(platform, home: '/home/dev')
            .map((ToolRequirement r) => r.executable)
            .toList();

        if (plan == null) {
          // No external command: the bundle is assembled in process. The
          // invariant still bites — preflight must check *something*, or the
          // target would report ready with no artifacts present at all.
          expect(checked, isNotEmpty,
              reason: '$platform runs no external command, so preflight must '
                  'still check for the artifacts the assembly needs');
          return;
        }

        expect(
          checked,
          contains(plan.executable),
          reason: 'dartvel build $platform runs "${plan.executable}", but '
              'preflight checks $checked. Preflight would pass and the build '
              'would then fail on something nobody looked for — which is how a '
              'target reports "ready" and cannot build.',
        );
      });
    }
  });
}

void terminalRenderingTests() {

  group('terminal backend selection', () {
    test('a plain desktop build links no terminal backend', () {
      // The default, and the one that must not regress: an application that
      // said nothing pays nothing.
      final backends = resolveRenderBackends(
        format: null,
        terminalOptIn: false,
      );
      expect(backends, <DVRenderBackend>{DVRenderBackend.gui});
    });

    test('opting in adds the terminal backend without removing the GUI', () {
      final backends = resolveRenderBackends(
        format: null,
        terminalOptIn: true,
      );
      expect(backends, <DVRenderBackend>{
        DVRenderBackend.gui,
        DVRenderBackend.terminal,
      });
    });

    test('a terminal-only build links no GUI backend at all', () {
      // Not a window that stays closed. Nothing.
      final backends = resolveRenderBackends(
        format: 'tui',
        terminalOptIn: false,
      );
      expect(backends, <DVRenderBackend>{DVRenderBackend.terminal});
    });

    test('a terminal-only build ignores the opt-in rather than adding a GUI',
        () {
      // Asking for a terminal build is the stronger statement; the pubspec key
      // enables a mode, it does not add one back.
      final backends = resolveRenderBackends(
        format: 'tui',
        terminalOptIn: true,
      );
      expect(backends, <DVRenderBackend>{DVRenderBackend.terminal});
    });
  });
}

// Terminal rendering, step two: the pubspec opt-in that decides whether a
// desktop build carries a terminal backend at all. The spec's rule is that an
// application which said nothing gets nothing.
void terminalOptInTests() {
  group('the terminal opt-in', () {
    test('absent means no terminal backend', () {
      // The default and the one that must never regress.
      expect(readTerminalOptIn(loadYaml('name: app\n') as YamlMap?), isFalse);
    });

    test('a dartvel section without the key means no', () {
      expect(
        readTerminalOptIn(loadYaml('''
name: app
dartvel:
  backendPort: 3000
''') as YamlMap?),
        isFalse,
      );
    });

    test('dartvel.terminal true opts in', () {
      expect(
        readTerminalOptIn(loadYaml('''
name: app
dartvel:
  terminal: true
''') as YamlMap?),
        isTrue,
      );
    });

    test('explicit false stays out', () {
      expect(
        readTerminalOptIn(loadYaml('''
name: app
dartvel:
  terminal: false
''') as YamlMap?),
        isFalse,
      );
    });

    test('a non-boolean value is refused rather than guessed', () {
      // "yes", "1" and a nested map are all plausible things to write and all
      // ambiguous. Guessing one way links a backend nobody asked for; guessing
      // the other silently ignores a request. Refusing says which it was.
      expect(
        () => readTerminalOptIn(loadYaml('''
name: app
dartvel:
  terminal: maybe
''') as YamlMap?),
        throwsFormatException,
      );
    });

    test('a missing pubspec is not an opt-in', () {
      expect(readTerminalOptIn(null), isFalse);
    });

    test('the opt-in reaches backend selection', () {
      // The two halves joined: what the pubspec says decides what gets linked.
      final pubspec = loadYaml('''
name: app
dartvel:
  terminal: true
''') as YamlMap?;
      expect(
        resolveRenderBackends(
          format: null,
          terminalOptIn: readTerminalOptIn(pubspec),
        ),
        <DVRenderBackend>{DVRenderBackend.gui, DVRenderBackend.terminal},
      );
    });
  });
  group('the backend binary', () {
    // The backend executable is part of the web-server build. There is no
    // separate `server` platform: a command nobody documented is a command
    // the rest of the toolchain cannot be expected to know about.
    test('server is not a build platform', () {
      expect(buildPlatformArguments, isNot(contains('server')));
      expect(isPlatformAvailableOn('server', 'linux'), isFalse);
      expect(
        () => resolveRequestedPlatform(
          positional: const <String>['server'],
          optionValue: 'all',
          optionWasParsed: false,
        ),
        throwsFormatException,
      );
    });

    test('web-server is, on any host', () {
      expect(buildPlatformArguments, contains('web-server'));
      for (final String host in const <String>['linux', 'macos', 'windows']) {
        expect(isPlatformAvailableOn('web-server', host), isTrue, reason: host);
      }
    });
  });
}
