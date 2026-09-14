/// Capturing a crash, keeping it, and sending it at the next launch.
library;

import 'dart:async';
import 'dart:math';

import 'crash_report.dart';
import 'crash_store.dart';
import 'release_health.dart';

/// Where recovered reports go: the deployment's backend, Sentry, Crashlytics,
/// or an application's own. The capture path is the same whichever it is.
abstract class DVCrashSink {
  Future<void> send(DVCrashReport report);
}

/// A sink in memory, for tests.
class DVMemoryCrashSink implements DVCrashSink {
  DVMemoryCrashSink({this.failing = false});

  /// When true every send throws, as an unreachable backend does.
  final bool failing;
  final List<DVCrashReport> received = <DVCrashReport>[];

  @override
  Future<void> send(DVCrashReport report) async {
    if (failing) throw StateError('crash sink unavailable');
    received.add(report);
  }
}

/// Which releases have their symbols in the symbol store.
abstract class DVCrashSymbols {
  bool has(String release);
}

class DVMemoryCrashSymbols implements DVCrashSymbols {
  DVMemoryCrashSymbols({Set<String> releases = const <String>{}})
      : releases = <String>{...releases};

  final Set<String> releases;

  @override
  bool has(String release) => releases.contains(release);
}

/// The crash reporter.
class DVCrashReporting {
  DVCrashReporting({
    required this.store,
    this.sink,
    required DVCrashContext Function() context,
    int breadcrumbs = 64,
    Set<String> sensitiveFields = const <String>{},
    this.nonFatalSampleRate = 1,
    double Function()? random,
    this.fullReportsPerRelease = 5,
    this.health,
    this.symbols,
    this.enabled = true,
    DateTime Function()? clock,
    Map<String, Object?> Function()? flags,
    void Function(String code, String message)? onDiagnostic,
  })  : _context = context,
        _random = random ?? Random().nextDouble,
        _clock = clock ?? DateTime.now,
        _flags = flags,
        _diagnose = onDiagnostic ?? dvLogCrashDiagnostic,
        breadcrumbs = DVCrashBreadcrumbs(
          capacity: breadcrumbs,
          sensitive: sensitiveFields,
          clock: clock,
        ) {
    if (!enabled) {
      _diagnose('DV-CRASH-009', 'crash reporting is disabled for this build');
    }
  }

  final DVCrashStore store;
  final DVCrashSink? sink;

  /// The share of non-fatal errors kept. Crashes are never sampled: the
  /// hundredth occurrence is the one that says it is not rare.
  final double nonFatalSampleRate;

  /// Full reports per device per release; past it crashes are counted, not
  /// written.
  final int fullReportsPerRelease;
  final DVReleaseHealth? health;
  final DVCrashSymbols? symbols;

  /// Whether reports are captured at all. Off is a declaration the build
  /// reports (`DV-CRASH-009`), never an accident.
  final bool enabled;

  final DVCrashBreadcrumbs breadcrumbs;

  final DVCrashContext Function() _context;
  final double Function() _random;
  final DateTime Function() _clock;
  final Map<String, Object?> Function()? _flags;
  final void Function(String code, String message) _diagnose;

  String? _sessionId;
  DateTime? _sessionStart;
  bool _nativeReported = false;
  final Set<String> _rateLimited = <String>{};

  /// Starts a session, which is what release health's denominator counts.
  void startSession(String sessionId) {
    _sessionId = sessionId;
    _sessionStart = _clock();
    final DVCrashContext context = _context();
    health?.sessionStarted(
      sessionId: sessionId,
      installId: context.installId,
      release: context.release,
      patch: context.patch,
      cohort: context.cohort,
    );
  }

  /// Installs what this build can capture.
  ///
  /// No native signal or exception handler exists in this build, so only
  /// Dart-level errors are captured, and it says so once
  /// (`DV-CRASH-006`) rather than letting a native crash go missing quietly.
  void install() {
    if (!enabled || _nativeReported) return;
    _nativeReported = true;
    _diagnose('DV-CRASH-006',
        'no native crash handler in this build; only Dart-level errors are '
        'captured');
  }

  /// Runs [body] with its uncaught errors recorded as crashes.
  R? runGuarded<R>(R Function() body) => runZonedGuarded<R>(
        body,
        (Object error, StackTrace stack) => record(error, stack, fatal: true),
      );

  /// Records [error], writing it before returning.
  ///
  /// Returns the report written, or null when nothing was written: disabled,
  /// a non-fatal error sampled out (`DV-CRASH-008`), or a device past this
  /// release's limit (`DV-CRASH-004`) — which still counts the crash against
  /// release health, because the limit stops the payload and not the
  /// arithmetic.
  DVCrashReport? record(Object error, StackTrace stack, {bool fatal = false}) =>
      _capture(
        error.runtimeType.toString(),
        '$error',
        stack,
        fatal ? DVCrashKind.fatal : DVCrashKind.nonFatal,
      );

  /// Records a hang: the platform thread did not answer for [blockedFor], and
  /// [stack] is where it was.
  DVCrashReport? recordHang(StackTrace stack, Duration blockedFor) {
    if (!enabled) return null;
    _diagnose('DV-CRASH-007',
        'the application did not respond for ${blockedFor.inMilliseconds}ms');
    return _capture(
        'ApplicationHang',
        'blocked for ${blockedFor.inMilliseconds}ms',
        stack,
        DVCrashKind.hang);
  }

  DVCrashReport? _capture(
    String errorType,
    String message,
    StackTrace stack,
    DVCrashKind kind,
  ) {
    if (!enabled) return null;
    if (kind == DVCrashKind.nonFatal &&
        nonFatalSampleRate < 1 &&
        _random() >= nonFatalSampleRate) {
      _diagnose('DV-CRASH-008',
          'a non-fatal $errorType was dropped by the sampling rate');
      return null;
    }

    final DVCrashContext context = _context();
    final String? session = _sessionId;
    if (session != null && kind != DVCrashKind.nonFatal) {
      health?.sessionCrashed(sessionId: session);
    }

    if (store.countCrash(context.release) > fullReportsPerRelease) {
      if (_rateLimited.add(context.release)) {
        _diagnose('DV-CRASH-004',
            'crashes on this device for ${context.release} are past '
            '$fullReportsPerRelease full reports; further ones are counted');
      }
      return null;
    }

    final DateTime now = _clock();
    final List<DVCrashFrame> frames = DVCrashFrame.parse(stack);
    final DVCrashReport report = DVCrashReport(
      id: dvCrashReportId(now),
      kind: kind,
      errorType: errorType,
      message: breadcrumbs.redactMap(<String, Object?>{'m': message})['m']!
          as String,
      frames: frames,
      fingerprint:
          DVCrashFingerprint.of(errorType: errorType, frames: frames),
      context: context,
      occurredAt: now,
      sessionLength:
          _sessionStart == null ? null : now.difference(_sessionStart!),
      flags: breadcrumbs.redactMap(_flags?.call() ?? const <String, Object?>{}),
      breadcrumbs: breadcrumbs.snapshot,
    );
    store.writeSync(report);
    return report;
  }

  /// Sends what earlier runs left, and returns how many were sent.
  ///
  /// A record cut short is dropped and named (`DV-CRASH-005`). A record whose
  /// sent note survived is removed without being sent again. A send that
  /// fails leaves the record for the next launch. With no sink, records stay
  /// where they are.
  Future<int> recoverAndSend() async {
    if (!enabled) return 0;
    int sent = 0;
    final Set<String> unsymbolicated = <String>{};
    for (final DVCrashStoreEntry entry in store.pending()) {
      if (entry.truncated) {
        _diagnose('DV-CRASH-005',
            'crash record ${entry.id} was cut short by the crash that wrote '
            'it and was dropped');
        store.remove(entry.id);
        continue;
      }
      if (store.isSent(entry.id)) {
        store.remove(entry.id);
        continue;
      }
      final DVCrashSink? out = sink;
      if (out == null) continue;

      DVCrashReport report = entry.report!;
      final DVCrashSymbols? symbolStore = symbols;
      if (symbolStore != null) {
        final bool has = symbolStore.has(report.context.release);
        report = report.copyWith(symbolicated: has);
        if (!has && unsymbolicated.add(report.context.release)) {
          _diagnose('DV-CRASH-003',
              'no symbols for release ${report.context.release}; its stacks '
              'are unsymbolicated');
        }
      }

      try {
        await out.send(report);
      } on Object {
        continue;
      }
      store.markSent(entry.id);
      store.remove(entry.id);
      sent++;
      _diagnose('DV-CRASH-001',
          'report ${entry.id} from the previous run was recovered and sent');
    }
    return sent;
  }
}

/// Notices when the platform thread stops answering.
///
/// The platform thread calls [beat]; something on another thread calls
/// [check] on a timer. One freeze is one hang however often [check] looks.
class DVHangWatchdog {
  DVHangWatchdog({
    required this.threshold,
    required DateTime Function() clock,
    required void Function(Duration blockedFor) onHang,
  })  : _clock = clock,
        _onHang = onHang;

  final Duration threshold;
  final DateTime Function() _clock;
  final void Function(Duration blockedFor) _onHang;

  DateTime? _lastBeat;
  bool _reported = false;

  void beat() {
    _lastBeat = _clock();
    _reported = false;
  }

  void check() {
    final DateTime? last = _lastBeat;
    if (last == null || _reported) return;
    final Duration blocked = _clock().difference(last);
    if (blocked < threshold) return;
    _reported = true;
    _onHang(blocked);
  }
}
