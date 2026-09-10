// An example is evidence, and no framework file will ever name it.
//
// The reachability check scans packages/*/lib for a caller, which is the
// right question for framework code and unanswerable for an example: nothing
// in packages/ imports examples/, and nothing should. So citing an example
// as evidence failed by construction, however real the example was.
//
// That matters because an example is sometimes the only honest evidence
// there is. The Android provider, its manifest receiver and the WidgetKit
// extension only run for a project that actually declares a home widget --
// without one in the example, the packaging code ran on nothing in CI and
// every job was green either way.
//
// An example file carrying a Dartvel annotation is reached by building that
// example, which the Platform build matrix does on every push.
import 'package:test/test.dart';

import '../tool/ci/evidence_reachable.dart';

void main() {
  test('an annotated example file is reached by the build', () {
    expect(
      dvExampleIsExercised(
        path: 'examples/dartvel_example/lib/widgets/next_shift.dart',
        source: '@DVHomeWidget(title: "Next shift")\n'
            'class NextShiftWidget extends StatelessWidget {}',
      ),
      isTrue,
    );
  });

  // A file with no annotation is not a generation input, so building the
  // example proves nothing about it and the ordinary caller rule applies.
  test('an example file with no annotation is not', () {
    expect(
      dvExampleIsExercised(
        path: 'examples/dartvel_example/lib/util/helpers.dart',
        source: 'String greet() => "hi";',
      ),
      isFalse,
    );
  });

  // The exemption is for examples only. Framework code still has to be
  // called by something, which is the whole point of the check.
  test('a package file gets no such exemption', () {
    expect(
      dvExampleIsExercised(
        path: 'packages/dartvel_core/lib/src/thing.dart',
        source: '@DVModel()\nclass _Thing {}',
      ),
      isFalse,
    );
  });
}
