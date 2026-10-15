import 'package:dartvel_core/dartvel.dart' show DVAppLifecycle, DVBoot;
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
        (DVBoot boot) async {
          expect(boot.args, ['--example']);
          calls.add('boot');
        },
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
        boot: [(_) => throw StateError('broken boot')],
      ),
      throwsStateError,
    );
    await tester.pump();
    expect(DV.lifecycle.app.value, DVAppLifecycle.failed);
    expect(find.text('Unable to start the application.'), findsOneWidget);
  });
}
