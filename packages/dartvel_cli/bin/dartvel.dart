#!/usr/bin/env dart

import 'dart:io';
import '../lib/dartvel_impl.dart' as impl;

Future<void> main(List<String> cliArgs) async {
  try {
    await impl.main(cliArgs);
  } catch (error, stacktrace) {
    stderr.writeln(error);
    stderr.writeln(stacktrace);

    exit(1);
  }
}
