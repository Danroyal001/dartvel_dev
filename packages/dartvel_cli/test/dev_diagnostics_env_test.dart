// The diagnostics endpoints a Dartvel server serves -- /_dartvel/logs and
// /_dartvel/traces, which `dartvel logs` and `dartvel traces` read -- are off
// unless the server process has DARTVEL_DIAGNOSTICS set. That default is
// right for a deployment and wrong for the development loop: it would mean
// two of the CLI's own commands answer "not serving that" against the server
// the CLI just started, which reads as the commands being broken.
import 'package:dartvel_cli/src/commands/dev_command.dart';
import 'package:test/test.dart';

void main() {
  test('the dev backend gets the diagnostics endpoints', () {
    expect(
      dvDevBackendEnvironment(const <String, String>{})['DARTVEL_DIAGNOSTICS'],
      '1',
    );
  });

  test('a developer who turned them off keeps them off', () {
    // The override has to win, because the reason to set it to 0 is that
    // something in the log buffer should not be reachable over the port --
    // and a convenience default that overrules that is a security bug.
    expect(
      dvDevBackendEnvironment(
        const <String, String>{'DARTVEL_DIAGNOSTICS': '0'},
      )['DARTVEL_DIAGNOSTICS'],
      '0',
    );
  });

  test('an explicit log level survives too', () {
    expect(
      dvDevBackendEnvironment(
        const <String, String>{'DARTVEL_LOG_LEVEL': 'warn'},
      )['DARTVEL_LOG_LEVEL'],
      'warn',
    );
  });

  test('and debug is the level while you are developing', () {
    expect(
      dvDevBackendEnvironment(const <String, String>{})['DARTVEL_LOG_LEVEL'],
      'debug',
    );
  });
}
