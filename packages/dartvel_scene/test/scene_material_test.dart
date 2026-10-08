import 'dart:convert';

import 'package:dartvel_scene/dartvel_scene.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _json(Object value) => utf8.encode(jsonEncode(value));

void main() {
  group('DVSceneMaterialSpec.fromBytes', () {
    test('reads every field, in either colour spelling', () {
      final DVSceneMaterialSpec spec = DVSceneMaterialSpec.fromBytes(_json(<String, Object>{
        'baseColor': '#1F8A4C',
        'opacity': 0.5,
        'metallic': 0.25,
        'roughness': 0.9,
        'emissive': 0xFFCC00,
      }));
      expect(spec.baseColor, 0x1F8A4C);
      expect(spec.opacity, 0.5);
      expect(spec.metallic, 0.25);
      expect(spec.roughness, 0.9);
      expect(spec.emissive, 0xFFCC00);
    });

    test('an empty object is a plain white, non-metal, opaque surface', () {
      expect(DVSceneMaterialSpec.fromBytes(_json(<String, Object>{})), const DVSceneMaterialSpec());
    });

    test('a misspelt key fails and names the key, rather than rendering white', () {
      expect(
        () => DVSceneMaterialSpec.fromBytes(_json(<String, Object>{'basecolor': '#FF0000'})),
        throwsA(isA<DVSceneMaterialFormatException>().having((e) => e.field, 'field', 'basecolor')),
      );
    });

    test('a colour that does not parse fails', () {
      for (final Object bad in <Object>['red', '#FFF', '#GG0000', -1, 0x1000000]) {
        expect(
          () => DVSceneMaterialSpec.fromBytes(_json(<String, Object>{'baseColor': bad})),
          throwsA(isA<DVSceneMaterialFormatException>().having((e) => e.field, 'field', 'baseColor')),
          reason: '$bad',
        );
      }
    });

    test('a factor outside 0..1 fails', () {
      expect(
        () => DVSceneMaterialSpec.fromBytes(_json(<String, Object>{'roughness': 1.5})),
        throwsA(isA<DVSceneMaterialFormatException>().having((e) => e.field, 'field', 'roughness')),
      );
    });

    test('bytes that are not a JSON object fail', () {
      expect(() => DVSceneMaterialSpec.fromBytes(utf8.encode('not json')), throwsA(isA<DVSceneMaterialFormatException>()));
      expect(() => DVSceneMaterialSpec.fromBytes(_json(<int>[1, 2])), throwsA(isA<DVSceneMaterialFormatException>()));
    });

    test('channels splits 0xRRGGBB into 0..1 red, green, blue', () {
      expect(DVSceneMaterialSpec.channels(0xFF8000), <double>[1, 128 / 255, 0]);
    });
  });
}
