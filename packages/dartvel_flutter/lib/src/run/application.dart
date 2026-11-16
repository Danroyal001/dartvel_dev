import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVAppEntry, DVBoot, DVEmbeddedEntry, DVEntry, DVEntryKindOf;
import 'package:dartvel_core/framework.dart'
    show DVBootStep, dvResetBootForTest, dvRunBoot;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dartvel_flutter.dart';
import '../routing/first_frame_gate.dart' show dvWatchWebFirstFrame;

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

List<String> _launchArguments = const <String>[];

/// The process's arguments, kept by the generated entry
/// (`lib/dartvel_client/main.g.dart`) for `DV.run()`, which takes nothing:
/// Dart hands them only to a `main(List<String>)`, and the application's own
/// main is `void main() => DV.run();`.
List<String> get dvLaunchArguments => _launchArguments;

/// Called by the generated entry before the application's main.
void dvSetLaunchArguments(List<String> arguments) =>
    _launchArguments = List<String>.unmodifiable(arguments);

/// Framework entry used by the generated application facade.
Future<void> dvRunApplication(
  List<String> args, {
  required Widget Function() root,
  List<DVBootStep> boot = const [],
  FutureOr<void> Function(List<String>)? launch,
  DVEntry entry = const DVEntry.app(),
  DVStudioSplash? splash,
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
        // A host application owns the process an embedded entry runs in:
        // no single-instance lock, no argv to open, no window of its own.
        if (launch != null && entry is! DVEmbeddedEntry) await launch(args);
        DV.lifecycle.setApp(.booting);
        final List<DVBootStep> steps = _withSplash(boot, entry: entry, splash: splash);
        // The same runner a server, a worker or a command boots through;
        // only the entry differs.
        await dvRunBoot(steps, DVBoot(entry: entry, args: _args));
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
        dvWatchWebFirstFrame();
        // Drawn at the scale that suits the screen: unchanged on phones,
        // tablets and desktops, larger on a television, smaller on a watch.
        // Ready after the first frame. Registered before runApp: the first
        // frame can be drawn while runApp runs, and a callback added after it
        // then waited for a second frame that a still screen never draws, so
        // the app stayed `booting` for good. scheduleFrame makes sure a frame
        // comes either way.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          DV.lifecycle.setApp(.ready);
        });
        runApp(DVDisplayScale(child: root()));
        WidgetsBinding.instance.scheduleFrame();
        completed.complete();
      } catch (error, stack) {
        DV.lifecycle.setApp(.failed);
        DV.log.error(
          'Application boot failed.',
          error: error,
          stackTrace: stack,
        );
        dvWatchWebFirstFrame();
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

/// Draws [splash] with its loading bar while the boot steps run, and
/// returns the steps, each filling the bar as it finishes.
///
/// On a device the launch screen the platform draws stays until Flutter's
/// first frame and nothing can move on it, and the boot steps run before
/// that frame -- so a slow boot was a still picture. This frame looks the
/// same as the launch screen, adds the bar, and the application replaces it.
/// The bar is the steps that run for this entry plus one share for the
/// application's own first frame, so it never sits full while the app is
/// still being built.
///
/// Not on the web, whose page already draws the same splash and bar in HTML
/// before any Dart runs; not for an embedded entry, inside a host that shows
/// its own; and not when the project asked for no bar, where the launch
/// screen simply stays up as it always has.
List<DVBootStep> _withSplash(
  List<DVBootStep> boot, {
  required DVEntry entry,
  required DVStudioSplash? splash,
}) {
  if (splash == null ||
      splash.progressColor == null ||
      kIsWeb ||
      entry is! DVAppEntry) {
    return boot;
  }
  final List<DVBootStep> running = <DVBootStep>[
    for (final DVBootStep step in boot)
      if (step.entries.isEmpty || step.entries.contains(entry.kind)) step,
  ];
  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  int finished = 0;
  runApp(Directionality(
    textDirection: .ltr,
    child: DVStudioSplashView(splash, progress: progress),
  ));
  WidgetsBinding.instance.scheduleFrame();
  return <DVBootStep>[
    for (final DVBootStep step in running)
      DVBootStep(
        entries: step.entries,
        run: (DVBoot context) async {
          await step.run(context);
          finished += 1;
          progress.value = finished / (running.length + 1);
        },
      ),
  ];
}
