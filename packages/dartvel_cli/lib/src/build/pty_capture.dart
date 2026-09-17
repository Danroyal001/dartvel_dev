/// Running a terminal application under a pseudo-terminal, on each host a
/// terminal target builds on.
///
/// Dart cannot hand a child process an arbitrary file descriptor, so on Linux
/// and macOS the pseudo-terminal is `script(1)`'s -- and the two `script`s
/// disagree about their arguments. Windows has no `script`; a pseudo console
/// there is ConPTY, which `conpty_windows.dart` opens through `dart:ffi`.
library;

/// A `script` invocation that runs a command inside a pseudo-terminal.
class DVPtyLaunch {
  const DVPtyLaunch({
    required this.executable,
    required this.arguments,
    required this.inner,
  });

  final String executable;
  final List<String> arguments;

  /// The shell command run inside the terminal: it sizes the terminal, then
  /// runs what was asked for.
  final String inner;
}

/// How to open a pseudo-terminal with `script` on [hostOs], or null on
/// Windows, which has none.
DVPtyLaunch? dvPtyScriptLaunch({
  required String hostOs,
  required String command,
  required int rows,
  required int columns,
}) {
  // The size is set inside the pty, because stty needs a terminal to talk to
  // and there is not one until script has made it.
  final String inner = 'stty rows $rows cols $columns 2>/dev/null; $command';
  switch (hostOs) {
    case 'windows':
      return null;
    case 'macos':
      // BSD script: `script [-q] [file [command ...]]`. No -c, and no -e
      // because the child's status is already script's own.
      return DVPtyLaunch(
        executable: 'script',
        arguments: <String>['-q', '/dev/null', '/bin/sh', '-c', inner],
        inner: inner,
      );
    default:
      // util-linux: -c takes the command, -e returns the child's status.
      return DVPtyLaunch(
        executable: 'script',
        arguments: <String>['-q', '-e', '-c', inner, '/dev/null'],
        inner: inner,
      );
  }
}

/// The command line CreateProcessW is given for [command] under ConPTY.
///
/// A batch file is not an executable to CreateProcess, so a `.cmd` or `.bat`
/// launcher runs through `cmd.exe`. `/d` skips AutoRun, which would otherwise
/// run whatever a runner's registry says before the launcher.
String dvConPtyCommandLine(String command) {
  final String first = command.trim().split(' ').first.toLowerCase();
  if (first.endsWith('.cmd') || first.endsWith('.bat')) {
    return 'cmd.exe /d /c $command';
  }
  return command;
}

/// Whether a capture passed, and why not.
class DVPtyVerdict {
  const DVPtyVerdict({required this.passed, required this.message});

  final bool passed;
  final String message;
}

/// Judges a capture of [bytes] bytes.
///
/// With [interrupt], the application was sent Ctrl+C at the end of the window
/// and [exitCode] is what it exited with, or null when it did not exit in
/// time. Killing a running UI proves only that it started; exiting 0 on
/// Ctrl+C proves it was reading the terminal and put it back.
DVPtyVerdict dvPtyVerdict({
  required int bytes,
  required bool interrupt,
  required int? exitCode,
}) {
  if (bytes == 0) {
    // An empty capture is the failure this exists to catch: the application
    // started, drew nothing, and every check downstream would pass a file
    // that exists.
    return const DVPtyVerdict(
      passed: false,
      message: 'The command wrote nothing at all.',
    );
  }
  if (!interrupt) {
    return DVPtyVerdict(passed: true, message: 'Captured $bytes bytes.');
  }
  if (exitCode == null) {
    return DVPtyVerdict(
      passed: false,
      message:
          'The command did not exit after Ctrl+C. It drew $bytes bytes '
          'and then stopped reading the terminal, or ignored the key.',
    );
  }
  if (exitCode != 0) {
    return DVPtyVerdict(
      passed: false,
      message: 'The command exited $exitCode after Ctrl+C, not 0.',
    );
  }
  return DVPtyVerdict(
    passed: true,
    message: 'Captured $bytes bytes, and Ctrl+C exited cleanly.',
  );
}
