// The dev menu a dev-client shell carries: reload, the capability report for
// the device it is actually running on, and the log.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/dev_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const DVDevClientManifest shell = DVDevClientManifest(
    target: 'android',
    bindings: <String>['dartvel_flutter@0.4.0', 'plugin:jni'],
  );

  group('the inspectors', inspectorTests);

  tearDown(() {
    DVNativeBridge.unregister('camera.takePhoto');
  });

  testWidgets('reload asks for the next bundle', (WidgetTester tester) async {
    var reloads = 0;
    await tester.pumpWidget(MaterialApp(
      home: DVDevMenu(
        shell: shell,
        branch: 'feature/checkout',
        log: const <String>[],
        onReload: () async => reloads++,
      ),
    ));

    await tester.tap(find.text('Reload'));
    await tester.pump();

    expect(reloads, 1);
  });

  testWidgets('the capability report is what this device registered',
      (WidgetTester tester) async {
    // Registered at runtime, not read from the manifest: the report is for
    // the device in somebody's hand, and the two can differ.
    DVNativeBridge.register('camera.takePhoto', (_) => <int>[]);

    await tester.pumpWidget(MaterialApp(
      home: DVDevMenu(
        shell: shell,
        branch: 'feature/checkout',
        log: const <String>[],
        onReload: () async {},
      ),
    ));

    expect(find.text('camera.takePhoto'), findsOneWidget);
    expect(find.text('plugin:jni'), findsOneWidget);
    expect(find.textContaining('feature/checkout'), findsOneWidget);
  });

  testWidgets('the log shows what loading did', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DVDevMenu(
        shell: shell,
        branch: 'feature/checkout',
        log: const <String>[
          'DV-DEVCLIENT-002: This bundle needs plugin:camera',
        ],
        onReload: () async {},
      ),
    ));

    expect(find.textContaining('plugin:camera'), findsOneWidget);
  });
}

// The inspectors: what `dartvel inspect` answers about the project the paired
// server is serving, read from that server.
void inspectorTests() {
  const DVDevClientManifest shell = DVDevClientManifest(
    target: 'android',
    bindings: <String>['dartvel_flutter@0.4.0'],
  );

  final Map<String, Object?> graph = <String, Object?>{
    'graphVersion': 1,
    'models': <Object?>[
      <String, Object?>{'name': 'Note', 'source': 'lib/models/note.dart'},
    ],
    'routes': <Object?>[
      <String, Object?>{'path': '/orders/:id', 'page': 'OrderPage'},
    ],
    'functions': <Object?>[
      <String, Object?>{'name': 'addNote', 'method': 'POST', 'path': '/api/notes'},
    ],
    'jobs': <Object?>[
      <String, Object?>{'name': 'SendReceipt', 'queue': 'mail'},
    ],
  };

  testWidgets('show the routes, models, functions and jobs of the project',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DVDevMenu(
        shell: shell,
        branch: 'main',
        log: const <String>[],
        onReload: () async {},
        inspect: () async => DVDevClientInspection.fromGraph(graph),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('/orders/:id'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('POST /api/notes'), findsOneWidget);
    expect(find.text('SendReceipt (mail)'), findsOneWidget);
  });

  testWidgets('an inspection that fails says why, and the menu still works',
      (WidgetTester tester) async {
    var reloads = 0;
    await tester.pumpWidget(MaterialApp(
      home: DVDevMenu(
        shell: shell,
        branch: 'main',
        log: const <String>[],
        onReload: () async => reloads++,
        inspect: () async =>
            throw const DVDevClientInspectionException('HTTP 401'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 401'), findsOneWidget);
    await tester.tap(find.text('Reload'));
    expect(reloads, 1);
  });
}
