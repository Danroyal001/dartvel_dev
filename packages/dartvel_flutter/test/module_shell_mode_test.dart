// What a module's shell mode does once the application is running.
//
// Like the theme mode, it was read from the parent's pubspec, carried into
// the registry, checked against the deployment -- and then applied to
// nothing. A module mounted `shell: none` rendered inside the application's
// chrome exactly as an inheriting one did.
//
// The four modes are four different pictures on screen, and the difference is
// worth stating in one place: inherit is the application's chrome; extend is
// the module's chrome inside the application's; override is the module's
// instead of the page's; none is no chrome at all, which is what a kiosk
// screen or an embedded panel actually wants.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _chrome = Key('module-chrome');
const Key _page = Key('page-body');

DVModule _mount(String shell, {bool declareShell = true}) {
  dvModuleRegistry.resetForTesting();
  dvResetModuleShells();
  final DVModule module = dvModuleRegistry.register(
    id: 'notes',
    mountPath: '/notes',
    config: <String, Object?>{'shell': shell},
  );
  if (declareShell) {
    module.useShell((BuildContext context, Widget child) => Column(
          key: _chrome,
          children: <Widget>[const Text('Notes'), Expanded(child: child)],
        ));
  }
  return module;
}

/// A module page, wrapped the way the generated router wraps one.
Future<void> show(WidgetTester tester, DVModule module) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext context) => dvModuleShell(
        context,
        module.id,
        const DVPageShell(
          spec: DVPageScaffoldSpec(title: 'Notes', showAppBar: true),
          child: SizedBox(key: _page),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  tearDown(() {
    dvModuleRegistry.resetForTesting();
    dvResetModuleShells();
  });

  group('the mode a module was mounted with', () {
    test('is read off the registration, and defaults to inherit', () {
      expect(_mount('none').shellMode, DVModuleShellMode.none);
      expect(_mount('extend').shellMode, DVModuleShellMode.extend);
      expect(_mount('override').shellMode, DVModuleShellMode.override);
      expect(_mount('inherit').shellMode, DVModuleShellMode.inherit);
    });

    test('a mode nobody recognises is refused', () {
      expect(() => _mount('half').shellMode, throwsA(isA<StateError>()));
    });
  });

  group('what surrounds a module page', () {
    testWidgets('inherit is the page\'s own chrome and nothing added',
        (WidgetTester tester) async {
      await show(tester, _mount('inherit'));

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byKey(_chrome), findsNothing);
      expect(find.byKey(_page), findsOneWidget);
    });

    testWidgets('extend puts the module\'s chrome around the page, keeping the '
        'page\'s own', (WidgetTester tester) async {
      await show(tester, _mount('extend'));

      expect(find.byKey(_chrome), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget,
          reason: 'extend adds to the chrome, it does not replace it');
    });

    testWidgets('override replaces the page\'s chrome with the module\'s',
        (WidgetTester tester) async {
      await show(tester, _mount('override'));

      expect(find.byKey(_chrome), findsOneWidget);
      expect(find.byType(Scaffold), findsNothing,
          reason: 'override means instead of, not as well as');
      expect(find.byKey(_page), findsOneWidget,
          reason: 'the page is still rendered; only its chrome went');
    });

    testWidgets('none is the page and no chrome at all',
        (WidgetTester tester) async {
      await show(tester, _mount('none'));

      expect(find.byType(Scaffold), findsNothing);
      expect(find.byKey(_chrome), findsNothing);
      expect(find.byKey(_page), findsOneWidget);
    });

    testWidgets('a module that declared no shell still loses the page\'s under '
        'override', (WidgetTester tester) async {
      // Unlike a theme, an absent shell is a decision the parent can make on
      // its own: "this module has no chrome" needs nothing from the module.
      await show(tester, _mount('override', declareShell: false));

      expect(find.byType(Scaffold), findsNothing);
      expect(find.byKey(_page), findsOneWidget);
    });
  });
}
