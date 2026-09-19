// A section attached with the id of one already there takes its place.
//
// Free Studio's Backend section lists the app's backend functions. Studio Pro
// has a Backend section too, with the builder, and attaching it beside the
// free one put "Backend" on the rail twice. The later one now replaces the
// earlier where it stood, so the rail keeps its order and has one Backend.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVStudioSection section(String id, String label, String body) =>
    DVStudioSection(
      id: id,
      label: label,
      icon: Icons.functions,
      build: (BuildContext context) => Text(body),
    );

void main() {
  testWidgets('the later of two sections with one id replaces the earlier',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVStudioScreen(sections: <DVStudioSection>[
          section('models', 'Data', 'records'),
          section('functions', 'Backend', 'a list of functions'),
          section('jobs', 'Tasks', 'tasks'),
          section('frontend', 'Frontend', 'frontend builder'),
          section('functions', 'Backend', 'the backend builder'),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Backend'), findsOneWidget);
    // Where the first stood: after Data, before Tasks.
    final double data = tester.getCenter(find.text('Data')).dy;
    final double backend = tester.getCenter(find.text('Backend')).dy;
    final double tasks = tester.getCenter(find.text('Tasks')).dy;
    expect(backend, greaterThan(data));
    expect(backend, lessThan(tasks));

    await tester.tap(
        find.byKey(const ValueKey<String>('dv-studio-section-functions')));
    await tester.pumpAndSettle();
    expect(find.text('the backend builder'), findsOneWidget);
    expect(find.text('a list of functions'), findsNothing);
  });
}
