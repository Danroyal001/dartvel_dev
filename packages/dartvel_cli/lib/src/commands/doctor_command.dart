import 'dart:io';
import 'package:args/command_runner.dart';
// Shown, not whole: dartvel_core exports a Platform enum that would shadow
// dart:io's Platform, which this file uses for environment and OS checks.
import 'package:dartvel_core/dartvel.dart' show DVKioskTarget;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../build/deep_link_files.dart';
import '../build/static_seo.dart' show dvGuardedRoutes;
import '../doctor/kiosk_check.dart';
import '../doctor/memory_check.dart';
import '../doctor/module_check.dart';
import '../utils/logger.dart';
import '../utils/toolchain.dart';
import 'build_command.dart'
    show
        browserExtensionBuildPlatforms,
        embeddedBuildPlatforms,
        extensionBuildPlatforms,
        normalizeBuildTarget,
        terminalBuildPlan,
        terminalBuildTargets;

/// Targets `dartvel doctor --target` accepts.
///
/// Derived from the build command's own sets rather than restated, because a
/// hand-maintained copy drifts: tvOS became an embedder target and could not
/// be asked about, while the browser extensions had check logic that the
/// option's allowlist made unreachable.
final List<String> doctorTargets = <String>[
  ...embeddedBuildPlatforms,
  ...extensionBuildPlatforms,
  ...browserExtensionBuildPlatforms,
  // Terminal targets need the dartvel_cli_flt embedder, which is no more a plain
  // Flutter SDK than flutter-tizen is. Third time this list drifted.
  ...terminalBuildTargets,
  // Not a toolchain question. `flutter doctor` answers that for these two;
  // what it cannot answer is whether the site the deep links point at serves
  // the verification documents this application needs (DV-LINKS-002 to 004).
  ...deepLinkDoctorTargets,
];

/// Targets `dartvel doctor --target` checks deployed deep links for.
const List<String> deepLinkDoctorTargets = <String>['android', 'ios'];

class DoctorCommand extends Command<void> {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Check your environment and project for common issues.';

  /// [root] is the project checked by `--modules`; the current directory
  /// when null.
  DoctorCommand({this.root}) {
    argParser.addFlag(
      'modules',
      negatable: false,
      help: 'Verify every module pin (digest, signing key, publisher, '
          'version) and compare what each module uses against what this '
          'application grants.',
    );
    argParser.addMultiOption(
      'target',
      allowed: doctorTargets,
      help: 'Validate the toolchain for an embedded, TV or extension build '
          'target, or, for android and ios, the deep-link verification '
          'documents the declared domains serve. Comma-separate several: '
          '--target android,ios.',
    );
  }

  final String? root;

  /// `dartvel doctor --modules`. On its own, like `--target`: the question
  /// is whether the mounted modules may be built, and it is answered without
  /// running the SDK checks.
  void _checkModuleTrust(String root) {
    final DVModuleCheck check = DVModuleCheck.trust(root);
    if (check.lines.isEmpty) {
      Logger.log('[+] Every mounted module verifies against its pin and uses '
          'only what it is granted.');
      return;
    }
    for (final String line in check.lines) {
      Logger.log(line);
    }
    if (!check.ok) exitCode = 1;
  }

  @override
  Future<void> run() async {
    if (argResults?['modules'] == true) {
      _checkModuleTrust(root ?? Directory.current.path);
      return;
    }
    final List<String> targets =
        (argResults?['target'] as List<String>?) ?? const <String>[];
    if (targets.isNotEmpty) {
      final Set<String> linkTargets = <String>{
        for (final String t in targets)
          if (deepLinkDoctorTargets.contains(t)) t,
      };
      if (linkTargets.isNotEmpty) {
        await _checkDeepLinks(root ?? Directory.current.path, linkTargets);
      }
      for (final String target in targets) {
        if (deepLinkDoctorTargets.contains(target)) continue;
        await _checkTargetToolchain(target);
      }
      return;
    }

    Logger.log('Dartvel Doctor');
    Logger.log('==================================================\n');

    var allGood = true;

    // 1. Check Dart SDK
    allGood = await _checkDartSDK() && allGood;

    // 2. Check Flutter SDK
    allGood = await _checkFlutterSDK() && allGood;

    // 3. Check Git
    allGood = await _checkGit() && allGood;

    Logger.log('\n--------------------------------------------------');
    Logger.log('Optional Tools');
    Logger.log('--------------------------------------------------\n');

    // 4. Check Shorebird (optional)
    await _checkShorebird();

    // 5. Check Codemagic CLI (optional)
    await _checkCodemagic();

    Logger.log('\n--------------------------------------------------');
    Logger.log('Project Status');
    Logger.log('--------------------------------------------------\n');

    // 6. If in a Dartvel project, check project-specific things
    final pubspec = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      await _checkProjectConfig();
      allGood = _checkKiosk(pubspec) && allGood;
    } else {
      Logger.log('[-] Not in a Dartvel project');
      Logger.log(
          '    Run this command in a project directory for additional checks');
    }

    Logger.log('');
    if (allGood) {
      Logger.log('[+] All system checks passed!');
    } else {
      Logger.log('[!] Some checks failed. See above for details.');
    }

    // 7. Run flutter doctor for comprehensive Flutter environment check
    Logger.log('\n==================================================');
    Logger.log('Flutter Doctor Output');
    Logger.log('==================================================\n');
    try {
      final flutterDoctorProcess = await Process.start(
        'flutter',
        ['doctor', '-v'],
        runInShell: true,
      );
      await stdout.addStream(flutterDoctorProcess.stdout);
      await stderr.addStream(flutterDoctorProcess.stderr);
      await flutterDoctorProcess.exitCode;
    } catch (_) {
      Logger.log('[!] Could not run flutter doctor');
    }
  }

  /// `dartvel doctor --target android,ios`: what the declared domains serve,
  /// not what the build wrote -- a file that is right in build/web and
  /// behind a redirect in production is the failure this exists for.
  Future<void> _checkDeepLinks(String root, Set<String> targets) async {
    Logger.log('Dartvel Doctor — deep links: ${targets.join(', ')}');
    Logger.log('==================================================\n');
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    final Object? document =
        pubspec.existsSync() ? loadYaml(pubspec.readAsStringSync()) : null;
    final Object? dartvel = document is Map ? document['dartvel'] : null;
    final DVDeepLinks? links;
    try {
      links = DVDeepLinks.parse(dartvel is Map ? dartvel['deepLinks'] : null);
    } on FormatException catch (error) {
      Logger.log('[!] ${error.message}');
      exitCode = 1;
      return;
    }
    if (links == null || links.domains.isEmpty) {
      Logger.log('[-] dartvel.deepLinks declares no domains; nothing to check.');
      return;
    }
    final List<String> missing = links.missingIdentifiers(targets);
    for (final String error in missing) {
      Logger.log('[!] $error');
    }
    final File router =
        File(p.join(root, 'lib', 'dartvel_client', 'router.g.dart'));
    final String source = router.existsSync() ? router.readAsStringSync() : '';
    final List<String> routes = <String>{
      for (final RegExpMatch m in RegExp("path: '(/[^']*)'").allMatches(source))
        m.group(1)!,
    }.toList()
      ..sort();
    final List<String> findings = await dvCheckDeepLinks(
      links: links,
      targets: targets,
      routes: routes,
      guarded: dvGuardedRoutes(source),
      signingFingerprint: targets.contains('android')
          ? await dvAndroidSigningFingerprint(root)
          : null,
    );
    for (final String finding in findings) {
      Logger.log('[!] $finding');
    }
    if (missing.isEmpty && findings.isEmpty) {
      Logger.log('[+] ${links.domains.join(', ')} serve verification documents '
          'that name this application and cover its routes.');
      return;
    }
    // DV-LINKS-004 is a warning; the rest fail.
    if (missing.isNotEmpty ||
        findings.any((String f) => !f.startsWith('DV-LINKS-004'))) {
      exitCode = 1;
    }
  }

  /// Validates the embedder toolchain required for an embedded/TV build target.
  Future<void> _checkTargetToolchain(String target) async {
    Logger.log('Dartvel Doctor — target: $target');
    Logger.log('==================================================\n');

    // Terminal targets answer from the build plan itself rather than from a
    // second copy here. A doctor that names a different executable from the
    // one the build runs is worse than no doctor: it reports ready for
    // something that will not build.
    if (terminalBuildTargets.contains(target)) {
      await _checkTerminalToolchain(target);
      return;
    }

    // Executable each target's build path invokes.
    final executable = switch (target) {
      'tizen' => 'flutter-tizen',
      'sony-elinux' => 'flutter-elinux',
      'webos' => 'flutter-webos',
      'tvos' => 'flutter-tvos',
      // The Fuchsia embedder is a checkout driven by its own scripts, not a
      // Flutter CLI wrapper on PATH.
      // The script the build runs, so doctor and build agree about what has
      // to be present. Reporting a different file answers a different
      // question from "can this target build".
      'fuchsia' => '${dartvelToolchainRoot(Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '')}'
          '/dartvel_fuchsia/$fuchsiaAppBuildScript',
      'vscode' => 'npm',
      // A browser extension is Flutter web output plus a generated manifest,
      // so the web toolchain is the whole requirement.
      'chrome-extension' || 'firefox-extension' => 'flutter',
      _ => 'flutter',
    };
    final label = switch (target) {
      'vscode' => 'toolchain',
      'chrome-extension' || 'firefox-extension' => 'toolchain',
      _ => 'embedder',
    };

    final available = await _isExecutableAvailable(executable);
    if (available) {
      Logger.log('[+] $target $label: $executable found');
      Logger.log('\n[+] Target $target looks ready to build.');
    } else {
      Logger.log('[!] $target $label: $executable not found on PATH');
      Logger.log(
        switch (target) {
          'vscode' =>
            '    Install Node.js/npm before running `dartvel build vscode`.',
          'chrome-extension' || 'firefox-extension' =>
            '    Install Flutter with web support before running '
                '`dartvel build $target`.',
          _ => '    Install the $target Flutter embedder before running '
              '`dartvel build $target`.',
        },
      );
    }

    if (target == 'sony-elinux') {
      Logger.log(
        '\n[-] Note: `sony-elinux-iso` and `sony-elinux-img` also require the '
        'configured Sony eLinux image toolchain for image assembly.',
      );
    }
  }

  Future<bool> _isExecutableAvailable(String executable) async {
    try {
      final locator = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(locator, [executable], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkDartSDK() async {
    try {
      final result = await Process.run('dart', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = (result.stdout.toString() + result.stderr.toString())
            .split('\n')
            .first
            .trim();
        Logger.log('[+] Dart SDK: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('[!] Dart SDK: Not found or not in PATH');
    return false;
  }

  Future<bool> _checkFlutterSDK() async {
    try {
      final result =
          await Process.run('flutter', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final version = lines.isNotEmpty ? lines.first.trim() : 'installed';
        Logger.log('[+] Flutter SDK: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('[!] Flutter SDK: Not found or not in PATH');
    return false;
  }

  Future<bool> _checkGit() async {
    try {
      final result = await Process.run('git', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        Logger.log('[+] Git: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('[!] Git: Not found (recommended for version control)');
    return true; // Not critical
  }

  Future<void> _checkTerminalToolchain(String target) async {
    final plan = terminalBuildPlan(normalizeBuildTarget(target).platform);
    final available = await _isExecutableAvailable(plan.toolchain);
    if (available) {
      Logger.log('[+] $target embedder: ${plan.toolchain} found');
      Logger.log('\n[+] Target $target looks ready to build.');
      return;
    }
    Logger.log('[!] $target embedder: ${plan.toolchain} not found on PATH');
    Logger.log(
      '    Terminal rendering uses the dartvel_cli_flt embedder, which renders '
      'from Rust through the Kitty graphics protocol. `flutter build '
      '${plan.platform}` cannot produce a terminal binary, so this target is '
      'skipped rather than substituted.',
    );
  }

  Future<void> _checkShorebird() async {
    try {
      final result =
          await Process.run('shorebird', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        Logger.log('[+] Shorebird: $version');
      } else {
        Logger.log('[-] Shorebird: Not installed (optional for OTA updates)');
      }
    } catch (_) {
      Logger.log('[-] Shorebird: Not installed (optional for OTA updates)');
    }
  }

  Future<void> _checkCodemagic() async {
    try {
      final result =
          await Process.run('codemagic', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        Logger.log('[+] Codemagic CLI: $version');
      } else {
        Logger.log('[-] Codemagic CLI: Not installed (optional for CI/CD)');
      }
    } catch (_) {
      Logger.log('[-] Codemagic CLI: Not installed (optional for CI/CD)');
    }
  }

  /// Validates a declared kiosk policy, and says what each target will do
  /// with it.
  ///
  /// Counts towards the verdict because a kiosk that cannot be honoured is not
  /// a warning: there is no "present it another way" fallback for locking a
  /// device, so a policy nothing can enforce ships as an application anyone can
  /// walk out of.
  bool _checkKiosk(File pubspec) {
    Object? dartvel;
    try {
      final Object? loaded = loadYaml(pubspec.readAsStringSync());
      dartvel = loaded is YamlMap ? loaded['dartvel'] : null;
    } on Object {
      // A pubspec that will not parse is reported by the checks above.
      return true;
    }

    final DVKioskCheck check = DVKioskCheck.run(dartvel, _configuredTargets(), root: Directory.current.path);
    if (check.lines.isNotEmpty) {
      Logger.log('');
      for (final String line in check.lines) {
        Logger.log(line);
      }
    }

    // The modules the project declares. A declaration to mount something the
    // build cannot mount is the same kind of promise as a kiosk policy that
    // cannot be honoured, and was being carried on from with a log line.
    final DVModuleCheck modules = DVModuleCheck.run(Directory.current.path);
    if (modules.lines.isNotEmpty) {
      Logger.log('');
      for (final String line in modules.lines) {
        Logger.log(line);
      }
    }

    // dartvel.memory against each device profile's declared RAM, and
    // touchPages against the platforms that refuse it.
    final Object? platforms = dartvel is Map ? dartvel['platforms'] : null;
    final DVMemoryCheck memory = DVMemoryCheck.run(
      dartvel,
      <String>[if (platforms is List) for (final Object? p in platforms) '$p'],
    );
    if (memory.lines.isNotEmpty) {
      Logger.log('');
      for (final String line in memory.lines) {
        Logger.log(line);
      }
    }

    return check.ok && modules.ok && memory.ok;
  }

  /// The kiosk targets this project builds for.
  ///
  /// Read from `dartvel.platforms` where it is declared. An empty list still
  /// validates the policy itself, which is the half that does not depend on
  /// where it ships.
  List<DVKioskTarget> _configuredTargets() {
    const Map<String, DVKioskTarget> known = <String, DVKioskTarget>{
      'sony-elinux': DVKioskTarget.sonyELinux,
      'android': DVKioskTarget.androidScreenPinning,
      'ios': DVKioskTarget.iPadOS,
      'windows': DVKioskTarget.windows,
      'macos': DVKioskTarget.macos,
      'linux': DVKioskTarget.linuxDesktop,
      'tizen': DVKioskTarget.tizen,
      'webos': DVKioskTarget.webos,
      'web': DVKioskTarget.web,
    };

    try {
      final Object? loaded = loadYaml(
          File(p.join(Directory.current.path, 'pubspec.yaml'))
              .readAsStringSync());
      final Object? dartvel = loaded is YamlMap ? loaded['dartvel'] : null;
      final Object? platforms =
          dartvel is Map ? dartvel['platforms'] : null;
      if (platforms is! List) return const <DVKioskTarget>[];
      return <DVKioskTarget>[
        for (final Object? entry in platforms)
          if (known['$entry'] != null) known['$entry']!,
      ];
    } on Object {
      return const <DVKioskTarget>[];
    }
  }

  Future<void> _checkProjectConfig() async {
    final cwd = Directory.current.path;
    final pubspec = File(p.join(cwd, 'pubspec.yaml'));
    final content = await pubspec.readAsString();
    final hasDartvelConfig =
        RegExp(r'^dartvel:\s*$', multiLine: true).hasMatch(content);
    final hasFlutterDependency =
        content.contains('flutter:') || content.contains('sdk: flutter');

    if (hasDartvelConfig) {
      Logger.log('[+] dartvel: configuration section found');
    } else {
      Logger.log('[!] dartvel: missing pubspec.yaml dartvel: section');
    }

    if (hasFlutterDependency) {
      Logger.log('[+] Flutter dependency configured');
    } else {
      Logger.log('[!] Flutter dependency not found in pubspec.yaml');
    }

    final expectedDirs = [
      'lib/pages',
      'lib/backend/functions',
      'lib/models',
    ];
    for (final dir in expectedDirs) {
      final exists = Directory(p.join(cwd, dir)).existsSync();
      Logger.log(
          '${exists ? '[+]' : '[!]'} $dir ${exists ? 'exists' : 'missing'}');
    }

    final env = File(p.join(cwd, '.env'));
    if (env.existsSync()) {
      Logger.log('[+] .env present');
    } else {
      Logger.log(
          '[-] .env not present; runtime configuration will use defaults');
    }
  }
}
