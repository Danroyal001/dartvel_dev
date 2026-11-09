/// `dartvel: display:` in pubspec.yaml, handed to the app as defines.
///
/// ```yaml
/// dartvel:
///   display:
///     scaling: auto      # auto (default) | off | a number such as 1.5
///     screen: billboard  # optional: watch | phone | tablet | desktop | tv | billboard
/// ```
///
/// The app reads them in `DVDisplayScale`. A value it would not understand
/// fails the build here rather than drawing the app at the wrong size.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const List<String> _screenClasses = ['watch', 'phone', 'tablet', 'desktop', 'tv', 'billboard'];

/// The `--dart-define` arguments for the [dartvel] section's `display` block.
List<String> dvDisplayDefines(Object? dartvel) {
  final Object? display = dartvel is Map ? dartvel['display'] : null;
  if (display == null) return const [];
  if (display is! Map) {
    throw const FormatException('dartvel.display must be a map with scaling and/or screen.');
  }
  final List<String> defines = [];
  final Object? scaling = display['scaling'];
  if (scaling != null) {
    final String text = '$scaling'.trim().toLowerCase();
    final double? number = double.tryParse(text);
    final bool valid = text == 'auto' || text == 'off' || (number != null && number > 0);
    if (!valid) {
      throw FormatException('dartvel.display.scaling is "$scaling"; use auto, off or a number above 0 such as 1.5.');
    }
    defines.add('--dart-define=DARTVEL_DISPLAY_SCALING=$text');
  }
  final Object? screen = display['screen'];
  if (screen != null) {
    final String text = '$screen'.trim().toLowerCase();
    if (!_screenClasses.contains(text)) {
      throw FormatException('dartvel.display.screen is "$screen"; use one of ${_screenClasses.join(', ')}.');
    }
    defines.add('--dart-define=DARTVEL_SCREEN_CLASS=$text');
  }
  return defines;
}

/// The dartvel section of [root]'s pubspec.yaml, or null when there is none.
Object? dvReadDartvelSection(String root) {
  try {
    final Object? doc = loadYaml(File(p.join(root, 'pubspec.yaml')).readAsStringSync());
    return doc is Map ? doc['dartvel'] : null;
  } on Object {
    return null;
  }
}
