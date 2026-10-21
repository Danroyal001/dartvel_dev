// DV.Platform.fonts: the fonts installed on the machine, and using one.
//
// Two silent failures matter. A list that comes back empty with no word on
// why reads as "this machine has no fonts" when the truth is "this browser
// will not say" -- so an empty list always carries its reason. And a font
// that "loaded" but still renders in the fallback face looks like a working
// picker until somebody reads the slides -- so loading is checked by
// measuring the text, not by trusting the call returned.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String dejavu = '/usr/share/fonts/truetype/dejavu';

Map<String, Object?> face(String family, String style,
        {int weight = 400, bool italic = false, int width = 5, String? path, int index = 0}) =>
    <String, Object?>{
      'family': family,
      'style': style,
      'weight': weight,
      'italic': italic,
      'width': width,
      'path': path ?? '/fonts/$family-$style.ttf',
      'index': index,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<Object?> reads = <Object?>[];

  setUp(() {
    reads.clear();
    DVSystemFonts.debugReset();
  });
  tearDown(() {
    DVNativeBridge.unregister('fonts.faces');
    DVNativeBridge.unregister('fonts.read');
    DVSystemFonts.debugReset();
  });

  group('families', () {
    test('one name per family, sorted, from every face the platform lists', () async {
      DVNativeBridge.register('fonts.faces', (Object? _) => <String, Object?>{
            'faces': <Object?>[
              face('Liberation Serif', 'Regular'),
              face('DejaVu Sans', 'Bold', weight: 700),
              face('DejaVu Sans', 'Book'),
              face('cantarell', 'Regular'),
            ],
          });

      final DVFontFamilies families = await DV.Platform.fonts.families();

      expect(families, <String>['cantarell', 'DejaVu Sans', 'Liberation Serif']);
      expect(families.reason, isNull);
    });

    test('an empty list says why', () async {
      DVNativeBridge.register('fonts.faces', (Object? _) => <String, Object?>{
            'faces': const <Object?>[],
            'reason': 'The person declined to let this page see the installed fonts.',
          });

      final DVFontFamilies families = await DV.Platform.fonts.families();

      expect(families, isEmpty);
      expect(families.reason, contains('declined'));
    });

    test('a platform with no font binding still says why', () async {
      final DVFontFamilies families = await DV.Platform.fonts.families();

      expect(families, isEmpty);
      expect(families.reason, isNotNull);
      expect(families.reason!.length, greaterThan(30));
    });

    test('a binding that fails is a reason, not an exception', () async {
      DVNativeBridge.register('fonts.faces', (Object? _) => throw StateError('fontconfig gone'));

      final DVFontFamilies families = await DV.Platform.fonts.families();

      expect(families, isEmpty);
      expect(families.reason, contains('fontconfig gone'));
    });
  });

  test('faces of one family, matched without regard to case', () async {
    DVNativeBridge.register('fonts.faces', (Object? _) => <String, Object?>{
          'faces': <Object?>[
            face('DejaVu Sans', 'Book'),
            face('DejaVu Sans', 'Bold Oblique', weight: 700, italic: true),
            face('DejaVu Serif', 'Book'),
          ],
        });

    final List<DVSystemFontFace> faces = await DV.Platform.fonts.faces(family: 'dejavu sans');

    expect(faces.map((DVSystemFontFace f) => f.style), <String>['Book', 'Bold Oblique']);
    expect(faces.last.weight, FontWeight.w700);
    expect(faces.last.italic, isTrue);
  });

  group('load', () {
    final bool haveDejaVu = File('$dejavu/DejaVuSans.ttf').existsSync();
    final String? skip = haveDejaVu ? null : 'DejaVu fonts are not installed here';

    void bindDejaVu() {
      DVNativeBridge.register('fonts.faces', (Object? _) => <String, Object?>{
            'faces': <Object?>[
              face('DejaVu Sans', 'Book', path: '$dejavu/DejaVuSans.ttf'),
              // Same weight and slant as Book, narrower: the engine can only
              // tell faces apart by weight and slant, so one of the two has
              // to win, and it is the normal width.
              face('DejaVu Sans', 'Condensed', width: 4, path: '$dejavu/DejaVuSansCondensed.ttf'),
              face('DejaVu Sans', 'Bold', weight: 700, path: '$dejavu/DejaVuSans-Bold.ttf'),
            ],
          });
      DVNativeBridge.register('fonts.read', (Object? arguments) {
        reads.add(arguments);
        final String path = (arguments! as Map<Object?, Object?>)['path']! as String;
        return Uint8List.fromList(File(path).readAsBytesSync());
      });
    }

    double widthOf(WidgetTester tester, String family) {
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.text('iiiiiiiiii'));
      expect(paragraph.text.style?.fontFamily, family);
      return paragraph.size.width;
    }

    testWidgets('text renders in the loaded font, not the fallback', (WidgetTester tester) async {
      bindDejaVu();
      Widget sample(String family) => Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: Text('iiiiiiiiii', style: TextStyle(fontFamily: family, fontSize: 20))),
          );

      // Not loaded: the test engine has no system fonts, so this is the
      // fallback face, in which every glyph is a square as wide as the size.
      await tester.pumpWidget(sample('DejaVu Sans'));
      final double fallback = widthOf(tester, 'DejaVu Sans');
      expect(fallback, 200);

      final String family = await tester.runAsync(() => DV.Platform.fonts.load('dejavu sans')) ?? '';
      expect(family, 'DejaVu Sans');
      await tester.pumpWidget(sample(family));
      await tester.pump();

      // DejaVu's "i" is a fraction of its em.
      expect(widthOf(tester, family), lessThan(fallback / 2));
    }, skip: skip != null);

    testWidgets('one face per weight and slant, the normal width', (WidgetTester tester) async {
      bindDejaVu();
      await tester.runAsync(() => DV.Platform.fonts.load('DejaVu Sans'));

      final List<String> paths = <String>[
        for (final Object? read in reads) (read! as Map<Object?, Object?>)['path']! as String,
      ];
      expect(paths, containsAll(<String>['$dejavu/DejaVuSans.ttf', '$dejavu/DejaVuSans-Bold.ttf']));
      expect(paths, isNot(contains('$dejavu/DejaVuSansCondensed.ttf')));
    }, skip: skip != null);

    testWidgets('a family loaded once is not read again', (WidgetTester tester) async {
      bindDejaVu();
      await tester.runAsync(() => DV.Platform.fonts.load('DejaVu Sans'));
      final int first = reads.length;
      await tester.runAsync(() => DV.Platform.fonts.load('DejaVu Sans'));
      expect(reads.length, first);
      expect(DV.Platform.fonts.isLoaded('DejaVu Sans'), isTrue);
    }, skip: skip != null);
  });

  test('loading a family the machine does not have is refused, with the reason', () async {
    DVNativeBridge.register('fonts.faces', (Object? _) => <String, Object?>{
          'faces': <Object?>[face('DejaVu Sans', 'Book')],
        });

    await expectLater(
      DV.Platform.fonts.load('Comic Sans MS'),
      throwsA(isA<DVSystemFontUnavailable>()
          .having((DVSystemFontUnavailable e) => e.family, 'family', 'Comic Sans MS')
          .having((DVSystemFontUnavailable e) => e.reason, 'reason', contains('not installed'))),
    );
  });

  test('loading where nothing can be read is refused with the platform\'s reason', () async {
    DVNativeBridge.register('fonts.faces', (Object? _) => <String, Object?>{
          'faces': const <Object?>[],
          'reason': 'This browser has no Local Font Access API.',
        });

    await expectLater(
      DV.Platform.fonts.load('DejaVu Sans'),
      throwsA(isA<DVSystemFontUnavailable>()
          .having((DVSystemFontUnavailable e) => e.reason, 'reason', contains('Local Font Access'))),
    );
  });
}
