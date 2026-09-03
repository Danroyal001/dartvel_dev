import 'dart:collection';

/// What the windowing layer measures, and what it finds in the measurements.
///
/// The specification's performance contract for Multi-Window names five
/// measurements -- `open()` to `ready` (real and virtual), tear-out handover,
/// shared-store write rate and coalescing ratio, store size and spill count,
/// and restore-on-launch duration -- and four diagnostics. This is where they
/// live. The manager, the shared store and the tab workspace record into it;
/// the running application publishes it beside its live window list, and
/// `dartvel analyze performance` reads it from there.
///
/// Time comes from [nowMicros] rather than a stopwatch so a test can hand in
/// a clock and know the duration between two reads, instead of asserting on
/// whatever the runner's scheduler happened to allow.
class DVWindowPerformance {
  DVWindowPerformance({
    int Function()? nowMicros,
    this.frameBudget = const Duration(milliseconds: 16),
    this.startupBudget = const Duration(milliseconds: 500),
    this.minimumSamples = 3,
  }) : _now = nowMicros ?? _stopwatchMicros;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int _stopwatchMicros() => _stopwatch.elapsedMicroseconds;

  /// The recorder everything reports into. [DVWindowManager.reset] installs a
  /// fresh one so one test's samples are not the next test's findings.
  static DVWindowPerformance current = DVWindowPerformance();

  final int Function() _now;

  /// One frame at 60Hz: what a close of owned windows, or a burst of writes
  /// to one key, is measured against.
  final Duration frameBudget;

  /// What a workspace restore on launch is measured against.
  final Duration startupBudget;

  /// How many opens a call site needs before "always degrades" is a finding
  /// rather than a coincidence.
  final int minimumSamples;

  /// A point in time, for callers that measure a span.
  int mark() => _now();

  Duration _since(int mark) => Duration(microseconds: _now() - mark);

  final List<DVWindowOpenSample> _opens = <DVWindowOpenSample>[];
  final List<DVWindowTearOutSample> _tearOuts = <DVWindowTearOutSample>[];
  final List<DVWorkspaceRestoreSample> _restores = <DVWorkspaceRestoreSample>[];
  final List<DVOwnedCloseSample> _ownedCloses = <DVOwnedCloseSample>[];
  final Map<String, DVRouteDegradations> _byRoute = <String, DVRouteDegradations>{};

  int _storeWrites = 0;
  int _storeFlushes = 0;
  int _spills = 0;
  final Map<String, int> _sizes = <String, int>{};
  final Map<String, int> _lastWrite = <String, int>{};
  final Map<String, int> _burst = <String, int>{};

  /// Every `open()` that made a window, real or virtual, in order.
  List<DVWindowOpenSample> get opens => UnmodifiableListView(_opens);

  /// Every tear-out, from the gesture to the new window being ready.
  List<DVWindowTearOutSample> get tearOuts => UnmodifiableListView(_tearOuts);

  /// Every workspace restore.
  List<DVWorkspaceRestoreSample> get restores => UnmodifiableListView(_restores);

  /// Every close of a window that owned others.
  List<DVOwnedCloseSample> get ownedCloses => UnmodifiableListView(_ownedCloses);

  /// Opens and degradations per call site. The call site is the route: that
  /// is what a window is identified by, and what a developer can find.
  Map<String, DVRouteDegradations> get degradationsByRoute =>
      UnmodifiableMapView(_byRoute);

  /// Calls to `set` on the shared store.
  int get storeWrites => _storeWrites;

  /// Writes that reached the backend after coalescing.
  int get storeFlushes => _storeFlushes;

  /// The share of writes coalescing absorbed: 0 when every write was flushed,
  /// approaching 1 when nearly all of them collapsed into one.
  double get coalescingRatio =>
      _storeWrites == 0 ? 0 : 1 - _storeFlushes / _storeWrites;

  /// Values that left the preference store for file storage.
  int get spillCount => _spills;

  /// Encoded bytes currently stored, across every key, spilled or not.
  int get storeSizeBytes => _sizes.values.fold(0, (int a, int b) => a + b);

  /// Per key, how many writes landed within [frameBudget] of the previous
  /// write to the same key -- writes coalescing has to absorb.
  Map<String, int> get burstWrites => UnmodifiableMapView(_burst);

  // -- recording -----------------------------------------------------------

  void recordOpen({
    required String route,
    required bool virtual,
    required Duration elapsed,
    String? code,
  }) {
    _opens.add(DVWindowOpenSample(route: route, virtual: virtual, elapsed: elapsed, code: code));
    final DVRouteDegradations site = _byRoute.putIfAbsent(route, () => DVRouteDegradations._());
    site._opens += 1;
    if (code != null) {
      site._degraded += 1;
      site._codes[code] = (site._codes[code] ?? 0) + 1;
    }
  }

  void recordOpenFrom(int mark, {required String route, required bool virtual, String? code}) =>
      recordOpen(route: route, virtual: virtual, elapsed: _since(mark), code: code);

  void recordTearOutFrom(int mark, {required String route}) =>
      _tearOuts.add(DVWindowTearOutSample(route: route, elapsed: _since(mark)));

  void recordRestoreFrom(int mark, {required String name, required int tabs}) =>
      _restores.add(DVWorkspaceRestoreSample(name: name, tabs: tabs, elapsed: _since(mark)));

  void recordOwnedCloseFrom(int mark, {required String owner, required int owned}) =>
      _ownedCloses.add(DVOwnedCloseSample(owner: owner, owned: owned, elapsed: _since(mark)));

  void recordStoreWrite(String key) {
    _storeWrites += 1;
    final int now = _now();
    final int? last = _lastWrite[key];
    if (last != null && now - last < frameBudget.inMicroseconds) {
      _burst[key] = (_burst[key] ?? 0) + 1;
    }
    _lastWrite[key] = now;
  }

  /// [bytes] is null when the key was removed.
  void recordStoreFlush(String key, {required int? bytes, bool spilled = false}) {
    _storeFlushes += 1;
    if (bytes == null) {
      _sizes.remove(key);
    } else {
      _sizes[key] = bytes;
    }
    if (spilled) _spills += 1;
  }

  // -- findings ------------------------------------------------------------

  /// What the measurements say is wrong. Each subject appears once: a call
  /// site that always degrades is one finding, not a thousand log lines.
  List<DVWindowPerformanceFinding> get findings {
    final out = <DVWindowPerformanceFinding>[];
    _byRoute.forEach((String route, DVRouteDegradations site) {
      if (site.opens >= minimumSamples && site.degraded == site.opens) {
        final String codes = site.codes.keys.join(', ');
        out.add(DVWindowPerformanceFinding(
          kind: DVWindowPerformanceIssue.alwaysDegrades,
          subject: route,
          count: site.opens,
          message: 'every open of $route degraded ($codes); the call site never gets a window',
        ));
      }
    });
    _burst.forEach((String key, int count) {
      out.add(DVWindowPerformanceFinding(
        kind: DVWindowPerformanceIssue.writtenWithinFrame,
        subject: key,
        count: count,
        message: 'shared key "$key" was written $count time(s) within '
            '${frameBudget.inMilliseconds}ms of its previous write; coalescing is absorbing a per-frame signal',
      ));
    });
    for (final DVWorkspaceRestoreSample restore in _restores) {
      if (restore.elapsed > startupBudget) {
        out.add(DVWindowPerformanceFinding(
          kind: DVWindowPerformanceIssue.restoreOverBudget,
          subject: restore.name,
          count: restore.tabs,
          message: 'restoring workspace "${restore.name}" (${restore.tabs} tab(s)) took '
              '${restore.elapsed.inMilliseconds}ms, over the ${startupBudget.inMilliseconds}ms startup budget',
        ));
      }
    }
    for (final DVOwnedCloseSample close in _ownedCloses) {
      if (close.elapsed > frameBudget) {
        out.add(DVWindowPerformanceFinding(
          kind: DVWindowPerformanceIssue.ownedOutliveFrame,
          subject: close.owner,
          count: close.owned,
          message: '${close.owned} window(s) owned by ${close.owner} outlived their owner by '
              '${close.elapsed.inMilliseconds}ms, over the ${frameBudget.inMilliseconds}ms frame budget',
        ));
      }
    }
    return out;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'opens': <Map<String, Object?>>[for (final s in _opens) s.toJson()],
        'tearOuts': <Map<String, Object?>>[for (final s in _tearOuts) s.toJson()],
        'restores': <Map<String, Object?>>[for (final s in _restores) s.toJson()],
        'ownedCloses': <Map<String, Object?>>[for (final s in _ownedCloses) s.toJson()],
        'degradations': <String, Object?>{
          for (final MapEntry<String, DVRouteDegradations> e in _byRoute.entries)
            e.key: e.value.toJson(),
        },
        'store': <String, Object?>{
          'writes': _storeWrites,
          'flushes': _storeFlushes,
          'coalescingRatio': coalescingRatio,
          'sizeBytes': storeSizeBytes,
          'spills': _spills,
          'burstWrites': Map<String, int>.of(_burst),
        },
        'findings': <Map<String, Object?>>[for (final f in findings) f.toJson()],
      };
}

/// Opens and degradations at one call site.
class DVRouteDegradations {
  DVRouteDegradations._();
  int _opens = 0;
  int _degraded = 0;
  final Map<String, int> _codes = <String, int>{};

  int get opens => _opens;
  int get degraded => _degraded;
  Map<String, int> get codes => UnmodifiableMapView(_codes);

  Map<String, Object?> toJson() => <String, Object?>{
        'opens': _opens,
        'degraded': _degraded,
        'codes': Map<String, int>.of(_codes),
      };
}

class DVWindowOpenSample {
  const DVWindowOpenSample({
    required this.route,
    required this.virtual,
    required this.elapsed,
    this.code,
  });
  final String route;
  final bool virtual;
  final Duration elapsed;

  /// The DV-WINDOW code the open degraded with, or null for a real window.
  final String? code;

  Map<String, Object?> toJson() => <String, Object?>{
        'route': route,
        'virtual': virtual,
        'micros': elapsed.inMicroseconds,
        if (code != null) 'code': code,
      };
}

class DVWindowTearOutSample {
  const DVWindowTearOutSample({required this.route, required this.elapsed});
  final String route;
  final Duration elapsed;
  Map<String, Object?> toJson() =>
      <String, Object?>{'route': route, 'micros': elapsed.inMicroseconds};
}

class DVWorkspaceRestoreSample {
  const DVWorkspaceRestoreSample({required this.name, required this.tabs, required this.elapsed});
  final String name;
  final int tabs;
  final Duration elapsed;
  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'tabs': tabs, 'micros': elapsed.inMicroseconds};
}

class DVOwnedCloseSample {
  const DVOwnedCloseSample({required this.owner, required this.owned, required this.elapsed});
  final String owner;
  final int owned;
  final Duration elapsed;
  Map<String, Object?> toJson() =>
      <String, Object?>{'owner': owner, 'owned': owned, 'micros': elapsed.inMicroseconds};
}

/// The four diagnostics the specification's performance contract names.
enum DVWindowPerformanceIssue {
  alwaysDegrades,
  writtenWithinFrame,
  restoreOverBudget,
  ownedOutliveFrame,
}

class DVWindowPerformanceFinding {
  const DVWindowPerformanceFinding({
    required this.kind,
    required this.subject,
    required this.count,
    required this.message,
  });
  final DVWindowPerformanceIssue kind;

  /// The route, key or workspace the finding is about.
  final String subject;
  final int count;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'subject': subject,
        'count': count,
        'message': message,
      };
}
