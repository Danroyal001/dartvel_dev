// DV.Platform.fonts on Linux, against this machine's real fontconfig.
//
// The oracle is fontconfig's own command-line tool: `fc-list` with the same
// pattern -- scalable TrueType and CFF (OpenType) faces -- must print the same
// families the binding lists. A list that parsed and named fonts nobody has,
// or quietly dropped half of them, is what this catches.
//
// Live: needs libfontconfig and fc-list. Skipped without them. Under
// `flutter test` the process's fontconfig is the test runner's own hermetic
// configuration (FONTCONFIG_FILE, Roboto and Material Icons), and fc-list,
// started from the test, reads the same one -- so the comparison is like for
// like. The machine's full list is checked by running an app (README).
@TestOn('linux')
library;

import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_fonts_ffi.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> fcListFamilies() {
  final Set<String> families = <String>{};
  for (final String format in <String>['TrueType', 'CFF']) {
    final ProcessResult result = Process.runSync('fc-list', <String>[
      '--format',
      '%{index}|%{family[0]}\n',
      ':fontformat=$format',
    ]);
    for (final String line in (result.stdout as String).split('\n')) {
      final int bar = line.indexOf('|');
      if (bar < 0) continue;
      // A variable font's named instances carry the instance in the high
      // bits of the index; the binding lists the file once.
      if ((int.tryParse(line.substring(0, bar)) ?? 0) >> 16 != 0) continue;
      final String family = line.substring(bar + 1).trim();
      if (family.isNotEmpty) families.add(family);
    }
  }
  return families;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? skip;
  try {
    if (Process.runSync('fc-list', <String>['--version']).exitCode != 0) skip = 'fc-list does not run';
  } on ProcessException {
    skip = 'no fc-list on this machine';
  }

  setUp(() {
    DVSystemFonts.debugReset();
    expect(DVLinuxFonts.register(), isTrue, reason: 'libfontconfig did not open');
  });
  tearDown(() {
    DVNativeBridge.unregister('fonts.faces');
    DVNativeBridge.unregister('fonts.read');
    DVSystemFonts.debugReset();
  });

  test('lists exactly the families fc-list lists', () async {
    final Set<String> expected = fcListFamilies();
    expect(expected, isNotEmpty, reason: 'this machine has no scalable fonts to compare');

    final DVFontFamilies families = await DV.Platform.fonts.families();

    expect(families.reason, isNull);
    expect(families.toSet(), expected);
  }, skip: skip);

  test('each face carries a file that exists and a weight on the OpenType scale', () async {
    final List<DVSystemFontFace> faces = await DV.Platform.fonts.faces();
    expect(faces, isNotEmpty);
    for (final DVSystemFontFace face in faces) {
      expect(File(face.path!).existsSync(), isTrue, reason: '$face');
    }
    final List<DVSystemFontFace> bold = await DV.Platform.fonts.faces(family: 'DejaVu Sans');
    if (bold.isNotEmpty) {
      expect(bold.map((DVSystemFontFace f) => f.weight), contains(FontWeight.w700));
      expect(bold.map((DVSystemFontFace f) => f.italic), contains(true));
    }
  }, skip: skip);

  testWidgets('a listed family loads into the engine and text renders in it', (WidgetTester tester) async {
    final DVFontFamilies families = (await tester.runAsync(() => DV.Platform.fonts.families()))!;
    // A family with Latin letters: an icon font draws no "i" and would fall
    // back whatever happened.
    final String family = <String>['DejaVu Sans', 'Liberation Sans', 'Roboto']
        .firstWhere(families.contains, orElse: () => families.first);

    Widget sample(String name) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Text('iiiiiiiiii', style: TextStyle(fontFamily: name, fontSize: 20))),
        );
    double width() => tester.renderObject<RenderParagraph>(find.text('iiiiiiiiii')).size.width;

    final String loaded = (await tester.runAsync(() => DV.Platform.fonts.load(family)))!;
    await tester.pumpWidget(sample(loaded));
    await tester.pump();

    expect(loaded, family);
    expect(DV.Platform.fonts.isLoaded(family), isTrue);
    // The test runner's fallback draws every glyph as a square one em wide,
    // so ten of them at 20 are 200 wide. A real face's "i" is a fraction.
    expect(width(), lessThan(150), reason: '$family rendered in the fallback face');
  }, skip: skip != null);

  test('a file fontconfig did not list is not read', () async {
    await expectLater(
      DVNativeBridge.invoke<Object?>('fonts.read', <String, Object?>{'path': '/etc/passwd'}),
      throwsArgumentError,
    );
  }, skip: skip);
}
