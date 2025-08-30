#!/usr/bin/env dart
import 'dart:io';
import 'dartvel_impl.dart' as impl;

Future<void> main(List<String> args) async {
  try {
    await impl.main(args);
  } catch (e, st) {
    stderr.writeln(e);
    stderr.writeln(st);
    exit(1);
  }
}
