/// `dartvel.memory`: the defaults and per-target ceilings `DV.Memory.allocate`
/// applies to every arena it creates.
library;

import 'size.dart';
import 'target.dart';

enum _Touch { desktop, always, never }

final class _Layer {
  const _Layer({this.budget, this.segment, this.touch});
  final DVSize? budget;
  final DVSize? segment;
  final _Touch? touch;

  static const _Layer empty = _Layer();
}

/// What configuration says for one target.
final class DVMemorySettings {
  const DVMemorySettings({
    required this.segment,
    required this.segmentConfigured,
    required this.touchPages,
    this.budget,
    this.ceiling,
    this.ceilingSource,
  });

  /// The default budget when `allocate()` names no size; null when nothing
  /// configured one.
  final DVSize? budget;

  /// The largest arena this target may reserve: the budget a target entry or
  /// a device profile declares. A top-level budget is a default, not a
  /// ceiling.
  final DVSize? ceiling;

  /// Where [ceiling] came from, e.g. `tizen` or `device profile lobby`.
  final String? ceilingSource;

  final DVSize segment;

  /// Whether [segment] was configured rather than the profile default.
  final bool segmentConfigured;

  /// Whether pages are committed at startup on this target.
  final bool touchPages;
}

/// The parsed `dartvel.memory` section, with any device-profile overrides.
final class DVMemoryConfig {
  const DVMemoryConfig._({
    required _Layer global,
    required Map<String, _Layer> targets,
    required Map<String, _Layer> profiles,
    required Map<String, DVSize> ram,
    required Map<String, String> platforms,
    required this.problems,
  }) : _global = global,
       _targets = targets,
       _profiles = profiles,
       _ram = ram,
       _platforms = platforms;

  /// Nothing configured: every target gets its profile defaults.
  static const DVMemoryConfig none = DVMemoryConfig._(
    global: _Layer.empty,
    targets: <String, _Layer>{},
    profiles: <String, _Layer>{},
    ram: <String, DVSize>{},
    platforms: <String, String>{},
    problems: <String>[],
  );

  final _Layer _global;
  final Map<String, _Layer> _targets;
  final Map<String, _Layer> _profiles;
  final Map<String, DVSize> _ram;
  final Map<String, String> _platforms;

  /// What could not be read. Each names the key it is about. A problem is
  /// never resolved into a default silently: the value is left out, and this
  /// says so.
  final List<String> problems;

  /// The configuration keys a target entry may use.
  static const Map<String, List<DVMemoryTarget>> targetKeys =
      <String, List<DVMemoryTarget>>{
        'android': <DVMemoryTarget>[DVMemoryTarget.android],
        'ios': <DVMemoryTarget>[DVMemoryTarget.ios],
        'windows': <DVMemoryTarget>[DVMemoryTarget.windows],
        'linux': <DVMemoryTarget>[DVMemoryTarget.linux],
        'macos': <DVMemoryTarget>[DVMemoryTarget.macos],
        'fuchsia': <DVMemoryTarget>[DVMemoryTarget.fuchsia],
        'sony-elinux': <DVMemoryTarget>[DVMemoryTarget.sonyElinux],
        'tizen': <DVMemoryTarget>[DVMemoryTarget.tizen],
        'webos': <DVMemoryTarget>[DVMemoryTarget.webos],
        'web': <DVMemoryTarget>[DVMemoryTarget.webJs, DVMemoryTarget.webWasm],
        'web-js': <DVMemoryTarget>[DVMemoryTarget.webJs],
        'web-wasm': <DVMemoryTarget>[DVMemoryTarget.webWasm],
      };

  /// Reads `memory` and `deviceProfiles.<id>.{memory, ram, platform}` out of
  /// a project's `dartvel:` section.
  static DVMemoryConfig parse(Object? dartvelSection) {
    final List<String> problems = <String>[];
    final Map<Object?, Object?> dv = dartvelSection is Map
        ? dartvelSection
        : const <Object?, Object?>{};

    final Object? memory = dv['memory'];
    if (memory != null && memory is! Map) {
      problems.add('memory must be a map');
    }
    final Map<Object?, Object?> section = memory is Map
        ? memory
        : const <Object?, Object?>{};

    final _Layer global = _layer(section, 'memory', problems);
    final Map<String, _Layer> targets = <String, _Layer>{};
    final Object? declared = section['targets'];
    if (declared is Map) {
      declared.forEach((Object? key, Object? body) {
        final String name = '$key';
        if (!targetKeys.containsKey(name)) {
          problems.add(
            'memory.targets.$name is not a Dartvel target '
            '(one of ${targetKeys.keys.join(', ')})',
          );
          return;
        }
        targets[name] = body is Map
            ? _layer(body, 'memory.targets.$name', problems)
            : _Layer.empty;
      });
    } else if (declared != null) {
      problems.add('memory.targets must be a map');
    }

    final Map<String, _Layer> profiles = <String, _Layer>{};
    final Map<String, DVSize> ram = <String, DVSize>{};
    final Map<String, String> platforms = <String, String>{};
    final Object? deviceProfiles = dv['deviceProfiles'];
    if (deviceProfiles is Map) {
      deviceProfiles.forEach((Object? id, Object? body) {
        if (body is! Map) return;
        final String name = '$id';
        final Object? m = body['memory'];
        if (m is Map) {
          profiles[name] = _layer(m, 'deviceProfiles.$name.memory', problems);
        }
        final Object? r = body['ram'];
        if (r != null) {
          final DVSize? size = DVSize.tryRead(r);
          if (size == null) {
            problems.add('deviceProfiles.$name.ram: "$r" is not a size');
          } else {
            ram[name] = size;
          }
        }
        final Object? platform = body['platform'];
        if (platform is String) platforms[name] = platform;
      });
    }

    return DVMemoryConfig._(
      global: global,
      targets: targets,
      profiles: profiles,
      ram: ram,
      platforms: platforms,
      problems: List<String>.unmodifiable(problems),
    );
  }

  static _Layer _layer(
    Map<Object?, Object?> body,
    String path,
    List<String> problems,
  ) {
    DVSize? size(String key) {
      final Object? raw = body[key];
      if (raw == null) return null;
      final DVSize? read = DVSize.tryRead(raw);
      if (read == null) {
        problems.add('$path.$key: "$raw" is not a size');
      }
      return read;
    }

    final DVSize? budget = size('budget');
    DVSize? segment = size('segment');
    if (segment != null && !segment.isPowerOfTwo) {
      problems.add('$path.segment: $segment is not a power of two');
      segment = null;
    }
    _Touch? touch;
    final Object? raw = body['touchPages'];
    if (raw != null) {
      touch = switch (raw) {
        'desktop' => _Touch.desktop,
        true || 'true' || 'always' => _Touch.always,
        false || 'false' || 'never' => _Touch.never,
        _ => null,
      };
      if (touch == null) {
        problems.add('$path.touchPages: "$raw" is not desktop, true or false');
      }
    }
    return _Layer(budget: budget, segment: segment, touch: touch);
  }

  _Layer _targetLayer(DVMemoryTarget target) {
    // The specific key wins over `web`.
    _Layer? found;
    targetKeys.forEach((String key, List<DVMemoryTarget> covers) {
      if (!covers.contains(target) || !_targets.containsKey(key)) return;
      if (found == null || covers.length == 1) found = _targets[key];
    });
    return found ?? _Layer.empty;
  }

  /// The settings for [target], with [deviceProfile]'s memory override over
  /// the target entry, over the top-level values, over the profile defaults.
  DVMemorySettings resolve(DVMemoryTarget target, {String? deviceProfile}) {
    final _Layer t = _targetLayer(target);
    final _Layer? p = deviceProfile == null || deviceProfile.isEmpty
        ? null
        : _profiles[deviceProfile];

    final DVSize? ceiling = p?.budget ?? t.budget;
    final String? ceilingSource = p?.budget != null
        ? 'device profile $deviceProfile'
        : t.budget != null
        ? target.id
        : null;
    final DVSize? segment = p?.segment ?? t.segment ?? _global.segment;
    return DVMemorySettings(
      budget: ceiling ?? _global.budget,
      ceiling: ceiling,
      ceilingSource: ceilingSource,
      segment: segment ?? target.profile.segment,
      segmentConfigured: segment != null,
      touchPages: _touchFor(target, deviceProfile) == _Touch.never
          ? false
          : target.profile == DVMemoryProfile.desktop,
    );
  }

  _Touch _touchFor(DVMemoryTarget target, String? deviceProfile) {
    final _Layer? p = deviceProfile == null ? null : _profiles[deviceProfile];
    return p?.touch ??
        _targetLayer(target).touch ??
        _global.touch ??
        _Touch.desktop;
  }

  /// Whether configuration asks for touchPages on a target that refuses it
  /// (`DV-MEMORY-004`). `touchPages: desktop` asks only for desktops, so it
  /// is never a refusal.
  bool touchPagesRefusedOn(DVMemoryTarget target, {String? deviceProfile}) =>
      _touchFor(target, deviceProfile) == _Touch.always &&
      target.profile.refusesTouchPages;

  /// The device profiles this configuration read.
  Iterable<String> get deviceProfiles => <String>{
    ..._ram.keys,
    ..._platforms.keys,
    ..._profiles.keys,
  };

  /// `deviceProfiles.<id>.ram`, when declared.
  DVSize? profileRam(String id) => _ram[id];

  /// `deviceProfiles.<id>.platform`, when declared.
  String? profilePlatform(String id) => _platforms[id];
}
