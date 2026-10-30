// DV-STATE-001: a collection with nothing yet and no action to create one.
//
// An empty collection wants the action that creates the first one. One that
// offers nothing leaves the reader on a page with no way forward, and nothing
// said so -- it renders fine, which is why it is worth a diagnostic.
import 'package:dartvel_core/src/observability/observability.dart'
    show DVLogRecord, DVObservability;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Invoice {}

class Refund {}

class Payout {}

class Dispute {}

List<DVLogRecord> _reports() => DVObservability.recentLogs
    .where((DVLogRecord r) => r.code == 'DV-STATE-001')
    .toList();

Future<void> _show<T>(WidgetTester tester, DVEmpty empty) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DVTable<T>(
        List<T>.empty(),
        columns: <DVTableColumn<T>>[
          DVTableColumn<T>(label: 'Id', value: (T row) => '$row'),
        ],
        empty: empty,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(DVObservability.resetLogging);
  tearDown(DVObservability.resetLogging);

  testWidgets('nothing yet with no action is reported, at info, naming it',
      (WidgetTester tester) async {
    await _show<Invoice>(tester, const DVEmpty.nothingYet());

    final List<DVLogRecord> reports = _reports();
    expect(reports, hasLength(1));
    expect(reports.single.level, DVLogLevel.info);
    expect('${reports.single.message} ${reports.single.context}',
        contains('Invoice'));
  });

  testWidgets('once per collection, not once per frame',
      (WidgetTester tester) async {
    await _show<Refund>(tester, const DVEmpty.nothingYet());
    await _show<Refund>(tester, const DVEmpty.nothingYet(label: 'None'));
    await tester.pump();

    expect(_reports(), hasLength(1));
  });

  testWidgets('an action declared is not reported', (WidgetTester tester) async {
    await _show<Payout>(
      tester,
      DVEmpty.nothingYet(
        action: TextButton(onPressed: () {}, child: const Text('New payout')),
      ),
    );

    expect(_reports(), isEmpty);
  });

  testWidgets('the other two empties want no create action',
      (WidgetTester tester) async {
    await _show<Dispute>(tester, const DVEmpty.nothingMatching());
    await _show<Dispute>(tester, const DVEmpty.nothingVisible());

    expect(_reports(), isEmpty);
  });
}
