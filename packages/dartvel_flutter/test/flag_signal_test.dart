// A flag read in a build method is a signal: the widget rebuilds when the rules
// change under it, and it composes with other signals without a second
// mechanism.
//
// The silent failure here is a widget that read the flag once and never again:
// a kill switch flipped at two in the morning that every open screen ignores
// until somebody navigates away and back.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final DVFeatureFlag<bool> newCheckout = DVFeatureFlag<bool>(
  key: 'newCheckout',
  defaultValue: false,
  owner: 'payments',
  expires: DateTime.utc(2099, 1, 1),
);

final DVFeatureFlag<int> pageSize = DVFeatureFlag<int>(
  key: 'pageSize',
  defaultValue: 20,
  owner: 'feed',
  expires: DateTime.utc(2099, 1, 1),
);

DVFlagRules rulesWith(Map<String, Object?> values) =>
    DVFlagRules.fromJson(<String, Object?>{
      'format': 1,
      'rulesVersion': 1,
      'flags': <String, Object?>{
        for (final MapEntry<String, Object?> e in values.entries)
          e.key: <Object?>[
            <String, Object?>{'value': e.value},
          ],
      },
    });

Widget host(Widget Function(BuildContext context) build) => Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: build),
    );

void main() {
  setUp(() {
    DVFlags.resetForTest();
    DVFlags.onDiagnostic = (String code, String message) {};
  });

  testWidgets('a widget reading a flag rebuilds when the rules change',
      (WidgetTester tester) async {
    int builds = 0;
    await tester.pumpWidget(host((BuildContext context) {
      builds++;
      return Text(context.flag(newCheckout).value ? 'new' : 'old');
    }));
    expect(find.text('old'), findsOneWidget);

    DVFlags.setRules(rulesWith(<String, Object?>{'newCheckout': true}));
    await tester.pump();

    expect(find.text('new'), findsOneWidget,
        reason: 'a flipped flag must reach a screen that is already open');
    expect(builds, 2);
  });

  testWidgets('reading without subscribing does not rebuild',
      (WidgetTester tester) async {
    int builds = 0;
    await tester.pumpWidget(host((BuildContext context) {
      builds++;
      return Text('${context.flag(pageSize).read()}');
    }));
    DVFlags.setRules(rulesWith(<String, Object?>{'pageSize': 50}));
    await tester.pump();
    expect(builds, 1);
  });

  testWidgets('a flag composes with other signals and plain values',
      (WidgetTester tester) async {
    await tester.pumpWidget(host((BuildContext context) {
      final DVReadableSignal<bool> shown = context.flag(newCheckout) & true;
      return Text(shown.value ? 'shown' : 'hidden');
    }));
    expect(find.text('hidden'), findsOneWidget);

    DVFlags.setRules(rulesWith(<String, Object?>{'newCheckout': true}));
    await tester.pump();
    expect(find.text('shown'), findsOneWidget);
  });

  testWidgets('a widget that is gone is not rebuilt, and nothing throws',
      (WidgetTester tester) async {
    await tester.pumpWidget(host((BuildContext context) =>
        Text(context.flag(newCheckout).value ? 'new' : 'old')));
    await tester.pumpWidget(const SizedBox());

    DVFlags.setRules(rulesWith(<String, Object?>{'newCheckout': true}));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
