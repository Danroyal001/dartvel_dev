/// Compiling the web-server binary's backend, in loading units where the
/// host can.
///
/// `dart compile exe` writes the standalone AOT runtime, the program's
/// snapshot on the next 64 KiB boundary, and a 16-byte trailer naming where
/// the snapshot starts. It compiles every library into that one snapshot:
/// a `deferred as` import compiles, and its `loadLibrary()` completes at
/// once, because the code is already there.
///
/// The SDK's own tools can do more, and `dart compile exe` only does not ask
/// them to. `gen_snapshot --loading_unit_manifest` splits the program into
/// the root unit and one ELF per group of libraries reached only through
/// deferred imports, and the runtime's embedding API loads a unit when the
/// program first asks for it (`Dart_SetDeferredLoadHandler`, `Dart_LoadELF`,
/// `Dart_DeferredLoadComplete`, all exported by `dartaotruntime`). So on a
/// Linux host this runs the same two steps `dart compile exe` runs --
/// `gen_kernel` in AOT mode and `gen_snapshot` -- with that one flag added,
/// and assembles the executable exactly as `dart compile exe` does. The
/// units come back separately, for the build to carry inside the binary
/// (see dartvel_shelf's loading_units.dart for the other half).
///
/// Elsewhere -- macOS and Windows, whose `dart compile exe` puts the
/// snapshot in a Mach-O or PE image the ELF loader cannot map, or an SDK
/// without gen_snapshot -- it is `dart compile exe`, one unit, and the same
/// program runs the same.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'server_binary.dart' show DVServerBinaryRun;

/// The magic number `dart compile exe` ends an executable with.
const int _snapshotMagic = 0xf6f6dcdc;
const int _alignment = 65536;

/// The tools of a Dart SDK that compile a program in loading units.
final class DVAotToolchain {
  const DVAotToolchain._(this.sdk);

  /// The SDK's root: the directory holding `bin/` and `lib/`.
  final String sdk;

  String get runtime => p.join(sdk, 'bin', Platform.isWindows ? 'dartaotruntime.exe' : 'dartaotruntime');
  String get genKernel => p.join(sdk, 'bin', 'snapshots', 'gen_kernel_aot.dart.snapshot');
  String get genSnapshot => p.join(sdk, 'bin', 'utils', Platform.isWindows ? 'gen_snapshot.exe' : 'gen_snapshot');
  String get platform => p.join(sdk, 'lib', '_internal', 'vm_platform_product.dill');

  /// The toolchain of the SDK [dart] belongs to, or null when [dart] is not
  /// an SDK's `dart` with all four tools beside it.
  ///
  /// [dart] as a bare name is the `dart` this process runs on: the CLI runs
  /// under the SDK the project resolved its packages with.
  static DVAotToolchain? find(String dart) {
    final String executable = p.isAbsolute(dart) ? dart : Platform.resolvedExecutable;
    String resolved = executable;
    try {
      resolved = File(executable).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
    final DVAotToolchain toolchain = DVAotToolchain._(p.dirname(p.dirname(resolved)));
    for (final String tool in <String>[
      toolchain.runtime,
      toolchain.genKernel,
      toolchain.genSnapshot,
      toolchain.platform,
    ]) {
      if (!File(tool).existsSync()) return null;
    }
    return toolchain;
  }
}

/// What compiling made.
final class DVCompiledServer {
  const DVCompiledServer({
    required this.ok,
    required this.lines,
    this.executable,
    this.units = const <int, Uint8List>{},
  });

  final bool ok;
  final List<String> lines;

  /// The executable: the runtime, the root unit and the trailer.
  final Uint8List? executable;

  /// Every other unit, by id, as the ELF gen_snapshot wrote.
  final Map<int, Uint8List> units;
}

/// Compiles [entry] of the project at [root]; in loading units when [units]
/// is true and the host and SDK can, as one otherwise. [defines] go to the
/// compiler as `-D` declarations.
Future<DVCompiledServer> dvCompileServer({
  required String root,
  required String entry,
  required DVServerBinaryRun run,
  String dart = 'dart',
  bool units = true,
  Map<String, String> defines = const <String, String>{},
}) async {
  final DVAotToolchain? toolchain = units && Platform.isLinux ? DVAotToolchain.find(dart) : null;
  final Directory work = Directory(p.join(root, '.dart_tool', 'dartvel', 'server_compile'))
    ..createSync(recursive: true);
  final List<String> declared = <String>[
    for (final MapEntry<String, String> d in defines.entries) '-D${d.key}=${d.value}',
  ];

  if (toolchain == null) {
    final String out = p.join(work.path, 'server.exe');
    final ProcessResult result = await run(
      dart,
      <String>['compile', 'exe', ...declared, entry, '-o', out],
      workingDirectory: root,
    );
    if (result.exitCode != 0) return _failed('dart compile exe', result);
    final File compiled = File(out);
    final Uint8List bytes = compiled.readAsBytesSync();
    compiled.deleteSync();
    return DVCompiledServer(ok: true, lines: const <String>[], executable: bytes);
  }

  final String dill = p.join(work.path, 'server.dill');
  final String elf = p.join(work.path, 'server.aot');
  final String manifest = p.join(work.path, 'units.json');
  for (final FileSystemEntity old in work.listSync()) {
    old.deleteSync(recursive: true);
  }
  // What `dart compile exe` runs, in the same order, with the same flags:
  // an AOT kernel of the product platform, then the snapshot.
  final ProcessResult kernel = await run(
    toolchain.runtime,
    <String>[
      toolchain.genKernel,
      '--platform',
      toolchain.platform,
      '--aot',
      '--target-os=linux',
      '--packages',
      p.join(root, '.dart_tool', 'package_config.json'),
      '-Ddart.vm.product=true',
      ...declared,
      '-o',
      dill,
      entry,
    ],
    workingDirectory: root,
  );
  if (kernel.exitCode != 0) return _failed('gen_kernel', kernel);
  final ProcessResult snapshot = await run(
    toolchain.genSnapshot,
    <String>[
      '--snapshot_kind=app-aot-elf',
      '--elf=$elf',
      '--strip',
      '--loading_unit_manifest=$manifest',
      dill,
    ],
    workingDirectory: root,
  );
  if (snapshot.exitCode != 0) return _failed('gen_snapshot', snapshot);

  final Object? listed = jsonDecode(File(manifest).readAsStringSync());
  final Map<int, Uint8List> parts = <int, Uint8List>{};
  Uint8List? rootUnit;
  for (final Object? unit in (listed as Map)['loadingUnits'] as List) {
    final Map<Object?, Object?> u = unit! as Map;
    final int id = u['id']! as int;
    // The manifest names each unit's file relative to where gen_snapshot
    // ran, or absolutely.
    final String named = '${u['path']}';
    final File file = File(p.isAbsolute(named) ? named : p.join(root, named));
    final Uint8List bytes = (file.existsSync() ? file : File(p.join(work.path, p.basename(named))))
        .readAsBytesSync();
    if (id == 1) {
      rootUnit = bytes;
    } else {
      parts[id] = bytes;
    }
  }
  if (rootUnit == null) {
    return const DVCompiledServer(ok: false, lines: <String>['gen_snapshot wrote no root unit.']);
  }

  // The runtime, the root unit on the next 64 KiB boundary, and the trailer
  // naming where it starts: byte for byte what `dart compile exe` writes.
  final Uint8List runtime = File(toolchain.runtime).readAsBytesSync();
  final int at = ((runtime.length + _alignment - 1) ~/ _alignment) * _alignment;
  final ByteData trailer = ByteData(16)
    ..setUint64(0, at, Endian.little)
    ..setUint64(8, _snapshotMagic, Endian.little);
  final Uint8List executable = (BytesBuilder(copy: false)
        ..add(runtime)
        ..add(Uint8List(at - runtime.length))
        ..add(rootUnit)
        ..add(trailer.buffer.asUint8List()))
      .takeBytes();
  for (final FileSystemEntity old in work.listSync()) {
    old.deleteSync(recursive: true);
  }
  return DVCompiledServer(
    ok: true,
    lines: <String>[
      if (parts.isNotEmpty)
        'Compiled in ${parts.length + 1} loading units; ${parts.length} load when first used.',
    ],
    executable: executable,
    units: parts,
  );
}

DVCompiledServer _failed(String step, ProcessResult result) => DVCompiledServer(
      ok: false,
      lines: <String>[
        '$step exited ${result.exitCode}:',
        ...'${result.stdout}\n${result.stderr}'.split('\n').where((String l) => l.trim().isNotEmpty),
      ],
    );
