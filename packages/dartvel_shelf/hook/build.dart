import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    final pkgRoot = Directory.fromUri(input.packageRoot);
    final rustDir = Directory('${pkgRoot.path}/rust');

    final cargoCheck = await Process.run('cargo', ['--version'])
        .catchError((_) => ProcessResult(-1, 127, '', ''));
    if (cargoCheck.exitCode != 0) {
      stdout.writeln(
          'dartvel_shelf hook: cargo not found on system, skipping Rust compilation.');
      return;
    }

    if (!rustDir.existsSync()) {
      stdout.writeln('dartvel_shelf hook: rust directory missing, skipping.');
      return;
    }

    const codeAssetType = 'code_assets/code';
    final buildAssetTypes = input.config.buildAssetTypes;
    final wantsCodeAsset = buildAssetTypes.contains(codeAssetType);
    if (!wantsCodeAsset) {
      stdout.writeln(
          'dartvel_shelf hook: target does not support native code assets; skipping.');
      return;
    }

    // The hook must build for the architecture the toolchain asks for, not
    // the one it runs on: a macOS universal build invokes this hook once per
    // architecture and lipos the results together, so answering both requests
    // with a host-arch dylib hands lipo two arm64 inputs and fails the build.
    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;
    final tripleInfo = _resolveTarget(targetOS, targetArch);
    if (tripleInfo == null) {
      stdout.writeln(
          'dartvel_shelf hook: no native artifact target configured for '
          '$targetOS/$targetArch; skipping.');
      return;
    }
    final (triple, libName, subdir) = tripleInfo;

    // Cross-arch triples (the x86_64 half of a universal build on an arm64
    // host) need their std library installed. Best-effort and quiet: without
    // rustup the subsequent build still fails with cargo's own message.
    //
    // Bounded, and skipped when the target is already installed, because a
    // universal build runs this hook once per architecture — concurrently —
    // and two `rustup target add` processes contend for the same ~/.rustup
    // lock. An unbounded wait there is invisible: the hook prints nothing
    // while it blocks, so a deadlock looks exactly like a slow build until
    // CI's own limit kills the job hours later.
    if (!await _hasRustTarget(triple)) {
      await _runBounded(
        'rustup',
        <String>['target', 'add', triple],
        const Duration(minutes: 5),
      );
    }

    final cargo = await Process.start(
        'cargo', ['build', '--release', '--target', triple],
        workingDirectory: rustDir.path);
    await stdout.addStream(cargo.stdout);
    await stderr.addStream(cargo.stderr);
    final cargoCode = await cargo.exitCode;
    if (cargoCode != 0) {
      throw StateError('cargo build failed (exit $cargoCode)');
    }

    final built = File('${rustDir.path}/target/$triple/release/$libName');
    if (!await built.exists()) {
      throw StateError('built dynlib missing: ${built.path}');
    }

    final cbindgen = await Process.run(
      'cbindgen',
      [
        '--crate',
        'dartvel_shelf_core',
        '--config',
        'cbindgen.toml',
        '--output',
        'include/dartvel_shelf.h',
      ],
      workingDirectory: rustDir.path,
    );
    if (cbindgen.exitCode != 0) {
      throw StateError('cbindgen failed: ${cbindgen.stderr}');
    }

    final ff = await Process.run(
      'dart',
      ['run', 'ffigen', '--config', 'ffigen.yaml'],
      workingDirectory: pkgRoot.path,
    );
    if (ff.exitCode != 0) {
      throw StateError('ffigen failed: ${ff.stderr}');
    }

    final nativeDir = Directory('${pkgRoot.path}/lib/native/$subdir')
      ..createSync(recursive: true);
    final nativeOut = File('${nativeDir.path}/$libName');
    await built.copy(nativeOut.path);

    final outFile = input.outputDirectory.resolve(libName);
    await built.copy(outFile.toFilePath());

    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'dartvel_shelf.dart',
      file: outFile,
      linkMode: DynamicLoadingBundled(),
    ));

    output.dependencies.add(Directory('${rustDir.path}/src').uri);
    output.dependencies.add(File('${rustDir.path}/Cargo.toml').uri);
    output.dependencies.add(File('${rustDir.path}/cbindgen.toml').uri);
    output.dependencies
        .add(File('${rustDir.path}/include/dartvel_shelf.h').uri);
    output.dependencies.add(File('${pkgRoot.path}/ffigen.yaml').uri);
  });
}

/// Whether rustup already has [triple]'s standard library.
///
/// Reading the installed list is lock-free, so the common case — the target
/// is present — never touches the lock `rustup target add` takes.
Future<bool> _hasRustTarget(String triple) async {
  final result = await _runBounded(
    'rustup',
    const <String>['target', 'list', '--installed'],
    const Duration(minutes: 1),
  );
  if (result == null || result.exitCode != 0) return false;
  return '${result.stdout}'.split('\n').map((l) => l.trim()).contains(triple);
}

/// Runs [executable] and kills it if it outlives [timeout].
///
/// Returns null when the process could not be started, failed, or timed out —
/// every caller here treats those the same way, and the build that follows
/// reports the real problem with its own diagnostics.
Future<ProcessResult?> _runBounded(
  String executable,
  List<String> arguments,
  Duration timeout,
) async {
  try {
    final process = await Process.start(executable, arguments);
    final stdoutText = process.stdout.transform(const SystemEncoding().decoder).join();
    final stderrText = process.stderr.transform(const SystemEncoding().decoder).join();
    final code = await process.exitCode.timeout(timeout, onTimeout: () {
      stderr.writeln(
          'dartvel_shelf hook: $executable ${arguments.join(' ')} exceeded '
          '${timeout.inMinutes}m; killing it and continuing.');
      process.kill(ProcessSignal.sigkill);
      return -1;
    });
    return ProcessResult(process.pid, code, await stdoutText, await stderrText);
  } catch (_) {
    return null;
  }
}

/// Maps the *requested* build target — never the host — onto a Rust triple,
/// library name, and `lib/native/` subdirectory.
///
/// Unmapped targets return null and the hook skips with a message naming
/// them, so a new target shows up as an explicit gap rather than a host-arch
/// library bundled under the wrong name.
(String, String, String)? _resolveTarget(OS os, Architecture arch) {
  if (os == OS.linux) {
    return switch (arch) {
      Architecture.arm64 => (
          'aarch64-unknown-linux-gnu',
          'libdartvel_shelf.so',
          'linux-arm64'
        ),
      Architecture.x64 => (
          'x86_64-unknown-linux-gnu',
          'libdartvel_shelf.so',
          'linux-x64'
        ),
      _ => null,
    };
  }
  if (os == OS.macOS) {
    return switch (arch) {
      Architecture.arm64 => (
          'aarch64-apple-darwin',
          'libdartvel_shelf.dylib',
          'macos-arm64'
        ),
      Architecture.x64 => (
          'x86_64-apple-darwin',
          'libdartvel_shelf.dylib',
          'macos-x64'
        ),
      _ => null,
    };
  }
  if (os == OS.windows) {
    return switch (arch) {
      Architecture.arm64 => (
          'aarch64-pc-windows-msvc',
          'dartvel_shelf.dll',
          'windows-arm64'
        ),
      Architecture.x64 => (
          'x86_64-pc-windows-msvc',
          'dartvel_shelf.dll',
          'windows-x64'
        ),
      _ => null,
    };
  }
  return null;
}
