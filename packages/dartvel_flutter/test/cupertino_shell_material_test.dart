// A Dartvel primitive works the same on every platform, or it is not a
// primitive.
//
// On Apple platforms DVPageShell builds a CupertinoPageScaffold, which
// provides no Material. Material-based widgets assert one: DVModifier's text
// input is a TextField, and DVNavLink used to be an InkWell. Both threw "No
// Material widget found" before the first frame, so a page carrying a form or
// a link rendered nothing at all on macOS, iOS and tvOS while working
// everywhere else.
//
// The integration suite caught it only after the InkWell was removed, because
// the first Material widget in the tree is the one that throws and there were
// two.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpOn(
    WidgetTester tester,
    TargetPlatform platform,
    Widget child,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: platform),
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Title'),
        child: child,
      ),
    ));
    await tester.pumpAndSettle();
  }

  // Both Apple platforms, because the shell picks Cupertino on each and a fix
  // that only reached one would be worse than none.
  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  ]) {
    testWidgets('a text input builds under the $platform shell',
        (WidgetTester tester) async {
      // ignore: prefer_const_constructors
      await pumpOn(tester, platform,
          DVText('Email').modifier(DVModifier().input(label: 'Email')));

      expect(tester.takeException(), isNull,
          reason: 'a form input must build on $platform');
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a link builds under the $platform shell',
        (WidgetTester tester) async {
      await pumpOn(tester, platform, const DVNavLink(
        to: DVRouteTarget('/docs'),
        child: DVText('Docs'),
      ));

      expect(tester.takeException(), isNull,
          reason: 'a link must build on $platform');
      expect(find.text('Docs'), findsOneWidget);
    });

    testWidgets('the shell adds no visible surface on $platform',
        (WidgetTester tester) async {
      // Whatever supplies Material must not paint over the Cupertino
      // background, or every Apple page gains a white sheet.
      await pumpOn(tester, platform, const DVText('body text'));

      final Iterable<Material> materials =
          tester.widgetList<Material>(find.byType(Material));
      expect(materials, isNotEmpty,
          reason: 'something has to provide Material');
      expect(
        materials.every((Material m) => m.type == MaterialType.transparency),
        isTrue,
        reason: 'the shell must not paint its own surface on Cupertino',
      );
    });
  }
}
