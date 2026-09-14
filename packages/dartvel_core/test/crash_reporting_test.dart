// Crash reporting and release health: the failures that look like success.
//
// A crash reporter is judged by the crashes it never mentions. One that waits
// for a round trip before writing loses exactly the reports that matter, the
// ones from a process already going down. One that deletes a report only after
// sending it — and sends again when the process dies in between — makes one
// crash look like two. One that groups by message puts every crash whose
// message is "null" into one bucket, and splits one bug into a thousand
// because its message carries an id. And a release-health gate whose
// denominator counts devices that were assigned to a rollout but never
// started a session reports a healthy release while a tenth of the fleet
// crashes on launch.
//
// Every test below is about one of those.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVCrashContext context({
  String release = '1.4.0',
  String installId = 'install-1',
  String? cohort,
}) =>
    DVCrashContext(
      release: release,
      patch: 'p3',
      protocolVersion: '7',
      platform: 'android',
      deviceClass: 'phone',
      locale: 'en-GB',
      installId: installId,
      cohort: cohort,
    );

StackTrace stack(List<String> frames) =>
    StackTrace.fromString(<String>[
      for (int i = 0; i < frames.length; i++) '#$i      ${frames[i]}',
    ].join('\n'));

final StackTrace checkoutStack = stack(<String>[
  'CheckoutController.pay (package:shop/checkout/controller.dart:88:7)',
  'PayButton.onPressed (package:shop/checkout/pay_button.dart:31:12)',
  'GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:315:24)',
  '_rootRun (dart:async/zone.dart:1399:13)',
]);

final StackTrace profileStack = stack(<String>[
  'ProfilePage.build (package:shop/profile/page.dart:40:3)',
  'StatelessElement.build (package:flutter/src/widgets/framework.dart:5550:49)',
  '_rootRun (dart:async/zone.dart:1399:13)',
]);

class _Diagnostics {
  final List<String> codes = <String>[];
  void call(String code, String message) => codes.add(code);
  int count(String code) => codes.where((String c) => c == code).length;
}

/// A store whose next remove throws, standing in for a process that dies
/// after a report was sent and before its record was deleted.
class _DiesBeforeRemove extends DVMemoryCrashStore {
  bool dieOnRemove = true;

  @override
  void remove(String id) {
    if (dieOnRemove) {
      dieOnRemove = false;
      throw StateError('process died');
    }
    super.remove(id);
  }
}

void main() {
  late _Diagnostics diagnostics;

  setUp(() => diagnostics = _Diagnostics());

  DVCrashReporting reporter({
    required DVCrashStore store,
    DVCrashSink? sink,
    DVCrashContext Function()? contextOf,
    Set<String> sensitiveFields = const <String>{},
    double nonFatalSampleRate = 1,
    double Function()? random,
    int fullReportsPerRelease = 5,
    DVReleaseHealth? health,
    DVCrashSymbols? symbols,
    bool enabled = true,
  }) =>
      DVCrashReporting(
        store: store,
        sink: sink,
        context: contextOf ?? context,
        sensitiveFields: sensitiveFields,
        nonFatalSampleRate: nonFatalSampleRate,
        random: random,
        fullReportsPerRelease: fullReportsPerRelease,
        health: health,
        symbols: symbols,
        enabled: enabled,
        onDiagnostic: diagnostics.call,
      );

  group('a crash is on disk before the handler returns', () {
    test('record writes synchronously, with nothing awaited', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashReporting crashes = reporter(store: store);

      // No await anywhere between the crash and the check: a handler running
      // in a process that is going down gets no later turn of the event loop.
      crashes.record(StateError('boom'), checkoutStack, fatal: true);

      final List<DVCrashStoreEntry> pending = store.pending();
      expect(pending, hasLength(1));
      expect(pending.single.report!.errorType, 'StateError');
      expect(pending.single.report!.kind, DVCrashKind.fatal);
    });

    test('a file store written by one run is read by the next', () {
      final Directory dir =
          Directory.systemTemp.createTempSync('dv_crash_store_');
      addTearDown(() => dir.deleteSync(recursive: true));

      reporter(store: DVFileCrashStore(dir.path))
          .record(StateError('boom'), checkoutStack, fatal: true);

      // A new store on the same directory is the next launch.
      final List<DVCrashStoreEntry> pending =
          DVFileCrashStore(dir.path).pending();
      expect(pending, hasLength(1));
      expect(pending.single.report!.context.release, '1.4.0');
    });

    test('the report carries the release, patch, protocol and context', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashReport report = reporter(store: store)
          .record(StateError('boom'), checkoutStack, fatal: true)!;

      expect(report.context.release, '1.4.0');
      expect(report.context.patch, 'p3');
      expect(report.context.protocolVersion, '7');
      expect(report.frames.first.function, 'CheckoutController.pay');
      expect(report.frames.first.uri, 'package:shop/checkout/controller.dart');
      expect(report.frames.first.line, 88);
    });
  });

  group('recovered at launch, sent once', () {
    test('a recovered report is sent and removed, and says so', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVMemoryCrashSink sink = DVMemoryCrashSink();
      reporter(store: store)
          .record(StateError('boom'), checkoutStack, fatal: true);

      final int sent = await reporter(store: store, sink: sink).recoverAndSend();

      expect(sent, 1);
      expect(sink.received, hasLength(1));
      expect(store.pending(), isEmpty);
      expect(diagnostics.count('DV-CRASH-001'), 1);
    });

    test('a process that dies after sending does not send again next launch',
        () async {
      final _DiesBeforeRemove store = _DiesBeforeRemove();
      final DVMemoryCrashSink sink = DVMemoryCrashSink();
      reporter(store: store)
          .record(StateError('boom'), checkoutStack, fatal: true);

      // First launch: sent, then the process dies before the record goes.
      await expectLater(
          reporter(store: store, sink: sink).recoverAndSend(), throwsStateError);
      expect(sink.received, hasLength(1));

      // Second launch: the record is still there, and must not go out twice.
      await reporter(store: store, sink: sink).recoverAndSend();

      expect(sink.received, hasLength(1),
          reason: 'one crash reported twice is a crash rate that doubled '
              'overnight for no reason anyone can find');
      expect(store.pending(), isEmpty);
    });

    test('a failed send is kept for the next launch', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      reporter(store: store)
          .record(StateError('boom'), checkoutStack, fatal: true);

      final int sent =
          await reporter(store: store, sink: DVMemoryCrashSink(failing: true))
              .recoverAndSend();

      expect(sent, 0);
      expect(store.pending(), hasLength(1));
    });

    test('with no sink the report stays local', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      reporter(store: store)
          .record(StateError('boom'), checkoutStack, fatal: true);

      expect(await reporter(store: store).recoverAndSend(), 0);
      expect(store.pending(), hasLength(1));
    });

    test('a record truncated by the crash that wrote it is dropped and named',
        () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVMemoryCrashSink sink = DVMemoryCrashSink();
      final DVCrashReport report = reporter(store: store)
          .record(StateError('boom'), checkoutStack, fatal: true)!;
      store.truncate(report.id);

      await reporter(store: store, sink: sink).recoverAndSend();

      expect(sink.received, isEmpty);
      expect(store.pending(), isEmpty);
      expect(diagnostics.count('DV-CRASH-005'), 1);
    });

    test('a release with no symbols is sent marked unsymbolicated', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVMemoryCrashSink sink = DVMemoryCrashSink();
      reporter(store: store)
          .record(StateError('boom'), checkoutStack, fatal: true);

      await reporter(
        store: store,
        sink: sink,
        symbols: DVMemoryCrashSymbols(releases: <String>{'1.3.0'}),
      ).recoverAndSend();

      expect(sink.received.single.symbolicated, isFalse);
      expect(diagnostics.count('DV-CRASH-003'), 1);
    });

    test('a release whose symbols arrived is sent symbolicated', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVMemoryCrashSink sink = DVMemoryCrashSink();
      reporter(store: store)
          .record(StateError('boom'), checkoutStack, fatal: true);

      await reporter(
        store: store,
        sink: sink,
        symbols: DVMemoryCrashSymbols(releases: <String>{'1.4.0'}),
      ).recoverAndSend();

      expect(sink.received.single.symbolicated, isTrue);
      expect(diagnostics.count('DV-CRASH-003'), 0);
    });
  });

  group('sensitive values never enter a report', () {
    test('a declared sensitive field in a breadcrumb is redacted, at any depth',
        () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashReporting crashes =
          reporter(store: store, sensitiveFields: <String>{'cardNumber'});

      crashes.breadcrumbs.add('backend', 'createOrder', data: <String, Object?>{
        'cardNumber': '4242424242424242',
        'order': <String, Object?>{
          'cardNumber': '5555555555554444',
          'items': 3,
        },
        'lines': <Object?>[
          <String, Object?>{'cardNumber': '378282246310005'},
        ],
        'accessToken': 'tok_live_abc',
      });
      crashes.record(StateError('boom'), checkoutStack, fatal: true);

      // The stored bytes, not the object: a redaction applied to a copy that
      // is then discarded protects nothing.
      final String stored = store.raw.values.single;
      expect(stored, isNot(contains('4242424242424242')));
      expect(stored, isNot(contains('5555555555554444')));
      expect(stored, isNot(contains('378282246310005')));
      expect(stored, isNot(contains('tok_live_abc')));
      expect(stored, contains(DVLogger.redactedValue));
      expect(stored, contains('"items":3'),
          reason: 'redaction removes the sensitive value, not the breadcrumb');
    });

    test('the breadcrumb buffer keeps only the declared number', () {
      final DVCrashReporting crashes =
          reporter(store: DVMemoryCrashStore());
      final DVCrashBreadcrumbs crumbs = crashes.breadcrumbs;
      for (int i = 0; i < crumbs.capacity + 10; i++) {
        crumbs.add('navigation', '/page/$i');
      }

      expect(crumbs.snapshot, hasLength(crumbs.capacity));
      expect(crumbs.snapshot.last.message, '/page/${crumbs.capacity + 9}');
      expect(crumbs.snapshot.first.message, '/page/10');
    });
  });

  group('grouping is by where it crashed, not by what it said', () {
    test('the same message from two different places is two groups', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashReporting crashes = reporter(store: store);

      final DVCrashReport a = crashes.record(
          StateError('Null check operator used on a null value'), checkoutStack,
          fatal: true)!;
      final DVCrashReport b = crashes.record(
          StateError('Null check operator used on a null value'), profileStack,
          fatal: true)!;

      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('one place with a message that carries an id is one group', () {
      final DVCrashReporting crashes = reporter(store: DVMemoryCrashStore());

      final DVCrashReport a = crashes.record(
          StateError('order 1042 has no lines'), checkoutStack,
          fatal: true)!;
      final DVCrashReport b = crashes.record(
          StateError('order 9981 has no lines'), checkoutStack,
          fatal: true)!;

      expect(a.fingerprint, b.fingerprint);
    });

    test('the group survives a release that moved the line', () {
      final StackTrace moved = stack(<String>[
        'CheckoutController.pay (package:shop/checkout/controller.dart:97:7)',
        'PayButton.onPressed (package:shop/checkout/pay_button.dart:33:12)',
        'GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:315:24)',
      ]);
      expect(
        DVCrashFingerprint.of(
            errorType: 'StateError', frames: DVCrashFrame.parse(checkoutStack)),
        DVCrashFingerprint.of(
            errorType: 'StateError', frames: DVCrashFrame.parse(moved)),
      );
    });

    test('framework frames are trimmed, so the group is named by app code', () {
      final List<DVCrashFrame> frames = DVCrashFrame.parse(checkoutStack);
      expect(DVCrashFingerprint.applicationFrames(frames).map((f) => f.uri),
          everyElement(startsWith('package:shop/')));
    });

    test('an override fingerprint wins where the default is wrong', () {
      expect(
        DVCrashFingerprint.of(
            errorType: 'StateError',
            frames: DVCrashFrame.parse(checkoutStack),
            override: 'shared-helper'),
        DVCrashFingerprint.of(
            errorType: 'ArgumentError',
            frames: DVCrashFrame.parse(profileStack),
            override: 'shared-helper'),
      );
    });
  });

  group('rate limits stop payloads, not arithmetic', () {
    test('past the limit a crash is counted but not written, across relaunch',
        () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVReleaseHealth health = DVReleaseHealth();

      for (int launch = 0; launch < 8; launch++) {
        // A crash loop: a new reporter each launch, the same device and store.
        final DVCrashReporting crashes = reporter(
          store: store,
          health: health,
          fullReportsPerRelease: 3,
        );
        crashes.startSession('session-$launch');
        crashes.record(StateError('loop'), checkoutStack, fatal: true);
      }

      expect(store.pending(), hasLength(3),
          reason: 'the limit has to survive the restart a crash loop is made '
              'of, or it limits nothing');
      expect(diagnostics.count('DV-CRASH-004'), greaterThan(0));
      expect(health.numbers(release: '1.4.0').crashedSessions, 8,
          reason: 'a counted crash still contributes to release health');
    });
  });

  group('sampling applies to non-fatal errors only', () {
    test('a sampled-out non-fatal is dropped and named', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashReporting crashes = reporter(
          store: store, nonFatalSampleRate: 0.25, random: () => 0.9);

      expect(crashes.record(StateError('handled'), checkoutStack), isNull);
      expect(store.pending(), isEmpty);
      expect(diagnostics.count('DV-CRASH-008'), 1);
    });

    test('a crash is never sampled, however low the rate', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashReporting crashes = reporter(
          store: store, nonFatalSampleRate: 0, random: () => 0.99);

      expect(crashes.record(StateError('fatal'), checkoutStack, fatal: true),
          isNotNull);
      expect(store.pending(), hasLength(1));
    });
  });

  group('declared off, and hangs', () {
    test('disabling is a declaration the build reports', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashReporting crashes = reporter(store: store, enabled: false);

      expect(crashes.record(StateError('boom'), checkoutStack, fatal: true),
          isNull);
      expect(store.pending(), isEmpty);
      expect(diagnostics.count('DV-CRASH-009'), 1);
    });

    test('install says native crashes are not captured in this build', () {
      reporter(store: DVMemoryCrashStore()).install();
      expect(diagnostics.count('DV-CRASH-006'), 1);
    });

    test('a hang past the threshold is filed once per episode', () {
      DateTime now = DateTime.utc(2026, 9, 13, 12);
      final List<Duration> hangs = <Duration>[];
      final DVHangWatchdog watchdog = DVHangWatchdog(
        threshold: const Duration(seconds: 5),
        clock: () => now,
        onHang: hangs.add,
      );

      watchdog.beat();
      now = now.add(const Duration(seconds: 4));
      watchdog.check();
      expect(hangs, isEmpty, reason: 'four seconds is not a hang at five');

      now = now.add(const Duration(seconds: 2));
      watchdog.check();
      watchdog.check();
      expect(hangs, hasLength(1),
          reason: 'one freeze is one hang, however often the watchdog looks');

      watchdog.beat();
      now = now.add(const Duration(seconds: 6));
      watchdog.check();
      expect(hangs, hasLength(2));
    });

    test('a hang is recorded as a hang report with DV-CRASH-007', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashReport report = reporter(store: store)
          .recordHang(checkoutStack, const Duration(seconds: 7))!;

      expect(report.kind, DVCrashKind.hang);
      expect(store.pending(), hasLength(1));
      expect(diagnostics.count('DV-CRASH-007'), 1);
    });
  });

  group('release health', () {
    test('a session that never started is not in the denominator', () {
      final DVReleaseHealth health = DVReleaseHealth();
      // Ten devices were offered the release; two opened it; one crashed.
      for (int i = 0; i < 10; i++) {
        health.assign(installId: 'device-$i', release: '1.4.0', cohort: '10pct');
      }
      health.sessionStarted(
          sessionId: 's1', installId: 'device-0', release: '1.4.0', cohort: '10pct');
      health.sessionStarted(
          sessionId: 's2', installId: 'device-1', release: '1.4.0', cohort: '10pct');
      health.sessionCrashed(sessionId: 's1');

      final DVReleaseHealthNumbers numbers = health.numbers(release: '1.4.0');
      expect(numbers.sessions, 2);
      expect(numbers.crashFreeSessions, 0.5,
          reason: 'counting the eight devices that never opened it would say '
              '90% and the gate would never trip');
      expect(numbers.crashFreeUsers, 0.5);
    });

    test('a crash in an unstarted session is not invented as a session', () {
      final DVReleaseHealth health = DVReleaseHealth();
      health.sessionStarted(
          sessionId: 's1', installId: 'device-0', release: '1.4.0');
      health.sessionCrashed(sessionId: 'never-started');

      expect(health.numbers(release: '1.4.0').crashFreeSessions, 1.0);
    });

    test('a cohort crashing inside a healthy average holds the rollout', () {
      final DVReleaseHealth health = DVReleaseHealth();
      // 90 healthy sessions in the main fleet, 10 in the rollout cohort, of
      // which 5 crash: 95% overall, 50% in the cohort.
      for (int i = 0; i < 90; i++) {
        health.sessionStarted(
            sessionId: 'main-$i', installId: 'm$i', release: '1.4.0', cohort: 'stable');
      }
      for (int i = 0; i < 10; i++) {
        health.sessionStarted(
            sessionId: 'roll-$i', installId: 'r$i', release: '1.4.0', cohort: 'rollout');
        if (i < 5) health.sessionCrashed(sessionId: 'roll-$i');
      }

      final DVReleaseHealthGate gate = DVReleaseHealthGate(
        crashFreeSessions: 0.9,
        stagedFlags: <String>['newCheckout'],
        onDiagnostic: diagnostics.call,
      );
      final DVReleaseHealthDecision decision =
          gate.evaluate(health, release: '1.4.0');

      expect(health.numbers(release: '1.4.0').crashFreeSessions, 0.95);
      expect(decision.hold, isTrue);
      expect(decision.heldCohorts, <String>['rollout']);
      expect(decision.flagsToTurnOff, <String>['newCheckout']);
      expect(diagnostics.count('DV-CRASH-010'), 1);
    });

    test('a healthy release is not held', () {
      final DVReleaseHealth health = DVReleaseHealth();
      for (int i = 0; i < 20; i++) {
        health.sessionStarted(
            sessionId: 's$i', installId: 'd$i', release: '1.4.0');
      }
      health.sessionCrashed(sessionId: 's0');

      final DVReleaseHealthDecision decision = DVReleaseHealthGate(
        crashFreeSessions: 0.9,
        onDiagnostic: diagnostics.call,
      ).evaluate(health, release: '1.4.0');

      expect(decision.hold, isFalse);
      expect(decision.flagsToTurnOff, isEmpty);
      expect(diagnostics.count('DV-CRASH-010'), 0);
    });

    test('a recorded crash counts against the session it happened in', () {
      final DVReleaseHealth health = DVReleaseHealth();
      final DVCrashReporting crashes =
          reporter(store: DVMemoryCrashStore(), health: health);
      crashes.startSession('launch-1');
      crashes.record(StateError('boom'), checkoutStack, fatal: true);

      final DVReleaseHealthNumbers numbers = health.numbers(release: '1.4.0');
      expect(numbers.sessions, 1);
      expect(numbers.crashedSessions, 1);
      expect(numbers.crashFreeSessions, 0.0);
    });
  });

  test('a report round-trips through JSON', () {
    final DVCrashReport report = reporter(store: DVMemoryCrashStore())
        .record(StateError('boom'), checkoutStack, fatal: true)!;
    final DVCrashReport back = DVCrashReport.fromJson(
        jsonDecode(jsonEncode(report.toJson())) as Map<String, Object?>);

    expect(back.id, report.id);
    expect(back.fingerprint, report.fingerprint);
    expect(back.frames.length, report.frames.length);
    expect(back.context.cohort, report.context.cohort);
  });
}
