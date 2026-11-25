import 'package:dartvel_core/config.dart' as config;
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `dartvel.theme` reads the same from YAML and from a Dart config class, and
/// writes back exactly what it read.
void main() {
  const DVThemeConfig declared = DVThemeConfig(
    seed: '#B83A12',
    mode: .dark,
    colors: <DVColorRole, DVColorPair>{
      DVColorRole.accent: DVColorPair(light: '#B83A12', dark: '#FF8A5C'),
      DVColorRole.focus: DVColorPair.both('#1C1917'),
      DVColorRole.selection: DVColorPair(light: '#B83A1240', dark: '#FF8A5C55'),
    },
  );

  test('class -> pubspec -> class is the same theme', () {
    final DVThemeConfigReading read = DVThemeConfig.parse(declared.toPubspec());
    expect(read.problems, isEmpty);
    expect(read.config, declared);
  });

  test('YAML -> class -> pubspec is the same object, colours normalised', () {
    final DVThemeConfigReading read = DVThemeConfig.parse(loadYaml('''
seed: "#b83a12"
mode: dark
colors:
  accent: { light: "#B83A12", dark: "#ff8a5c" }
  focus: "#1c1917"
  selection: { light: "#B83A1240", dark: "#FF8A5C55" }
'''));
    expect(read.problems, isEmpty);
    expect(read.config, declared);
    expect(read.config.toPubspec(), <String, Object?>{
      'seed': '#B83A12',
      'mode': 'dark',
      'colors': <String, Object?>{
        'accent': <String, Object?>{'light': '#B83A12', 'dark': '#FF8A5C'},
        'focus': '#1C1917',
        'selection': <String, Object?>{'light': '#B83A1240', 'dark': '#FF8A5C55'},
      },
    });
  });

  test('nothing declared is Dartvel\'s own theme and writes nothing', () {
    final DVThemeConfigReading read = DVThemeConfig.parse(null);
    expect(read.config, DVThemeConfig.dartvel);
    expect(read.config.declaresColours, isFalse);
    expect(DVThemeConfig.dartvel.toPubspec(), isEmpty);
  });

  test('a bad entry costs that entry and says why, never the rest', () {
    final DVThemeConfigReading read = DVThemeConfig.parse(<String, Object?>{
      'seed': 'brick',
      'mode': 'sepia',
      'palette': 1,
      'colors': <String, Object?>{'brand': '#000000', 'accent': 'red', 'background': '#FAF7F2'},
    });
    expect(read.config.seed, isNull);
    expect(read.config.mode, DVThemeMode.system);
    expect(read.config.colors, <DVColorRole, DVColorPair>{DVColorRole.background: const DVColorPair.both('#FAF7F2')});
    expect(read.problems.join('\n'), allOf(contains('seed'), contains('sepia'), contains('palette'), contains('brand'), contains('accent')));
  });

  test('one mode named means that colour in both, never Dartvel blue in the other', () {
    final DVThemeConfigReading read = DVThemeConfig.parse(<String, Object?>{
      'colors': <String, Object?>{'accent': <String, Object?>{'light': '#B83A12'}},
    });
    expect(read.config.colors[DVColorRole.accent], const DVColorPair.both('#B83A12'));
  });

  test('what the build reads without Flutter: accent from seed, link from accent, background only when named', () {
    const DVThemeConfig seedOnly = DVThemeConfig(seed: '#B83A12');
    expect(seedOnly.accentHex(dark: false), '#B83A12');
    expect(seedOnly.accentHex(dark: true), isNull);
    expect(seedOnly.linkHex(dark: false), '#B83A12');
    expect(seedOnly.backgroundHex(dark: false), isNull);
    expect(declared.linkHex(dark: true), '#FF8A5C');
    expect(DVThemeConfig.opaque('#B83A1240'), '#B83A12');
    expect(DVThemeConfig.argb('#B83A1240'), 0x40B83A12);
  });

  test('the Dart config class carries the theme with the same keys (parity)', () {
    final config.DartvelPubspecConfig read =
        config.DartvelPubspecConfig.fromPubspec(<Object?, Object?>{'theme': declared.toPubspec()});
    expect(read.problems, isEmpty);
    expect(read.theme, declared);
    expect(read.toPubspec()['theme'], declared.toPubspec());
    expect(const _AppConfig().toPubspec()['theme'], declared.toPubspec());
    expect(const _Bare().toPubspec().containsKey('theme'), isFalse);
  });
}

class _AppConfig extends config.DartvelConfig {
  const _AppConfig();
  @override
  DVThemeConfig get theme => const DVThemeConfig(
        seed: '#B83A12',
        mode: .dark,
        colors: <DVColorRole, DVColorPair>{
          DVColorRole.accent: DVColorPair(light: '#B83A12', dark: '#FF8A5C'),
          DVColorRole.focus: DVColorPair.both('#1C1917'),
          DVColorRole.selection: DVColorPair(light: '#B83A1240', dark: '#FF8A5C55'),
        },
      );
}

class _Bare extends config.DartvelConfig {
  const _Bare();
}
