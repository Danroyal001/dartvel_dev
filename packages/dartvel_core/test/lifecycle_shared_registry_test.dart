// One registry, so the CLI and the application talk about the same build.
//
// The specification says the CLI, Studio, the analyzer and external tools
// observe the same canonical lifecycle state. They could not: the registry was
// reachable only as `DV.lifecycle`, a static on `DV` in dartvel_flutter, and
// the CLI depends on dartvel_core and deliberately not on Flutter. So the one
// signal whose whole subject is the build pipeline was unreachable from the
// build pipeline, and `setBuild` was called by nothing but its own test —
// declared, documented, and driven by nobody.
//
// The registry lives here now and `DV.lifecycle` returns it, so a process that
// runs a build and a process that renders one are reading the same object
// rather than two that agree by coincidence.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  tearDown(dvLifecycle.resetForTesting);

  test('the registry is the same object every time it is reached', () {
    expect(identical(dvLifecycle, dvLifecycle), isTrue);
  });

  test('a build state set through it is read back through it', () {
    dvLifecycle.setBuild(DVBuildLifecycle.generating);
    expect(dvLifecycle.build.value, DVBuildLifecycle.generating);
  });

  test('resetting returns the build signal to idle', () {
    dvLifecycle.setBuild(DVBuildLifecycle.compiling);
    dvLifecycle.resetForTesting();
    expect(dvLifecycle.build.value, DVBuildLifecycle.idle);
  });
}
