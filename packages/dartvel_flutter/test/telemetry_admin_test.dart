// The entitlements and events surface.
//
// Both sections exist to separate "nothing happened" from "this admin cannot
// see what happened" — a hosted provider keeps its records elsewhere, and an
// empty list would claim otherwise.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('entitlements are listed per customer',
      (WidgetTester tester) async {
    final billing = DVLocalBillingProvider()
      ..grant('acme', Entitlement.analytics)
      ..grant('acme', const Entitlement('exports'))
      ..grant('globex', Entitlement.analytics);

    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVTelemetryAdmin(billing: billing)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Entitlements (2 customers)'), findsOneWidget);
    expect(find.text('acme'), findsOneWidget);
    expect(find.text('analytics, exports'), findsOneWidget);
  });

  testWidgets('nobody holding an entitlement is stated, not left blank',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVTelemetryAdmin(billing: DVLocalBillingProvider())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Nobody holds an entitlement.'), findsOneWidget);
  });

  testWidgets('events are listed newest first', (WidgetTester tester) async {
    final analytics = LocalAnalyticsProvider();
    await analytics.logEvent('first', <String, Object>{});
    await analytics.logEvent('second', <String, Object>{'plan': 'pro'});

    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVTelemetryAdmin(analytics: analytics)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Events (2)'), findsOneWidget);
    expect(find.text('plan=pro'), findsOneWidget);

    // The reason to open this is something that just happened.
    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data)
        .where((String? d) => d == 'first' || d == 'second')
        .toList();
    expect(names, <String>['second', 'first']);
  });

  testWidgets('a long event log is capped and says so',
      (WidgetTester tester) async {
    final analytics = LocalAnalyticsProvider();
    for (var i = 0; i < 10; i++) {
      await analytics.logEvent('event$i', <String, Object>{});
    }

    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVTelemetryAdmin(analytics: analytics, eventLimit: 3),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Events (10)'), findsOneWidget);
    expect(find.text('showing the most recent 3'), findsOneWidget);
    expect(find.text('event9'), findsOneWidget);
    expect(find.text('event0'), findsNothing);
  });

  testWidgets('no local provider is explained rather than shown as empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Material(child: DVTelemetryAdmin()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No local provider configured'), findsOneWidget);
    expect(find.text('No events recorded.'), findsNothing);
  });
}
