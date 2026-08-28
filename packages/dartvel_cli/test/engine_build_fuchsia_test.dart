// Fuchsia is a different target operating system, not another Linux CPU.
//
// engineBuildPlan has one non-host path and it is Linux's: it passes
// `--target-os linux`, `--linux-cpu`, and a Debian sysroot. Fuchsia shares
// none of that. It takes `--target-os fuchsia` and `--fuchsia-cpu`, its
// sysroot comes from the Fuchsia SDK that gclient fetches rather than from
// `build/linux/debian_*`, and asking for a Debian sysroot on it is not a
// worse build, it is a build that cannot be configured.
//
// This is the last target still marked blocked. The wall is that the fork's
// bundled Flutter predates Dart 3.4, and moving off it means rebuilding the
// engine, which means the plan has to be able to describe a Fuchsia one.
import 'package:dartvel_cli/src/build/engine_build.dart';
import 'package:test/test.dart';

void main() {
  group('a Fuchsia engine build', () {
    EngineBuildPlan plan({EngineMode mode = EngineMode.release}) =>
        engineBuildPlan(
          arch: EngineArch.x64,
          mode: mode,
          os: EngineOs.fuchsia,
          srcRoot: '/src/flutter',
        );

    test('targets fuchsia rather than linux', () {
      final args = plan().gnArgs;

      expect(args, containsAllInOrder(<String>['--target-os', 'fuchsia']));
      expect(args, isNot(contains('linux')));
    });

    test('names the cpu with the argument fuchsia takes', () {
      final args = plan().gnArgs;

      expect(args, containsAllInOrder(<String>['--fuchsia-cpu', 'x64']));
      expect(args, isNot(contains('--linux-cpu')));
    });

    test('asks for no Debian sysroot', () {
      // The Fuchsia SDK supplies it. `--target-sysroot` pointed at
      // build/linux/debian_* is not a worse build, it is one gn refuses.
      final p = plan();

      expect(p.gnArgs, isNot(contains('--target-sysroot')));
      expect(p.targetSysrootPath, isNull);
      expect(p.sysrootArch, isNull);
    });

    test('does not take the host path even though the cpu matches the host',
        () {
      // x64-on-x64 is the one case the Linux planner short-circuits as a host
      // build. A Fuchsia x64 engine is a cross build from an x86-64 runner and
      // the host config would quietly produce a Linux engine.
      final p = plan();

      expect(p.usesHostConfig, isFalse);
      expect(p.outDirectory, isNot(contains('host_')));
      expect(p.outDirectory, contains('fuchsia'));
    });

    test('the engine it produces is an ELF x86-64 object', () {
      // Fuchsia's ELF carries the same e_machine as Linux x86-64, so the
      // architecture check that caught an x86-64 engine shipped as ARM still
      // applies here.
      expect(plan().expectedEngineMachine, ElfMachine.x64);
    });

    test('each mode gets its own output directory', () {
      expect(plan(mode: EngineMode.release).outDirectory,
          isNot(plan(mode: EngineMode.debug).outDirectory));
    });

    test('asks for the embedder built for the target', () {
      // The flag the fork's own build_and_copy_engine_artifacts.sh passes,
      // and the one whose absence produced "relocation R_X86_64_PC32 cannot
      // be used against symbol 'FlutterEngineSendPlatformMessageResponse';
      // recompile with -fPIC" -- every embedder symbol, at the link, after
      // the whole engine had compiled.
      //
      // Without it gn configures the embedder for the host, so the objects
      // are not position-independent and the shared library cannot be linked.
      expect(plan().gnArgs, contains('--embedder-for-target'));
    });

    test('linux builds do not ask for it', () {
      // Linux embedder builds link today without it, and adding a flag to
      // every target to fix one is how a working build stops working.
      final linux = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
        srcRoot: '/src/flutter',
      );

      expect(linux.gnArgs, isNot(contains('--embedder-for-target')));
    });

    test('builds unoptimised, as the fork does', () {
      // The fork's build_and_copy_engine_artifacts.sh passes --unopt and
      // copies out of out/fuchsia_debug_unopt_x64/so.unstripped/. It is the
      // only configuration of this engine anyone has shipped, and a release
      // build of it fails at the link on every embedder symbol.
      expect(plan(mode: EngineMode.debug).gnArgs, contains('--unopt'));
      expect(plan(mode: EngineMode.debug).outDirectory,
          'out/fuchsia_debug_unopt_x64');
    });

    test('the library is taken from so.unstripped', () {
      // Where an unopt build leaves it, and where the fork copies it from.
      expect(plan(mode: EngineMode.debug).enginePath,
          contains('so.unstripped/libflutter_engine.so'));
    });

    test('linux is still optimised', () {
      final linux = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
        srcRoot: '/src/flutter',
      );

      expect(linux.gnArgs, isNot(contains('--unopt')));
      expect(linux.enginePath, isNot(contains('so.unstripped')));
    });

    test('does not force the Dart SDK to be compiled from source', () {
      // The fork's script does not pass it, and it is the last difference
      // between that invocation and the one failing at the link.
      expect(plan(mode: EngineMode.debug).gnArgs,
          isNot(contains('--no-prebuilt-dart-sdk')));
    });

    test('linux still builds it from source', () {
      expect(
        engineBuildPlan(
          arch: EngineArch.arm,
          mode: EngineMode.release,
          srcRoot: '/src/flutter',
        ).gnArgs,
        contains('--no-prebuilt-dart-sdk'),
      );
    });

    test('linux builds are unchanged', () {
      // The new argument must default to what every existing caller means.
      final linux = engineBuildPlan(
        arch: EngineArch.arm,
        mode: EngineMode.release,
        srcRoot: '/src/flutter',
      );

      expect(linux.gnArgs, containsAllInOrder(<String>['--target-os', 'linux']));
      expect(linux.gnArgs, containsAllInOrder(<String>['--linux-cpu', 'arm']));
    });
  });
}
