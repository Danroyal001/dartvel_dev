// Server state (NEW_SPEC "Server State"): a page names the backend function
// that produces its data, and reads the result as `context.serverState`.
//
// These cover the runtime half: the page's loader runs the state, shows the
// page's loading companion until it arrives and its error companion if it
// fails, hands the typed value to the page, and runs it again on
// `context.refreshServerState()` -- never merely because the page rebuilt.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class const DashboardState(final int openWorkOrders);

/// The class form: DVClassWidget<T> with initServerState.
class const DashboardPage({super.key, required final Future<DashboardState> Function() fetch})
    extends DVClassWidget<DashboardState> {
  @override
  Future<DashboardState> initServerState() => fetch();

  @override
  Widget build(BuildContext context) {
    final DashboardState state = context.serverState;
    return DVBox.list(<Widget>[
      DVText('Open work orders: ${state.openWorkOrders}'),
      DVText('Refresh').modifier(
          DVModifier().onTap(() => context.refreshServerState())),
    ]);
  }
}

Widget loaderFor(DartvelPage page) => MaterialApp(
      home: Scaffold(
        body: DvDataLoader(
          load: () => page.initServerState() ?? page.loadData(const {}, const {}),
          loading: const DVText('Loading companion'),
          error: const DVText('Error companion'),
          child: page,
        ),
      ),
    );

void main() {
  testWidgets('the loading companion shows until the state arrives, then the '
      'page reads it typed', (WidgetTester tester) async {
    final Completer<DashboardState> answer = Completer<DashboardState>();
    await tester.pumpWidget(loaderFor(DashboardPage(fetch: () => answer.future)));
    expect(find.text('Loading companion'), findsOneWidget);
    answer.complete(const DashboardState(7));
    await tester.pumpAndSettle();
    expect(find.text('Open work orders: 7'), findsOneWidget);
  });

  testWidgets('a failed state shows the error companion', (WidgetTester tester) async {
    await tester.pumpWidget(loaderFor(DashboardPage(
        fetch: () => Future<DashboardState>.error(StateError('no server')))));
    await tester.pumpAndSettle();
    expect(find.text('Error companion'), findsOneWidget);
  });

  testWidgets('refreshServerState runs it again; a rebuild does not',
      (WidgetTester tester) async {
    int runs = 0;
    Future<DashboardState> fetch() async => DashboardState(++runs);
    final DashboardPage page = DashboardPage(fetch: fetch);
    await tester.pumpWidget(loaderFor(page));
    await tester.pumpAndSettle();
    expect(find.text('Open work orders: 1'), findsOneWidget);

    // The same tree pumped again is a rebuild, not a reason to fetch.
    await tester.pumpWidget(loaderFor(page));
    await tester.pumpAndSettle();
    expect(runs, 1);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(runs, 2);
    expect(find.text('Open work orders: 2'), findsOneWidget);
  });

  test('a class page with no server state keeps loadData', () {
    expect(const _PlainPage().initServerState(), isNull);
  });
}

class const _PlainPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => const DVText('plain');
}
