// What a module's theme mode does once the application is running.
//
// The four modes -- inherit, extend, override, isolated -- were read from the
// parent's pubspec, carried into the generated registry and refused when a
// federated module declared one it could not honour. Then nothing happened: a
// module mounted `theme: override` rendered in the parent's colours exactly
// as an inheriting one did, which is the mode being decorative rather than
// wrong, and the kind of gap that survives because the screen looks fine.
//
// The parent's theme is its MaterialApp's, which is application code. A
// module's is whatever the module itself declares, so the mode is a rule for
// combining two things rather than a switch on one.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final ThemeData _parentTheme = ThemeData(
  colorScheme: const ColorScheme.light(primary: Color(0xFF112233)),
  visualDensity: VisualDensity.compact,
);

final ThemeData _moduleTheme = ThemeData(
  colorScheme: const ColorScheme.light(primary: Color(0xFFAABBCC)),
);

DVModule _mount(String theme, {bool declareTheme = true}) {
  dvResetModuleThemes();
  dvModuleRegistry.resetForTesting();
  final DVModule module = dvModuleRegistry.register(
    id: 'notes',
    mountPath: '/notes',
    config: <String, Object?>{'theme': theme},
  );
  if (declareTheme) module.useTheme(_moduleTheme);
  return module;
}

/// Renders a module page under a parent theme and reports what it saw.
Future<ThemeData> themeSeenBy(WidgetTester tester, DVModule module) async {
  late ThemeData seen;
  await tester.pumpWidget(MaterialApp(
    theme: _parentTheme,
    home: Builder(
      builder: (BuildContext context) => dvModuleTheme(
        context,
        module.id,
        Builder(builder: (BuildContext inner) {
          seen = Theme.of(inner);
          return const SizedBox.shrink();
        }),
      ),
    ),
  ));
  await tester.pump();
  return seen;
}

void main() {
  tearDown(() {
    dvModuleRegistry.resetForTesting();
    // The declared themes too: they live beside the registry rather than in
    // it, so clearing one leaves the other, and a module that declares no
    // theme would quietly pick up the last test's.
    dvResetModuleThemes();
  });

  group('the mode a module was mounted with', () {
    test('is read off the registration, and defaults to inherit', () {
      expect(_mount('override').themeMode, DVModuleThemeMode.override);
      expect(_mount('extend').themeMode, DVModuleThemeMode.extend);
      expect(_mount('isolated').themeMode, DVModuleThemeMode.isolated);
      expect(_mount('inherit').themeMode, DVModuleThemeMode.inherit);
      dvModuleRegistry.resetForTesting();
      expect(
        dvModuleRegistry.register(id: 'notes', mountPath: '/notes').themeMode,
        DVModuleThemeMode.inherit,
      );
    });

    test('a mode nobody recognises is refused, not treated as inherit', () {
      expect(() => _mount('inherit-ish').themeMode, throwsA(isA<StateError>()));
    });
  });

  group('what the module renders in', () {
    testWidgets('inherit is the parent, unchanged', (WidgetTester tester) async {
      final ThemeData seen = await themeSeenBy(tester, _mount('inherit'));

      expect(seen.colorScheme.primary, _parentTheme.colorScheme.primary);
      expect(seen.visualDensity, _parentTheme.visualDensity);
    });

    testWidgets('override is the module, and only the module',
        (WidgetTester tester) async {
      final ThemeData seen = await themeSeenBy(tester, _mount('override'));

      expect(seen.colorScheme.primary, _moduleTheme.colorScheme.primary);
      // Not the parent's density: override means the module's theme, not a
      // merge of the two.
      expect(seen.visualDensity, _moduleTheme.visualDensity);
    });

    testWidgets('extend keeps what the module did not say',
        (WidgetTester tester) async {
      final ThemeData seen = await themeSeenBy(tester, _mount('extend'));

      expect(seen.colorScheme.primary, _moduleTheme.colorScheme.primary,
          reason: 'the module said this');
      expect(seen.visualDensity, _parentTheme.visualDensity,
          reason: 'the module said nothing about this, so the parent stands');
    });

    testWidgets('isolated leaves no path back to the parent',
        (WidgetTester tester) async {
      // The same wrap as override, deliberately: Theme replaces what
      // descendants see, so neither leaks the parent -- not even through the
      // fields the module left at their defaults. What this asserts is that
      // property, not a difference from override that does not exist.
      final ThemeData seen = await themeSeenBy(tester, _mount('isolated'));

      expect(seen.colorScheme.primary, _moduleTheme.colorScheme.primary);
      expect(seen.visualDensity, isNot(_parentTheme.visualDensity));
    });

    testWidgets('a module that declared no theme keeps the parent, whatever '
        'the mode says', (WidgetTester tester) async {
      // The mode is the parent's declaration; the theme is the module's. A
      // parent can ask for override and get a module that has nothing to
      // override with, and rendering an unthemed default there would look
      // like the application had broken.
      final ThemeData seen = await themeSeenBy(
        tester,
        _mount('override', declareTheme: false),
      );

      expect(seen.colorScheme.primary, _parentTheme.colorScheme.primary);
    });
  });
}
