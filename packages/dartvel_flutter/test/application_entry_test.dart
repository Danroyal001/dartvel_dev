import 'package:dartvel_core/dartvel.dart' show DVAppLifecycle, DVBoot, DVEntryKind, DVEntryKindOf;
import 'package:dartvel_core/framework.dart' show DVBootStep;
import 'package:dartvel_core/src/observability/observability.dart'
    show DVLogSink, DVLogger, DVMemoryLogSink, DVObservability;
import 'package:dartvel_core/dartvel.dart' show DVLogLevel, DVLogRecord;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(dvResetApplicationEntryForTest);
  testWidgets('hooks finish before root and duplicate runs are ignored', (
    tester,
  ) async {
    final calls = <String>[];
    await dvRunApplication(
      ['--example'],
      root: () {
        calls.add('root');
        return const Directionality(textDirection: .ltr, child: DVText('Home'));
      },
      boot: [
        DVBootStep(
          run: (DVBoot boot) async {
            expect(boot.args, ['--example']);
            expect(boot.entry.kind, DVEntryKind.app);
            calls.add('boot');
          },
        ),
        DVBootStep(
          entries: const {DVEntryKind.server},
          run: (_) => calls.add('server boot'),
        ),
      ],
    );
    await tester.pump();
    expect(calls, ['boot', 'root']);
    expect(find.text('Home'), findsOneWidget);
    expect(DV.lifecycle.app.value, DVAppLifecycle.ready);
    await dvRunApplication(
      [],
      root: () {
        calls.add('duplicate');
        return const SizedBox();
      },
    );
    expect(calls, ['boot', 'root']);
  });
  testWidgets('boot failure reports failed and presents a failure page', (
    tester,
  ) async {
    await expectLater(
      dvRunApplication(
        [],
        root: () => const SizedBox(),
        boot: [DVBootStep(run: (_) => throw StateError('broken boot'))],
      ),
      throwsStateError,
    );
    await tester.pump();
    expect(DV.lifecycle.app.value, DVAppLifecycle.failed);
    expect(find.text('Unable to start the application.'), findsOneWidget);
  });

  // DV-RUN-004: a boot phase that throws names the phase, so a report says
  // where start-up stopped rather than only that it did.
  for (final ({String name, int phase, String phaseName, Object? step, bool Function(_FailAt) at}) failure in <({String name, int phase, String phaseName, Object? step, bool Function(_FailAt) at})>[
    (name: 'surface selection', phase: 2, phaseName: 'surface selection', step: null, at: (f) => f == _FailAt.launch),
    (name: 'a @DVBoot function', phase: 4, phaseName: 'boot functions', step: 1, at: (f) => f == _FailAt.boot),
    (name: 'the root widget', phase: 5, phaseName: 'surface', step: null, at: (f) => f == _FailAt.root),
  ]) {
    testWidgets('a failure in ${failure.name} reports DV-RUN-004 naming phase '
        '${failure.phase}', (tester) async {
      final logs = DVMemoryLogSink();
      final previous = DVObservability.logger;
      DVObservability.logger = DVLogger(sinks: <DVLogSink>[logs]);
      addTearDown(() => DVObservability.logger = previous);
      _FailAt? which;
      for (final f in _FailAt.values) {
        if (failure.at(f)) which = f;
      }
      await expectLater(
        dvRunApplication(
          [],
          launch: (_) {
            if (which == _FailAt.launch) throw StateError('no display');
          },
          root: () {
            if (which == _FailAt.root) throw StateError('broken root');
            return const SizedBox();
          },
          boot: [
            DVBootStep(run: (_) {}),
            DVBootStep(run: (_) {
              if (which == _FailAt.boot) throw StateError('broken boot');
            }),
          ],
        ),
        throwsStateError,
      );
      await tester.pump();
      expect(DV.lifecycle.app.value, DVAppLifecycle.failed);
      final reports = [
        for (final record in logs.records)
          if (record.code == 'DV-RUN-004') record,
      ];
      expect(reports, hasLength(1));
      expect(reports.single.context['phase'], failure.phase);
      expect(reports.single.context['phaseName'], failure.phaseName);
      expect(reports.single.context['bootStep'], failure.step);
      expect(reports.single.message, contains(failure.phaseName));
    });
  }

  testWidgets('the boot-failure page retries the boot and the app starts', (
    tester,
  ) async {
    // Failure has a page with a retry (Application Entry): a boot that
    // failed on a network blip or a locked file must be able to try again
    // without the person killing the app.
    var attempts = 0;
    await expectLater(
      dvRunApplication(
        ['--again'],
        root: () =>
            const Directionality(textDirection: .ltr, child: DVText('Home')),
        boot: [
          DVBootStep(
            run: (DVBoot boot) {
              attempts++;
              expect(boot.args, ['--again']);
              if (attempts == 1) throw StateError('locked');
            },
          ),
        ],
      ),
      throwsStateError,
    );
    await tester.pump();
    expect(DV.lifecycle.app.value, DVAppLifecycle.failed);
    expect(find.text('Try again'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Try again'), matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNotNull);
    // The button runs dvRetryApplication. Awaited here rather than tapped:
    // a tap starts the boot inside a test frame, and the test binding then
    // draws runApp's warm-up frame inside runApp and finishes this body
    // from there, before runApp returns. A real binding does not re-enter.
    await dvRetryApplication();
    await tester.pump();
    expect(attempts, 2);
    expect(find.text('Home'), findsOneWidget);
    expect(DV.lifecycle.app.value, DVAppLifecycle.ready);
  });

  // DV-RUN-003: "boot exceeded its budget; the slowest phase and @DVBoot
  // function are named" (dartvel.run.bootBudget, phases 1-5 for an app
  // entry). A boot that has grown slow is otherwise noticed by the person
  // waiting at the splash, not by anybody who can fix it.
  group('the boot budget', () {
    late DVMemoryLogSink logs;
    setUp(() {
      logs = DVMemoryLogSink();
      final previous = DVObservability.logger;
      DVObservability.logger = DVLogger(sinks: <DVLogSink>[logs]);
      addTearDown(() => DVObservability.logger = previous);
    });
    List<DVLogRecord> budgetWarnings() => [
          for (final record in logs.records)
            if (record.code == 'DV-RUN-003') record,
        ];

    testWidgets('a boot over budget warns, naming the slowest phase and '
        '@DVBoot function', (tester) async {
      // The boot's clock, advanced by the boot functions themselves: the
      // test binding's time does not pass on its own.
      var now = DateTime(2026, 11, 8);
      await dvRunApplication(
        [],
        root: () => const SizedBox(),
        bootBudget: const Duration(milliseconds: 800),
        clock: () => now,
        boot: [
          DVBootStep(run: (_) => now = now.add(const Duration(milliseconds: 100))),
          DVBootStep(run: (_) => now = now.add(const Duration(milliseconds: 900))),
          DVBootStep(run: (_) => now = now.add(const Duration(milliseconds: 50))),
        ],
      );
      await tester.pump();
      final warnings = budgetWarnings();
      expect(warnings, hasLength(1));
      expect(warnings.single.level, DVLogLevel.warn);
      expect(warnings.single.context['budgetMs'], 800);
      expect(warnings.single.context['elapsedMs'], 1050);
      expect(warnings.single.context['slowestPhase'], 4);
      expect(warnings.single.context['slowestPhaseName'], 'boot functions');
      expect(warnings.single.context['slowestBootStep'], 1);
      expect(warnings.single.message, contains('@DVBoot function 2'));
      expect(DV.lifecycle.app.value, DVAppLifecycle.ready);
    });

    testWidgets('a boot within budget says nothing', (tester) async {
      var now = DateTime(2026, 11, 8);
      await dvRunApplication(
        [],
        root: () => const SizedBox(),
        bootBudget: const Duration(milliseconds: 800),
        clock: () => now,
        boot: [
          DVBootStep(run: (_) => now = now.add(const Duration(milliseconds: 700))),
        ],
      );
      await tester.pump();
      expect(budgetWarnings(), isEmpty);
    });
  });
}

enum _FailAt { launch, boot, root }
