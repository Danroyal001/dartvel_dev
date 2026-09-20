// Studio could not tell you what the application is made of.
//
// A module is a whole Dartvel application mounted inside another, and Studio
// had no section for them: you could see a module's pages in the Site map
// with no way to learn which module they came from, where it was mounted, or
// that a declared module had failed to mount at all. The owner's ask is the
// wider one -- a section for modules, importing one from anywhere, and a
// public marketplace for them later.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The graph the build writes beside Studio, as the section reads it.
Map<String, Object?> graph({List<Map<String, Object?>>? modules}) =>
    <String, Object?>{
      'graphVersion': 2,
      'models': const <Object?>[],
      'routes': const <Object?>[],
      'functions': const <Object?>[],
      'jobs': const <Object?>[],
      'modules': modules ?? const <Object?>[],
    };

const Map<String, Object?> notes = <String, Object?>{
  'id': 'notes',
  'package': 'notes_module',
  'mount': '/notes',
  'source': 'modules/notes',
  'deployment': 'embedded',
  'mounted': true,
  'pages': 3,
  'data': 'shared',
  'version': '1.2.0',
};

const Map<String, Object?> broken = <String, Object?>{
  'id': 'billing',
  'package': 'billing_module',
  'mount': '/billing',
  'source': 'modules/billing',
  'deployment': 'embedded',
  'mounted': false,
  'pages': 0,
  'data': 'shared',
  'problems': <String>['No Dartvel project at modules/billing'],
};

Future<void> open(WidgetTester tester, Map<String, Object?> manifest) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Material(
      child: DVStudioModulesSection(manifest: () async => manifest),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it names each mounted module, where it is and what it brings',
      (WidgetTester tester) async {
    await open(tester, graph(modules: <Map<String, Object?>>[notes]));

    expect(find.text('notes'), findsOneWidget);
    expect(find.text('/notes'), findsOneWidget);
    expect(find.textContaining('modules/notes'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets);
  });

  testWidgets('a module that failed to mount says so, with the reason',
      (WidgetTester tester) async {
    // The whole reason this is in the graph. A declaration the build could
    // not honour left no trace anywhere an operator looks, so an application
    // shipped without a section and nobody found out until a customer did.
    await open(tester, graph(modules: <Map<String, Object?>>[notes, broken]));

    expect(find.text('Not mounted'), findsOneWidget);
    expect(find.textContaining('No Dartvel project at modules/billing'),
        findsOneWidget);
  });

  testWidgets('it says how to add one, and what a module is',
      (WidgetTester tester) async {
    await open(tester, graph());

    expect(find.textContaining('No modules'), findsOneWidget);
    // Importing from anywhere: a path beside the project, a package from
    // pub, or a git repository. Studio shows the declaration to paste,
    // because a build reads pubspec.yaml and a panel that wrote it behind
    // your back would be editing a file you version.
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-module-add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('dartvel:'), findsWidgets);
    expect(find.textContaining('git:'), findsWidgets);
  });

  testWidgets('the marketplace is named and honestly marked as not open',
      (WidgetTester tester) async {
    await open(tester, graph());

    expect(find.textContaining('Marketplace'), findsWidgets);
    expect(find.textContaining('not open yet'), findsWidgets);
  });
}
