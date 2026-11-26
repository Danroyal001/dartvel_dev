/// Where a build's time goes, phase by phase.
///
/// A web-server build of a site of two hundred routes took twenty-five
/// minutes, and its log could not say which part: Flutter's compile, the
/// semantics read, the fonts, the pack. Every phase `dartvel build` runs is
/// timed here, printed as a table when the build ends and written to
/// `build/dartvel_build_timings.json`, so a slow build says what was slow and
/// a change meant to speed it up can be measured against the last one.
///
/// Phases can overlap: the backend compiles beside Flutter's build, and
/// Flutter runs dart2js and dart2wasm at once. A phase that ran beside
/// another is marked, so the column is not read as a sum.
library;

import 'dart:convert';
import 'dart:io';

/// One timed phase.
class DVBuildPhase {
  DVBuildPhase(this.name, this.elapsed, {this.detail, this.beside = false, this.depth = 0});

  /// What ran, as the table names it.
  final String name;

  final Duration elapsed;

  /// A short note: how many routes, what was reused.
  final String? detail;

  /// True when the phase ran beside another (its time is inside another
  /// phase's wall time, not added to it).
  final bool beside;

  /// 0 for a phase of the build, 1 for a part of the phase above it.
  final int depth;

  Map<String, Object?> toJson() => <String, Object?>{
    'phase': name,
    'seconds': elapsed.inMilliseconds / 1000,
    if (detail != null) 'detail': detail,
    if (beside) 'beside': true,
    if (depth > 0) 'depth': depth,
  };
}

/// The phases of one build, in the order they ended.
class DVBuildTimings {
  DVBuildTimings({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _started = _clock();
  }

  final DateTime Function() _clock;
  late final DateTime _started;
  final List<DVBuildPhase> phases = <DVBuildPhase>[];

  /// Records a phase measured elsewhere.
  void add(String name, Duration elapsed, {String? detail, bool beside = false, int depth = 0}) {
    phases.add(DVBuildPhase(name, elapsed, detail: detail, beside: beside, depth: depth));
  }

  /// Runs [body] and records how long it took under [name], also when it
  /// throws: a failed phase's time is part of the build's.
  Future<T> time<T>(String name, Future<T> Function() body, {String? Function(T result)? detail}) async {
    final DateTime start = _clock();
    bool finished = false;
    late final T result;
    try {
      result = await body();
      finished = true;
      return result;
    } finally {
      add(name, _clock().difference(start), detail: finished && detail != null ? detail(result) : null);
    }
  }

  /// [time] for a phase that does not wait on anything.
  T timeSync<T>(String name, T Function() body) {
    final DateTime start = _clock();
    try {
      return body();
    } finally {
      add(name, _clock().difference(start));
    }
  }

  /// From the start of the build until now.
  Duration get total => _clock().difference(_started);

  /// The table the build prints when it ends.
  List<String> table() {
    if (phases.isEmpty) return const <String>[];
    final List<String> names = <String>[for (final DVBuildPhase phase in phases) '${'  ' * phase.depth}${phase.name}'];
    final int width = names.fold<int>('Total'.length, (int widest, String name) => name.length > widest ? name.length : widest);
    String seconds(Duration elapsed) => (elapsed.inMilliseconds / 1000).toStringAsFixed(1).padLeft(7);
    return <String>[
      '${'Phase'.padRight(width)}  seconds',
      for (final (int index, DVBuildPhase phase) in phases.indexed)
        '${names[index].padRight(width)}  ${seconds(phase.elapsed)}'
            '${phase.beside ? '  (beside)' : ''}'
            '${phase.detail == null ? '' : '  ${phase.detail}'}',
      '${'Total'.padRight(width)}  ${seconds(total)}',
    ];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'totalSeconds': total.inMilliseconds / 1000,
    'phases': <Object?>[for (final DVBuildPhase phase in phases) phase.toJson()],
  };

  /// Writes [toJson] to `build/dartvel_build_timings.json` under [root].
  void write(String root) {
    try {
      final File file = File('$root/build/dartvel_build_timings.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
    } on FileSystemException {
      // Timings are a report; a build is not failed for lacking one.
    }
  }
}

/// How long each of Flutter's build targets ran, read from a
/// `flutter build -v` log: `dart2js`, `dart2wasm`, `web_static_assets`...
///
/// Flutter stamps each verbose line with the time since the line before it
/// (`[ +123 ms]`, `[+1136 ms]`, `[        ]` for under a millisecond), and
/// logs `<target>: Starting due to ...` and `<target>: Complete`. A target
/// that never completed (a failed build) is left out.
Map<String, Duration> dvFlutterTargetTimes(String verboseLog) {
  final RegExp stamp = RegExp(r'^\[\s*(?:\+(\d+)\s*ms)?\s*\]\s?(.*)$');
  final RegExp starting = RegExp(r'^([A-Za-z0-9_]+): Starting due to');
  final RegExp complete = RegExp(r'^([A-Za-z0-9_]+): Complete\s*$');
  int now = 0;
  final Map<String, int> began = <String, int>{};
  final Map<String, Duration> times = <String, Duration>{};
  for (final String line in const LineSplitter().convert(verboseLog)) {
    final RegExpMatch? stamped = stamp.firstMatch(line);
    if (stamped == null) continue;
    now += int.tryParse(stamped.group(1) ?? '') ?? 0;
    final String text = stamped.group(2)!;
    final RegExpMatch? start = starting.firstMatch(text);
    if (start != null) {
      began[start.group(1)!] = now;
      continue;
    }
    final RegExpMatch? end = complete.firstMatch(text);
    if (end != null) {
      final int? from = began.remove(end.group(1)!);
      if (from != null) times[end.group(1)!] = Duration(milliseconds: now - from);
    }
  }
  return times;
}
