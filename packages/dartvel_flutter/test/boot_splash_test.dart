// The splash with its loading bar on every platform, not only the web.
//
// On a device the launch screen the platform draws stays up until Flutter's
// first frame, and nothing can move on it. The application's boot steps run
// before that frame, so a slow boot was a still picture with no sign of
// progress. dvRunApplication now draws the application's own splash -- the
// same colour and picture as the launch screen -- with the loading bar along
// the top, filled as the boot steps finish, and then the application.
import 'dart:async';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart' show DVEntry;
import 'package:dartvel_core/framework.dart' show DVBootStep;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const DVStudioSplash splash = DVStudioSplash(
  color: Color(0xFF112233),
  darkColor: Color(0xFF000000),
  progressColor: Color(0xFFFF0000),
);

double barValue(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .value!;

void main() {
  tearDown(dvResetApplicationEntryForTest);

  testWidgets('the splash shows while the boot steps run, its bar filling '
      'as each finishes, then the application', (WidgetTester tester) async {
    final Completer<void> first = Completer<void>();
    final Completer<void> second = Completer<void>();
    unawaited(dvRunApplication(
      const <String>[],
      splash: splash,
      root: () => const Directionality(
          textDirection: .ltr, child: DVText('Home')),
      boot: <DVBootStep>[
        DVBootStep(run: (_) => first.future),
        DVBootStep(run: (_) => second.future),
      ],
    ));
    await tester.pump();
    expect(find.byType(DVStudioSplashView), findsOneWidget);
    expect(barValue(tester), 0);
    expect(
      tester.widget<ColoredBox>(find.descendant(
          of: find.byType(DVStudioSplashView),
          matching: find.byType(ColoredBox)).first).color,
      const Color(0xFF112233),
    );

    first.complete();
    // The step ends during this pump; the bar shows it on the next frame.
    await tester.pump();
    await tester.pump();
    // Two steps and the application's first frame: a third each.
    expect(barValue(tester), closeTo(1 / 3, 0.001));
    expect(tester.getSemantics(find.byType(DVStudioSplashView)).value, '33%');

    second.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(DVStudioSplashView), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a splash with no loading bar is not drawn: the launch screen '
      'stays until the first frame, as before', (WidgetTester tester) async {
    final Completer<void> step = Completer<void>();
    unawaited(dvRunApplication(
      const <String>[],
      splash: const DVStudioSplash(
          color: Color(0xFF112233), darkColor: Color(0xFF000000)),
      root: () => const Directionality(
          textDirection: .ltr, child: DVText('Home')),
      boot: <DVBootStep>[DVBootStep(run: (_) => step.future)],
    ));
    await tester.pump();
    expect(find.byType(DVStudioSplashView), findsNothing);
    step.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('an embedded entry draws no splash: the host shows its own',
      (WidgetTester tester) async {
    final Completer<void> step = Completer<void>();
    unawaited(dvRunApplication(
      const <String>[],
      splash: splash,
      entry: const DVEntry.embedded('checkout'),
      root: () => const Directionality(
          textDirection: .ltr, child: DVText('Checkout')),
      boot: <DVBootStep>[DVBootStep(run: (_) => step.future)],
    ));
    await tester.pump();
    expect(find.byType(DVStudioSplashView), findsNothing);
    step.complete();
  });

  testWidgets('the splash draws a picture handed over as bytes',
      (WidgetTester tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: .ltr,
      child: DVStudioSplashView(DVStudioSplash(
        color: const Color(0xFFFFFFFF),
        darkColor: const Color(0xFF000000),
        imageBytes: kTransparentPng,
      )),
    ));
    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
  });
}

/// A 1x1 transparent PNG.
final Uint8List kTransparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
