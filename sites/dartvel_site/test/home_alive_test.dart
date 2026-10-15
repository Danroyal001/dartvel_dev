// The home page shows Dartvel working rather than describing it, and every
// claim on it is one the repository can back.
//
// The hero's demo is real Dartvel code running on the page, and the code it
// prints is checked against the code that runs, so the two cannot drift. The
// bands that tell the product story and show proof hold no app this project
// cannot point at and no number nobody measured: an earlier draft listed five
// "live apps" with descriptions nobody had written down anywhere, and a
// figure of 5 for them.
import 'dart:io';

import 'package:dartvel_site/components/hero_demo.dart' show kHeroDemoSource;
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home page's source with comment lines left out.
String home() => File('lib/pages/index.dart')
    .readAsLinesSync()
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Future<void> pumpDemo(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: Center(child: HeroDemo())),
  ));
}

void main() {
  group('the hero demo', () {
    testWidgets('derived signals follow the quantity', (WidgetTester tester) async {
      await pumpDemo(tester);
      expect(find.text('\$12'), findsOneWidget);
      expect(find.text('Free delivery'), findsNothing);

      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Add one'));
        await tester.pump();
      }
      expect(find.text('5'), findsOneWidget);
      expect(find.text('\$60'), findsOneWidget);
      expect(find.text('Free delivery'), findsOneWidget,
          reason: 'total > 50 is a signal and should have turned true');
    });

    testWidgets('the quantity never goes below one', (WidgetTester tester) async {
      await pumpDemo(tester);
      await tester.tap(find.byTooltip('Remove one'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('\$12'), findsOneWidget);
    });

    testWidgets('both buttons have a name for every input', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpDemo(tester);
      expect(find.bySemanticsLabel('Add one'), findsWidgets);
      expect(find.bySemanticsLabel('Remove one'), findsWidgets);
      handle.dispose();
    });

    test('the code it prints is the code it runs', () {
      final String source =
          File('lib/components/hero_demo.dart').readAsStringSync();
      final int start = source.indexOf('Widget _heroDemo(');
      expect(start, isNonNegative);
      final String body = source.substring(start);
      for (final String line in kHeroDemoSource) {
        if (line.trim().isEmpty || line.trimLeft().startsWith('//')) continue;
        expect(body, contains(line.trim()),
            reason: 'the demo shows "$line" and does not run it');
      }
    });
  });

  group('the home page', () {
    test('the hero is alive: a mesh behind it and a glow on the demo', () {
      final String source = home();
      expect(source, contains('mesh: '));
      expect(File('lib/components/hero_demo.dart').readAsStringSync(),
          contains('.hoverGlow('));
      expect(File('lib/components/site.dart').readAsStringSync(),
          contains('.meshGradient('));
    });

    test('the story names every surface, and the paid ones say so', () {
      final String source = home();
      final int at = source.indexOf("Eyebrow('ONE PROJECT')");
      expect(at, isNonNegative);
      final String story = source.substring(at, source.indexOf('Eyebrow(', at + 10));
      for (final String surface in <String>[
        "'Web'", "'Web server'", "'Phones'", "'Desktops'",
        "'Microcontrollers'", "'XR headsets'", "'Studio'",
      ]) {
        expect(story, contains(surface), reason: '$surface is missing');
      }
      expect('Cloud plan'.allMatches(story).length, greaterThanOrEqualTo(2),
          reason: 'MCU and XR are paid targets');
    });

    test('names no app this repository cannot point at', () {
      final String source = home();
      for (final String name in <String>[
        'Wahala', 'EatingToday', 'Elena', 'Dartvel VPN', 'Authenticator',
      ]) {
        expect(source, isNot(contains(name)));
      }
    });

    test('every measured figure is in the measurement it came from', () {
      final String measured =
          File('../../docs/web-performance.md').readAsStringSync();
      final RegExp figure = RegExp(r"Figure\('(\d[^']*?)\s*(ms|KB)'");
      final List<Match> figures = figure.allMatches(home()).toList();
      expect(figures, isNotEmpty, reason: 'the proof band shows no measurement');
      for (final Match m in figures) {
        expect(measured, contains('${m[1]} ${m[2]}'),
            reason: '${m[1]} ${m[2]} is not in docs/web-performance.md');
      }
    });

    test('states the version and the spec counts from their one source', () {
      final String source = home();
      expect(source, isNot(matches(RegExp(r"'0\.\d+\.\d+'"))),
          reason: 'a version typed into a sentence goes stale');
      expect(source, isNot(matches(RegExp(r"Stat\('\d+', 'sections"))));
      expect(source, contains('kDartvelVersion'));
    });

    test('does not tell an Expo user there is no hosted build service', () {
      expect(home(), isNot(contains('There is no hosted build service')));
    });

    test('draws its terminal and cards with Dartvel primitives', () {
      final String source = home();
      for (final String raw in <String>[
        'Container(', ' Text(', 'Padding(', 'SizedBox(', 'Row(', 'Column(',
      ]) {
        expect(source, isNot(contains(raw)), reason: '$raw in application code');
      }
    });
  });
}
