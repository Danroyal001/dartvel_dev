#!/usr/bin/env dart

// `dartvel create`: make a new project.
//
// This used to forward to `dartvel_cli:new`, an executable that does not
// exist.
import 'dart:io';

void main(List<String> args) async {
  final process = await Process.start(
    'dart',
    ['run', 'dartvel_cli:dartvel', 'create', ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}
