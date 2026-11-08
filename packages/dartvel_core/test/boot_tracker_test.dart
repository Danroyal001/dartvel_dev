import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:dartvel_core/src/observability/observability.dart'
    show DVLogSink, DVLogger, DVMemoryLogSink, DVObservability;
import 'package:test/test.dart';

/// The boot sequence as every entry walks it (Application Entry): the
/// lifecycle each phase moves to, and DV-RUN-004 naming the phase that threw,
/// so an app, a server, a worker and a cron process all say where start-up
/// stopped in the same words.
void main() {
  late DVMemoryLogSink logs;
  late DVLogger previous;
  setUp(() {
    logs = DVMemoryLogSink();
    previous = DVObservability.logger;
    DVObservability.logger = DVLogger(sinks: <DVLogSink>[logs]);
  });
  tearDown(() => DVObservability.logger = previous);

  test('phases move the lifecycle: 1-2 initializing, 3-5 booting, then ready',
      () {
    final DVLifecycleRegistry lifecycle = DVLifecycleRegistry();
    final DVBootTracker boot = DVBootTracker(
      const DVEntry.server(role: DVServerRole.web),
      lifecycle: lifecycle,
    );
    expect(lifecycle.app.value, DVAppLifecycle.uninitialized);
    boot.enter(1, 'initializing');
    expect(lifecycle.app.value, DVAppLifecycle.initializing);
    boot.enter(3, 'providers and modules');
    expect(lifecycle.app.value, DVAppLifecycle.booting);
    boot.enter(5, 'surface');
    expect(lifecycle.app.value, DVAppLifecycle.booting);
    boot.ready();
    expect(lifecycle.app.value, DVAppLifecycle.ready);
  });

  test('a failure is DV-RUN-004 naming the phase and the @DVBoot function',
      () {
    final DVLifecycleRegistry lifecycle = DVLifecycleRegistry();
    final DVBootTracker boot = DVBootTracker(
      const DVEntry.server(role: DVServerRole.worker),
      lifecycle: lifecycle,
    );
    boot
      ..enter(1, 'initializing')
      ..enter(4, 'boot functions')
      ..step(0)
      ..step(2);
    final DVBootFailure failure =
        boot.fail(StateError('no key'), StackTrace.current);
    expect(lifecycle.app.value, DVAppLifecycle.failed);
    expect(failure.phase, 4);
    expect(failure.phaseName, 'boot functions');
    expect(failure.bootStep, 2);
    expect(failure.error, isA<StateError>());
    expect(failure.toString(), contains('DV-RUN-004'));
    expect(failure.toString(), contains('phase 4, boot functions'));
    expect(failure.toString(), contains('@DVBoot function 3'));
    expect(failure.toString(), contains('server (worker)'));
    final List<DVLogRecord> reports = <DVLogRecord>[
      for (final DVLogRecord record in logs.records)
        if (record.code == 'DV-RUN-004') record,
    ];
    expect(reports, hasLength(1));
    expect(reports.single.level, DVLogLevel.error);
    expect(reports.single.context['phase'], 4);
    expect(reports.single.context['phaseName'], 'boot functions');
    expect(reports.single.context['bootStep'], 2);
    expect(reports.single.context['entry'], 'server');
  });

  test('a failure outside phase 4 names no @DVBoot function', () {
    final DVBootTracker boot =
        DVBootTracker(const DVEntry.app(), lifecycle: DVLifecycleRegistry());
    boot
      ..enter(4, 'boot functions')
      ..step(0)
      ..enter(5, 'surface');
    final DVBootFailure failure = boot.fail(StateError('x'), StackTrace.empty);
    expect(failure.phase, 5);
    expect(failure.bootStep, isNull);
    expect(failure.toString(), isNot(contains('@DVBoot')));
  });
}
