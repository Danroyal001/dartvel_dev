/// A C library or a Rust crate, as a module.
///
/// One carrier for a device and the backend alike: `@Native` functions bound
/// to a code asset the module's own build hook produces -- compiled from the
/// C sources with the platform's C toolchain, or built from the crate with
/// cargo for the target being built. The hook runs when the application is
/// built, for that application's target, so the same module is a `.so` on
/// Android and Linux, a `.dylib` on Apple platforms and a `.dll` on Windows
/// without anyone writing a path. A browser has no C ABI: there the module
/// declares what `--elsewhere` says, and a WASM build of the same source is
/// the WASM kind's job.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;

import '../described_api.dart';
import 'dart_surface.dart';
import 'ffi_surface.dart';
import 'module_writer.dart';

/// The module spec for a native source whose surface is [surface].
DVForeignModuleSpec dvFfiModuleSpec({
  required String id,
  required String source,
  required DVFfiSurface surface,
  DVModuleOutcome elsewhere = DVModuleOutcome.unavailable,
}) {
  final String packageName = 'dv_${dvSnake(id)}_module';
  final String assetId = 'package:$packageName/native';
  final bool strings =
      surface.functions.any((DVFfiFunction f) => f.stringParams.isNotEmpty);
  final StringBuffer externs = StringBuffer();
  for (final DVFfiFunction f in surface.functions) {
    final List<String> params = <String>[
      for (final DVModuleParam param in f.operation.params)
        '${f.stringParams.contains(param.name) ? 'Pointer<Utf8>' : param.type} ${param.name}',
    ];
    externs
      ..writeln("@Native<${f.nativeSignature}>(symbol: '${f.name}', "
          "assetId: '$assetId')")
      ..writeln('external ${f.operation.returnType} _${f.name}(${params.join(', ')});')
      ..writeln();
  }
  final DVCarrierSource native = DVCarrierSource(
    imports: <String>[
      "import 'dart:ffi';",
      if (strings) "import 'package:ffi/ffi.dart';",
    ],
    declarations: externs.toString(),
    body: (DVModuleOperation op) {
      final DVFfiFunction f = surface.functions
          .firstWhere((DVFfiFunction f) => f.operation.name == op.name);
      final String args = <String>[
        for (final DVModuleParam param in op.params)
          f.stringParams.contains(param.name)
              ? '${param.name}.toNativeUtf8(allocator: arena)'
              : param.name,
      ].join(', ');
      // A string is allocated for the call and freed after it, whatever
      // the call does: the module owns it, the native side only borrows it.
      return f.stringParams.isEmpty
          ? '_${f.name}($args)'
          : 'using((Arena arena) => _${f.name}($args))';
    },
  );

  final Map<String, String> copied = <String, String>{};
  final List<String> files = surface.language == 'c'
      ? <String>[...surface.headers, ...surface.sources]
      : _crateFiles(surface.directory);
  for (final String file in files) {
    copied['native/${surface.language == 'rust' ? 'rust/' : ''}$file'] =
        File(p.join(surface.directory, file)).readAsStringSync();
  }

  return DVForeignModuleSpec(
    id: id,
    kind: 'ffi',
    source: source,
    description: '${surface.name}, as a Dartvel module.',
    operations: <DVModuleOperation>[
      for (final DVFfiFunction f in surface.functions) f.operation,
    ],
    outcomes: <String, Map<DVModuleEnvironment, DVModuleOutcome>>{
      for (final DVFfiFunction f in surface.functions)
        f.operation.name: <DVModuleEnvironment, DVModuleOutcome>{
          DVModuleEnvironment.native: DVModuleOutcome.real,
          DVModuleEnvironment.web: elsewhere,
          DVModuleEnvironment.backend: DVModuleOutcome.real,
        },
    },
    carriers: <DVModuleEnvironment, DVCarrierSource>{
      DVModuleEnvironment.native: native,
      DVModuleEnvironment.backend: native,
    },
    dependencies: <String, String>{
      if (strings) 'ffi': '^2.1.0',
      'hooks': '^0.20.1',
      'code_assets': '^0.19.7',
      // 0.17.2 is the last release on hooks 0.20, which the rest of
      // Dartvel is on; one application cannot hold two majors of hooks.
      if (surface.language == 'c') 'native_toolchain_c': '^0.17.2',
    },
    skipped: surface.skipped,
    extraFiles: <String, String>{
      ...copied,
      'hook/build.dart': surface.language == 'c'
          ? _cHook(surface)
          : _rustHook(surface),
    },
  );
}

/// The crate's own files: what cargo needs to build it, and nothing it made.
List<String> _crateFiles(String dir) {
  final List<String> out = <String>[];
  for (final FileSystemEntity e in Directory(dir).listSync(recursive: true)) {
    if (e is! File) continue;
    final String rel = p.relative(e.path, from: dir).replaceAll('\\', '/');
    final List<String> parts = rel.split('/');
    if (parts.first == 'target' || parts.any((String s) => s.startsWith('.'))) {
      continue;
    }
    if (rel == 'Cargo.toml' || rel == 'Cargo.lock' || rel == 'build.rs' ||
        parts.first == 'src') {
      out.add(rel);
    }
  }
  return out..sort();
}

String _cHook(DVFfiSurface surface) => '''
// GENERATED by dartvel add. Builds the C sources for the target the
// application is being built for, with that target's C toolchain.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    if (!input.config.buildAssetTypes.contains('code_assets/code')) return;
    await CBuilder.library(
      name: 'native',
      assetName: 'native',
      sources: <String>[
${surface.sources.map((String s) => "        'native/$s',").join('\n')}
      ],
      includes: <String>['native'],
    ).run(input: input, output: output);
  });
}
''';

String _rustHook(DVFfiSurface surface) {
  final String lib = surface.name.replaceAll('-', '_');
  return '''
// GENERATED by dartvel add. Builds the crate with cargo for the target the
// application is being built for, as a C-ABI shared library.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    if (!input.config.buildAssetTypes.contains('code_assets/code')) return;
    final OS os = input.config.code.targetOS;
    final Architecture arch = input.config.code.targetArchitecture;
    final String? triple = _triple(os, arch);
    if (triple == null) {
      throw UnsupportedError('No Rust target for \$os/\$arch.');
    }
    final Uri crate = input.packageRoot.resolve('native/rust/');
    final String targetDir = input.outputDirectory.resolve('cargo/').toFilePath();
    final Map<String, String> env = <String, String>{};
    final Uri? compiler = input.config.code.cCompiler?.compiler;
    if (compiler != null) {
      final String key =
          'CARGO_TARGET_\${triple.toUpperCase().replaceAll('-', '_')}_LINKER';
      env[key] = compiler.toFilePath();
      if (os == OS.android) {
        env['RUSTFLAGS'] = '-C link-arg=--target=\$triple'
            '\${input.config.code.android.targetNdkApi}';
      }
    }
    await Process.run('rustup', <String>['target', 'add', triple]);
    final ProcessResult built = await Process.run(
      'cargo',
      <String>[
        'rustc', '--release', '--lib', '--crate-type', 'cdylib',
        '--target', triple, '--target-dir', targetDir,
      ],
      workingDirectory: crate.toFilePath(),
      environment: env,
    );
    if (built.exitCode != 0) {
      throw StateError('cargo failed for \$triple:\\n\${built.stderr}');
    }
    final String file = switch (os) {
      OS.windows => '$lib.dll',
      OS.macOS || OS.iOS => 'lib$lib.dylib',
      _ => 'lib$lib.so',
    };
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'native',
      linkMode: DynamicLoadingBundled(),
      file: Uri.file('\$targetDir\$triple/release/\$file'),
    ));
    output.dependencies.add(crate.resolve('src/'));
    output.dependencies.add(crate.resolve('Cargo.toml'));
  });
}

String? _triple(OS os, Architecture arch) => switch ((os, arch)) {
      (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
      (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
      (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
      (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
      (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
      (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',
      (OS.android, Architecture.arm64) => 'aarch64-linux-android',
      (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
      (OS.android, Architecture.x64) => 'x86_64-linux-android',
      (OS.iOS, Architecture.arm64) => 'aarch64-apple-ios',
      _ => null,
    };
''';
}
