/// `dartvel.xr`: what the spatial builds read from pubspec.yaml.
///
/// One declaration, read by `dartvel build horizon` to write the Horizon OS
/// manifest (the panel's default size, the headsets the store lists the app
/// for) and by `dartvel build visionos`. The same object is what a Dart
/// config file builds: [DVXRConfig.toDeclaration] gives back exactly the map
/// [DVXRConfig.parse] reads, so the two forms cannot drift.
///
/// The section also names keys the XR specification designs and no build
/// applies yet -- `enabled`, `immersion`, `comfort`, `anchors`,
/// `performance`. They are recognised, kept exactly as written and carried
/// through the round trip, so a project that declares them is not refused,
/// and nothing claims to have honoured them.
library;

/// A Meta Horizon OS device, by the identifier Meta's
/// `com.oculus.supportedDevices` manifest entry takes.
///
/// https://developers.meta.com/horizon/resources/publish-mobile-manifest/
enum DVHorizonDevice {
  quest2,
  questpro,
  quest3,
  quest3s,

  /// Listed by Meta beside the headsets. Not in the default: a panel app has
  /// not been shown to be usable there, and listing an app for a device is a
  /// promise to the people who buy it.
  vrglasses;

  /// The identifier in pubspec.yaml and in the manifest.
  String get key => name;

  static DVHorizonDevice? fromKey(String key) {
    for (final DVHorizonDevice device in values) {
      if (device.key == key) return device;
    }
    return null;
  }
}

/// The size a 2D panel opens at, in density-independent pixels, and the
/// smallest the person may make it.
///
/// Horizon OS reads it from the activity's `<layout>` element. Meta's default
/// is 1024x640 dp.
final class DVXRPanelSize {
  const DVXRPanelSize({
    this.width = 1024,
    this.height = 640,
    this.minWidth,
    this.minHeight,
  });

  final int width;
  final int height;
  final int? minWidth;
  final int? minHeight;

  bool get isDefault =>
      width == 1024 && height == 640 && minWidth == null && minHeight == null;

  Map<String, Object?> toDeclaration() => <String, Object?>{
        if (width != 1024 || height != 640 || minWidth != null || minHeight != null) ...<String, Object?>{
          'width': width,
          'height': height,
        },
        if (minWidth != null) 'minWidth': minWidth,
        if (minHeight != null) 'minHeight': minHeight,
      };

  @override
  bool operator ==(Object other) =>
      other is DVXRPanelSize &&
      other.width == width &&
      other.height == height &&
      other.minWidth == minWidth &&
      other.minHeight == minHeight;

  @override
  int get hashCode => Object.hash(width, height, minWidth, minHeight);
}

/// The parsed `dartvel.xr` section.
final class DVXRConfig {
  const DVXRConfig({
    this.panel = const DVXRPanelSize(),
    this.horizonDevices = defaultHorizonDevices,
    this.designed = const <String, Object?>{},
    this.problems = const <String>[],
  });

  /// The four Quest headsets. `vrglasses` is asked for, never assumed.
  static const List<DVHorizonDevice> defaultHorizonDevices = <DVHorizonDevice>[
    DVHorizonDevice.quest2,
    DVHorizonDevice.questpro,
    DVHorizonDevice.quest3,
    DVHorizonDevice.quest3s,
  ];

  /// Keys the specification designs and no build applies yet.
  static const Set<String> designedKeys = <String>{
    'enabled',
    'immersion',
    'comfort',
    'anchors',
    'performance',
  };

  final DVXRPanelSize panel;

  /// The headsets the Horizon Store lists the app for.
  final List<DVHorizonDevice> horizonDevices;

  /// The designed keys, exactly as declared.
  final Map<String, Object?> designed;

  /// What was wrong with the declaration, one sentence each.
  final List<String> problems;

  /// The value of the `com.oculus.supportedDevices` manifest entry.
  String get horizonSupportedDevices =>
      horizonDevices.map((DVHorizonDevice device) => device.key).join('|');

  /// Reads `dartvel.xr`. A missing section is the default.
  static DVXRConfig parse(Object? raw) {
    if (raw == null) return const DVXRConfig();
    if (raw is! Map) {
      return const DVXRConfig(problems: <String>[
        'dartvel.xr must be a map, for example with panel and horizon.',
      ]);
    }
    final List<String> problems = <String>[];
    final Map<String, Object?> designed = <String, Object?>{};
    for (final Object? key in raw.keys) {
      final String name = '$key';
      if (name == 'panel' || name == 'horizon') continue;
      if (designedKeys.contains(name)) {
        designed[name] = raw[key];
        continue;
      }
      problems.add('dartvel.xr.$name is not a setting; the settings are panel, '
          'horizon, ${designedKeys.join(', ')}.');
    }

    DVXRPanelSize panel = const DVXRPanelSize();
    final Object? rawPanel = raw['panel'];
    if (rawPanel != null && rawPanel is! Map) {
      problems.add('dartvel.xr.panel must be a map with width and height in dp.');
    } else if (rawPanel is Map) {
      for (final Object? key in rawPanel.keys) {
        if (!const <String>{'width', 'height', 'minWidth', 'minHeight'}.contains('$key')) {
          problems.add('dartvel.xr.panel.$key is not a setting; the settings are '
              'width, height, minWidth and minHeight.');
        }
      }
      int? size(String key) {
        final Object? value = rawPanel[key];
        if (value == null) return null;
        if (value is! int || value < 1) {
          problems.add('dartvel.xr.panel.$key must be a whole number of dp '
              'above nought, not "$value".');
          return null;
        }
        return value;
      }

      final int width = size('width') ?? 1024;
      final int height = size('height') ?? 640;
      final int? minWidth = size('minWidth');
      final int? minHeight = size('minHeight');
      if (minWidth != null && minWidth > width) {
        problems.add('dartvel.xr.panel.minWidth ($minWidth) is wider than the '
            'panel opens ($width); the panel could never open at its own size.');
      }
      if (minHeight != null && minHeight > height) {
        problems.add('dartvel.xr.panel.minHeight ($minHeight) is taller than '
            'the panel opens ($height); the panel could never open at its own size.');
      }
      panel = DVXRPanelSize(
          width: width, height: height, minWidth: minWidth, minHeight: minHeight);
    }

    List<DVHorizonDevice> devices = defaultHorizonDevices;
    final Object? rawHorizon = raw['horizon'];
    if (rawHorizon != null && rawHorizon is! Map) {
      problems.add('dartvel.xr.horizon must be a map with devices.');
    } else if (rawHorizon is Map) {
      for (final Object? key in rawHorizon.keys) {
        if ('$key' != 'devices') {
          problems.add('dartvel.xr.horizon.$key is not a setting; the setting is devices.');
        }
      }
      final Object? listed = rawHorizon['devices'];
      if (listed != null && listed is! List) {
        problems.add('dartvel.xr.horizon.devices must be a list, for example [quest3, quest3s].');
      } else if (listed is List) {
        final List<DVHorizonDevice> found = <DVHorizonDevice>[];
        for (final Object? entry in listed) {
          final DVHorizonDevice? device = DVHorizonDevice.fromKey('$entry'.trim());
          if (device == null) {
            problems.add('dartvel.xr.horizon.devices has "$entry"; the devices are '
                '${DVHorizonDevice.values.map((DVHorizonDevice d) => d.key).join(', ')}.');
          } else if (!found.contains(device)) {
            found.add(device);
          }
        }
        if (listed.isEmpty) {
          problems.add('dartvel.xr.horizon.devices must name at least one device: '
              'a store listing for no headset is not a build.');
        }
        if (found.isNotEmpty) devices = List<DVHorizonDevice>.unmodifiable(found);
      }
    }

    return DVXRConfig(
      panel: panel,
      horizonDevices: devices,
      designed: Map<String, Object?>.unmodifiable(designed),
      problems: List<String>.unmodifiable(problems),
    );
  }

  /// The pubspec map this configuration is. Only what differs from the
  /// default is written, so a default configuration is an empty map.
  Map<String, Object?> toDeclaration() {
    final bool defaultDevices = horizonDevices.length == defaultHorizonDevices.length &&
        <int>[for (int index = 0; index < horizonDevices.length; index++) index]
            .every((int index) => horizonDevices[index] == defaultHorizonDevices[index]);
    return <String, Object?>{
      if (!panel.isDefault) 'panel': panel.toDeclaration(),
      if (!defaultDevices)
        'horizon': <String, Object?>{
          'devices': <String>[for (final DVHorizonDevice d in horizonDevices) d.key],
        },
      ...designed,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DVXRConfig &&
      other.panel == panel &&
      other.horizonSupportedDevices == horizonSupportedDevices &&
      other.designed.toString() == designed.toString();

  @override
  int get hashCode => Object.hash(panel, horizonSupportedDevices, designed.toString());
}
