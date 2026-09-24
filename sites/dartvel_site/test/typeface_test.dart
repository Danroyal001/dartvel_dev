// The site's typeface is one somebody chose.
//
// Flutter's default is Roboto, and a marketing site set in the framework's
// default font tells a reader that nobody made a decision. The same goes for
// the code blocks: RobotoMono is the default mono to match the default sans.
//
// This checks the theme the pages are actually given rather than a copy of
// it, and checks that the families it names are bundled, because a family
// name with no font behind it falls back to the default silently. That is
// the failure worth testing: the page still renders, in Roboto, and looks
// fine to whoever changed it.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartvel_site/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Every font family the pubspec bundles, and the files behind it.
Map<String, List<String>> bundledFonts() {
  final Object? doc = loadYaml(File('pubspec.yaml').readAsStringSync());
  final Object? flutter = (doc! as Map)['flutter'];
  final Object? fonts = flutter is Map ? flutter['fonts'] : null;
  return <String, List<String>>{
    for (final Object? entry in fonts is List ? fonts : const <Object?>[])
      if (entry is Map)
        '${entry['family']}': <String>[
          for (final Object? asset
              in entry['fonts'] is List ? entry['fonts']! as List : const [])
            if (asset is Map) '${asset['asset']}',
        ],
  };
}

/// The families the site's own code names, from the theme and from every
/// fontFamily written in a page or a component.
Set<String> namedFamilies() {
  final Set<String> named = <String>{};
  for (final Brightness brightness in Brightness.values) {
    final String? family = dartvelSiteTheme(brightness).textTheme.bodyMedium?.fontFamily;
    if (family != null) named.add(family);
  }
  for (final String dir in <String>['lib/pages', 'lib/components']) {
    for (final FileSystemEntity entity
        in Directory(dir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final RegExpMatch match in RegExp(r"""fontFamily\(?:? ?'([^']+)'""")
          .allMatches(entity.readAsStringSync())) {
        named.add(match.group(1)!);
      }
    }
  }
  return named;
}

/// Fonts nobody should be reading this site in.
const Set<String> kDefaults = <String>{
  'Roboto',
  'RobotoMono',
  'Roboto Mono',
  'Inter',
  'Arial',
  'Helvetica',
  'Open Sans',
  'Segoe UI',
  '.SF Pro Text',
};

void main() {
  weightTests();

  test('the theme names a typeface, and it is not the default one', () {
    for (final Brightness brightness in Brightness.values) {
      final ThemeData theme = dartvelSiteTheme(brightness);
      final String? family = theme.textTheme.bodyMedium?.fontFamily;
      expect(family, isNotNull,
          reason: 'the $brightness theme sets no fontFamily, so every page '
              'renders in Flutter\'s default');
      expect(kDefaults, isNot(contains(family)), reason: '$brightness');
    }
  });

  test('nothing on the site asks for a default font by name', () {
    final Set<String> named = namedFamilies();
    expect(named, isNotEmpty);
    expect(named.intersection(kDefaults), isEmpty,
        reason: 'these families are the ones a reader sees when nobody chose');
  });

  test('the weight the site asks for is the weight it gets', () async {
    // Both faces are variable fonts: one file, one wght axis. If the engine
    // does not drive that axis from fontWeight, every heading, label and
    // body line renders at the file's default instance and the page still
    // looks finished. That is the failure this is here for, and it is
    // invisible in a screenshot unless you already know.
    //
    // The fonts are loaded from disk first. `flutter test` ships a test font
    // for everything by default, and an earlier version of this measured
    // that: every family, including one that does not exist, laid out to
    // exactly 864 points, so the check passed or failed on the harness
    // rather than on the typeface.
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final MapEntry<String, List<String>> entry in bundledFonts().entries) {
      final FontLoader loader = FontLoader(entry.key);
      for (final String asset in entry.value) {
        loader.addFont(Future<ByteData>.value(
          ByteData.sublistView(File(asset).readAsBytesSync()),
        ));
      }
      await loader.load();
    }

    // Ink rather than width. Width works for Manrope and proves nothing for
    // JetBrains Mono: a monospaced face has the same advance at every
    // weight by definition, so the first version of this reported the mono
    // as broken when it was doing exactly what a mono does. What does
    // change is how much of the glyph is painted.
    Future<int> inkAt(String family, FontWeight weight) async {
      const Size size = Size(900, 120);
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder, Offset.zero & size);
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: 'Ship a Flutter app',
          style: TextStyle(
            fontFamily: family,
            fontSize: 64,
            fontWeight: weight,
            color: const Color(0xFF000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset.zero);
      painter.dispose();
      final ui.Image image = await recorder
          .endRecording()
          .toImage(size.width.round(), size.height.round());
      final ByteData? bytes =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      var ink = 0;
      for (int i = 3; i < bytes!.lengthInBytes; i += 4) {
        ink += bytes.getUint8(i);
      }
      return ink;
    }

    for (final String family in <String>['Manrope', 'JetBrainsMono']) {
      final int light = await inkAt(family, FontWeight.w300);
      final int heavy = await inkAt(family, FontWeight.w700);
      expect(heavy, greaterThan(light),
          reason: '$family paints the same at w300 and w700, so the wght '
              'axis is not being driven and every weight on the site is the '
              "file's default one");
    }
  });

  test('every family the site names is bundled, with a file that exists', () {
    // A family name with no font behind it falls back to the default without
    // saying so: the page still renders and still looks wrong.
    final Map<String, List<String>> bundled = bundledFonts();
    for (final String family in namedFamilies()) {
      expect(bundled.keys, contains(family),
          reason: '$family is named and not declared under flutter.fonts');
      expect(bundled[family], isNotEmpty, reason: family);
      for (final String asset in bundled[family]!) {
        expect(File(asset).existsSync(), isTrue,
            reason: '$family names $asset and it is not there');
      }
    }
  });
}

// Weight and slant, which are the other half of choosing a typeface.
void weightTests() {
  /// Every fontWeight the site's own code asks for.
  Set<String> weightsNamed() {
    final Set<String> found = <String>{};
    for (final String dir in <String>['lib/pages', 'lib/components']) {
      for (final FileSystemEntity entity
          in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final RegExpMatch match
            in RegExp(r'FontWeight\.(\w+)').allMatches(entity.readAsStringSync())) {
          found.add(match.group(1)!);
        }
      }
    }
    return found;
  }

  test('nothing is set heavier than bold', () {
    // w800 and w900 at a headline size read as shouting, and at body size
    // they read as a mistake. Emphasis is one step up from the body weight.
    expect(weightsNamed().intersection(<String>{'w800', 'w900', 'black', 'extraBold'}),
        isEmpty);
  });

  test('nothing is set lighter than regular at body size', () {
    expect(weightsNamed().intersection(<String>{'w100', 'w200', 'w300', 'thin', 'extraLight', 'light'}),
        isEmpty);
  });

  test('nothing on the site is italic', () {
    // Emphasis is a weight step. An italic in a UI face is a second
    // typeface nobody chose.
    for (final String dir in <String>['lib/pages', 'lib/components']) {
      for (final FileSystemEntity entity
          in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        expect(entity.readAsStringSync(), isNot(contains('FontStyle.italic')),
            reason: entity.path);
      }
    }
  });
}
