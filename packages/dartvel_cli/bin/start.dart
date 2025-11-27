#!/usr/bin/env dart

// Alias for 'dartvel dev' command
import 'dart:io';

void main(List<String> args) async {
  // Forward to the 'dev' command
  final process = await Process.start(
    'dart',
    ['run', 'dartvel_cli:dev', ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  exit(exitCode);
}
