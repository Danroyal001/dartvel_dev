import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/linux_dependency.dart';
import 'logger.dart';

const List<LinuxDependency> kLinuxDependencies = [
  LinuxDependency(
    binary: 'ninja',
    description: 'Ninja build tool',
    packages: {
      PackageManager.apt: ['ninja-build'],
      PackageManager.dnf: ['ninja-build'],
      PackageManager.yum: ['ninja-build'],
      PackageManager.pacman: ['ninja'],
      PackageManager.zypper: ['ninja'],
      PackageManager.apk: ['ninja'],
    },
  ),
  LinuxDependency(
    binary: 'cmake',
    description: 'CMake build system',
    packages: {
      PackageManager.apt: ['cmake'],
      PackageManager.dnf: ['cmake'],
      PackageManager.yum: ['cmake'],
      PackageManager.pacman: ['cmake'],
      PackageManager.zypper: ['cmake'],
      PackageManager.apk: ['cmake'],
    },
  ),
  LinuxDependency(
    binary: 'pkg-config',
    description: 'pkg-config utility',
    packages: {
      PackageManager.apt: ['pkg-config'],
      PackageManager.dnf: ['pkgconf-pkg-config'],
      PackageManager.yum: ['pkgconfig'],
      PackageManager.pacman: ['pkgconf'],
      PackageManager.zypper: ['pkg-config'],
      PackageManager.apk: ['pkgconf'],
    },
  ),
  LinuxDependency(
    binary: 'clang',
    description: 'Clang compiler',
    packages: {
      PackageManager.apt: ['clang'],
      PackageManager.dnf: ['clang'],
      PackageManager.yum: ['clang'],
      PackageManager.pacman: ['clang'],
      PackageManager.zypper: ['clang'],
      PackageManager.apk: ['clang'],
    },
  ),
  LinuxDependency(
    binary: 'ld.lld',
    description: 'LLVM LLD linker',
    packages: {
      PackageManager.apt: ['lld'],
      PackageManager.dnf: ['lld'],
      PackageManager.yum: ['lld'],
      PackageManager.pacman: ['lld'],
      PackageManager.zypper: ['lld'],
      PackageManager.apk: ['lld'],
    },
  ),
];

Future<String?> resolveExecutable(String command) async {
  try {
    final result = await Process.run('which', [command]);
    if (result.exitCode != 0) return null;
    final out = result.stdout;
    if (out is String) {
      final trimmed = out.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (out is List<int>) {
      final text = utf8.decode(out).trim();
      return text.isEmpty ? null : text;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<bool> commandExists(String command) async =>
    (await resolveExecutable(command)) != null;

Future<PackageManager?> detectPackageManager() async {
  const candidates = [
    (PackageManager.apt, ['apt-get']),
    (PackageManager.dnf, ['dnf']),
    (PackageManager.yum, ['yum']),
    (PackageManager.pacman, ['pacman']),
    (PackageManager.zypper, ['zypper']),
    (PackageManager.apk, ['apk']),
  ];
  for (final (manager, commands) in candidates) {
    for (final name in commands) {
      if (await commandExists(name)) {
        return manager;
      }
    }
  }
  return null;
}

String packageManagerLabel(PackageManager manager) {
  switch (manager) {
    case PackageManager.apt:
      return 'apt';
    case PackageManager.dnf:
      return 'dnf';
    case PackageManager.yum:
      return 'yum';
    case PackageManager.pacman:
      return 'pacman';
    case PackageManager.zypper:
      return 'zypper';
    case PackageManager.apk:
      return 'apk';
  }
}

bool isRootUser() {
  final uid = Platform.environment['EUID'] ?? Platform.environment['UID'];
  if (uid == '0') return true;
  final user = Platform.environment['USER'];
  return user == 'root';
}

bool isLinuxDevice(String? deviceId) {
  if (deviceId == null || deviceId.isEmpty) return false;
  final id = deviceId.toLowerCase();
  return id == 'linux' || id.startsWith('linux-') || id.contains('/linux');
}

List<String>? buildInstallCommand(
    PackageManager manager, List<String> packages) {
  if (packages.isEmpty) return null;
  final needsSudo = !isRootUser();
  final prefix = <String>[];
  if (needsSudo) prefix.add('sudo');
  switch (manager) {
    case PackageManager.apt:
      return [...prefix, 'apt-get', 'install', '-y', ...packages];
    case PackageManager.dnf:
      return [...prefix, 'dnf', 'install', '-y', ...packages];
    case PackageManager.yum:
      return [...prefix, 'yum', 'install', '-y', ...packages];
    case PackageManager.pacman:
      return [...prefix, 'pacman', '-Sy', '--noconfirm', ...packages];
    case PackageManager.zypper:
      return [...prefix, 'zypper', '--non-interactive', 'install', ...packages];
    case PackageManager.apk:
      return [...prefix, 'apk', 'add', '--no-cache', ...packages];
  }
}

Future<int> runLoggedProcess(List<String> command, {String tag = 'cmd'}) async {
  Logger.log('[$tag] executing: ${command.join(' ')}');
  final process = await Process.start(command.first, command.sublist(1));
  final stdoutFuture = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) => Logger.log('[$tag][out] $line'));
  final stderrFuture = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) => Logger.log('[$tag][err] $line'));
  final code = await process.exitCode;
  await Future.wait([stdoutFuture, stderrFuture]);
  Logger.log('[$tag] exit code $code');
  return code;
}

Future<void> ensureLinuxDependencies() async {
  if (!Platform.isLinux) {
    Logger.log(
        'Skipping Linux dependency check (platform=${Platform.operatingSystem}).');
    return;
  }

  Logger.log('Checking required Linux desktop dependencies...');
  final missing = <LinuxDependency>[];
  for (final dep in kLinuxDependencies) {
    final present = await commandExists(dep.binary);
    if (present) {
      Logger.log('Dependency present: ${dep.binary}');
    } else {
      Logger.log('Dependency missing: ${dep.binary} (${dep.description})');
      missing.add(dep);
    }
  }

  if (missing.isEmpty) {
    Logger.log('All required Linux dependencies are installed.');
    return;
  }

  final manager = await detectPackageManager();
  if (manager == null) {
    Logger.log(
        'Unable to detect supported package manager; install missing dependencies manually.');
    return;
  }

  Logger.log('Detected package manager: ${packageManagerLabel(manager)}');
  final packages = <String>{};
  for (final dep in missing) {
    packages.addAll(dep.packagesFor(manager));
  }
  packages.removeWhere((pkg) => pkg.isEmpty);

  if (packages.isEmpty) {
    Logger.log('No package mappings available for ${packageManagerLabel(manager)}; install the missing tools manually.');
    return;
  }

  final command = buildInstallCommand(manager, packages.toList()..sort());
  if (command == null) {
    Logger.log(
        'Unable to construct install command; aborting automatic installation.');
    return;
  }

  Logger.log('Attempting to install missing packages: ${packages.join(', ')}');
  final code = await runLoggedProcess(command, tag: 'deps');
  if (code == 0) {
    Logger.log('Dependency installation completed successfully.');
  } else {
    Logger.log('Dependency installation failed (exit code $code). Please install the packages manually.');
  }
}

Future<Map<String, String>> flutterEnvOverrides() async {
  if (!Platform.isLinux) return const {};

  final overrides = <String, String>{};
  final snapNinja = File('/snap/flutter/current/usr/bin/ninja');
  if (!snapNinja.existsSync()) {
    final ninjaPath = await resolveExecutable('ninja');
    if (ninjaPath != null) {
      Logger.log(
          'Using system ninja at $ninjaPath for Flutter (snap binary missing).');
      overrides['FLUTTER_NINJA'] = ninjaPath;
      overrides['NINJA_PATH'] = ninjaPath;
      overrides['CMAKE_MAKE_PROGRAM'] = ninjaPath;
    } else {
      Logger.log('Flutter snap ninja binary missing and no ninja found in PATH.');
    }
  }

  final lldPath =
      await resolveExecutable('ld.lld') ?? await resolveExecutable('lld');
  if (lldPath != null) {
    Logger.log('Using linker at $lldPath for Flutter builds.');
    overrides['CMAKE_LINKER'] = lldPath;
    overrides['LD'] = lldPath;
    overrides['LLD_PATH'] = lldPath;
  } else {
    Logger.log('LLD linker (ld.lld) not found; Flutter desktop builds may fail.');
  }

  return overrides;
}

Future<void> resetFlutterLinuxBuildArtifacts(
    String projectRoot, Map<String, String> env) async {
  if (!Platform.isLinux) return;
  if (env.isEmpty) return;
  final buildDir = Directory(p.join(projectRoot, 'build', 'linux'));
  if (!buildDir.existsSync()) return;
  final targets = [
    File(p.join(buildDir.path, 'CMakeCache.txt')),
    File(p.join(buildDir.path, 'CMakeCache.txt.backup')), // just in case
    File(p.join(buildDir.path, 'build.ninja')),
    File(p.join(buildDir.path, 'x64', 'debug', 'CMakeCache.txt')),
    File(p.join(buildDir.path, 'x64', 'debug', 'build.ninja')),
    File(p.join(buildDir.path, 'x64', 'profile', 'CMakeCache.txt')),
    File(p.join(buildDir.path, 'x64', 'profile', 'build.ninja')),
    File(p.join(buildDir.path, 'x64', 'release', 'CMakeCache.txt')),
    File(p.join(buildDir.path, 'x64', 'release', 'build.ninja')),
  ];
  for (final file in targets) {
    if (file.existsSync()) {
      Logger.log('Removing stale ${p.relative(file.path, from: projectRoot)}');
      try {
        await file.delete();
      } catch (err) {
        Logger.log('Failed to delete ${file.path}: $err');
      }
    }
  }
}
