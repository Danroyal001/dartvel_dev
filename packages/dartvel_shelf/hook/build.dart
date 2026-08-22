import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    final pkgRoot = Directory.fromUri(input.packageRoot);
    final rustDir = Directory('${pkgRoot.path}/rust');

    // A version check that takes longer than this is not slow, it is stuck.
    final cargoCheck = await _runBounded(
      'cargo',
      <String>['--version'],
      const Duration(minutes: 1),
    );
    if (cargoCheck == null || cargoCheck.exitCode != 0) {
      stdout.writeln(
          'dartvel_shelf hook: cargo not found on system, skipping Rust compilation.');
      return;
    }

    if (!rustDir.existsSync()) {
      stdout.writeln('dartvel_shelf hook: rust directory missing, skipping.');
      return;
    }

    // Probed here rather than discovered mid-build, and treated the way a
    // missing cargo is: absent means skip, not fail.
    //
    // This hook runs for anything depending on this package, including a
    // `dart run` on a documentation checker. Hard-failing on a tool that such
    // a command has no reason to need turns an unrelated job red — which is
    // exactly what happened to the spec-status check, after it had already
    // spent minutes compiling Rust it did not need either.
    final cbindgenCheck = await _runBounded(
      'cbindgen',
      <String>['--version'],
      const Duration(minutes: 1),
    );
    if (cbindgenCheck == null || cbindgenCheck.exitCode != 0) {
      stdout.writeln(
          'dartvel_shelf hook: cbindgen not found, skipping native build. '
          'Install it with `cargo install cbindgen` to regenerate bindings.');
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

    // Generous: a cold cache compiles close to two hundred crates, some of
    // them slow. Finite: without a limit, "slow" and "wedged" are the same
    // thing until something else gives up hours later.
    final cargo = await _runBounded(
      'cargo',
      <String>['build', '--release', '--target', triple],
      const Duration(minutes: 30),
      workingDirectory: rustDir.path,
      stream: true,
    );
    if (cargo == null || cargo.exitCode != 0) {
      throw StateError(
          'cargo build failed (exit ${cargo?.exitCode ?? 'timed out'})');
    }

    final built = File('${rustDir.path}/target/$triple/release/$libName');
    if (!await built.exists()) {
      throw StateError('built dynlib missing: ${built.path}');
    }

    final cbindgen = await _runBounded(
      'cbindgen',
      <String>[
        '--crate',
        'dartvel_shelf_core',
        '--config',
        'cbindgen.toml',
        '--output',
        'include/dartvel_shelf.h',
      ],
      const Duration(minutes: 5),
      workingDirectory: rustDir.path,
    );
    if (cbindgen == null || cbindgen.exitCode != 0) {
      throw StateError('cbindgen failed: ${cbindgen?.stderr ?? 'timed out'}');
    }

    final ff = await _runBounded(
      'dart',
      <String>['run', 'ffigen', '--config', 'ffigen.yaml'],
      const Duration(minutes: 5),
      workingDirectory: pkgRoot.path,
    );
    if (ff == null || ff.exitCode != 0) {
      throw StateError('ffigen failed: ${ff?.stderr ?? 'timed out'}');
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

/// The environment a hook child process should see, or null to inherit.
///
/// Returns null whenever the parent is already sufficient — rebuilding an
/// environment we have no reason to touch is a way to lose something from it.
///
/// The case this exists for came from Windows CI. Once the native build
/// stopped hanging it reached ffigen, which died with "Could not find the pub
/// cache. No `LOCALAPPDATA` environment variable exists." The Rust half had
/// already succeeded; the failure was a child inheriting an environment with
/// neither `PUB_CACHE` nor `LOCALAPPDATA` in it.
///
/// Nothing is guessed when there is no home directory to derive from: an
/// invented path would replace a clear error with a confusing one.
Map<String, String>? hookChildEnvironment(Map<String, String> parent) {
  if (parent.containsKey('PUB_CACHE')) return null;
  if (parent.containsKey('LOCALAPPDATA')) return null;

  final userProfile = parent['USERPROFILE'];
  final home = parent['HOME'];
  final String derived;
  if (userProfile != null && userProfile.isNotEmpty) {
    // Where Dart puts it on Windows when LOCALAPPDATA is available.
    derived = '$userProfile\\AppData\\Local\\Pub\\Cache';
  } else if (home != null && home.isNotEmpty) {
    derived = '$home/.pub-cache';
  } else {
    return null;
  }

  return <String, String>{...parent, 'PUB_CACHE': derived};
}

/// Runs [executable] and kills it if it outlives [timeout].
///
/// Every process this hook starts goes through here. The hook runs before
/// anything else — before `dart run` reaches a CLI main, before any Dartvel
/// logging — so a process that hangs here hangs the whole build with no output
/// at all, and nothing downstream can time it out because nothing downstream
/// has started. A Windows build spent 40 minutes this way having printed only
/// "Running build hooks..."; two earlier attempts ran 257 and 226 minutes.
///
/// Returns null when the process could not be started or timed out — every
/// caller treats those the same way, and the build that follows reports the
/// real problem with its own diagnostics.
///
/// Set [stream] for a process whose progress is worth watching. A long
/// compile that prints nothing is indistinguishable from a stuck one, which is
/// the confusion this whole function exists to end.
Future<ProcessResult?> _runBounded(
  String executable,
  List<String> arguments,
  Duration timeout, {
  String? workingDirectory,
  bool stream = false,
}) async {
  try {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: hookChildEnvironment(Platform.environment),
    );

    Future<String> stdoutText;
    Future<String> stderrText;
    if (stream) {
      // Forwarded live rather than buffered, so a slow build shows progress
      // and a wedged one visibly stops.
      stdoutText = stdout.addStream(process.stdout).then((_) => '');
      stderrText = stderr.addStream(process.stderr).then((_) => '');
    } else {
      stdoutText =
          process.stdout.transform(const SystemEncoding().decoder).join();
      stderrText =
          process.stderr.transform(const SystemEncoding().decoder).join();
    }

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
