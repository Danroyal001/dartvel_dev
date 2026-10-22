#!/usr/bin/env dart

import 'dart:async';
import 'dart:io';
import 'package:dartvel_cli/dartvel_impl.dart' as impl;

/// The reader went away: `dartvel --version | head -1` has what it wanted.
bool _brokenPipe(Object error) =>
    (error is FileSystemException && error.osError?.errorCode == 32) ||
    (error is SocketException && error.osError?.errorCode == 32) ||
    (error is StdoutException && error.osError?.errorCode == 32);

Future<void> main(List<String> cliArgs) async {
  // A write to a closed pipe fails asynchronously, outside the try below, so
  // it is caught at the zone and ends the run quietly, as a command-line tool
  // whose reader has stopped reading does.
  await runZonedGuarded(() async {
    try {
      await impl.main(cliArgs);
    } catch (error, stacktrace) {
      if (_brokenPipe(error)) exit(0);
      stderr.writeln(error);
      stderr.writeln(stacktrace);

      exit(1);
    }
  }, (Object error, StackTrace stacktrace) {
    if (_brokenPipe(error)) exit(0);
    stderr.writeln(error);
    stderr.writeln(stacktrace);
    exit(1);
  });
}
