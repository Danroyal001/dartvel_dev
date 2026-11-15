// A host application starts a Dartvel project at its generated
// dartvelEmbeddedEntry_<project>, which boots the same runtime as DV.run but
// as an embedded entry: the host owns the process, so there is no launch
// negotiation (no single-instance lock, no argv to open), and boot hooks see
// DVEntry.embedded with the project's name.
import 'package:dartvel_core/dartvel.dart'
    show DVBoot, DVEmbeddedEntry, DVEntry, DVEntryKind, DVEntryKindOf;
import 'package:dartvel_core/framework.dart' show DVBootStep;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(dvResetApplicationEntryForTest);

  testWidgets('an embedded entry boots as embedded and skips the launch',
      (WidgetTester tester) async {
    final List<String> calls = <String>[];
    DVEntry? seen;
    await dvRunApplication(
      const <String>[],
      entry: const DVEntry.embedded('checkout'),
      root: () {
        calls.add('root');
        return const Directionality(
            textDirection: .ltr, child: DVText('Checkout'));
      },
      launch: (_) => calls.add('launch'),
      boot: <DVBootStep>[
        DVBootStep(run: (DVBoot boot) {
          seen = boot.entry;
          calls.add('boot');
        }),
      ],
    );
    await tester.pump();
    expect(calls, <String>['boot', 'root']);
    expect(seen!.kind, DVEntryKind.embedded);
    expect((seen! as DVEmbeddedEntry).project, 'checkout');
    expect(find.text('Checkout'), findsOneWidget);
  });

  testWidgets('the app entry still negotiates its launch',
      (WidgetTester tester) async {
    final List<String> calls = <String>[];
    await dvRunApplication(
      const <String>[],
      root: () => const Directionality(
          textDirection: .ltr, child: DVText('Home')),
      launch: (_) => calls.add('launch'),
    );
    await tester.pump();
    expect(calls, <String>['launch']);
  });
}
