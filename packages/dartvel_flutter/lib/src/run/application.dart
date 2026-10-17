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
  runZonedGuarded(
    () async {
      try {
        WidgetsFlutterBinding.ensureInitialized();
        DV.lifecycle.setApp(.initializing);
        if (launch != null) await launch(args);
        DV.lifecycle.setApp(.booting);
        // The same runner a server, a worker or a command boots through;
        // only the entry differs.
        await dvRunBoot(boot, DVBoot(entry: const DVEntry.app(), args: _args));
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          DV.lifecycle.setApp(.ready);
        });
        completed.complete();
      } catch (error, stack) {
        DV.lifecycle.setApp(.failed);
        DV.log.error(
          'Application boot failed.',
          error: error,
          stackTrace: stack,
        );
        runApp(
          MaterialApp(
            theme: dartvelDefaultTheme(.light),
            darkTheme: dartvelDefaultTheme(.dark),
            home: DVBox(DVText('Unable to start the application.')),
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
