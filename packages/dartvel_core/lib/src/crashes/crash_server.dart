/// Crash reporting in a server process: the generated backend's unhandled
/// errors, recorded through the same runtime with the role of the process
/// that had them.
library;

import 'dart:async';

import '../process/process_configuration.dart';
import '../scheduling/scheduler.dart';
import 'crash_config.dart';
import 'crash_identity.dart';
import 'crash_ingest.dart';
import 'crash_report.dart';
import 'crash_reporting.dart';
import 'crash_store.dart';

/// Where a server process keeps crash records for [appId].
///
/// `DARTVEL_CRASH_DIR` when the deployment mounts one; otherwise beside the
/// application, in `.dartvel/crashes` under [currentDirectory], which survives
/// the restart a crash causes. A process whose working directory is the root
/// -- a container started with no WORKDIR -- keeps them under
/// [tempDirectory] rather than writing to `/`.
String dvServerCrashDirectoryFor({
  required String appId,
  required Map<String, String> environment,
  required String currentDirectory,
  required String tempDirectory,
}) {
  final String declared = (environment['DARTVEL_CRASH_DIR'] ?? '').trim();
  if (declared.isNotEmpty) return declared;
  String cwd = currentDirectory.trim();
  while (cwd.length > 1 && (cwd.endsWith('/') || cwd.endsWith(r'\'))) {
    cwd = cwd.substring(0, cwd.length - 1);
  }
  final bool root = cwd.isEmpty ||
      cwd == '/' ||
      cwd == r'\' ||
      RegExp(r'^[A-Za-z]:\\?$').hasMatch(cwd);
  return root ? '$tempDirectory/dartvel-crashes/$appId' : '$cwd/.dartvel/crashes';
}

/// A sink that keeps a report in a [DVCrashReportRepository] directly: how a
/// backend whose clients send to it keeps its own reports, without a request
/// to itself.
class DVRepositoryCrashSink implements DVCrashSink {
  const DVRepositoryCrashSink(this.repository);

  final DVCrashReportRepository repository;

  @override
  Future<void> send(DVCrashReport report) async {
    // A report already kept -- the process died between sending and noting
    // the send -- is delivered.
    await repository.put(report, receivedAt: DateTime.now().toUtc());
  }
}

/// The crash reporter in a server process.
///
/// Installed by the generated backend with the process's role, and fed its
/// unhandled errors: a request that failed with a 500, a schedule that threw,
/// an error nothing in the process caught. Each is recorded as unhandled,
/// which is never sampled, and written before [record] returns.
///
/// A server does not restart to send, so a report is sent soon after it is
/// written rather than at the next launch; what an earlier process left is
/// sent at install.
abstract final class DVServerCrashes {
  static DVCrashReporting? _reporter;
  static Object? _lastFailure;
  static bool _recording = false;
  static bool _queued = false;
  static Future<void> _sending = Future<void>.value();

  /// The reporter installed in this process, or null.
  static DVCrashReporting? get reporter => _reporter;

  /// The last thing that went wrong while recording or sending, kept rather
  /// than thrown: this runs inside a request's error path.
  static Object? get lastFailure => _lastFailure;

  /// Completes when the sends queued so far are done.
  static Future<void> get idle => _sending;

  /// Installs the reporter for [appId] at [release] in a [role] process.
  ///
  /// Returns null, having said `DV-CRASH-009`, when [config] disables this
  /// build. [store] and [installId] come from the caller, because working
  /// them out needs a file system this library does not assume.
  static DVCrashReporting? install({
    required String appId,
    required String release,
    required DVProcessRole role,
    required DVCrashStore store,
    required String installId,
    DVCrashConfig config = const DVCrashConfig(),
    DVCrashSink? sink,
    String? platform,
    void Function(String code, String message)? onDiagnostic,
  }) {
    const bool product = bool.fromEnvironment('dart.vm.product');
    const bool profile = bool.fromEnvironment('dart.vm.profile');
    final DVCrashBuildMode mode = product
        ? DVCrashBuildMode.release
        : profile
            ? DVCrashBuildMode.profile
            : DVCrashBuildMode.debug;
    if (!config.enabledIn(mode)) {
      _reporter = null;
      (onDiagnostic ?? dvLogCrashDiagnostic)(
        'DV-CRASH-009',
        'crash reporting is disabled for ${mode.name} builds of $appId, as '
            'dartvel.crashes declares',
      );
      return null;
    }
    final DVCrashReporting reporter = DVCrashReporting(
      store: store,
      sink: sink,
      context: () => DVCrashContext(
        release: release,
        installId: installId,
        platform: platform,
        deviceClass: 'server',
        role: role.name,
      ),
      breadcrumbs: config.breadcrumbs,
      nonFatalSampleRate: config.nonFatalSampleRate,
      fullReportsPerRelease: config.fullReportsPerRelease,
      flags: dvCrashFlagsSnapshot,
      onDiagnostic: onDiagnostic,
    )..install();
    _reporter = reporter;
    _queueSend();
    return reporter;
  }

  /// Records [error] as unhandled. Never throws, and never re-enters itself.
  static DVCrashReport? record(Object error, StackTrace stack) {
    final DVCrashReporting? reporter = _reporter;
    if (reporter == null || _recording) return null;
    _recording = true;
    try {
      final DVCrashReport? report = reporter.record(error, stack, fatal: true);
      _queueSend();
      return report;
    } on Object catch (failure) {
      _lastFailure = failure;
      return null;
    } finally {
      _recording = false;
    }
  }

  /// Records a schedule that threw: what [DVScheduler.onFailure] is given.
  static void recordScheduled(DVScheduledFailure failure) =>
      record(failure.error, failure.stackTrace ?? StackTrace.empty);

  static void _queueSend() {
    final DVCrashReporting? reporter = _reporter;
    if (reporter == null || reporter.sink == null || _queued) return;
    _queued = true;
    _sending = _sending.then((_) async {
      _queued = false;
      try {
        await reporter.recoverAndSend();
      } on Object catch (failure) {
        _lastFailure = failure;
      }
    });
  }

  /// Forgets the installation, for tests.
  static void resetForTest() {
    _reporter = null;
    _lastFailure = null;
    _recording = false;
    _queued = false;
    _sending = Future<void>.value();
  }
}
