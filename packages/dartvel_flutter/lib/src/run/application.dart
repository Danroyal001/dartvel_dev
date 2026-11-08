import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVBoot, DVEntry;
import 'package:dartvel_core/framework.dart'
    show DVBootStep, dvResetBootForTest, dvRunBoot;
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
        final previousFlutterError = FlutterError.onError;
        FlutterError.onError = (details) {
          DV.log.error(
            'Flutter error.',
            error: details.exception,
            stackTrace: details.stack,
          );
          previousFlutterError?.call(details);
        };
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
            home: DVBox(DVText(DV.I18n.t(DVFrameworkStrings.startFailed))),
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

/// Resets only the entry guard for isolated framework tests.
void dvResetApplicationEntryForTest() {
  _running = false;
  _args = const [];
  dvResetBootForTest();
}
