#!/usr/bin/env dart

import 'dart:io';
import 'package:path/path.dart' as path;

/// Checks if a command is available in the system PATH
Future<bool> isCommandAvailable(String command) async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run('where', [command]);
      return result.exitCode == 0;
    } else {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    }
  } catch (_) {
    return false;
  }
}

/// Installs dependencies based on the current platform
Future<void> installDependencies() async {
  print('🚀 Checking system dependencies...');

  // Get script directory early for use in the script
  final scriptDir = File(Platform.script.toFilePath()).parent;

  // Check for Rust
  if (!await isCommandAvailable('cargo')) {
    print('🔧 Rust not found. Installing Rust...');
    try {
      // First, ensure we have curl
      if (!await isCommandAvailable('curl')) {
        print('📥 Installing curl...');
        await _run('sudo', ['apt-get', 'update']);
        await _run('sudo', ['apt-get', 'install', '-y', 'curl']);
      }
      if (Platform.isLinux) {
        print('🐧 Detected Linux system');

        // Install Rust with a specific version that works with older GLIBC
        await _run('sh', [
          '-c',
          'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.70.0'
        ]);

        // Create a rust-toolchain.toml in the rust directory
        final rustDir = Directory('${scriptDir.parent.path}/rust');
        if (!await rustDir.exists()) {
          await rustDir.create(recursive: true);
        }

        final rustToolchainConfig = '''
[toolchain]
channel = "1.70.0"
components = ["rust-src", "rustfmt", "clippy"]
profile = "minimal"
''';
        await File('${rustDir.path}/rust-toolchain.toml')
            .writeAsString(rustToolchainConfig);

        // Update PATH to include cargo
        final home = Platform.environment['HOME'];
        final cargoPath = '$home/.cargo/bin';
        final newPath = '$cargoPath:${Platform.environment['PATH']}';
        Platform.environment['PATH'] = newPath;

        // Source the cargo env
        await _run('sh', ['-c', 'source $home/.cargo/env']);
      } else if (Platform.isMacOS) {
        print('🍎 Detected macOS system');
        if (!await isCommandAvailable('brew')) {
          print('🍺 Homebrew not found. Installing Homebrew...');
          await _run('sh', [
            '-c',
            '/bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
          ]);
        }
        await _run('brew', ['install', 'rust']);
      } else if (Platform.isWindows) {
        print('🪟 Detected Windows system');
        if (!await isCommandAvailable('winget')) {
          throw Exception(
              'Winget is required to install Rust on Windows. Please install it first.');
        }
        await _run('winget', ['install', 'Rust.Rustup']);
        // Refresh PATH after installation
        final newPath =
            '${Platform.environment['USERPROFILE']}\\.cargo\bin;${Platform.environment['PATH']}';
        Platform.environment['PATH'] = newPath;
      }

      // Verify Rust installation
      final rustcCheck = await Process.run('rustc', ['--version']);
      if (rustcCheck.exitCode != 0) {
        throw Exception('Failed to verify Rust installation');
      }
      print('✅ Rust installed successfully');
    } catch (e) {
      throw Exception('Failed to install Rust: $e');
    }
  }

  // Check for cbindgen
  if (!await isCommandAvailable('cbindgen')) {
    print('🔧 cbindgen not found. Installing cbindgen...');
    try {
      await _run('cargo', ['install', 'cbindgen']);
      print('✅ cbindgen installed successfully');
    } catch (e) {
      print(
          '⚠️  Warning: Failed to install cbindgen. Some features might not work: $e');
    }
  }

  // Platform-specific dependencies
  if (Platform.isLinux) {
    print('🐧 Checking Linux build dependencies...');

    // Check for GLIBC version
    try {
      final glibcVersion = await Process.run('ldd', ['--version']);
      print(
          'ℹ️  GLIBC version: ${glibcVersion.stdout.toString().split('\n').first}');
    } catch (e) {
      print('⚠️  Could not determine GLIBC version: $e');
    }

    // Check for build essentials
    if (!await isCommandAvailable('gcc')) {
      print('🔧 Installing build essentials...');
      await _run('sudo', ['apt-get', 'update']);
      await _run('sudo', ['apt-get', 'install', '-y', 'build-essential']);
    }

    // Check for LLVM (needed for bindgen)
    if (!await isCommandAvailable('llvm-config')) {
      print('🔧 Installing LLVM and Clang...');
      await _run('sudo',
          ['apt-get', 'install', '-y', 'llvm-dev', 'libclang-dev', 'clang']);
    }

    // Check for pkg-config
    if (!await isCommandAvailable('pkg-config')) {
      print('🔧 Installing pkg-config...');
      await _run('sudo', ['apt-get', 'install', '-y', 'pkg-config']);
    }

    // Check for OpenSSL
    if (!await isCommandAvailable('openssl')) {
      print('🔧 Installing OpenSSL...');
      await _run('sudo', ['apt-get', 'install', '-y', 'libssl-dev']);
    }
  }
}

/// Prefer the system toolchain (avoids snap/Flutter ld using newer GLIBC).
Map<String, String> _preferSystemToolchainEnv() {
  final env = Map<String, String>.from(Platform.environment);

  String pick(String bin) {
    // Define exe at function scope since it's used in the return statement
    final exe = Platform.isWindows ? '$bin.exe' : bin;

    try {
      // Try to use system command to find the executable
      final result = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        [bin],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final path = result.stdout.toString().split('\n').first.trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          return path;
        }
      }
    } catch (_) {
      // If system command fails, fall through to the common locations check
    }

    // Fallback to common locations if system command fails or throws
    final home = env['USERPROFILE'] ?? env['HOME'] ?? '';

    final pathCandidates = <String>[
      if (home.isNotEmpty) path.join(home, '.cargo', 'bin', exe),
      if (Platform.isWindows && home.isNotEmpty)
        path.join(home, 'scoop', 'shims', exe),
      if (Platform.isMacOS) '/opt/homebrew/bin/$bin',
      if (Platform.isMacOS) '/opt/local/bin/$bin',
      '/usr/local/bin/$bin',
      '/usr/bin/$bin',
      '/bin/$bin',
      if (Platform.isWindows) ...[
        'C:\\Windows\\System32\\$exe',
        'C:\\Windows\\$exe',
        'C:\\Program Files\\Git\\usr\\bin\\$exe',
      ],
      '/snap/bin/$bin',
    ];

    for (final candidate in pathCandidates) {
      if (candidate.isEmpty) continue;
      if (File(candidate).existsSync()) return candidate;
    }

    return exe; // fallback to PATH resolution
  }

  // Rebuild PATH with system dirs first and deprioritize flutter segments
  final sep = Platform.isWindows ? ';' : ':';
  final parts = (env['PATH'] ?? '').split(sep);
  final sys = Platform.isWindows
      ? <String>{}
      : <String>{
          '/usr/bin',
          '/bin',
          '/usr/local/bin',
          '/opt/homebrew/bin',
          '/opt/local/bin'
        };
  final kept = <String>[
    ...sys,
    ...parts.where(
        (part) => part.isNotEmpty && !part.toLowerCase().contains('flutter')),
    ...parts.where((part) => part.toLowerCase().contains('flutter')),
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

Future<void> _run(String exe, List<String> args,
    {String? workingDir, Map<String, String>? env}) async {
  print('Running ${exe} ${args.join(' ')}');

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

Future<void> main() async {
  // Install dependencies first
  await installDependencies();

  final scriptDir = File(Platform.script.toFilePath()).parent;

  final pkgDir = scriptDir.parent.path; // packages/dartvel_shelf

  final rustDir = Directory('$pkgDir/rust').path;

  final sysEnv = _preferSystemToolchainEnv();

  final cargoExe = sysEnv['DARTVEL_CARGO_EXE'] ??
      (Platform.isWindows ? 'cargo.exe' : 'cargo');

  final cbindgenExe = sysEnv['DARTVEL_CBINDGEN_EXE'] ??
      (Platform.isWindows ? 'cbindgen.exe' : 'cbindgen');

  await _run(cargoExe, ['fetch'], workingDir: rustDir, env: sysEnv);

  await _run(cargoExe, ['build', '--release'],
      workingDir: rustDir, env: sysEnv);

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
  final bindingsFile = File(path.join(pkgDir, 'lib/src/ffi/bindings.dart'));

  if (!bindingsFile.existsSync()) {
    throw StateError('bindings.dart not found after ffigen run');
  }

  final lines = bindingsFile.readAsLinesSync();
  final privateTopLevelDeclarations = <String>[];
  final privateTopLevelDeclarationPattern =
      RegExp(r'^(final\s+class|class|typedef|enum|extension)\s+_');

  for (final line in lines) {
    final trimmed = line.trim();

    if (privateTopLevelDeclarationPattern.hasMatch(trimmed))
      privateTopLevelDeclarations.add(trimmed);
  }

  if (privateTopLevelDeclarations.isNotEmpty) {
    stderr.writeln(
        'ERROR: ffigen produced private top-level declarations starting with underscore:');
    for (final decl in privateTopLevelDeclarations.take(8)) {
      stderr.writeln('  ' + decl);
    }
    stderr.writeln(
        'Adjust ffigen.yaml include lists to avoid generating private names.');
    throw StateError('Invalid private declarations in bindings.dart: ' +
        privateTopLevelDeclarations.length.toString());
  }
  stdout
      .writeln('✅ Built dartvel_shelf core and generated fresh FFI bindings.');
}
