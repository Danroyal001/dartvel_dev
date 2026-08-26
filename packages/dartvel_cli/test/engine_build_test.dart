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
}
