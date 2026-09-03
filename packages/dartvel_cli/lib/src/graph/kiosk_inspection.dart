import 'package:dartvel_core/dartvel.dart'
    show DVKioskEnforcement, DVKioskPolicy, DVKioskTarget;

/// The effective kiosk policy, per target and per kiosk window, with the
/// source of each value.
///
/// Three declarations can set a value: the `dartvel.kiosk` section, a device
/// profile's `kiosk` entry over it (selected by `--device-profile`, as the
/// build selects it), and a named policy's entry over the section for the
/// kiosk window that uses it. Doctor says whether the result can be honoured;
/// this says what the result is, and why -- the question at a front desk
/// that boots into the wrong page.
class DVKioskInspection {
  DVKioskInspection._({
    required this.enabled,
    required this.profile,
    required this.profileOverrides,
    required this.device,
    required this.windows,
    required this.targets,
  });

  final bool enabled;
  final String? profile;

  /// Whether the selected profile has a kiosk entry at all.
  final bool profileOverrides;
  final DVEffectiveKioskPolicy device;
  final Map<String, DVEffectiveKioskPolicy> windows;
  final Map<DVKioskTarget, DVKioskEnforcement> targets;

  static DVKioskInspection of(Object? dartvelSection, {String? profile}) {
    final Map<String, Object?> section = _map(dartvelSection);
    final Map<String, Object?> kiosk = _map(section['kiosk']);
    final Map<String, Object?> base = <String, Object?>{...kiosk}
      ..remove('policies')
      ..remove('windows');

    final Map<String, Object?> profiles = _map(section['deviceProfiles']);
    final Map<String, Object?> override =
        profile == null ? const <String, Object?>{} : _map(_map(profiles[profile])['kiosk']);
    final bool overrides = profile != null && _map(profiles[profile])['kiosk'] is Map;

    final DVEffectiveKioskPolicy device = DVEffectiveKioskPolicy._resolve(
      base: base,
      over: override,
      overSource: profile == null ? null : 'profile:$profile',
    );

    final Map<String, Object?> named = _map(kiosk['policies']);
    final Map<String, DVEffectiveKioskPolicy> windows = <String, DVEffectiveKioskPolicy>{
      for (final MapEntry<String, Object?> e in named.entries)
        e.key: DVEffectiveKioskPolicy._resolve(
          base: base,
          over: _map(e.value),
          overSource: 'policy:${e.key}',
        ),
    };

    final Map<DVKioskTarget, DVKioskEnforcement> targets = <DVKioskTarget, DVKioskEnforcement>{
      for (final DVKioskTarget target in DVKioskTarget.values)
        target: DVKioskEnforcement.resolve(policy: device.policy, target: target),
    };

    return DVKioskInspection._(
      enabled: device.policy.enabled,
      profile: profile,
      profileOverrides: overrides,
      device: device,
      windows: windows,
      targets: targets,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'profile': profile,
        'profileOverrides': profileOverrides,
        'device': device.toJson(),
        'windows': <String, Object?>{
          for (final MapEntry<String, DVEffectiveKioskPolicy> e in windows.entries) e.key: e.value.toJson(),
        },
        'targets': <String, Object?>{
          for (final MapEntry<DVKioskTarget, DVKioskEnforcement> e in targets.entries)
            e.key.name: <String, Object?>{
              'strength': e.value.strength.name,
              'inputScope': e.value.inputScope.name,
              'exitMethod': e.value.exitMethod.name,
              'scopeHonoured': e.value.scopeHonoured,
              'supported': e.value.supported,
              'codes': e.value.codes,
            },
        },
      };

  /// The text form, one line per value and per target.
  List<String> lines() {
    if (!enabled) return <String>['kiosk: none declared'];
    final List<String> out = <String>[
      'kiosk (${device.policy.scope.name} scope)'
          '${profile == null ? '' : ', profile $profile${profileOverrides ? '' : ' (no kiosk entry; the section alone)'}'}',
    ];
    out.addAll(device.lines(indent: '  '));
    for (final MapEntry<String, DVEffectiveKioskPolicy> e in windows.entries) {
      out.add('  window ${e.key}');
      out.addAll(e.value.lines(indent: '    ', onlyOverridden: true));
    }
    out.add('  targets');
    for (final MapEntry<DVKioskTarget, DVKioskEnforcement> e in targets.entries) {
      final DVKioskEnforcement en = e.value;
      final String codes = en.codes.isEmpty ? '' : '  ${en.codes.join(', ')}';
      out.add('    ${e.key.name.padRight(22)} ${en.supported ? en.strength.name : 'unsupported'}'
          ', exit ${en.exitMethod.name}, input ${en.inputScope.name}'
          '${en.scopeHonoured ? '' : ', scope not honoured'}$codes');
    }
    return out;
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)) : <String, Object?>{};
}

/// One resolved policy: its values by dotted key, and where each came from.
class DVEffectiveKioskPolicy {
  DVEffectiveKioskPolicy._(this.policy, this.values, this.sources);

  final DVKioskPolicy policy;
  final Map<String, Object?> values;

  /// `section`, `default`, or the [over] source: `profile:<id>` or
  /// `policy:<name>`.
  final Map<String, String> sources;

  static DVEffectiveKioskPolicy _resolve({
    required Map<String, Object?> base,
    required Map<String, Object?> over,
    required String? overSource,
  }) {
    final Map<String, Object?> merged = <String, Object?>{...base, ...over};
    final DVKioskPolicy policy = DVKioskPolicy.parse(<String, Object?>{'kiosk': merged});
    final Map<String, Object?> values = _valuesOf(policy);
    final Set<String> fromOver = _flatten(over).keys.toSet();
    final Set<String> fromBase = _flatten(base).keys.toSet();
    final Map<String, String> sources = <String, String>{
      for (final String key in values.keys)
        key: fromOver.contains(key) && overSource != null
            ? overSource
            : fromBase.contains(key)
                ? 'section'
                : 'default',
    };
    return DVEffectiveKioskPolicy._(policy, values, sources);
  }

  /// The parsed policy as the declaration's own keys, so a value reads the
  /// way it was written. Durations are seconds; a secret is its name.
  static Map<String, Object?> _valuesOf(DVKioskPolicy p) => <String, Object?>{
        'enabled': p.enabled,
        'scope': p.scope.name,
        'home': p.home,
        'routes.allow': p.allow,
        'input.systemGestures': p.blockSystemGestures,
        'input.hardwareKeys': p.blockHardwareKeys,
        'input.shortcuts': p.blockShortcuts,
        'session.idleTimeout': _seconds(p.idleTimeout),
        'session.idleWarning': _seconds(p.idleWarning),
        'session.onIdle': p.onIdle.name,
        'session.clearOnReset': <String>[for (final c in p.clearOnReset) c.name],
        'display.fullscreen': p.fullscreen,
        'exit.method': p.exitMethod.name,
        'exit.pin': p.exitPinSecret == null ? null : 'secret:${p.exitPinSecret}',
        'exit.maxAttempts': p.maxAttempts,
        'exit.lockoutFor': _seconds(p.lockoutFor),
        'exit.audit': p.audit,
      };

  static String _seconds(Duration d) => '${d.inSeconds}s';

  static Map<String, Object?> _flatten(Map<String, Object?> map, [String prefix = '']) {
    final Map<String, Object?> out = <String, Object?>{};
    map.forEach((String key, Object? value) {
      final String path = '$prefix$key';
      if (value is Map) {
        out.addAll(_flatten(DVKioskInspection._map(value), '$path.'));
      } else {
        out[path] = value;
      }
    });
    return out;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'values': values,
        'sources': sources,
        'problems': policy.problems,
      };

  List<String> lines({required String indent, bool onlyOverridden = false}) => <String>[
        for (final MapEntry<String, Object?> e in values.entries)
          if (!onlyOverridden || (sources[e.key] != 'section' && sources[e.key] != 'default'))
            '$indent${e.key.padRight(22)} ${_show(e.value)}  (${sources[e.key]})',
        for (final String problem in policy.problems) '$indent[!] $problem',
      ];

  static String _show(Object? value) => value is List ? (value.isEmpty ? '[]' : value.join(', ')) : '$value';
}
