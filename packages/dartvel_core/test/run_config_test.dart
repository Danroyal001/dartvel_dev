import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

/// `dartvel.run` (Application Entry, Configuration): the one block DV.run
/// reads of its own. A value the runtime cannot honour fails the build rather
/// than being served as the default, the rule the other configuration blocks
/// follow.
void main() {
  test('the defaults are the spec\'s', () {
    final DVRunConfig config = DVRunConfig.parse(null);
    expect(config.bootBudget, const Duration(milliseconds: 800));
    expect(config.headlessBudget, const Duration(seconds: 5));
    expect(config.shutdownGrace, const Duration(seconds: 20));
  });

  test('durations are read in ms, s, m and h', () {
    final DVRunConfig config = DVRunConfig.parse(<String, Object?>{
      'bootBudget': '1200ms',
      'headlessBudget': '1m',
      'shutdownGrace': '5s',
    });
    expect(config.bootBudget, const Duration(milliseconds: 1200));
    expect(config.headlessBudget, const Duration(minutes: 1));
    expect(config.shutdownGrace, const Duration(seconds: 5));
  });

  test('a misspelt key or an unreadable duration is refused', () {
    expect(() => DVRunConfig.parse(<String, Object?>{'shutdownGrance': '5s'}),
        throwsArgumentError);
    expect(() => DVRunConfig.parse(<String, Object?>{'shutdownGrace': 'soon'}),
        throwsArgumentError);
    expect(() => DVRunConfig.parse(<String, Object?>{'bootBudget': 800}),
        throwsArgumentError);
    expect(() => DVRunConfig.parse('fast'), throwsArgumentError);
  });
}
