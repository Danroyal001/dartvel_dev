// `dartvel build` advances DV.lifecycle.build as it runs.
//
// The signal, its enum and its setter all existed and the build never touched
// one of them. `setBuild` was called by nothing but its own test, so an
// application, Studio or an external tool observing the build pipeline saw
// `idle` for the entire pipeline and could not tell a build that was
// generating from one that had failed from one that was never started.
//
// The stage wrapper exists rather than a line of setBuild before each phase
// because the failure path is the half that gets forgotten: a build that
// throws while compiling has to leave `failed` behind, not the last state it
// happened to reach on the way.
import 'package:dartvel_cli/src/build/build_lifecycle.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late List<DVBuildLifecycle> seen;

  setUp(() {
    dvLifecycle.resetForTesting();
    seen = <DVBuildLifecycle>[];
    dvLifecycle.build.listen(seen.add);
  });

  tearDown(dvLifecycle.resetForTesting);

  test('a build that runs reports every stage in order, and completes',
      () async {
    final DVBuildStages stages = DVBuildStages();
    await stages.run(DVBuildLifecycle.scanning, () async {});
    await stages.run(DVBuildLifecycle.generating, () async {});
    await stages.run(DVBuildLifecycle.compiling, () async {});
    stages.completed();

    await Future<void>.delayed(Duration.zero);
    expect(seen, <DVBuildLifecycle>[
      DVBuildLifecycle.scanning,
      DVBuildLifecycle.generating,
      DVBuildLifecycle.compiling,
      DVBuildLifecycle.completed,
    ]);
  });

  test('a stage returns what its body returned', () async {
    final DVBuildStages stages = DVBuildStages();
    expect(await stages.run(DVBuildLifecycle.analyzing, () async => 7), 7);
  });

  // The half that gets forgotten. A build that dies while compiling must not
  // leave `compiling` behind, which reads as a build still running.
  test('a stage that throws leaves failed behind, and rethrows', () async {
    final DVBuildStages stages = DVBuildStages();
    await expectLater(
      stages.run(DVBuildLifecycle.compiling, () async => throw StateError('x')),
      throwsStateError,
    );

    await Future<void>.delayed(Duration.zero);
    expect(dvLifecycle.build.value, DVBuildLifecycle.failed);
    expect(seen.last, DVBuildLifecycle.failed);
    expect(seen, isNot(contains(DVBuildLifecycle.completed)));
  });

  // A build that stopped for a reason the pipeline caught itself -- a refused
  // capture, a validation failure -- is as failed as one that threw.
  test('a build can be failed without an exception', () async {
    final DVBuildStages stages = DVBuildStages();
    await stages.run(DVBuildLifecycle.validating, () async {});
    stages.failed();

    await Future<void>.delayed(Duration.zero);
    expect(dvLifecycle.build.value, DVBuildLifecycle.failed);
  });

  test('the signal starts idle, so a process that never builds says so', () {
    expect(dvLifecycle.build.value, DVBuildLifecycle.idle);
  });
}
