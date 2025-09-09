#!/usr/bin/env dart

import 'dart:io';
import 'package:path/path.dart' as p;

/// Prefer the system toolchain (avoids snap/Flutter ld using newer GLIBC).
Map<String, String> _preferSystemToolchainEnv() {
  final env = Map<String, String>.from(Platform.environment);
  String pick(String bin) {
    final exe = Platform.isWindows ? '$bin.exe' : bin;

    final home = env['USERPROFILE'] ?? env['HOME'] ?? '';
    
    final cand = <String>[
      if (Platform.isWindows && home.isNotEmpty) p.join(home, '.cargo', 'bin', exe),
      if (Platform.isWindows && home.isNotEmpty) p.join(home, 'scoop', 'shims', exe),
      if (Platform.isMacOS) '/opt/homebrew/bin/$bin',
      '/usr/bin/$bin',
      '/bin/$bin',
      '/usr/local/bin/$bin',
      if (Platform.isWindows) 'C\\\\Windows\\\\System32\\\\' + exe,
      if (Platform.isWindows) 'C\\\\Windows\\\\' + exe,
      if (Platform.isWindows) 'C\\\\Program Files\\\\Git\\\\usr\\\\bin\\\\' + exe,
      '/snap/bin/$bin',
    ];

    for (final c in cand) {
      if (c.isEmpty) continue;
      if (File(c).existsSync()) return c;
    }
    return exe; // fallback to PATH resolution
  }

  // Rebuild PATH with system dirs first and deprioritize flutter segments
  final sep = Platform.isWindows ? ';' : ':';
  final parts = (env['PATH'] ?? '').split(sep);
  final sys = Platform.isWindows
      ? <String>{}
      : <String>{'/usr/bin', '/bin', '/usr/local/bin', '/opt/homebrew/bin', '/opt/local/bin'};
  final kept = <String>[
    ...sys,
    ...parts.where((p) => p.isNotEmpty && !p.toLowerCase().contains('flutter')),
    ...parts.where((p) => p.toLowerCase().contains('flutter')),
  ];
  env['PATH'] = kept.join(sep);
  // Force CC/LD/CXX to system bins when present (POSIX only)
  if (!Platform.isWindows) {
    env['CC'] = pick('cc');
    env['CXX'] = pick('c++');
    env['LD'] = pick('ld');
    env['AR'] = pick('ar');
  }
  return env;
}

Future<void> main() async {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final pkgDir = scriptDir.parent.path; // packages/dartvel_shelf
  final rustDir = Directory('$pkgDir/rust').path;

  final sysEnv = _preferSystemToolchainEnv();
  final cargoExe = sysEnv['DARTVEL_CARGO_EXE'] ?? (Platform.isWindows ? 'cargo.exe' : 'cargo');
  final cbindgenExe = sysEnv['DARTVEL_CBINDGEN_EXE'] ?? (Platform.isWindows ? 'cbindgen.exe' : 'cbindgen');
  await _run(cargoExe, ['build', '--release'], workingDir: rustDir, env: sysEnv);
  await _run(cbindgenExe,
      ['--config', 'cbindgen.toml', '-o', 'include/dartvel_shelf.h'],
      workingDir: rustDir, env: sysEnv);
  // Ensure Dart dependencies are ready
  await _run('dart', ['pub', 'get'], workingDir: pkgDir);
  // Run ffigen (required). Try both invocation styles and pass explicit config file.
  Object? lastError;
  try {
    await _run('dart', ['run', 'ffigen', '--config', 'ffigen.yaml'],
        workingDir: pkgDir);
  } catch (e) {
    lastError = e;
    try {
      await _run('dart', ['run', 'ffigen:ffigen', '--config', 'ffigen.yaml'],
          workingDir: pkgDir);
      lastError = null;
    } catch (e2) {
      lastError = e2;
    }
  }
  if (lastError != null) {
    stderr.writeln('ERROR: ffigen failed to run.');
    stderr.writeln(
        '• Ensure dev_dependencies contains ffigen in packages/dartvel_shelf/pubspec.yaml');
    stderr.writeln('• Install:  dart pub add -d ffigen');
    stderr.writeln(
        '• Then re-run: dart packages/dartvel_shelf/tool/build_rust.dart');
    throw lastError!;
  }
  // Validate bindings: ensure no top-level declarations start with underscore
  final bindingsFile = File(p.join(pkgDir, 'lib/src/ffi/bindings.dart'));
  if (!bindingsFile.existsSync()) {
    throw StateError('bindings.dart not found after ffigen run');
  }
  final lines = bindingsFile.readAsLinesSync();
  final privateTopLevelDeclarations = <String>[];
  final privateTopLevelDeclarationPattern = RegExp(r'^(final\s+class|class|typedef|enum|extension)\s+_');
  for (final line in lines) {
    final trimmed = line.trim();
    if (privateTopLevelDeclarationPattern.hasMatch(trimmed)) privateTopLevelDeclarations.add(trimmed);
  }
  if (privateTopLevelDeclarations.isNotEmpty) {
    stderr.writeln('ERROR: ffigen produced private top-level declarations starting with underscore:');
    for (final decl in privateTopLevelDeclarations.take(8)) {
      stderr.writeln('  ' + decl);
    }
    stderr.writeln('Adjust ffigen.yaml include lists to avoid generating private names.');
    throw StateError('Invalid private declarations in bindings.dart: ' + privateTopLevelDeclarations.length.toString());
  }
  stdout.writeln('✅ Built dartvel_shelf core and generated fresh FFI bindings.');
}

Future<void> _run(String exe, List<String> args,
    {String? workingDir, Map<String, String>? env}) async {
  final mergedEnv = env == null
      ? Platform.environment
      : {
          ...Platform.environment,
          ...env,
        };
  final p = await Process.start(exe, args,
      workingDirectory: workingDir, runInShell: true, environment: mergedEnv);
  await stdout.addStream(p.stdout);
  await stderr.addStream(p.stderr);
  final code = await p.exitCode;
  if (code != 0) throw ProcessException(exe, args, 'exit code $code', code);
}
