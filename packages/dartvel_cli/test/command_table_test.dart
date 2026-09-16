// The command table can be read without running a command.
//
// The site's CLI reference is built from it, so a command added here reaches
// the docs without anybody typing it out a second time.
import 'package:dartvel_cli/dartvel_impl.dart';
import 'package:test/test.dart';

void main() {
  test('the table holds the commands dartvel --help lists', () {
    final runner = dartvelCommandRunner();
    for (final String name in <String>[
      'create',
      'dev',
      'build',
      'routes',
      'db',
      'doctor',
    ]) {
      expect(runner.commands, contains(name), reason: name);
    }
    expect(runner.commands['build']!.argParser.options, contains('platform'));
  });

  test('each call builds a fresh table', () {
    // Commands hold parsed state, so two readers must not share one runner.
    expect(identical(dartvelCommandRunner(), dartvelCommandRunner()), isFalse);
  });
}
