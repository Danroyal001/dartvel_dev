// Studio shows the application's splash while it loads, never a blank page.
//
// The web page's splash -- the application's colour, its image and a loading
// bar -- is removed at Flutter's first frame. For Studio that first frame was
// an empty box: Studio's code is a deferred library fetched after the route
// opens, and the grant is asked again before anything is drawn. Between the
// two, a person who opened Studio looked at a white page. The generator hands
// Studio the splash the build writes, and Studio draws it until it is ready.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const DVStudioSplash _splash = DVStudioSplash(
  color: Color(0xFFFFF4E0),
  darkColor: Color(0xFF0A0D13),
  progressColor: Color(0xFF2F6BFF),
);

Color? _painted(WidgetTester tester) => tester
    .widget<ColoredBox>(find.descendant(
      of: find.byType(DVStudioSplashView),
      matching: find.byType(ColoredBox),
    ).first)
    .color;

void main() {
  testWidgets('while Studio\'s code loads, the application\'s splash is on '
      'screen', (WidgetTester tester) async {
    final Completer<void> loading = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: DVStudioDeferred(
        load: () => loading.future,
        splash: _splash,
        builder: (BuildContext context) => const Text('Studio'),
      ),
    ));
    await tester.pump();

    expect(find.byType(DVStudioSplashView), findsOneWidget);
    expect(_painted(tester), const Color(0xFFFFF4E0));
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: 'the loading bar the web splash had carries on');

    loading.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioSplashView), findsNothing);
    expect(find.text('Studio'), findsOneWidget);
  });

  testWidgets('on a device set to dark, the dark splash', (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const MaterialApp(home: DVStudioSplashView(_splash)));
    expect(_painted(tester), const Color(0xFF0A0D13));
  });

  testWidgets('while the grant is asked, a served Studio shows the splash '
      'the route was given', (WidgetTester tester) async {
    final Completer<DVStudioReply> access = Completer<DVStudioReply>();
    Future<DVStudioReply> send(String method, String path, {Object? body}) =>
        path == 'api/access'
            ? access.future
            : Future<DVStudioReply>.value(const DVStudioReply(404, null));
    await tester.pumpWidget(MaterialApp(
      home: DVStudioHost(
        splash: _splash,
        child: DVStudioApp(
          client: DVStudioClient(send),
          location: Uri.parse('https://shop.example/__studio'),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(DVStudioSplashView), findsOneWidget);
    access.complete(const DVStudioReply(200, <String, Object?>{'granted': false}));
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioSplashView), findsNothing);
  });
}
