/// Building a Flutter engine for an architecture Google does not publish.
///
/// Google publishes embedder engines for `linux-x64` and `linux-arm64`. It
/// publishes no 32-bit `linux-arm`, which is what webOS TVs run, so a webOS
/// bundle has no engine to link against until one is built from source. That
/// is the whole of the webOS blocker — LG's engine exports `FlutterEngineRun`
/// like any other Custom Embedder API engine.
///
/// The distinction this file exists to hold is that building *for* another
/// architecture is not the same command as building *on* one. `et build -c
/// host_release` builds for the machine it runs on whatever architecture was
/// asked for, and reports success, so a request for arm produced an x86-64
/// engine and an artifact named `engine-arm-release` to put it in.
library;

import 'dart:typed_data';

/// An architecture an engine can be built for.
enum EngineArch {
  x64('x64', debianName: 'amd64', gnDefinesSysroot: true),
  arm64('arm64', debianName: 'arm64', gnDefinesSysroot: true),

  /// 32-bit ARM. Here for webOS, and the reason this file is not a constant.
  ///
  /// `build/config/sysroot.gni` assigns a default Linux sysroot for x64, arm64
  /// and riscv64 and nothing else, so gn stops at "Undefined identifier:
  /// sysroot" before it compiles a file. The sysroot itself exists --
  /// `sysroots.json` lists `bullseye_armhf` -- so the answer is to name it,
  /// not to patch the engine.
  arm('arm', debianName: 'armhf', gnDefinesSysroot: false);

  const EngineArch(
    this.gnName, {
    required this.debianName,
    required this.gnDefinesSysroot,
  });

  /// What `tools/gn` calls this under `--linux-cpu`.
  final String gnName;

  /// What the sysroot tarball is called. `install-sysroot.py` translates
  /// `arm` to `armhf` itself; the directory it unpacks to keeps the Debian
  /// name, which is what gn has to be given.
  final String debianName;

  /// Whether `sysroot.gni` picks a sysroot for this cpu on its own.
  final bool gnDefinesSysroot;
}

/// Which engine flavour to build.
enum EngineMode {
  debug('debug'),
  profile('profile'),
  release('release');

  const EngineMode(this.name);
  final String name;
}

/// The `e_machine` values an ELF header can carry that concern us.
enum ElfMachine {
  x64(0x3E, is64Bit: true),
  arm64(0xB7, is64Bit: true),
  arm32(0x28, is64Bit: false);

  const ElfMachine(this.code, {required this.is64Bit});

  /// Bytes 18-19 of the header, little-endian.
  final int code;

  /// Byte 4: 1 for ELFCLASS32, 2 for ELFCLASS64. A 32-bit ARM engine and a
  /// 64-bit one differ here as well as in `e_machine`, and webOS needs the
  /// 32-bit one specifically.
  final bool is64Bit;
}

/// The build a request for one architecture and mode actually resolves to.
class EngineBuildPlan {
  const EngineBuildPlan({
    required this.arch,
    required this.mode,
    required this.usesHostConfig,
    required this.outDirectory,
    required this.gnArgs,
    required this.sysrootArch,
    required this.targetSysrootPath,
    required this.expectedEngineMachine,
    required this.expectedGenSnapshotMachine,
    required this.enginePath,
    required this.genSnapshotPath,
  });

  final EngineArch arch;
  final EngineMode mode;

  /// Whether this can ride `et build -c host_<mode>`, which only builds for
  /// the machine it runs on.
  final bool usesHostConfig;

  /// Where the build writes, relative to `engine/src`.
  final String outDirectory;

  /// Arguments to `flutter/tools/gn`. Empty for a host build, which does not
  /// need to bypass `et`.
  final List<String> gnArgs;

  /// The sysroot `install-sysroot.py --arch=` must fetch before a cross build,
  /// or null when the host sysroot suffices.
  final String? sysrootArch;

  /// The sysroot to name in `--target-sysroot`, relative to `engine/src`, or
  /// null when gn picks one itself. Only 32-bit arm needs this.
  final String? targetSysrootPath;

  /// What `libflutter_engine.so` must be for this build to have worked.
  final ElfMachine expectedEngineMachine;

  /// What `gen_snapshot` must be. Not the same as the engine on a cross
  /// build: gen_snapshot runs on the builder and emits code for the target,
  /// so it stays host-architecture. Asserting one machine for both would fail
  /// a correct cross build.
  final ElfMachine expectedGenSnapshotMachine;

  final String enginePath;
  final String genSnapshotPath;

  /// Whether these bytes are an ELF matching [expectedEngineMachine].
  ///
  /// Takes the head of the file rather than a path so it can be asserted on
  /// without a build having run.
  bool accepts(List<int> headerBytes) {
    final machine = readElfMachine(headerBytes);
    return machine == expectedEngineMachine;
  }
}

/// The ELF machine a header describes, or null if it is not an ELF header we
/// recognise — too short, wrong magic, or an architecture not listed here.
ElfMachine? readElfMachine(List<int> bytes) {
  if (bytes.length < 20) return null;
  if (bytes[0] != 0x7F || bytes[1] != 0x45 || bytes[2] != 0x4C ||
      bytes[3] != 0x46) {
    return null;
  }
  final elfClass = bytes[4];
  if (elfClass != 1 && elfClass != 2) return null;
  final is64Bit = elfClass == 2;
  final machine = bytes[18] | (bytes[19] << 8);
  for (final candidate in ElfMachine.values) {
    if (candidate.code == machine && candidate.is64Bit == is64Bit) {
      return candidate;
    }
  }
  return null;
}

/// A synthetic ELF header, for asserting acceptance without a build.
List<int> elfHeader({required int machine, required bool is64Bit}) {
  final bytes = Uint8List(64);
  bytes[0] = 0x7F;
  bytes[1] = 0x45;
  bytes[2] = 0x4C;
  bytes[3] = 0x46;
  bytes[4] = is64Bit ? 2 : 1;
  bytes[5] = 1;
  bytes[18] = machine & 0xFF;
  bytes[19] = (machine >> 8) & 0xFF;
  return bytes;
}

const Map<EngineArch, ElfMachine> _machineForArch = <EngineArch, ElfMachine>{
  EngineArch.x64: ElfMachine.x64,
  EngineArch.arm64: ElfMachine.arm64,
  EngineArch.arm: ElfMachine.arm32,
};

/// The architecture the GitHub runners build on. Everything else is a cross
/// build, including arm64 — a runner is x86-64.
const EngineArch hostArch = EngineArch.x64;

/// Resolve a requested architecture and mode to the build that produces it.
EngineBuildPlan engineBuildPlan({
  required EngineArch arch,
  required EngineMode mode,
  String? srcRoot,
}) {
  final isHost = arch == hostArch;
  if (isHost) {
    final out = 'out/host_${mode.name}';
    return EngineBuildPlan(
      arch: arch,
      mode: mode,
      usesHostConfig: true,
      outDirectory: out,
      gnArgs: const <String>[],
      sysrootArch: null,
      targetSysrootPath: null,
      expectedEngineMachine: _machineForArch[arch]!,
      expectedGenSnapshotMachine: _machineForArch[hostArch]!,
      enginePath: '$out/libflutter_engine.so',
      genSnapshotPath: '$out/gen_snapshot',
    );
  }

  final out = 'out/linux_${mode.name}_${arch.gnName}';
  final relativeSysroot = arch.gnDefinesSysroot
      ? null
      : 'build/linux/debian_bullseye_${arch.debianName}-sysroot';
  // gn resolves a relative path against root_build_dir, which is the output
  // directory, not the source root. Absolute or not at all.
  final sysrootPath = relativeSysroot == null
      ? null
      : (srcRoot == null
          ? relativeSysroot
          : '${srcRoot.replaceAll(RegExp(r'/+$'), '')}/$relativeSysroot');
  return EngineBuildPlan(
    arch: arch,
    mode: mode,
    usesHostConfig: false,
    outDirectory: out,
    gnArgs: <String>[
      '--runtime-mode',
      mode.name,
      '--target-os',
      'linux',
      '--linux-cpu',
      arch.gnName,
      if (sysrootPath != null) ...<String>['--target-sysroot', sysrootPath],
      '--no-goma',
      '--no-prebuilt-dart-sdk',
    ],
    sysrootArch: arch.gnName,
    targetSysrootPath: relativeSysroot,
    expectedEngineMachine: _machineForArch[arch]!,
    // Runs on the builder, emits for the target.
    expectedGenSnapshotMachine: _machineForArch[hostArch]!,
    enginePath: '$out/libflutter_engine.so',
    genSnapshotPath: '$out/clang_x64/gen_snapshot',
  );
}
