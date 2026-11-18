/// Measures the proposal's Part 2 rows against local upstream checkouts.
///
///   dart run bin/measure.dart --sdk ~/src/sdk --flutter ~/src/flutter \
///       --pub ~/src/pub --dart_style ~/src/dart_style \
///       --json baseline.json
///
/// Prints the Part 2 table. A checkout you do not pass is not measured, and
/// its rows are listed as skipped rather than printed as zero.
library;

import 'dart:io';

import 'package:rust_stack_phase0/components.dart';
import 'package:rust_stack_phase0/line_count.dart';
import 'package:rust_stack_phase0/report.dart';

void main(List<String> args) {
  final paths = <String, String>{};
  String? jsonOut;
  for (var i = 0; i < args.length; i++) {
    final flag = args[i];
    final value = i + 1 < args.length ? args[i + 1] : null;
    final key = flag.startsWith('--') ? flag.substring(2) : null;
    if (key == 'json' && value != null) {
      jsonOut = value;
      i++;
    } else if (key != null && checkouts.containsKey(key) && value != null) {
      paths[key] = value;
      i++;
    } else {
      stderr.writeln(
        'usage: measure.dart '
        '${checkouts.keys.map((k) => '[--$k PATH]').join(' ')} '
        '[--json FILE]',
      );
      exitCode = 64;
      return;
    }
  }

  final counts = <Count>[];
  final skipped = <String>[];
  final pins = <String, String>{};
  for (final entry in paths.entries) {
    pins[entry.key] = _head(entry.value);
  }
  for (final component in part2Components) {
    final path = paths[component.checkout];
    if (path == null) {
      skipped.add('${component.name} (no --${component.checkout})');
      continue;
    }
    counts.add(measure(component, Directory(path)));
  }

  stdout.writeln(
    'Measured at: '
    '${pins.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
  );
  stdout.writeln();
  stdout.write(markdownTable(counts));
  if (skipped.isNotEmpty) {
    stdout.writeln();
    stdout.writeln('Not measured: ${skipped.join('; ')}.');
  }
  if (jsonOut != null) {
    File(jsonOut).writeAsStringSync('${jsonReport(counts, pins)}\n');
    stdout.writeln();
    stdout.writeln('Wrote $jsonOut');
  }
}

/// The checkout's commit, so the numbers say what they were measured on.
String _head(String path) {
  final result = Process.runSync('git', ['-C', path, 'rev-parse', 'HEAD']);
  return result.exitCode == 0 ? (result.stdout as String).trim() : 'unknown';
}
