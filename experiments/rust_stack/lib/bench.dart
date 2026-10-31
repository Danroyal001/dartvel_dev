/// Speed and memory baselines: what the original tools cost, so a Rust port
/// can be held to "faster, and no more memory" (the proposal's Part 4).
///
/// Memory is the peak, over the run, of the summed resident set size of the
/// whole process tree, sampled from /proc. A tree, because `dart analyze`
/// does its work in a separate analysis-server process; sampled, because this
/// container has no /usr/bin/time and a tree has no single high-water mark.
/// Sampling can miss a spike shorter than the interval, so the figure is a
/// floor on the true peak, and the interval is recorded with it.
library;

import 'dart:async';
import 'dart:io';

final class Stats {
  const Stats(this.min, this.median, this.max);
  final double min;
  final double median;
  final double max;
}

Stats summarize(List<double> samples) {
  if (samples.isEmpty) throw ArgumentError('no samples');
  final sorted = [...samples]..sort();
  final middle = sorted.length ~/ 2;
  final median = sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
  return Stats(sorted.first, median, sorted.last);
}

/// VmRSS in kB from the text of /proc/<pid>/status, or null when the process
/// has none (a zombie).
int? rssKb(String status) {
  final match = RegExp(
    r'^VmRSS:\s+(\d+)\s+kB',
    multiLine: true,
  ).firstMatch(status);
  return match == null ? null : int.parse(match.group(1)!);
}

/// [root] and every process below it, from a pid-to-parent map.
Set<int> descendants(int root, Map<int, int> parentOf) {
  final children = <int, List<int>>{};
  parentOf.forEach((pid, parent) => (children[parent] ??= []).add(pid));
  final tree = <int>{};
  final pending = [root];
  while (pending.isNotEmpty) {
    final pid = pending.removeLast();
    if (tree.add(pid)) pending.addAll(children[pid] ?? const []);
  }
  return tree;
}

final class Measurement {
  const Measurement(this.exitCode, this.wall, this.peakRssKb, this.interval);
  final int exitCode;
  final Duration wall;

  /// Peak summed RSS of the process tree, in kB.
  final int peakRssKb;
  final Duration interval;
}

/// Runs [command] and measures its wall time and the peak memory of its
/// process tree, sampling every [interval].
Future<Measurement> measure(
  List<String> command, {
  String? workingDirectory,
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final watch = Stopwatch()..start();
  final process = await Process.start(
    command.first,
    command.skip(1).toList(),
    workingDirectory: workingDirectory,
  );
  final drain = Future.wait([
    process.stdout.drain<void>(),
    process.stderr.drain<void>(),
  ]);
  var peak = 0;
  var done = false;
  final exit = process.exitCode.then((code) {
    done = true;
    return code;
  });
  while (!done) {
    final total = _treeRssKb(process.pid);
    if (total > peak) peak = total;
    await Future.any([exit, Future<void>.delayed(interval)]);
  }
  final code = await exit;
  watch.stop();
  await drain;
  return Measurement(code, watch.elapsed, peak, interval);
}

int _treeRssKb(int root) {
  final parentOf = <int, int>{};
  final statuses = <int, String>{};
  for (final entry in Directory('/proc').listSync(followLinks: false)) {
    final pid = int.tryParse(
      entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    );
    if (pid == null) continue;
    try {
      final status = File('/proc/$pid/status').readAsStringSync();
      final ppid = RegExp(
        r'^PPid:\s+(\d+)',
        multiLine: true,
      ).firstMatch(status);
      if (ppid == null) continue;
      parentOf[pid] = int.parse(ppid.group(1)!);
      statuses[pid] = status;
    } on FileSystemException {
      // The process ended between listing and reading.
    }
  }
  var total = 0;
  for (final pid in descendants(root, parentOf)) {
    total += rssKb(statuses[pid] ?? '') ?? 0;
  }
  return total;
}
