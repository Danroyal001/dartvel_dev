/// Material assets: what a `DVMesh.material(...)` asset's bytes say.
///
/// A material asset is a small JSON document, so a project can colour its
/// meshes without a shader toolchain:
///
/// ```json
/// {"baseColor": "#1F8A4C", "metallic": 0, "roughness": 0.8, "emissive": "#000000", "opacity": 1}
/// ```
///
/// Every field is optional. Colours are `#RRGGBB` strings or `0xRRGGBB`
/// integers. Anything else (an unknown key, a colour that does not parse, a
/// number out of range) is a [DVSceneMaterialFormatException] naming the
/// field, so a typo fails loudly instead of rendering white.
library dartvel_scene.material;

import 'dart:convert';

/// A physically based material's parameters.
final class DVSceneMaterialSpec {
  const DVSceneMaterialSpec({
    this.baseColor = 0xFFFFFF,
    this.opacity = 1,
    this.metallic = 0,
    this.roughness = 0.7,
    this.emissive = 0x000000,
  });

  /// 0xRRGGBB.
  final int baseColor;

  /// 0 (invisible) to 1 (opaque).
  final double opacity;
  final double metallic;
  final double roughness;

  /// 0xRRGGBB light the surface gives off.
  final int emissive;

  static const Set<String> _keys = <String>{'baseColor', 'opacity', 'metallic', 'roughness', 'emissive'};

  /// Reads a material asset's bytes.
  factory DVSceneMaterialSpec.fromBytes(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw DVSceneMaterialFormatException('', 'is not JSON (${error.message})');
    }
    if (decoded is! Map<String, Object?>) {
      throw const DVSceneMaterialFormatException('', 'must be a JSON object');
    }
    for (final String key in decoded.keys) {
      if (!_keys.contains(key)) {
        throw DVSceneMaterialFormatException(key, 'is not a material field (${_keys.join(', ')})');
      }
    }
    return DVSceneMaterialSpec(
      baseColor: _color(decoded, 'baseColor', 0xFFFFFF),
      opacity: _unit(decoded, 'opacity', 1),
      metallic: _unit(decoded, 'metallic', 0),
      roughness: _unit(decoded, 'roughness', 0.7),
      emissive: _color(decoded, 'emissive', 0x000000),
    );
  }

  static int _color(Map<String, Object?> map, String key, int fallback) {
    final Object? value = map[key];
    if (value == null) return fallback;
    if (value is int && value >= 0 && value <= 0xFFFFFF) return value;
    if (value is String) {
      final RegExpMatch? hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value);
      if (hex != null) return int.parse(hex.group(1)!, radix: 16);
    }
    throw DVSceneMaterialFormatException(key, 'must be "#RRGGBB" or 0xRRGGBB');
  }

  static double _unit(Map<String, Object?> map, String key, double fallback) {
    final Object? value = map[key];
    if (value == null) return fallback;
    if (value is num && value >= 0 && value <= 1) return value.toDouble();
    throw DVSceneMaterialFormatException(key, 'must be a number from 0 to 1');
  }

  /// [color] as linear-ish 0..1 channels, red first.
  static List<double> channels(int color) => <double>[
        ((color >> 16) & 0xFF) / 255,
        ((color >> 8) & 0xFF) / 255,
        (color & 0xFF) / 255,
      ];

  @override
  bool operator ==(Object other) =>
      other is DVSceneMaterialSpec &&
      other.baseColor == baseColor &&
      other.opacity == opacity &&
      other.metallic == metallic &&
      other.roughness == roughness &&
      other.emissive == emissive;

  @override
  int get hashCode => Object.hash(baseColor, opacity, metallic, roughness, emissive);
}

/// A material asset that does not say what a material is.
final class DVSceneMaterialFormatException implements Exception {
  const DVSceneMaterialFormatException(this.field, this.problem);

  /// The offending key, or empty for the document as a whole.
  final String field;
  final String problem;

  @override
  String toString() => field.isEmpty ? 'Material asset $problem.' : 'Material asset field "$field" $problem.';
}
