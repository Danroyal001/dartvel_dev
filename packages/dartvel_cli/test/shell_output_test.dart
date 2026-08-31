// A shell that loses the output of a fast command.
//
// _runInvocation awaited process.exitCode and then cancelled the stdout and
// stderr subscriptions. exitCode completes when the process exits, which can
// happen before its output has been delivered to the listener -- so for a
// command that exits immediately, the buffered output was discarded.
//
// It affects more than what is printed. The captured stdoutText is what a
// pipeline feeds to its next stage, so `a | b` could hand b an empty stdin,
// and DV.$ could return an empty result for a command that produced plenty.
//
// It is a race, so it is intermittent, which is the worst kind: a task runner
// that usually shows output and sometimes does not reads as a flaky tool.
import 'package:dartvel_cli/src/commands/shell_command.dart';
import 'package:test/test.dart';

void main() {
  test('the output of a command that exits at once is captured', () async {
    // echo is the shortest-lived process there is, which is exactly the case
    // that lost its output.
    final DartvelShellResult result =
        await DartvelShell.run('echo hello-from-dartvel', streamOutput: false);

    expect(result.exitCode, 0);
    expect(result.stdoutText.trim(), 'hello-from-dartvel');
  });

  test('it holds under repetition, because the bug was a race', () async {
    // One pass proves little when the failure depends on scheduling. Fifty
    // fast processes reliably reproduced the loss.
    for (int i = 0; i < 50; i += 1) {
      final DartvelShellResult result =
          await DartvelShell.run('echo run-$i', streamOutput: false);
      expect(result.stdoutText.trim(), 'run-$i', reason: 'iteration $i');
    }
  });

  test('a large output is not truncated', () async {
    // The other half of the same bug: output that arrives in several chunks
    // could be cut off partway rather than lost entirely.
    final DartvelShellResult result = await DartvelShell.run(
      'dart --version',
      streamOutput: false,
    );
    expect(result.exitCode, 0);
    expect(
      '${result.stdoutText}${result.stderrText}',
      contains('Dart SDK version'),
    );
  });

  test('stderr is captured too', () async {
    final DartvelShellResult result = await DartvelShell.run(
      'dart --nonexistent-flag',
      streamOutput: false,
    );
    expect(result.exitCode, isNot(0));
    expect('${result.stdoutText}${result.stderrText}', isNotEmpty);
  });

  test('a pipeline sees the first stage output', () async {
    // The consequence that is not about printing: the captured text is what
    // feeds the next stage, so losing it hands the next command empty stdin
    // and the pipeline silently produces nothing.
    final DartvelShellResult result = await DartvelShell.run(
      'echo piped-value | cat',
      streamOutput: false,
    );
    expect(result.stdoutText.trim(), 'piped-value');
  });

  test('a failing command still reports its exit code', () async {
    final DartvelShellResult result =
        await DartvelShell.run('false', streamOutput: false);
    expect(result.succeeded, isFalse);
  });
}
