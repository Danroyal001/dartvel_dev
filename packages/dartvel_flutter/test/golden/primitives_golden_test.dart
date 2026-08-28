// Golden tests for the primitives, which the spec calls first-class and which
// this repository had none of. `dartvel test golden` looks for this directory
// and, until now, found nothing to run.
//
// Chosen to cover what actually broke this session rather than to photograph
// the widget gallery:
//
//   - a link outside Material, which threw "No Material widget found" before
//     its first frame on every page without a Scaffold;
//   - a link's focus ring, whose only guard had been an assertion that
//     InkWell.focusColor was non-null -- a property that stayed correct
//     through a widget that could not build at all;
//   - a page under the Cupertino shell, where a form input threw for the same
//     reason and every Apple platform rendered nothing.
//
// A golden fails on any visual change, so each of those becomes a picture that
// differs rather than an exception nobody sees until a device runs it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A fixed-size surface, so a golden records the widget and not the window.
Widget frame(Widget child, {Size size = const Size(360, 120)}) => Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: child,
      ),
    );

GoRouter routerFor(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => subject,
        ),
        GoRoute(
          path: '/docs',
          builder: (BuildContext context, GoRouterState state) =>
              const SizedBox.shrink(),
        ),
      ],
    );

void main() {
  testWidgets('a link outside Material', (WidgetTester tester) async {
    // No MaterialApp, no Scaffold, no Material. The tree that used to throw.
    final GoRouter router = routerFor(frame(
      const Center(
        child: DVNavLink(
          to: DVRouteTarget('/docs'),
          child: DVText('Documentation'),
        ),
      ),
    ));
    DVNavigation.attach(router);

    await tester.pumpWidget(WidgetsApp.router(
      routerConfig: router,
      color: const Color(0xFFFFFFFF),
      builder: (BuildContext context, Widget? child) => DefaultTextStyle(
        style: const TextStyle(fontSize: 16, color: Color(0xFF111111)),
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DVNavLink),
      matchesGoldenFile('goldens/nav_link_bare.png'),
    );
  });

  testWidgets('a focused link shows its focus ring',
      (WidgetTester tester) async {
    // Inside a Scaffold, which is what DVPageShell builds for a real page:
    // Material for the ink, a DefaultTextStyle for the label, and the
    // Navigator's Overlay that a link's preview needs.
    final GoRouter router = routerFor(Scaffold(
      body: frame(
        const Center(
          child: DVNavLink(
            to: DVRouteTarget('/docs'),
            autofocus: true,
            child: DVText('Documentation'),
          ),
        ),
      ),
    ));
    DVNavigation.attach(router);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Tab, rather than relying on autofocus. FocusableActionDetector paints
    // the highlight only in keyboard traversal mode, so an autofocused link
    // holds focus and shows no ring -- correct behaviour, and a golden taken
    // that way would have recorded an unfocused-looking link as proof that
    // focus is visible.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    // The first version of this golden had no Scaffold. A bare MaterialApp
    // supplies no DefaultTextStyle -- Scaffold does -- so it recorded
    // Flutter's red-on-yellow "no text style" marker and would have enshrined
    // that as the correct appearance of a focused link.
    //
    // The check the old assertion could not make: focus has to be visible,
    // not merely configured.
    await expectLater(
      find.byType(DVNavLink),
      matchesGoldenFile('goldens/nav_link_focused.png'),
    );
  });

  testWidgets('a form input under the Cupertino shell',
      (WidgetTester tester) async {
    // The shell Apple platforms get. A TextField here threw "No Material
    // widget found" until the shell supplied a transparent Material.
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Settings', showAppBar: true),
        // ignore: prefer_const_constructors
        child: DVText('Email').modifier(DVModifier().input(label: 'Email')),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DVPageShell),
      matchesGoldenFile('goldens/cupertino_shell_input.png'),
    );
  });
}
