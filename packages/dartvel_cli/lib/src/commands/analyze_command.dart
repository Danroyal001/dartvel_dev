import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../graph/live_windows.dart';

/// `dartvel analyze performance` -- what the running application measured.
///
/// The windowing layer measures open-to-ready, tear-out handover, the shared
/// store's write rate and coalescing, its size and spills, and restore on
/// launch, and publishes them with its live window list. This aggregates
/// degradations per call site -- a site that always degrades is one finding,
/// not a thousand log lines -- and prints the findings the runtime drew.
///
/// Output goes to stdout unprefixed: `--json` has to be parseable.
class AnalyzeCommand extends Command<void> {
  @override
  final String name = 'analyze';

  @override
  final String description =
      'Analyze a running application: performance measurements and findings.';

  @override
  String get invocation => 'dartvel analyze performance [--json]';

  AnalyzeCommand() {
    argParser.addFlag('json', negatable: false, help: 'Emit the published measurements as JSON.');
  }

  @override
  Future<void> run() async {
    final bool asJson = argResults!['json'] as bool;
    final List<String> rest = argResults!.rest;
    if (rest.isEmpty || rest.first != 'performance') {
      throw UsageException(
        rest.isEmpty ? 'Say what to analyze.' : 'Unknown analysis "${rest.first}".',
        invocation,
      );
    }
    final DVLiveWindowsFile file = DVLiveWindowsFile.read(Directory.current.path);
    final Map<String, Object?>? live = file.live;

    if (live == null) {
      if (asJson) {
        _emit(jsonEncode(<String, Object?>{'live': false, 'ageMinutes': file.age?.inMinutes}));
      } else {
        _emit('performance: ${file.notRunning}');
      }
      return;
    }

    final Map<String, Object?> perf =
        live['performance'] is Map ? (live['performance']! as Map).cast<String, Object?>() : <String, Object?>{};

    if (asJson) {
      _emit(const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'app': live['app'],
        'at': live['at'],
        'performance': perf,
      }));
      return;
    }

    _emit('performance of ${live['app']}, as of ${live['at']}');
    _emitOpens(perf);
    _emitDegradations(perf);
    _emitSpans('tear-out handover', perf['tearOuts']);
    _emitRestores(perf['restores']);
    _emitStore(perf['store']);
    _emitFindings(perf['findings']);
  }

  void _emitOpens(Map<String, Object?> perf) {
    final List<Map<String, Object?>> opens = _maps(perf['opens']);
    final List<Map<String, Object?>> real = opens.where((Map<String, Object?> o) => o['virtual'] != true).toList();
    final List<Map<String, Object?>> virtual = opens.where((Map<String, Object?> o) => o['virtual'] == true).toList();
    _emit('open to ready      real ${_summary(real)}; virtual ${_summary(virtual)}');
  }

  /// Per call site, worst first: the sites that degrade most often are the
  /// ones a developer should look at, and a site that never degrades is
  /// listed last so it does not bury them.
  void _emitDegradations(Map<String, Object?> perf) {
    final Map<String, Object?> sites =
        perf['degradations'] is Map ? (perf['degradations']! as Map).cast<String, Object?>() : <String, Object?>{};
    if (sites.isEmpty) return;
    final List<MapEntry<String, Map<String, Object?>>> rows = <MapEntry<String, Map<String, Object?>>>[
      for (final MapEntry<String, Object?> e in sites.entries)
        if (e.value is Map) MapEntry<String, Map<String, Object?>>(e.key, (e.value! as Map).cast<String, Object?>()),
    ]..sort((MapEntry<String, Map<String, Object?>> a, MapEntry<String, Map<String, Object?>> b) {
        final int byDegraded = _int(b.value['degraded']).compareTo(_int(a.value['degraded']));
        return byDegraded != 0 ? byDegraded : a.key.compareTo(b.key);
      });
    _emit('call sites');
    for (final MapEntry<String, Map<String, Object?>> row in rows) {
      final Map<String, Object?> codes =
          row.value['codes'] is Map ? (row.value['codes']! as Map).cast<String, Object?>() : <String, Object?>{};
      final String codeText = codes.isEmpty
          ? ''
          : '  ${codes.entries.map((MapEntry<String, Object?> c) => '${c.key}×${c.value}').join(', ')}';
      _emit('  ${row.key.padRight(24)} ${row.value['degraded']}/${row.value['opens']} degraded$codeText');
    }
  }

  void _emitSpans(String label, Object? samples) {
    final List<Map<String, Object?>> rows = _maps(samples);
    if (rows.isEmpty) return;
    _emit('${label.padRight(18)} ${_summary(rows)}');
  }

  void _emitRestores(Object? samples) {
    final List<Map<String, Object?>> rows = _maps(samples);
    if (rows.isEmpty) return;
    for (final Map<String, Object?> row in rows) {
      _emit('restore on launch  "${row['name']}": ${row['tabs']} tab(s) in ${_ms(row['micros'])}');
    }
  }

  void _emitStore(Object? store) {
    if (store is! Map) return;
    final Map<String, Object?> s = store.cast<String, Object?>();
    final num ratio = s['coalescingRatio'] is num ? s['coalescingRatio']! as num : 0;
    _emit('shared store       ${s['writes']} writes, ${s['flushes']} flushes '
        '(${(ratio * 100).round()}% coalesced), ${s['sizeBytes']} bytes, ${s['spills']} spill(s)');
  }

  void _emitFindings(Object? findings) {
    final List<Map<String, Object?>> rows = _maps(findings);
    _emit('findings: ${rows.length}');
    for (final Map<String, Object?> f in rows) {
      _emit('  ${f['kind']}  ${f['message']}');
    }
  }

  static String _summary(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 'none';
    final List<int> micros = <int>[for (final Map<String, Object?> r in rows) _int(r['micros'])]..sort();
    final int median = micros[micros.length ~/ 2];
    return '${rows.length} sample(s), median ${_ms(median)}, max ${_ms(micros.last)}';
  }

  static String _ms(Object? micros) => '${(_int(micros) / 1000).toStringAsFixed(1)}ms';

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  static List<Map<String, Object?>> _maps(Object? value) => <Map<String, Object?>>[
        if (value is List)
          for (final Object? item in value)
            if (item is Map) item.cast<String, Object?>(),
      ];

  // ignore: avoid_print
  void _emit(String line) => print(line);
}
