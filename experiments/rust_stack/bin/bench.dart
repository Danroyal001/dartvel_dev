/// Measures a command's wall time and peak memory over several runs and
/// appends the result to a JSON baseline file.
///
///   dart run bin/bench.dart --runs 5 --label "dart format: flutter lib" \
///       --json baselines/speed-memory-2026-10-29.json -- \
///       dart format -o none ../upstream/flutter/packages/flutter/lib
///
/// The first run is a warm-up and is not counted, so caches the tool keeps
/// between runs are warm for every counted one; the label should say so.
library;

import 'dart:convert';
import 'dart:io';

import 'package:rust_stack_phase0/bench.dart';

Future<void> main(List<String> args) async {
  var runs = 5;
  String? label;
  String? jsonOut;
  final separator = args.indexOf('--');
  if (separator < 0 || separator == args.length - 1) {
    stderr.writeln(
      'usage: bench.dart [--runs N] --label TEXT [--json FILE] -- COMMAND...',
    );
    exitCode = 64;
    return;
  }
  for (var i = 0; i < separator; i++) {
    switch (args[i]) {
      case '--runs':
        runs = int.parse(args[++i]);
      case '--label':
        label = args[++i];
      case '--json':
        jsonOut = args[++i];
    }
  }
  final command = args.sublist(separator + 1);
  label ??= command.join(' ');

  stdout.writeln('$label: warm-up');
  final warmUp = await measure(command);
  if (warmUp.exitCode != 0) {
    stderr.writeln(
      'warm-up exited ${warmUp.exitCode}; not measuring a failure',
    );
    exitCode = 1;
    return;
  }

  final walls = <double>[];
  final peaks = <double>[];
  for (var run = 1; run <= runs; run++) {
    final result = await measure(command);
    if (result.exitCode != warmUp.exitCode) {
      stderr.writeln('run $run exited ${result.exitCode}');
      exitCode = 1;
      return;
    }
    walls.add(result.wall.inMicroseconds / 1e6);
    peaks.add(result.peakRssKb / 1024);
    stdout.writeln(
      '  run $run: ${walls.last.toStringAsFixed(2)} s, '
      '${peaks.last.toStringAsFixed(0)} MB',
    );
  }
  final wall = summarize(walls);
  final peak = summarize(peaks);
  stdout.writeln(
    '$label: median ${wall.median.toStringAsFixed(2)} s '
    '(${wall.min.toStringAsFixed(2)}-${wall.max.toStringAsFixed(2)}), '
    'peak median ${peak.median.toStringAsFixed(0)} MB '
    '(${peak.min.toStringAsFixed(0)}-${peak.max.toStringAsFixed(0)})',
  );

  if (jsonOut != null) {
    final file = File(jsonOut);
    final existing = file.existsSync()
        ? (jsonDecode(file.readAsStringSync()) as Map<String, Object?>)
        : <String, Object?>{'machine': _machine(), 'results': <Object?>[]};
    (existing['results']! as List<Object?>).add({
      'label': label,
      'command': command,
      'runs': runs,
      'wallSeconds': {'min': wall.min, 'median': wall.median, 'max': wall.max},
      'peakRssMb': {'min': peak.min, 'median': peak.median, 'max': peak.max},
      'sampleIntervalMs': warmUp.interval.inMilliseconds,
    });
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(existing)}\n',
    );
  }
}

Map<String, Object?> _machine() {
  String? cpu;
  try {
    cpu = RegExp(
      r'^model name\s*:\s*(.+)$',
      multiLine: true,
    ).firstMatch(File('/proc/cpuinfo').readAsStringSync())?.group(1);
  } on FileSystemException {
    cpu = null;
  }
  return {
    'cpu': cpu,
    'cores': Platform.numberOfProcessors,
    'os': Platform.operatingSystemVersion,
    'dart': Platform.version,
    'note':
        'A cloud container, not a named reference machine: these numbers '
        'are provisional until the proposal\'s reference machines exist.',
  };
}
