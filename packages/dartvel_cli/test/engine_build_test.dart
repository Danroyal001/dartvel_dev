// Which engine the build actually produces.
//
// The workflow had an `arm` option in its dropdown for a week and always ran
// `et build -c host_release`, so a run requested for webOS's 32-bit ARM went
// green having produced an x86-64 engine named `engine-arm-release`. The name
// said arm; nothing else did. These assert the machine that comes out, not the
// label that goes on it.
import 'package:dartvel_cli/src/build/engine_build.dart';
import 'package:test/test.dart';

void main() {
  group('build configuration', () {
    test('a host-architecture build uses the host config', () {
      final plan = engineBuildPlan(
        arch: EngineArch.x64,
        mode: EngineMode.release,
      );

      expect(plan.usesHostConfig, isTrue);
      expect(plan.outDirectory, 'out/host_release');
    });

    test('a foreign architecture cross-compiles rather than building host', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      // The defect: `host_release` on an x64 runner produces x64 whatever the
      // requested arch, and the job cannot tell.
      expect(plan.usesHostConfig, isFalse);
      expect(plan.outDirectory, 'out/linux_release_arm');
      expect(plan.gnArgs, containsAllInOrder(<String>['--linux-cpu', 'arm']));
      expect(plan.gnArgs, contains('--target-os'));
    });

    test('cross-compiling requires the target sysroot', () {
      expect(
        engineBuildPlan(arch: EngineArch.arm, mode: EngineMode.release)
            .sysrootArch,
        'arm',
      );
      expect(
        engineBuildPlan(arch: EngineArch.x64, mode: EngineMode.release)
            .sysrootArch,
        isNull,
      );
    });
  });

  group('verifying what was built', () {
    // A cross build emits a host-architecture gen_snapshot that targets the
    // guest, next to a guest-architecture engine. Asserting one machine for
    // both would fail a correct build.
    test('the engine must match the requested architecture', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      expect(plan.expectedEngineMachine, ElfMachine.arm32);
      expect(plan.expectedGenSnapshotMachine, ElfMachine.x64);
    });

    test('a host build expects the host machine for both', () {
      final plan = engineBuildPlan(
        arch: EngineArch.x64,
        mode: EngineMode.release,
      );

      expect(plan.expectedEngineMachine, ElfMachine.x64);
      expect(plan.expectedGenSnapshotMachine, ElfMachine.x64);
    });

    test('an x86-64 engine is rejected when arm was requested', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      // Bytes 18-19 of an ELF header are e_machine, little-endian.
      // 0x3E is x86-64, 0x28 is 32-bit ARM.
      expect(plan.accepts(elfHeader(machine: 0x3E, is64Bit: true)), isFalse);
      expect(plan.accepts(elfHeader(machine: 0x28, is64Bit: false)), isTrue);
    });

    test('a truncated or non-ELF file is not accepted as an engine', () {
      final plan = engineBuildPlan(
        arch: EngineArch.x64,
        mode: EngineMode.release,
      );

      expect(plan.accepts(<int>[0x7F, 0x45]), isFalse);
      expect(plan.accepts(List<int>.filled(64, 0)), isFalse);
    });
  });

  group('collecting artifacts', () {
    test('the host gen_snapshot is taken from the cross build clang_x64', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      expect(plan.genSnapshotPath, 'out/linux_release_arm/clang_x64/gen_snapshot');
      expect(plan.enginePath, 'out/linux_release_arm/libflutter_engine.so');
    });

    test('a host build keeps gen_snapshot beside the engine', () {
      final plan = engineBuildPlan(
        arch: EngineArch.x64,
        mode: EngineMode.release,
      );

      expect(plan.genSnapshotPath, 'out/host_release/gen_snapshot');
    });
  });

  group('the sysroot gn does not define', () {
    // build/config/sysroot.gni assigns a default Linux sysroot for x64,
    // arm64 and riscv64 only. For 32-bit arm it assigns nothing, and gn stops
    // at "Undefined identifier: sysroot" before compiling a file. The sysroot
    // exists -- sysroots.json lists bullseye_armhf -- so the fix is to name
    // it rather than to patch the engine.
    test('32-bit arm must name its sysroot explicitly', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      expect(plan.targetSysrootPath,
          'build/linux/debian_bullseye_armhf-sysroot');
      expect(plan.gnArgs, containsAllInOrder(<String>[
        '--target-sysroot',
        'build/linux/debian_bullseye_armhf-sysroot',
      ]));
    });

    test('arm64 leaves the default alone', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm64,
        mode: EngineMode.release,
      );

      expect(plan.targetSysrootPath, isNull);
      expect(plan.gnArgs, isNot(contains('--target-sysroot')));
      // Still a cross build on an x86-64 runner, still needs the sysroot
      // fetched -- just not named, because gn knows where it goes.
      expect(plan.sysrootArch, 'arm64');
    });

    test('a host build needs neither', () {
      final plan = engineBuildPlan(
        arch: EngineArch.x64,
        mode: EngineMode.release,
      );

      expect(plan.targetSysrootPath, isNull);
      expect(plan.sysrootArch, isNull);
    });
  });

  group('naming the sysroot to gn', () {
    // gn resolves a bare relative path against root_build_dir --
    // out/linux_release_arm -- not against the source root. The stock
    // branches avoid this with rebase_path(); a path handed in on the
    // command line has to be absolute or it points three directories above
    // where the sysroot is, and the compile fails on missing headers rather
    // than on a bad argument.
    test('an absolute sysroot is emitted when the source root is known', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
        srcRoot: '/home/runner/work/dartvel/engine-root/engine/src',
      );

      expect(plan.gnArgs, contains(
        '/home/runner/work/dartvel/engine-root/engine/src/'
        'build/linux/debian_bullseye_armhf-sysroot',
      ));
      expect(plan.gnArgs, isNot(contains(
          'build/linux/debian_bullseye_armhf-sysroot')));
    });

    test('a trailing separator on the source root does not double up', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
        srcRoot: '/src/',
      );

      expect(plan.gnArgs,
          contains('/src/build/linux/debian_bullseye_armhf-sysroot'));
    });
  });

  group('the toolchain gn does not configure', () {
    // build/config/compiler/BUILD.gn emits -march/-mfloat-abi/-mfpu/-mthumb
    // for current_cpu == "arm", and its Linux target-triple block handles
    // arm64 and nothing else. So clang is handed ARM flags while still
    // targeting the host, and refuses them:
    //
    //   clang++: error: unsupported option '-mfloat-abi=' for target
    //            'x86_64-unknown-linux-gnu'
    //
    // The engine has a path for this. build/toolchain/custom takes a
    // toolchain, a sysroot and a triple, and its own comment gives
    // arm-linux-gnueabihf as the example.
    test('32-bit arm builds through the custom toolchain', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      expect(plan.usesCustomToolchain, isTrue);
      // armv7, not arm. The bundled clang ships a runtime directory per
      // triple and the one it has is armv7-unknown-linux-gnueabihf.
      expect(plan.targetTriple, 'armv7-unknown-linux-gnueabihf');
    });

    test('arm64 and x64 use the stock toolchains', () {
      expect(
        engineBuildPlan(arch: EngineArch.arm64, mode: EngineMode.release)
            .usesCustomToolchain,
        isFalse,
      );
      expect(
        engineBuildPlan(arch: EngineArch.x64, mode: EngineMode.release)
            .targetTriple,
        isNull,
      );
    });

    test('the custom toolchain is named to gn with its triple', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
        srcRoot: '/src',
        toolchainRoot: '/tc',
      );

      expect(plan.gnArgs, containsAllInOrder(<String>[
        '--target-toolchain', '/tc',
        '--target-triple', 'armv7-unknown-linux-gnueabihf',
      ]));
    });

    // build/toolchain/custom/BUILD.gn looks for ${triple}-ar, -readelf, -nm
    // and -strip beside clang. The engine ships llvm-ar and friends under
    // those names instead, so the toolchain directory has to be assembled.
    test('the custom toolchain needs triple-prefixed binutils', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      // clang and clang++ are deliberately absent: the toolchain root is
      // their own directory, so linking them would mean `ln -sf bin/clang
      // bin/clang` -- a symlink onto itself, which destroys the compiler.
      expect(plan.toolchainLinks.keys, isNot(contains('clang')));
      expect(plan.toolchainLinks.keys, isNot(contains('clang++')));
      expect(plan.toolchainLinks,
          containsPair('armv7-unknown-linux-gnueabihf-ar', 'llvm-ar'));
      expect(plan.toolchainLinks,
          containsPair('armv7-unknown-linux-gnueabihf-strip', 'llvm-strip'));
      expect(plan.toolchainLinks,
          containsPair('armv7-unknown-linux-gnueabihf-readelf', 'llvm-readelf'));
      expect(plan.toolchainLinks,
          containsPair('armv7-unknown-linux-gnueabihf-nm', 'llvm-nm'));
    });

    test('a stock build assembles no toolchain', () {
      expect(
        engineBuildPlan(arch: EngineArch.x64, mode: EngineMode.release)
            .toolchainLinks,
        isEmpty,
      );
    });

    // The armhf sysroot is hard-float. arm.gni defaults arm_float_abi to
    // softfp for armv7, which is a different calling convention: code built
    // that way links against hard-float libraries and produces a binary that
    // passes floats in the wrong registers. Nothing fails at build time.
    test('the float ABI is set to match the armhf sysroot', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      expect(plan.extraGnArgs, contains('arm_float_abi="hard"'));
    });
  });

  group('handing gn args through a shell', () {
    // The workflow interpolates these into a bash command line. gn reads
    // arm_float_abi=hard as an identifier and errors; it needs the quotes,
    // and bash eats an unprotected pair of them.
    test('a string-valued gn arg keeps its quotes through bash', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      // Asserting the whole string would pin how many args there are, which
      // is not what this is about.
      expect(shellRenderGnArgs(plan.extraGnArgs),
          contains("""--gn-args 'arm_float_abi="hard"'"""));
    });

    test('nothing to pass renders as nothing', () {
      expect(shellRenderGnArgs(const <String>[]), isEmpty);
    });
  });

  group('where the custom toolchain has to live', () {
    // A directory of links to clang did not work. clang finds its own
    // resource headers -- stddef.h among them -- relative to argv[0], and the
    // engine compiles with -no-canonical-prefixes, so it does not resolve the
    // symlink first. It looked for stddef.h beside the links and stopped:
    //
    //   flutter/third_party/libcxx/include/stddef.h:38:17:
    //     fatal error: 'stddef.h' file not found
    //
    // So the toolchain root is the engine's own clang directory, where bin,
    // lib and the resource headers already sit together, and only the
    // triple-prefixed binutils are added to it.
    test('the toolchain root is the engine clang directory', () {
      expect(
        engineClangDirectory('/w/engine-root/engine/src'),
        '/w/engine-root/engine/src/flutter/buildtools/linux-x64/clang',
      );
    });

    test('a trailing separator does not double up', () {
      expect(
        engineClangDirectory('/src/'),
        '/src/flutter/buildtools/linux-x64/clang',
      );
    });

    // If the links pointed into another directory, clang would again be
    // invoked from somewhere without its resource headers.
    test('every link resolves within the toolchain root', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      for (final MapEntry<String, String> link in plan.toolchainLinks.entries) {
        expect(link.value, isNot(contains('/')),
            reason: '${link.key} points outside the toolchain directory');
      }
    });
  });
  group('the target runtime libraries', () {
    // Three link errors -- a missing libclang_rt.builtins.a, then -lc++ and
    // -lunwind -- turned out to have one cause between them. clang ships a
    // runtime directory per target triple, and the one it has is
    // armv7-unknown-linux-gnueabihf. Asking for arm-unknown-linux-gnueabihf
    // asked for a directory that does not exist, so nothing inside it did
    // either, and each missing file read like a package to go and find.
    //
    // Nothing is substituted or staged. The libraries were there all along.
    test('nothing has to be supplied for a triple clang builds for', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      expect(plan.runtimeLibraries, isEmpty);
      expect(plan.builtinsPackage, isNull);
    });

    test('the runtime directory that must exist is named up front', () {
      final plan = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
      );

      // So a wrong triple fails on a missing directory in seconds, rather
      // than at the first link, 35 minutes of compiling later.
      expect(plan.requiredRuntimeDirectory, 'armv7-unknown-linux-gnueabihf');
    });

    test('a host build needs no separate runtime directory', () {
      expect(
        engineBuildPlan(arch: EngineArch.x64, mode: EngineMode.release)
            .requiredRuntimeDirectory,
        isNull,
      );
    });
  });
}
