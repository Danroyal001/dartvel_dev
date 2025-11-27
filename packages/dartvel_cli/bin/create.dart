#!/usr/bin/env dart

// Alias for 'dartvel new' command
import 'dart:io';

void main(List<String> args) async {
  // Forward to the 'new' command
  final process = await Process.start(
    'dart',
    ['run', 'dartvel_cli:new', ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  exit(exitCode);
}
