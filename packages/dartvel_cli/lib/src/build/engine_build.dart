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
  arm('arm',
      debianName: 'armhf',
      gnDefinesSysroot: false,
      triple: 'armv7-unknown-linux-gnueabihf');

  const EngineArch(
    this.gnName, {
    required this.debianName,
    required this.gnDefinesSysroot,
    this.triple,
  });

  /// What `tools/gn` calls this under `--linux-cpu`.
  final String gnName;

  /// What the sysroot tarball is called. `install-sysroot.py` translates
  /// `arm` to `armhf` itself; the directory it unpacks to keeps the Debian
  /// name, which is what gn has to be given.
  final String debianName;

  /// Whether `sysroot.gni` picks a sysroot for this cpu on its own.
  final bool gnDefinesSysroot;

  /// The target triple, for architectures the stock Linux toolchains do not
  /// configure. Null means gn sets the triple itself.
  ///
  /// It has to be the spelling clang's own runtime directories use --
  /// `armv7-unknown-linux-gnueabihf`, not the `arm-linux-gnueabihf` a Debian
  /// cross toolchain goes by. clang resolves its builtins, libc++ and
  /// libunwind by triple, so the wrong spelling means three libraries that
  /// were built and shipped look missing.
  ///
  /// `build/config/compiler/BUILD.gn` emits `-march`, `-mfloat-abi`, `-mfpu`
  /// and `-mthumb` for `current_cpu == "arm"`, and its Linux target-triple
  /// block covers arm64 only. clang is handed ARM flags while still targeting
  /// the host and rejects them.
  final String? triple;
}

/// What `build/toolchain/custom/BUILD.gn` expects to find beside clang, and
/// the name the engine's own LLVM build ships it under.
const Map<String, String> _binutils = <String, String>{
  'ar': 'llvm-ar',
  'readelf': 'llvm-readelf',
  'nm': 'llvm-nm',
  'strip': 'llvm-strip',
};

/// Which operating system the engine is built to run on.
///
/// This is a separate axis from the architecture and cannot be folded into
/// it. A Fuchsia x64 engine and a Linux x64 engine are the same cpu and
/// different builds: gn takes `--fuchsia-cpu` rather than `--linux-cpu`, and
/// the sysroot comes from the Fuchsia SDK that gclient fetches rather than
/// from `build/linux/debian_*`.
enum EngineOs {
  linux('linux', cpuArgument: '--linux-cpu'),

  /// Fuchsia. The last target still recorded as blocked, and the reason this
  /// axis exists: unblocking it means re-pinning the embedder fork to a
  /// modern Flutter, and bootstrap.sh requires the engine and the Flutter pin
  /// stay aligned, so the engine has to be rebuilt.
  fuchsia('fuchsia', cpuArgument: '--fuchsia-cpu');

  const EngineOs(this.gnName, {required this.cpuArgument});

  /// What `tools/gn` calls this under `--target-os`.
  final String gnName;

  /// The argument this target names its cpu with.
  final String cpuArgument;

  /// Whether the embedder library must be built for the target rather than
  /// the host. Linux links it today without asking, and adding the flag
  /// everywhere to fix one target is how a working build stops working.
  bool get needsEmbedderForTarget => this == EngineOs.fuchsia;

  /// Whether the Debian sysroots under `build/linux` apply. They do not on
  /// Fuchsia, where pointing `--target-sysroot` at one is not a worse build
  /// but a build gn refuses to configure.
  bool get usesDebianSysroot => this == EngineOs.linux;
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
    required this.targetTriple,
    required this.toolchainRoot,
    required this.toolchainLinks,
    required this.extraGnArgs,
    required this.runtimeLibraries,
    required this.builtinsPackage,
    required this.builtinsRuntimeSubdir,
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

  /// The triple to build for, or null when gn configures a toolchain for this
  /// architecture itself.
  final String? targetTriple;

  /// Whether this goes through `build/toolchain/custom`.
  bool get usesCustomToolchain => targetTriple != null;

  /// Where the custom toolchain lives, or null when none is used.
  final String? toolchainRoot;

  /// The links to add to [toolchainRoot], as link name to the binary beside it
  /// that it points at. Empty for a stock build.
  final Map<String, String> toolchainLinks;

  /// gn args that have no dedicated `tools/gn` switch.
  final List<String> extraGnArgs;

  /// C++ runtime libraries the custom toolchain expects to already have, by
  /// link name.
  ///
  /// `build/toolchain/custom` passes `-L<custom_toolchain>/lib` and nothing
  /// pointing at the output directory, so a vendor toolchain is expected to
  /// ship these. This one does not, and there is no turning the requirement
  /// off: `use_flutter_cxx` gates both the `-lc++` and the target that builds
  /// it, and it is a plain variable rather than a declare_arg.
  ///
  /// The engine builds them for the target anyway, so they are staged into the
  /// toolchain's lib directory between generating and building. Link names
  /// rather than file names, because the extension differs between a static
  /// and a shared build.
  final List<String> runtimeLibraries;

  /// The apt package carrying a libgcc for the target, or null when clang
  /// already ships compiler builtins for it.
  ///
  /// The builtins are the `__aeabi_*` helpers clang emits calls to. libgcc
  /// implements the same set -- the substitution `--rtlib=libgcc` makes -- and
  /// Ubuntu ships an armhf libgcc in the ordinary x86-64 archive as part of
  /// the cross compiler, so no multiarch sources are needed.
  final String? builtinsPackage;

  /// The directory under clang's resource directory that the linker looks in.
  final String? builtinsRuntimeSubdir;

  /// What the linker expects the builtins archive to be called.
  String? get builtinsFileName =>
      builtinsPackage == null ? null : 'libclang_rt.builtins.a';

  /// The artifacts to ask ninja for, relative to [outDirectory].
  ///
  /// A bare `ninja` builds the default target group, which for a Linux cross
  /// build is the GTK shell: it links `libflutter_linux_gtk.so` and never
  /// touches `libflutter_engine.so`, the Custom Embedder API library the
  /// embedders actually link. Naming them means the build asks for what it is
  /// going to collect.
  List<String> get ninjaTargets => <String>[
        for (final String path in <String>[enginePath, genSnapshotPath])
          path.substring(outDirectory.length + 1),
      ];

  /// The directory under clang's resource directory that must already hold
  /// this target's runtime libraries, or null when the host's will do.
  ///
  /// Asserted before the build. A triple clang has no runtime for produces
  /// three link errors, and they arrive after every one of the 7000 targets
  /// has compiled.
  String? get requiredRuntimeDirectory => targetTriple;

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
  EngineOs os = EngineOs.linux,
  String? srcRoot,
  String? toolchainRoot,
}) {
  // The host shortcut is a Linux one. On Fuchsia an x64 engine is still a
  // cross build from an x86-64 runner, and taking the host config there would
  // quietly produce a Linux engine that passes an architecture check.
  final isHost = arch == hostArch && os == EngineOs.linux;
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
      targetTriple: null,
      toolchainRoot: null,
      runtimeLibraries: const <String>[],
      builtinsPackage: null,
      builtinsRuntimeSubdir: null,
      toolchainLinks: const <String, String>{},
      extraGnArgs: const <String>[],
      expectedEngineMachine: _machineForArch[arch]!,
      expectedGenSnapshotMachine: _machineForArch[hostArch]!,
      enginePath: '$out/libflutter_engine.so',
      genSnapshotPath: '$out/gen_snapshot',
    );
  }

  final out = 'out/${os.gnName}_${mode.name}_${arch.gnName}';
  final relativeSysroot = (!os.usesDebianSysroot || arch.gnDefinesSysroot)
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
      os.gnName,
      os.cpuArgument,
      arch.gnName,
      // Fuchsia's embedder library has to be built for the target. Without
      // this gn configures it for the host, the objects are not
      // position-independent, and the link fails on every embedder symbol
      // with "relocation R_X86_64_PC32 ... recompile with -fPIC" -- after the
      // whole engine has compiled, so it reads as a broken source tree.
      //
      // It is the flag the embedder fork's own engine script passes.
      if (os.needsEmbedderForTarget) '--embedder-for-target',
      if (sysrootPath != null) ...<String>['--target-sysroot', sysrootPath],
      if (os.usesDebianSysroot && arch.triple != null && toolchainRoot != null)
        ...<String>['--target-toolchain', toolchainRoot],
      if (os.usesDebianSysroot && arch.triple != null)
        ...<String>['--target-triple', arch.triple!],
      '--no-goma',
      '--no-prebuilt-dart-sdk',
    ],
    sysrootArch: os.usesDebianSysroot ? arch.gnName : null,
    targetSysrootPath: relativeSysroot,
    targetTriple: arch.triple,
    toolchainRoot: arch.triple == null ? null : toolchainRoot,
    toolchainLinks: arch.triple == null
        ? const <String, String>{}
        : <String, String>{
            // Not clang or clang++: the toolchain root is their directory,
            // so a link would point at itself and destroy the binary.
            for (final MapEntry<String, String> tool in _binutils.entries)
              '${arch.triple}-${tool.key}': tool.value,
          },
    // The armhf sysroot is hard-float; arm.gni defaults armv7 to softfp, a
    // different calling convention. Mixing them links and then passes floats
    // in the wrong registers, so nothing fails until the device runs it.
    extraGnArgs: arch == EngineArch.arm
        ? const <String>['arm_float_abi="hard"']
        : const <String>[],
    runtimeLibraries: const <String>[],
    builtinsPackage: null,
    builtinsRuntimeSubdir: null,
    expectedEngineMachine: _machineForArch[arch]!,
    // Runs on the builder, emits for the target.
    expectedGenSnapshotMachine: _machineForArch[hostArch]!,
    enginePath: '$out/libflutter_engine.so',
    genSnapshotPath: '$out/clang_x64/gen_snapshot',
  );
}

/// Render gn args for a bash command line.
///
/// gn needs `arm_float_abi="hard"` with the quotes: without them it reads
/// `hard` as an identifier and stops. Bash strips an unprotected pair, so the
/// whole argument is wrapped in single quotes.
String shellRenderGnArgs(List<String> args) =>
    args.map((String a) => "--gn-args '$a'").join(' ');

/// The engine's bundled clang, which is also where a custom toolchain has to
/// be rooted.
///
/// clang locates its resource headers relative to `argv[0]`, and the engine
/// compiles with `-no-canonical-prefixes`, so it does not resolve a symlink
/// first. A separate directory of links to clang leaves it looking for
/// `stddef.h` beside the links, where there is none.
String engineClangDirectory(String srcRoot) =>
    '${srcRoot.replaceAll(RegExp(r'/+$'), '')}'
    '/flutter/buildtools/linux-x64/clang';
