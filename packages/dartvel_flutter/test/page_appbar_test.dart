// Whether a page shows an app bar.
//
// showAppBar was ignored whenever a title existed: the condition read
// `spec.showAppBar || spec.title != null`, and every page has a title because
// the title is what the browser tab and the SEO head use. So `showAppBar:
// false` produced a bar anyway, and the dartvel.dev site shipped with a grey
// strip above its own header.
//
// The title and the bar are different things. One names the document; the
// other is a piece of furniture the page may not want.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(DVPageScaffoldSpec spec, {TargetPlatform? platform}) => MaterialApp(
      theme: ThemeData(platform: platform ?? TargetPlatform.linux),
      home: DVPageShell(spec: spec, child: const DVText('content')),
    );

void main() {
  group('Material', () {
    testWidgets('showAppBar false means no bar, title or not',
        (WidgetTester tester) async {
      await tester.pumpWidget(host(const DVPageScaffoldSpec(
        title: 'Dartvel — Flutter, full stack',
        showAppBar: false,
      )));

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('showAppBar true shows the title in the bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(host(const DVPageScaffoldSpec(
        title: 'Settings',
        showAppBar: true,
      )));

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('showAppBar true with no title still shows a bar',
        (WidgetTester tester) async {
      // A bar with no title is a legitimate thing to ask for; it carries the
      // back button.
      await tester.pumpWidget(host(const DVPageScaffoldSpec(showAppBar: true)));

      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('Cupertino', () {
    testWidgets('the same rule applies', (WidgetTester tester) async {
      // The condition was duplicated in both branches, so the bug was too.
      await tester.pumpWidget(host(
        const DVPageScaffoldSpec(title: 'Dartvel', showAppBar: false),
        platform: TargetPlatform.iOS,
      ));

      expect(find.byType(CupertinoNavigationBar), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('and a requested bar still appears',
        (WidgetTester tester) async {
      await tester.pumpWidget(host(
        const DVPageScaffoldSpec(title: 'Dartvel', showAppBar: true),
        platform: TargetPlatform.iOS,
      ));

      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    });
  });
}
