// What a generated module does where it cannot run.
//
// A module declares one of four outcomes for every environment it is called
// from, and `unavailable` throws rather than returning something that looks
// like an answer. The failure names the module, the operation and the
// environment, because a crash report that says only "unsupported" is a
// crash report somebody has to reproduce to read.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('unavailable names the module, the operation and the environment', () {
    const DVModuleUnavailable failure =
        DVModuleUnavailable('slugify', 'slug', DVModuleEnvironment.web);
    expect(failure.code, 'DV-MODULE-013');
    expect(
        failure.toString(),
        allOf(contains('slugify'), contains('slug'), contains('web'),
            contains('DV-MODULE-013')));
  });

  test('the environment this code is running in is one of the three', () {
    // The VM running this test is not a browser and has no Flutter engine,
    // which is the backend.
    expect(DVModuleEnvironment.current, DVModuleEnvironment.backend);
  });

  test('outcomes are read from the words a pubspec uses, and nothing else',
      () {
    expect(DVModuleOutcome.parse('real'), DVModuleOutcome.real);
    expect(DVModuleOutcome.parse('compat'), DVModuleOutcome.compat);
    expect(DVModuleOutcome.parse('noop'), DVModuleOutcome.noop);
    expect(DVModuleOutcome.parse('unavailable'), DVModuleOutcome.unavailable);
    expect(DVModuleOutcome.parse('fallback'), isNull);
    expect(DVModuleOutcome.parse(null), isNull);
  });
}
