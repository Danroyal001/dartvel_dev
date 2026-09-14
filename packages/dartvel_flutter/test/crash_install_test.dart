// DV.Crashes: the crash reporter installed where Flutter reports errors.
//
// The runtime could record and send, and nothing called it: no hook in
// FlutterError.onError, none in PlatformDispatcher.onError, no isolate
// listener. Every test here is one of the ways an installation fails without
// saying so:
//
//  * the application's own FlutterError.onError replaced, so its logging
//    stops the day crash reporting is turned on;
//  * one error that reaches two hooks recorded twice, which doubles a crash
//    group and halves its crash-free rate;
//  * a report written after an await, lost when the process goes down;
//  * the handler throwing, or recursing through FlutterError.reportError;
//  * reports from the previous run left on disk because nothing sent them.
import 'dart:ui';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

DVCrashReporting reporter(DVCrashStore store, {DVCrashSink? sink}) =>
    DVCrashReporting(
      store: store,
      sink: sink,
      context: () => const DVCrashContext(release: '1.0.0', installId: 'i'),
      onDiagnostic: (String code, String message) {},
    );

/// Writes nothing, and reports an error through Flutter while failing — the
/// shape of a handler bug that recurses.
class _ReportingStore extends DVMemoryCrashStore {
  int writes = 0;

  @override
  void writeSync(DVCrashReport report) {
    writes++;
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('inside the handler')),
    );
    throw StateError('disk full');
  }
}

void main() {
  late List<FlutterErrorDetails> appSaw;
  late FlutterExceptionHandler? testHandler;
  late ErrorCallback? dispatcherBefore;
  late FlutterExceptionHandler appHandler;

  setUp(() {
    appSaw = <FlutterErrorDetails>[];
    testHandler = FlutterError.onError;
    dispatcherBefore = PlatformDispatcher.instance.onError;
    // What an application does in main() before the runtime starts.
    appHandler = appSaw.add;
    FlutterError.onError = appHandler;
  });

  tearDown(() {
    const DVCrashes().installation?.uninstall();
    FlutterError.onError = testHandler;
    PlatformDispatcher.instance.onError = dispatcherBefore;
  });

  FlutterErrorDetails details(Object error, {bool silent = false}) =>
      FlutterErrorDetails(
        exception: error,
        stack: StackTrace.current,
        silent: silent,
      );

  group('FlutterError.onError', () {
    test('the report is written before the handler returns', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      const DVCrashes().install(reporter(store));

      FlutterError.reportError(details(StateError('boom')));

      // No await between the report and this line.
      expect(store.raw, hasLength(1));
      expect(store.pending().single.report!.kind, DVCrashKind.fatal);
    });

    test("the application's own handler still runs, after the record", () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      int recordedWhenAppRan = -1;
      FlutterError.onError = (FlutterErrorDetails d) {
        recordedWhenAppRan = store.raw.length;
        appSaw.add(d);
      };
      const DVCrashes().install(reporter(store));

      final FlutterErrorDetails reported = details(StateError('boom'));
      FlutterError.reportError(reported);

      expect(appSaw, <FlutterErrorDetails>[reported]);
      expect(recordedWhenAppRan, 1);
    });

    test('a silent error is recorded as non-fatal', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      const DVCrashes().install(reporter(store));

      FlutterError.reportError(details(StateError('image'), silent: true));

      expect(store.pending().single.report!.kind, DVCrashKind.nonFatal);
    });
  });

  group('PlatformDispatcher.onError', () {
    test('an earlier handler is called and its answer returned', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final List<Object> earlier = <Object>[];
      PlatformDispatcher.instance.onError = (Object e, StackTrace s) {
        earlier.add(e);
        return true;
      };
      const DVCrashes().install(reporter(store));

      final StateError error = StateError('async');
      final bool handled =
          PlatformDispatcher.instance.onError!(error, StackTrace.current);

      expect(handled, isTrue);
      expect(earlier, <Object>[error]);
      expect(store.raw, hasLength(1));
    });

    test('with no earlier handler the error is left unhandled', () {
      // Answering true would swallow what the engine prints by default.
      PlatformDispatcher.instance.onError = null;
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      const DVCrashes().install(reporter(store));

      expect(
        PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.current),
        isFalse,
      );
      expect(store.raw, hasLength(1));
    });
  });

  group('one error, recorded once', () {
    test('the same error reaching two hooks is one report', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      const DVCrashes().install(reporter(store));
      final StateError error = StateError('twice');
      final StackTrace stack = StackTrace.current;

      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      PlatformDispatcher.instance.onError!(error, stack);

      expect(store.raw, hasLength(1));
    });

    test('the same hook seeing it again is a second occurrence', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      const DVCrashes().install(reporter(store));
      final FlutterErrorDetails reported = details(StateError('again'));

      FlutterError.reportError(reported);
      FlutterError.reportError(reported);

      expect(store.raw, hasLength(2));
    });

    test('an uncaught error arriving as text after the dispatcher is one '
        'report, and a second arrival is another', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashInstallation installation =
          const DVCrashes().install(reporter(store));
      final StateError error = StateError('isolate');
      final StackTrace stack = StackTrace.current;

      PlatformDispatcher.instance.onError!(error, stack);
      installation.receiveText('$error', '$stack', DVCrashHook.isolate);
      expect(store.raw, hasLength(1));

      installation.receiveText('$error', '$stack', DVCrashHook.isolate);
      expect(store.raw, hasLength(2));
    });
  });

  group('a failure inside the handler', () {
    test('neither escapes nor recurses, and the chain still runs', () {
      final _ReportingStore store = _ReportingStore();
      final DVCrashInstallation installation =
          const DVCrashes().install(reporter(store));

      expect(
        () => FlutterError.reportError(details(StateError('outer'))),
        returnsNormally,
      );
      expect(store.writes, 1);
      expect(installation.lastHandlerFailure, isA<StateError>());
      // The outer error and the one reported from inside the handler both
      // reach the application; neither is lost to the failure.
      expect(appSaw, hasLength(2));
    });
  });

  group('next launch', () {
    test('reports the previous run left are sent at install', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      reporter(store).record(StateError('last run'), StackTrace.current,
          fatal: true);
      final DVMemoryCrashSink sink = DVMemoryCrashSink();

      final DVCrashInstallation installation =
          const DVCrashes().install(reporter(store, sink: sink));

      expect(await installation.recovered, 1);
      expect(sink.received.single.message, contains('last run'));
      expect(store.raw, isEmpty);
    });

    test('a sink that fails does not fail the installation', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      reporter(store).record(StateError('last run'), StackTrace.current,
          fatal: true);

      final DVCrashInstallation installation = const DVCrashes()
          .install(reporter(store, sink: DVMemoryCrashSink(failing: true)));

      expect(await installation.recovered, 0);
      expect(store.raw, hasLength(1));
    });
  });

  group('installation', () {
    test('uninstall restores the handlers that were there', () {
      final ErrorCallback? before = PlatformDispatcher.instance.onError;
      const DVCrashes().install(reporter(DVMemoryCrashStore())).uninstall();

      expect(FlutterError.onError, same(appHandler));
      expect(PlatformDispatcher.instance.onError, same(before));
      expect(const DVCrashes().installation, isNull);
    });

    test('a handler the application set after install survives uninstall',
        () {
      final DVCrashInstallation installation =
          const DVCrashes().install(reporter(DVMemoryCrashStore()));
      void later(FlutterErrorDetails d) {}
      FlutterError.onError = later;

      installation.uninstall();

      expect(FlutterError.onError, same(later));
    });

    test('installing twice is refused rather than chaining twice', () {
      const DVCrashes().install(reporter(DVMemoryCrashStore()));

      expect(
        () => const DVCrashes().install(reporter(DVMemoryCrashStore())),
        throwsStateError,
      );
    });

    test('DV.Crashes is the facade', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      DV.Crashes.install(reporter(store));

      expect(DV.Crashes.installation, isNotNull);
    });
  });

  group('recording by hand', () {
    test('record writes a non-fatal report', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      const DVCrashes().install(reporter(store));

      final DVCrashReport? report =
          const DVCrashes().record(StateError('caught'), StackTrace.current);

      expect(report!.kind, DVCrashKind.nonFatal);
      expect(store.raw, hasLength(1));
    });

    test('record before install returns null and throws nothing', () {
      expect(const DVCrashes().record(StateError('early')), isNull);
    });
  });
}
