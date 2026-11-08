import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVBoot, DVEntry;
import 'package:dartvel_core/framework.dart'
    show DVBootStep, DVBootTracker, dvResetBoot, dvResetBootForTest, dvRunBoot;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dartvel_flutter.dart';

/// The generated router and Flutter configuration an existing host keeps.
class const DVAppParts({
  required final GoRouter router,
  final Locale? locale,
  final ThemeMode themeMode = .system,
  final Iterable<LocalizationsDelegate<dynamic>> localizationsDelegates =
      const [],
  final TransitionBuilder? builder,
});

bool _running = false;
bool _flutterErrorsLogged = false;
Future<void> Function()? _retry;
List<String> _args = const [];
List<String> get dvApplicationArguments => _args;

/// Framework entry used by the generated application facade.
Future<void> dvRunApplication(
  List<String> args, {
  required Widget Function() root,
  List<DVBootStep> boot = const [],
  FutureOr<void> Function(List<String>)? launch,
  Duration? bootBudget,
  DateTime Function()? clock,
}) async {
  if (_running) {
    DV.log.warn(
      'DV.run was already called in this isolate.',
      code: 'DV-RUN-002',
    );
    return;
  }
  _running = true;
  _args = List.unmodifiable(args);
  _retry = () {
    _running = false;
    dvResetBoot();
    return dvRunApplication(
      args,
      root: root,
      boot: boot,
      launch: launch,
      bootBudget: bootBudget,
      clock: clock,
    );
  };
  final completed = Completer<void>();
  // Where boot is, so a failure names it (DV-RUN-004). Numbers and names
  // follow the boot sequence table in NEW_SPEC.md, Application Entry; a
  // server, a worker and a cron process boot through the same tracker.
  final tracker = DVBootTracker(const DVEntry.app(), clock: clock);
  runZonedGuarded(
    () async {
      try {
        tracker.enter(1, 'initializing');
        WidgetsFlutterBinding.ensureInitialized();
        tracker.enter(2, 'surface selection');
        if (launch != null) await launch(args);
        tracker.enter(4, 'boot functions');
        // The same runner a server, a worker or a command boots through;
        // only the entry differs.
        await dvRunBoot(
          boot,
          DVBoot(entry: const DVEntry.app(), args: _args),
          onStep: tracker.step,
        );
        tracker.enter(5, 'surface');
        // Once per process: a retried boot must not log each error twice.
        if (!_flutterErrorsLogged) {
          _flutterErrorsLogged = true;
          final previousFlutterError = FlutterError.onError;
          FlutterError.onError = (details) {
            DV.log.error(
              'Flutter error.',
              error: details.exception,
              stackTrace: details.stack,
            );
            previousFlutterError?.call(details);
          };
        }
        dvStartAppLifecycleBridge();
        runApp(root());
        // dartvel.run.bootBudget covers phases 1-5: the root is up (DV-RUN-003).
        if (bootBudget != null) tracker.checkBudget(bootBudget);
        // Ready once a frame with the root in it has been drawn. A post-frame
        // callback alone waits for a frame something else schedules: where
        // runApp drew its first frame already, as a test binding does, or an
        // app shows a still page, nothing does, and the app stayed booting.
        WidgetsBinding.instance
          ..addPostFrameCallback((_) {
            tracker.ready();
          })
          ..ensureVisualUpdate();
        completed.complete();
      } catch (error, stack) {
        tracker.fail(error, stack);
        runApp(
          MaterialApp(
            theme: dartvelDefaultTheme(.light),
            darkTheme: dartvelDefaultTheme(.dark),
            home: DVBootFailurePage(
              // A second failure is logged and shown like the first.
              onRetry: () => unawaited(
                dvRetryApplication().then((_) {}, onError: (Object _) {}),
              ),
            ),
          ),
        );
        completed.completeError(error, stack);
      }
    },
    (error, stack) {
      DV.log.error(
        'Uncaught application error.',
        error: error,
        stackTrace: stack,
      );
      if (!completed.isCompleted) completed.completeError(error, stack);
    },
  );
  await completed.future;
}

/// Runs a failed boot again from the start, with the arguments, root and boot
/// functions the first run was given: what the boot-failure page's retry
/// does. Completes as [dvRunApplication] does; does nothing unless the last
/// boot failed.
Future<void> dvRetryApplication() async {
  final retry = _retry;
  if (retry == null || DV.lifecycle.app.value != DVAppLifecycle.failed) return;
  await retry();
}

/// Resets only the entry guard for isolated framework tests.
void dvResetApplicationEntryForTest() {
  _running = false;
  _flutterErrorsLogged = false;
  _retry = null;
  _args = const [];
  dvResetBootForTest();
}
