import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../build/conpty_windows.dart';
import '../build/pty_capture.dart';
import '../utils/logger.dart';

/// `dartvel capture pty` — run a command under a pseudo-terminal and keep
/// everything it writes.
///
/// The terminal target draws with escape sequences and Kitty graphics rather
/// than to a window, so "what it rendered" is a byte stream and not a
/// screenshot. It also checks whether it has a terminal and behaves
/// differently without one, which is why a pipe will not do.
///
/// Dart cannot hand a child process an arbitrary file descriptor, so on Linux
/// and macOS the pseudo-terminal is `script(1)`'s, and the Dart side is an
/// ordinary process launch. Windows has no `script`; there it is a ConPTY
/// pseudo console, opened through `dart:ffi`. See `build/pty_capture.dart`.
class PtyCaptureCommand extends Command<void> {
  @override
  final String name = 'pty';

  @override
  final String description =
      'Run a command under a pseudo-terminal and save its raw output.';

  @override
  String get invocation =>
      'dartvel capture pty <output> --seconds <n> [--interrupt] -- <command...>';

  PtyCaptureCommand() {
    argParser
      ..addOption(
        'seconds',
        defaultsTo: '25',
        help: 'How long to let the command run before ending the capture.',
      )
      ..addOption(
        'rows',
        defaultsTo: '40',
        help: 'Terminal height. The application lays out against this.',
      )
      ..addOption(
        'columns',
        defaultsTo: '120',
        help: 'Terminal width.',
      )
      ..addFlag(
        'interrupt',
        negatable: false,
        help: 'End the capture by typing Ctrl+C, and fail unless the command '
            'then exits 0. Without it the command is killed.',
      )
      ..addOption(
        'exit-within',
        defaultsTo: '15',
        help: 'With --interrupt, seconds the command has to exit.',
      );
  }

  @override
  Future<void> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length < 2) {
      Logger.log('❌ Give an output path and a command to run.');
      Logger.log('   $invocation');
      exit(64);
    }

    final String output = rest.first;
    final String command = rest.skip(1).join(' ');
    final int seconds = int.tryParse(argResults!['seconds'] as String) ?? 25;
    final int rows = int.tryParse(argResults!['rows'] as String) ?? 40;
    final int columns = int.tryParse(argResults!['columns'] as String) ?? 120;
    final bool interrupt = argResults!['interrupt'] as bool;
    final int exitWithin =
        int.tryParse(argResults!['exit-within'] as String) ?? 15;

    final File file = File(output);
    file.parent.createSync(recursive: true);
    final IOSink sink = file.openWrite();

    Logger.log('🖥️  Capturing "$command" for ${seconds}s at ${columns}x$rows'
        '${interrupt ? ', then Ctrl+C' : ''}');

    final DVPtyLaunch? launch = dvPtyScriptLaunch(
      hostOs: Platform.operatingSystem,
      command: command,
      rows: rows,
      columns: columns,
    );

    final int? exitCode;
    if (launch == null) {
      final DVConPtyRun run = await dvRunInConPty(
        commandLine: dvConPtyCommandLine(command),
        rows: rows,
        columns: columns,
        window: Duration(seconds: seconds),
        interrupt: interrupt,
        exitWithin: Duration(seconds: exitWithin),
        // Raw bytes: escape sequences are not text, and decoding them would
        // corrupt exactly what is being captured.
        onOutput: sink.add,
      );
      exitCode = run.exitCode;
    } else {
      exitCode = await _runUnderScript(
        launch,
        sink,
        seconds: seconds,
        interrupt: interrupt,
        exitWithin: exitWithin,
      );
    }

    await sink.flush();
    await sink.close();

    final int written = file.existsSync() ? file.lengthSync() : 0;
    Logger.log('   Wrote $written bytes to $output');
    if (interrupt) {
      Logger.log('   Exit after Ctrl+C: ${exitCode ?? 'did not exit'}');
    }
    final DVPtyVerdict verdict =
        dvPtyVerdict(bytes: written, interrupt: interrupt, exitCode: exitCode);
    if (!verdict.passed) {
      Logger.log('❌ ${verdict.message}');
      exit(1);
    }
    Logger.log('✅ ${verdict.message}');
  }

  /// Runs [launch], returning the exit code after Ctrl+C, or null when it was
  /// killed instead.
  Future<int?> _runUnderScript(
    DVPtyLaunch launch,
    IOSink sink, {
    required int seconds,
    required bool interrupt,
    required int exitWithin,
  }) async {
    if (!await _hasScript()) {
      Logger.log('❌ `script` is not on PATH. It is what allocates the '
          'pseudo-terminal: util-linux on Linux, part of the base system on '
          'macOS.');
      exit(69);
    }

    final Process process = await Process.start(
      launch.executable,
      launch.arguments,
      mode: ProcessStartMode.normal,
    );
    final Future<void> collected = process.stdout.forEach(sink.add);
    unawaited(process.stderr.drain<void>());

    // Ended on a timer rather than waited for. The application under capture
    // does not exit on its own -- it is a running UI -- so the capture is a
    // window of time, not a run to completion.
    await Future<void>.delayed(Duration(seconds: seconds));

    int? exitCode;
    if (interrupt) {
      // script copies its standard input to the terminal, and in raw mode
      // Ctrl+C arrives as a key rather than a signal.
      process.stdin.add(const <int>[3]);
      await process.stdin.flush();
      exitCode = await process.exitCode
          .then<int?>((int code) => code)
          .timeout(Duration(seconds: exitWithin), onTimeout: () => null);
    }
    if (exitCode == null) {
      process.kill(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      process.kill(ProcessSignal.sigkill);
    }
    unawaited(process.stdin.close().catchError((Object _) {}));

    await collected.timeout(const Duration(seconds: 5), onTimeout: () {});
    return exitCode;
  }

  Future<bool> _hasScript() async {
    // Not `script --version`: BSD script has no such option. Resolved on PATH
    // instead, which both answer the same way.
    try {
      final ProcessResult result =
          await Process.run('/bin/sh', <String>['-c', 'command -v script']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
