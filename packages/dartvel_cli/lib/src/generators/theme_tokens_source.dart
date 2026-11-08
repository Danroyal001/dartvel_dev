// dartvel.theme in pubspec.yaml, read into the Dart expression the generated
// application entry installs with DV.Theme.useTokens before it builds a
// theme. The checks a token set can fail are made here, at generation, so a
// missing mode is a build error naming the token rather than a wrong colour
// at runtime.

/// A `dartvel.theme` declaration the build refuses, with the diagnostic code
/// NEW_SPEC.md's Theme section gives it.
class DVThemeConfigException implements Exception {
  const DVThemeConfigException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// The token names the framework's vocabulary has, kind by kind. They are
/// the keys of `DVThemeTokens.dartvel` in dartvel_flutter, which refuses any
/// other name at runtime too.
const Map<String, List<String>> dvThemeTokenNames = <String, List<String>>{
  'color': <String>['surface', 'raised', 'onSurface', 'muted', 'outline', 'accent', 'onAccent', 'danger', 'onDanger'],
  'space': <String>['xs', 'sm', 'md', 'lg', 'xl'],
  'radius': <String>['sm', 'md', 'lg', 'full'],
};

const List<String> _fontNames = <String>['body'];

/// The modes every colour token must have a value in. High contrast is
/// optional: a token without it keeps its brightness value.
const List<String> _requiredModes = <String>['light', 'dark'];

/// The `DVThemeTokens` expression for [theme], the value of `dartvel.theme`,
/// or null when it declares no tokens and no fonts.
///
/// [bundledFamilies] are the families the project bundles under
/// `flutter.fonts`; a declared face outside them is DV-THEME-002.
String? dvThemeTokensSource(Object? theme, {required Set<String> bundledFamilies}) {
  if (theme is! Map) return null;
  final Object? tokens = theme['tokens'];
  final Object? fonts = theme['fonts'];
  final List<String> parts = <String>[];
  if (tokens is Map) {
    for (final Object? kind in tokens.keys) {
      if (!dvThemeTokenNames.containsKey('$kind')) {
        throw DVThemeConfigException(
          'DV-THEME-001',
          'dartvel.theme.tokens.$kind is not a kind of token. The kinds are '
              '${dvThemeTokenNames.keys.join(', ')}.',
        );
      }
    }
    final Object? color = tokens['color'];
    if (color is Map && color.isNotEmpty) {
      final List<String> entries = <String>[
        for (final MapEntry<Object?, Object?> entry in color.entries)
          "'${_known('color', entry.key)}': ${_colorToken('${entry.key}', entry.value)}",
      ];
      parts.add('color: <String, DVColorToken>{${entries.join(', ')}}');
    }
    for (final String kind in const <String>['space', 'radius']) {
      final Object? values = tokens[kind];
      if (values is! Map || values.isEmpty) continue;
      final List<String> entries = <String>[
        for (final MapEntry<Object?, Object?> entry in values.entries)
          "'${_known(kind, entry.key)}': ${_number(kind, '${entry.key}', entry.value)}",
      ];
      parts.add('$kind: <String, double>{${entries.join(', ')}}');
    }
  }
  if (fonts is Map && fonts.isNotEmpty) {
    final List<String> entries = <String>[];
    for (final MapEntry<Object?, Object?> entry in fonts.entries) {
      final String name = '${entry.key}';
      if (!_fontNames.contains(name)) {
        throw DVThemeConfigException(
          'DV-THEME-002',
          'dartvel.theme.fonts.$name is not a face the theme sets text in. '
              'The faces are ${_fontNames.join(', ')}.',
        );
      }
      final Object? font = entry.value;
      final Object? family = font is Map ? font['family'] : font;
      if (family is! String || family.isEmpty) {
        throw DVThemeConfigException(
          'DV-THEME-002',
          'dartvel.theme.fonts.$name names no family.',
        );
      }
      if (!bundledFamilies.contains(family)) {
        throw DVThemeConfigException(
          'DV-THEME-002',
          'dartvel.theme.fonts.$name is "$family", which is not bundled: no '
              'flutter.fonts entry in pubspec.yaml declares that family, so it '
              'would be drawn in a fallback on every target.',
        );
      }
      final Object? fallback = font is Map ? font['fallback'] : null;
      final List<String> chain = <String>[
        if (fallback is List) for (final Object? item in fallback) '$item',
      ];
      entries.add(
        "'$name': DVFontToken(family: ${_string(family)}"
        "${chain.isEmpty ? '' : ', fallback: <String>[${chain.map(_string).join(', ')}]'})",
      );
    }
    parts.add('fonts: <String, DVFontToken>{${entries.join(', ')}}');
  }
  if (parts.isEmpty) return null;
  return 'DVThemeTokens.dartvel.override(${parts.join(', ')})';
}

String _known(String kind, Object? key) {
  final String name = '$key';
  final List<String> names = dvThemeTokenNames[kind]!;
  if (!names.contains(name)) {
    throw DVThemeConfigException(
      'DV-THEME-001',
      'dartvel.theme.tokens has no token $kind.$name. The $kind tokens are '
          '${names.join(', ')}.',
    );
  }
  return name;
}

String _colorToken(String name, Object? value) {
  if (value is! Map) {
    throw DVThemeConfigException(
      'DV-THEME-001',
      'color.$name needs a value per mode: { light: ..., dark: ... }.',
    );
  }
  for (final String mode in _requiredModes) {
    if (value[mode] == null) {
      throw DVThemeConfigException(
        'DV-THEME-001',
        'color.$name has no value for $mode. Every colour token has a light '
            'and a dark value; highContrast is optional.',
      );
    }
  }
  final String light = _hex(name, 'light', value['light']);
  final String dark = _hex(name, 'dark', value['dark']);
  final Object? contrast = value['highContrast'];
  return "DVColorToken('$name', light: const Color($light), dark: const Color($dark)"
      "${contrast == null ? '' : ', highContrast: const Color(${_hex(name, 'highContrast', contrast)})'})";
}

final RegExp _hexColor = RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

/// `#RRGGBB`, or `#RRGGBBAA` as CSS writes alpha, as a Dart ARGB literal.
String _hex(String name, String mode, Object? value) {
  final String text = '$value';
  final RegExpMatch? match = _hexColor.firstMatch(text);
  if (match == null) {
    throw DVThemeConfigException(
      'DV-THEME-001',
      'color.$name $mode is "$text", which is not a colour. Write it as '
          '#RRGGBB or #RRGGBBAA.',
    );
  }
  final String digits = match.group(1)!.toUpperCase();
  final String argb = digits.length == 6 ? 'FF$digits' : '${digits.substring(6)}${digits.substring(0, 6)}';
  return '0x$argb';
}

String _number(String kind, String name, Object? value) {
  if (value is! num) {
    throw DVThemeConfigException(
      'DV-THEME-001',
      '$kind.$name is "$value", which is not a number of logical pixels.',
    );
  }
  return '${value.toDouble()}';
}

String _string(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";
