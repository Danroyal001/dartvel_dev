import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    final pkgRoot = Directory.fromUri(input.packageRoot);
    final rustDir = Directory('${pkgRoot.path}/rust');

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

    final tripleInfo = _resolveTarget();
    if (tripleInfo == null) {
      stdout
          .writeln('dartvel_shelf hook: unsupported host platform, skipping.');
      return;
    }
    final (triple, libName, subdir) = tripleInfo;

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

(String, String, String)? _resolveTarget() {
  final os = Platform.operatingSystem;
  final arch = _detectArch();
  switch (os) {
    case 'linux':
      if (arch == 'arm64') {
        return (
          'aarch64-unknown-linux-gnu',
          'libdartvel_shelf.so',
          'linux-arm64'
        );
      }
      return ('x86_64-unknown-linux-gnu', 'libdartvel_shelf.so', 'linux-x64');
    case 'macos':
      if (arch == 'arm64') {
        return (
          'aarch64-apple-darwin',
          'libdartvel_shelf.dylib',
          'macos-arm64'
        );
      }
      return ('x86_64-apple-darwin', 'libdartvel_shelf.dylib', 'macos-x64');
    case 'windows':
      if (arch == 'arm64') {
        return (
          'aarch64-pc-windows-msvc',
          'dartvel_shelf.dll',
          'windows-arm64'
        );
      }
      return ('x86_64-pc-windows-msvc', 'dartvel_shelf.dll', 'windows-x64');
    default:
      return null;
  }
}

String _detectArch() {
  final envArch = Platform.environment['PROCESSOR_ARCHITECTURE'] ??
      Platform.environment['HOSTTYPE'] ??
      '';
  final lower = envArch.toLowerCase();
  if (lower.contains('arm64') || lower.contains('aarch64')) {
    return 'arm64';
  }
  if (lower.contains('x86') || lower.contains('amd64')) {
    return 'x64';
  }

  final uname = Platform.isWindows ? null : _runSync('uname', ['-m']);
  if (uname != null) {
    if (uname.contains('arm') || uname.contains('aarch64')) {
      return 'arm64';
    }
  }
  return 'x64';
}

String? _runSync(String cmd, List<String> args) {
  try {
    final result = Process.runSync(cmd, args);
    if (result.exitCode == 0) {
      return (result.stdout as String?)?.trim();
    }
  } catch (_) {}
  return null;
}
