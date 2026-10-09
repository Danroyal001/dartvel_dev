// `dartvel.xr`: what the spatial builds (`dartvel build horizon`,
// `dartvel build visionos`) read from pubspec.yaml, and the Dart class that
// is the same declaration. The class and the map must round-trip exactly, or a
// project configured in Dart builds something different from one configured
// in YAML.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('dartvel.xr', () {
    test('no section is the default: a 1024x640 dp panel on the four Quest headsets', () {
      final DVXRConfig config = DVXRConfig.parse(null);
      expect(config.problems, isEmpty);
      expect(config.panel.width, 1024);
      expect(config.panel.height, 640);
      expect(config.panel.minWidth, isNull);
      expect(config.horizonDevices, <DVHorizonDevice>[
        DVHorizonDevice.quest2,
        DVHorizonDevice.questpro,
        DVHorizonDevice.quest3,
        DVHorizonDevice.quest3s,
      ]);
      expect(config.toDeclaration(), isEmpty);
    });

    test('the supportedDevices value is Meta\'s pipe-separated list', () {
      expect(DVXRConfig.parse(null).horizonSupportedDevices, 'quest2|questpro|quest3|quest3s');
    });

    test('pubspec -> class -> pubspec gives back every field', () {
      final Map<String, Object?> declared = <String, Object?>{
        'panel': <String, Object?>{'width': 1280, 'height': 800, 'minWidth': 360, 'minHeight': 225},
        'horizon': <String, Object?>{
          'devices': <String>['quest3', 'quest3s', 'vrglasses'],
        },
        // Designed keys the spec names. Not applied by any build yet, and
        // kept as written so a Dart config and a YAML one cannot disagree.
        'enabled': true,
        'immersion': <String>['passthrough', 'full'],
        'performance': <String, Object?>{'targetFps': 90},
      };
      final DVXRConfig config = DVXRConfig.parse(declared);
      expect(config.problems, isEmpty);
      expect(config.toDeclaration(), declared);
    });

    test('class -> pubspec -> class gives back an equal class', () {
      for (final DVXRConfig config in <DVXRConfig>[
        const DVXRConfig(),
        const DVXRConfig(panel: DVXRPanelSize(width: 800, height: 600)),
        const DVXRConfig(horizonDevices: <DVHorizonDevice>[DVHorizonDevice.quest3]),
        const DVXRConfig(
          panel: DVXRPanelSize(width: 1024, height: 640, minWidth: 360, minHeight: 225),
          horizonDevices: DVHorizonDevice.values,
        ),
      ]) {
        final DVXRConfig again = DVXRConfig.parse(config.toDeclaration());
        expect(again, config);
        expect(again.problems, isEmpty);
      }
    });

    test('every DVHorizonDevice has the identifier Meta documents', () {
      expect(<String>[for (final DVHorizonDevice d in DVHorizonDevice.values) d.key],
          <String>['quest2', 'questpro', 'quest3', 'quest3s', 'vrglasses']);
      for (final DVHorizonDevice device in DVHorizonDevice.values) {
        expect(DVHorizonDevice.fromKey(device.key), device);
      }
    });

    test('mistakes are named, not dropped', () {
      final DVXRConfig config = DVXRConfig.parse(<String, Object?>{
        'panel': <String, Object?>{'width': 0, 'height': '640', 'depth': 3},
        'horizon': <String, Object?>{'devices': <String>['quest3', 'quest4']},
        'imersion': <String>['full'],
      });
      final String said = config.problems.join('\n');
      expect(said, contains('dartvel.xr.panel.width'));
      expect(said, contains('dartvel.xr.panel.height'));
      expect(said, contains('dartvel.xr.panel.depth is not a setting'));
      expect(said, contains('"quest4"'));
      expect(said, contains('dartvel.xr.imersion is not a setting'));
    });

    test('an empty device list is refused: a store listing for no headset is not a build', () {
      final DVXRConfig config = DVXRConfig.parse(<String, Object?>{
        'horizon': <String, Object?>{'devices': <String>[]},
      });
      expect(config.problems.join('\n'), contains('at least one'));
    });

    test('a minimum larger than the default size is refused', () {
      final DVXRConfig config = DVXRConfig.parse(<String, Object?>{
        'panel': <String, Object?>{'width': 400, 'height': 300, 'minWidth': 800},
      });
      expect(config.problems.join('\n'), contains('minWidth'));
    });
  });
}
