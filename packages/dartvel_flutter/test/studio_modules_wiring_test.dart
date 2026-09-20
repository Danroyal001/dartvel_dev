// The Modules section as Studio actually builds it.
//
// The section's own test passed and the running Studio sat on "Loading
// modules…" forever, because the test built the widget directly and Studio
// builds it through dvStudioServerSections against a DVStudioClient. The
// wiring was the part that was wrong, and the wiring was the part nothing
// covered.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The graph an example with one mounted module writes.
const Map<String, Object?> _graph = <String, Object?>{
  'graphVersion': 2,
  'models': <Object?>[],
  'routes': <Object?>[],
  'functions': <Object?>[],
  'jobs': <Object?>[],
  'modules': <Object?>[
    <String, Object?>{
      'id': 'notes',
      'package': 'dartvel_example_notes',
      'mount': '/notes',
      'source': 'modules/notes',
      'deployment': 'embedded',
      'mounted': true,
      'pages': 2,
      'data': 'schema-isolated',
      'name': 'Notes',
      'version': '1.0.0',
    },
  ],
};

/// A transport that answers graph.json the way the server does: the body is
/// decoded JSON, and every other path is a 404.
DVStudioTransport get _transport =>
    (String method, String path, {Object? body}) async => path == 'graph.json'
        ? DVStudioReply(200, jsonDecode(jsonEncode(_graph)))
        : const DVStudioReply(404, <String, Object?>{});

void main() {
  testWidgets('the Modules section on the rail shows the mounted module',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<DVStudioSection> sections =
        dvStudioServerSections(DVStudioClient(_transport));

    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVStudioScreen(sections: sections)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey<String>('dv-studio-section-modules')));
    await tester.pumpAndSettle();

    expect(find.text('Loading modules…'), findsNothing,
        reason: 'the section has to leave its placeholder');
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('/notes'), findsOneWidget);
  });
}
