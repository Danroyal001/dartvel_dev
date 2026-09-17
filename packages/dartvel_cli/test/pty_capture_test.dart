// `dartvel capture pty` on each host a terminal target is built on.
//
// It was written for linux-cli, and util-linux `script` was its only way to a
// pseudo-terminal: `-e -c <command>` is util-linux syntax, which the BSD
// `script` on macOS reads as a file name, and Windows has no `script` at all.
// A macos-cli or windows-cli run could not be captured, so neither could be
// verified by running it.
import 'package:dartvel_cli/src/build/pty_capture.dart';
import 'package:test/test.dart';

void main() {
  group('how the pseudo-terminal is opened', () {
    test('linux uses util-linux script and keeps the child exit code', () {
      final launch = dvPtyScriptLaunch(
        hostOs: 'linux',
        command: './run.sh',
        rows: 40,
        columns: 120,
      )!;
      expect(launch.executable, 'script');
      expect(launch.arguments, <String>[
        '-q',
        '-e',
        '-c',
        launch.inner,
        '/dev/null',
      ]);
      expect(launch.inner, 'stty rows 40 cols 120 2>/dev/null; ./run.sh');
    });

    test('macos uses BSD script: the file first, then the command', () {
      // BSD script has no -c and no -e; the command follows the transcript
      // file as its own arguments, and the child's status is script's.
      final launch = dvPtyScriptLaunch(
        hostOs: 'macos',
        command: './run.sh',
        rows: 40,
        columns: 120,
      )!;
      expect(launch.executable, 'script');
      expect(launch.arguments, <String>[
        '-q',
        '/dev/null',
        '/bin/sh',
        '-c',
        launch.inner,
      ]);
      expect(launch.arguments, isNot(contains('-e')));
    });

    test('windows has no script, so it is not asked for one', () {
      // A pseudo console there is ConPTY, opened in-process.
      expect(
        dvPtyScriptLaunch(
          hostOs: 'windows',
          command: 'run.cmd',
          rows: 40,
          columns: 120,
        ),
        isNull,
      );
    });

    test('the Windows command line runs a batch launcher through cmd', () {
      expect(
        dvConPtyCommandLine(r'C:\out\run.cmd'),
        r'cmd.exe /d /c C:\out\run.cmd',
      );
      expect(
        dvConPtyCommandLine(r'C:\out\flt.exe --help'),
        r'C:\out\flt.exe --help',
      );
    });
  });

  group('what counts as a pass', () {
    test('without --interrupt, any output is a capture', () {
      expect(
        dvPtyVerdict(bytes: 900, interrupt: false, exitCode: null).passed,
        isTrue,
      );
      expect(
        dvPtyVerdict(bytes: 0, interrupt: false, exitCode: null).passed,
        isFalse,
      );
    });

    test('with --interrupt, the application has to exit, and cleanly', () {
      // Killing a running UI proves it started. Ctrl+C and exit 0 proves it
      // was reading the terminal and put it back: raw mode off, cursor shown,
      // alternate screen left.
      expect(
        dvPtyVerdict(bytes: 900, interrupt: true, exitCode: 0).passed,
        isTrue,
      );

      final hung = dvPtyVerdict(bytes: 900, interrupt: true, exitCode: null);
      expect(hung.passed, isFalse);
      expect(hung.message, contains('did not exit'));

      final crashed = dvPtyVerdict(bytes: 900, interrupt: true, exitCode: 101);
      expect(crashed.passed, isFalse);
      expect(crashed.message, contains('101'));
    });

    test('a clean exit that drew nothing is still a failure', () {
      expect(
        dvPtyVerdict(bytes: 0, interrupt: true, exitCode: 0).passed,
        isFalse,
      );
    });
  });
}
