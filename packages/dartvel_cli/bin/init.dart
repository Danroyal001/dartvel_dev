#!/usr/bin/env dart

// `dartvel init`: add Dartvel to a project that already exists.
//
// This used to forward to `dartvel_cli:new`, an executable that does not
// exist, and `init` itself was an alias of `create`. It is its own command
// now; see the Adoption section.
import 'dart:io';

void main(List<String> args) async {
  final process = await Process.start(
    'dart',
    ['run', 'dartvel_cli:dartvel', 'init', ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}
