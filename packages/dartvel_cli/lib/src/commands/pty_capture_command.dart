import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../utils/logger.dart';

/// `dartvel capture pty` — run a command under a pseudo-terminal and keep
/// everything it writes.
///
/// The terminal target draws with escape sequences and Kitty graphics rather
/// than to a window, so "what it rendered" is a byte stream and not a
/// screenshot. It also checks whether it has a terminal and behaves
/// differently without one, which is why a pipe will not do.
///
/// Dart cannot hand a child process an arbitrary file descriptor, so it cannot
/// allocate a pty and exec into it the way a C program would. `script(1)` does
/// exactly that job and is in util-linux on every runner this uses, so the
/// Dart side is an ordinary process launch.
class PtyCaptureCommand extends Command<void> {
  @override
  final String name = 'pty';

  @override
  final String description =
      'Run a command under a pseudo-terminal and save its raw output.';

  @override
  String get invocation =>
      'dartvel capture pty <output> --seconds <n> -- <command...>';

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
    final String rows = argResults!['rows'] as String;
    final String columns = argResults!['columns'] as String;

    if (!await _hasScript()) {
      Logger.log('❌ `script` is not on PATH. It comes with util-linux and is '
          'what allocates the pseudo-terminal.');
      exit(69);
    }

    // The size is set inside the pty, because stty needs a terminal to talk
    // to and there is not one until script has made it.
    final String inner = 'stty rows $rows cols $columns 2>/dev/null; $command';

    Logger.log('🖥️  Capturing "$command" for ${seconds}s at ${columns}x$rows');
    final Process process = await Process.start(
      'script',
      <String>['-q', '-e', '-c', inner, '/dev/null'],
      // Raw bytes: escape sequences and Kitty graphics are not text, and
      // decoding them would corrupt exactly what is being captured.
      mode: ProcessStartMode.normal,
    );

    final File file = File(output);
    file.parent.createSync(recursive: true);
    final IOSink sink = file.openWrite();
    final Future<void> collected = process.stdout.forEach(sink.add);
    unawaited(process.stderr.drain<void>());

    // Ended on a timer rather than waited for. The application under capture
    // does not exit on its own -- it is a running UI -- so the capture is a
    // window of time, not a run to completion.
    await Future<void>.delayed(Duration(seconds: seconds));
    process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    process.kill(ProcessSignal.sigkill);

    await collected.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    await sink.flush();
    await sink.close();

    final int written = file.existsSync() ? file.lengthSync() : 0;
    Logger.log('   Wrote $written bytes to $output');
    if (written == 0) {
      // An empty capture is the failure this exists to catch: the application
      // started, drew nothing, and every check downstream would pass a file
      // that exists.
      Logger.log('❌ The command wrote nothing at all.');
      exit(1);
    }
  }

  Future<bool> _hasScript() async {
    try {
      final ProcessResult result = await Process.run('script', <String>['--version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
