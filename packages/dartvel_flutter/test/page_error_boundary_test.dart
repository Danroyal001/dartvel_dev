// A widget that throws takes down its page, not the application.
//
// Error, Empty, and Loading States: an error boundary wraps each page, the
// visitor gets a sentence and a retry while the detail goes to the log, and
// DV-STATE-002 records that a boundary caught something. Before it, a throw
// in a page's build left Flutter's red error box -- the exception's own text,
// in front of a customer -- in the middle of an otherwise live page.
import 'package:dartvel_core/src/observability/observability.dart'
    show DVLogRecord, DVObservability;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _throws = true;

class _Fragile extends StatelessWidget {
  const _Fragile();

  @override
  Widget build(BuildContext context) {
    if (_throws) throw StateError('ledger row 42 has no currency');
    return const Text('the ledger');
  }
}

Widget _app() => const MaterialApp(
      home: Column(
        children: <Widget>[
          Text('app chrome'),
          Expanded(
            child: DVPageShell(
              spec: DVPageScaffoldSpec(title: 'Ledger'),
              child: DVBox.list(<Widget>[Text('heading'), _Fragile()]),
            ),
          ),
        ],
      ),
    );

List<DVLogRecord> _caught() => DVObservability.recentLogs
    .where((DVLogRecord r) => r.code == 'DV-STATE-002')
    .toList();

void main() {
  setUp(() {
    _throws = true;
    DVObservability.resetLogging();
  });
  tearDown(DVObservability.resetLogging);

  testWidgets('the page shows a sentence, not the exception',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    expect(tester.takeException(), isStateError,
        reason: 'the error is still reported, so crash reporting sees it');
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.textContaining('currency'), findsNothing,
        reason: 'the detail is for the log, not the visitor');
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('heading'), findsNothing,
        reason: 'the boundary replaces the page, not one widget in it');
  });

  testWidgets('the rest of the application keeps running',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    tester.takeException();
    await tester.pumpAndSettle();

    expect(find.text('app chrome'), findsOneWidget);
  });

  testWidgets('DV-STATE-002 is logged once, at error, with the detail',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    tester.takeException();
    await tester.pumpAndSettle();

    final List<DVLogRecord> caught = _caught();
    expect(caught, hasLength(1));
    expect(caught.single.level, DVLogLevel.error);
    expect('${caught.single.message} ${caught.single.context}',
        contains('ledger row 42 has no currency'));
  });

  testWidgets('a retry is offered, not performed', (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    tester.takeException();
    await tester.pumpAndSettle();

    // Fixed underneath, but nothing rebuilds the page until somebody asks:
    // a failed page retried silently is how a broken endpoint becomes a
    // traffic pattern.
    _throws = false;
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('the ledger'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('the ledger'), findsOneWidget);
    expect(find.text('heading'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
  });

  testWidgets('outside a page, Flutter\'s own error widget is untouched',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Fragile()));
    tester.takeException();
    await tester.pump();

    expect(find.byType(ErrorWidget), findsOneWidget);
    expect(_caught(), isEmpty);
  });

  testWidgets('the words are framework strings a catalogue replaces',
      (WidgetTester tester) async {
    addTearDown(DV.I18n.reset);
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{
        DVFrameworkStrings.pageError: 'Une erreur est survenue',
        DVFrameworkStrings.retry: 'Réessayer',
      },
    ));
    DV.I18n.useLocale(LocaleTag.frFR);

    await tester.pumpWidget(_app());
    tester.takeException();
    await tester.pumpAndSettle();

    expect(find.text('Une erreur est survenue'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
