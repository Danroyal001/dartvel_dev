import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVBoot, DVEntry;
import 'package:dartvel_core/framework.dart'
    show DVBootStep, dvResetBoot, dvResetBootForTest, dvRunBoot;
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
    return dvRunApplication(args, root: root, boot: boot, launch: launch);
  };
  final completed = Completer<void>();
  // Where boot is, so a failure names it (DV-RUN-004). Numbers and names
  // follow the boot sequence table in NEW_SPEC.md, Application Entry.
  var phase = (number: 1, name: 'initializing');
  int? bootStep;
  runZonedGuarded(
    () async {
      try {
        WidgetsFlutterBinding.ensureInitialized();
        DV.lifecycle.setApp(.initializing);
        phase = (number: 2, name: 'surface selection');
        if (launch != null) await launch(args);
        DV.lifecycle.setApp(.booting);
        phase = (number: 4, name: 'boot functions');
        // The same runner a server, a worker or a command boots through;
        // only the entry differs.
        await dvRunBoot(
          boot,
          DVBoot(entry: const DVEntry.app(), args: _args),
          onStep: (index) => bootStep = index,
        );
        bootStep = null;
        phase = (number: 5, name: 'surface');
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
        // Ready once a frame with the root in it has been drawn. A post-frame
        // callback alone waits for a frame something else schedules: where
        // runApp drew its first frame already, as a test binding does, or an
        // app shows a still page, nothing does, and the app stayed booting.
        WidgetsBinding.instance
          ..addPostFrameCallback((_) {
            DV.lifecycle.setApp(.ready);
          })
          ..ensureVisualUpdate();
        completed.complete();
      } catch (error, stack) {
        DV.lifecycle.setApp(.failed);
        DV.log.error(
          'Application boot failed in phase ${phase.number}, ${phase.name}'
          '${bootStep == null ? '' : ' (@DVBoot function ${bootStep! + 1})'}.',
          code: 'DV-RUN-004',
          context: {
            'phase': phase.number,
            'phaseName': phase.name,
            'bootStep': bootStep,
          },
          error: error,
          stackTrace: stack,
        );
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
