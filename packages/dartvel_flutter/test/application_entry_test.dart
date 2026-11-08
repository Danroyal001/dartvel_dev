import 'package:dartvel_core/dartvel.dart' show DVAppLifecycle, DVBoot, DVEntryKind, DVEntryKindOf;
import 'package:dartvel_core/framework.dart' show DVBootStep;
import 'package:dartvel_core/src/observability/observability.dart'
    show DVLogSink, DVLogger, DVMemoryLogSink, DVObservability;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
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
}

enum _FailAt { launch, boot, root }
