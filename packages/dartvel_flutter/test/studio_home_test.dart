// Studio's Home on screen: the first section on the rail, opened by default,
// drawing what `api/overview` answers -- counts that open their screens,
// site health, recent changes and quick actions -- by mouse, keyboard and
// screen reader alike.
import 'package:dartvel_core/dartvel.dart'
    show DVStudioHealthStatus, DVStudioOverview, DVStudioActivity,
        DVStudioHealthCheck;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final int _fiveMinutesAgo = DateTime.now()
    .toUtc()
    .subtract(const Duration(minutes: 5))
    .millisecondsSinceEpoch;

DVStudioOverview _overview() => DVStudioOverview(
  glance: const <String, int>{
    'pages': 12,
    'models': 1,
    'records': 340,
    'functions': 3,
    'team': 2,
  },
  health: const <DVStudioHealthCheck>[
    DVStudioHealthCheck(
      id: 'check:payments',
      status: DVStudioHealthStatus.critical,
      title: 'payments',
      detail: 'The payment provider timed out.',
    ),
    DVStudioHealthCheck(
      id: 'page-titles',
      status: DVStudioHealthStatus.recommended,
      title: 'Page titles',
      detail: 'A page has no title: /sale.',
      screen: 'pages',
    ),
    DVStudioHealthCheck(
      id: 'database',
      status: DVStudioHealthStatus.good,
      title: 'Database',
      detail: 'The database answers.',
    ),
  ],
  recent: <DVStudioActivity>[
    DVStudioActivity(
      at: _fiveMinutesAgo,
      kind: 'page',
      action: 'saved',
      label: 'Summer sale',
      screen: 'pages',
      object: 'sale',
    ),
  ],
);

DVStudioTransport _transport({
  int status = 200,
  List<String>? calls,
}) => (String method, String path, {Object? body}) async {
  calls?.add('$method $path');
  if (path == 'api/overview') {
    return status == 200
        ? DVStudioReply(200, _overview().toJson())
        : const DVStudioReply(500, <String, Object?>{
            'error': 'boom',
            'message': 'The database did not answer.',
          });
  }
  return const DVStudioReply(404, <String, Object?>{});
};

Future<List<(String, String?)>> _open(
  WidgetTester tester, {
  DVStudioTransport? transport,
  String? selected,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final List<(String, String?)> opened = <(String, String?)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: DVStudioScreen(
          sections: dvStudioServerSections(
            DVStudioClient(transport ?? _transport()),
          ),
          selected: selected,
          onSelect: (String section, String? object) =>
              opened.add((section, object)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('Home is first on the rail and is what Studio opens on', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final Finder rail = find.byWidgetPredicate(
      (Widget widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'dv-studio-section-',
          ),
    );
    expect(
      (tester.widget(rail.first).key! as ValueKey<String>).value,
      'dv-studio-section-home',
    );
    expect(find.byKey(const ValueKey<String>('dv-studio-home')), findsOneWidget);
  });

  testWidgets('draws the counts, the health, the changes and the actions', (
    WidgetTester tester,
  ) async {
    await _open(tester, selected: 'home');
    expect(find.text('12 pages'), findsOneWidget);
    expect(find.text('1 data model'), findsOneWidget);
    expect(find.text('340 records'), findsOneWidget);
    expect(find.text('3 backend functions'), findsOneWidget);
    expect(find.text('2 people can open Studio'), findsOneWidget);
    expect(find.text('Site health'), findsOneWidget);
    expect(find.text('payments'), findsOneWidget);
    expect(find.text('Needs attention now'), findsOneWidget);
    expect(find.text('The payment provider timed out.'), findsOneWidget);
    expect(find.text('Recent changes'), findsOneWidget);
    expect(find.text('Summer sale'), findsOneWidget);
    expect(find.text('5 minutes ago'), findsOneWidget);
    expect(find.text('Add a page'), findsOneWidget);
    expect(find.text('Design a data model'), findsOneWidget);
    expect(find.text('Add a teammate'), findsOneWidget);
    expect(find.text('View the site'), findsOneWidget);
  });

  testWidgets('a count opens its screen, and a change opens what changed', (
    WidgetTester tester,
  ) async {
    final List<(String, String?)> opened = await _open(tester, selected: 'home');
    await tester.tap(find.text('12 pages'));
    await tester.pumpAndSettle();
    expect(opened.last, ('pages', null));
    expect(find.byKey(const ValueKey<String>('dv-studio-home')), findsNothing);
  });

  testWidgets('a recent change opens the thing that changed', (
    WidgetTester tester,
  ) async {
    final List<(String, String?)> opened = await _open(tester, selected: 'home');
    await tester.tap(find.text('Summer sale'));
    await tester.pumpAndSettle();
    expect(opened.last, ('pages', 'sale'));
  });

  testWidgets('every count and action is reached with Tab and pressed with '
      'Enter', (WidgetTester tester) async {
    final List<(String, String?)> opened = await _open(tester, selected: 'home');
    // Tab until the first count has focus.
    bool reached = false;
    for (int i = 0; i < 40 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final FocusNode? focus = FocusManager.instance.primaryFocus;
      reached = focus?.context
              ?.findAncestorWidgetOfExactType<Semantics>()
              ?.properties
              .label ==
          '12 pages';
    }
    expect(reached, isTrue, reason: 'Tab never reached "12 pages"');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened.last, ('pages', null));
  });

  testWidgets('a screen reader is told each count is a button, and what each '
      'health check came to', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _open(tester, selected: 'home');
    expect(
      tester.getSemantics(find.bySemanticsLabel('12 pages')),
      matchesSemantics(
        label: '12 pages',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp('payments.*Needs attention now')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('Home that cannot be read says why and offers to try again', (
    WidgetTester tester,
  ) async {
    final List<String> calls = <String>[];
    await _open(
      tester,
      transport: _transport(status: 500, calls: calls),
      selected: 'home',
    );
    expect(find.text('Home could not be read'), findsOneWidget);
    expect(find.textContaining('The database did not answer.'), findsOneWidget);
    final int before = calls.where((String c) => c.endsWith('overview')).length;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
      calls.where((String c) => c.endsWith('overview')).length,
      before + 1,
    );
  });

  testWidgets('a project with no database to count says so in a sentence', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      transport: (String method, String path, {Object? body}) async =>
          DVStudioReply(200, const DVStudioOverview().toJson()),
      selected: 'home',
    );
    expect(find.text('No changes made in Studio yet.'), findsOneWidget);
  });
}
