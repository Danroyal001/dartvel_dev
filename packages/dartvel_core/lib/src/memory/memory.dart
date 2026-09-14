/// `DV.Memory`: the factory that creates instrumented arenas.
///
/// Importable on its own -- it reaches `dart:io` and `dart:ffi` only through
/// conditional imports -- so a web build compiles it without the rest of
/// dartvel_core.
library;

import 'package:meta/meta.dart';

import 'backing.dart';
import 'config.dart';
import 'platform_memory.dart';
import 'size.dart';
import 'target.dart';

export 'backing.dart'
    show
        DVMemoryBacking,
        DVMemorySegmentStore,
        DVMemoryHeapBacking,
        DVMemoryHeapSegment;
export 'config.dart';
export 'platform_memory.dart';
export 'size.dart';
export 'target.dart';

/// Aggregate usage across every live arena `DV.Memory` created.
final class DVMemoryUsage {
  const DVMemoryUsage({
    required this.arenas,
    required this.securedBytes,
    required this.usedBytes,
    required this.highWaterBytes,
    required this.fragmentedBytes,
    required this.resets,
  });

  final int arenas;
  final int securedBytes;
  final int usedBytes;
  final int highWaterBytes;
  final int fragmentedBytes;
  final int resets;
}

/// A factory, not a singleton arena: every [allocate] is an independent
/// [DVPlatformMemory] with its own budget, segments, cursor and lifecycle.
final class DVMemory {
  const DVMemory();

  static DVMemoryConfig _config = DVMemoryConfig.none;
  static DVMemoryTarget? _target;
  static String? _deviceProfile;
  static DVMemoryBacking? _backing;
  static final List<WeakReference<DVPlatformMemory>> _live =
      <WeakReference<DVPlatformMemory>>[];
  static int _nextId = 1;

  static const String _profileDefine = String.fromEnvironment(
    'DARTVEL_DEVICE_PROFILE',
  );

  /// Installs the project's `dartvel.memory` configuration. The generated
  /// client calls this at startup.
  ///
  /// [target] and [deviceProfile] default to what the build defined and the
  /// platform reports; [backing] to the platform's own.
  static void configure(
    DVMemoryConfig config, {
    DVMemoryTarget? target,
    String? deviceProfile,
    DVMemoryBacking? backing,
  }) {
    _config = config;
    _target = target;
    _deviceProfile = deviceProfile;
    _backing = backing;
  }

  /// The configuration arenas are created under.
  DVMemoryConfig get config => _config;

  /// Creates an arena, applying the configured defaults and the target's
  /// ceiling, and registers it.
  ///
  /// An explicit [segment] or [touchPages] wins over configuration; a size
  /// larger than the target's ceiling is capped to it, and the arena records
  /// `DV-MEMORY-001` saying so.
  DVPlatformMemory allocate({
    int? gigabytes,
    int? megabytes,
    DVMemoryProfile? profile,
    DVSize? segment,
    bool? touchPages,
  }) {
    if (gigabytes != null && megabytes != null) {
      throw ArgumentError('pass gigabytes or megabytes, not both');
    }
    final DVMemoryTarget target = _target ?? DVMemoryTarget.current;
    final String deviceProfile = _deviceProfile ?? _profileDefine;
    final DVMemorySettings s = _config.resolve(
      target,
      deviceProfile: deviceProfile,
    );

    final DVSize? asked = gigabytes != null
        ? DVSize.gb(gigabytes)
        : megabytes != null
        ? DVSize.mb(megabytes)
        : s.budget;
    final DVSize chosenSegment =
        segment ??
        (profile != null && !s.segmentConfigured ? profile.segment : s.segment);
    final bool touch =
        touchPages ??
        (_config.touchPagesRefusedOn(target, deviceProfile: deviceProfile)
            ? true
            : s.touchPages);

    final DVPlatformMemory arena = DVPlatformMemory.configured(
      asked: asked,
      profile: profile,
      segment: chosenSegment,
      touchPages: touch,
      target: target,
      backing: _backing ?? dvDefaultMemoryBacking(),
      ceiling: s.ceiling,
      ceilingSource: s.ceilingSource,
      id: _nextId++,
    );
    _live.add(WeakReference<DVPlatformMemory>(arena));
    return arena;
  }

  /// The live arenas this factory created, in creation order. An arena that
  /// was disposed, or that nothing references any more, is not listed.
  List<DVPlatformMemory> get arenas {
    _live.removeWhere((WeakReference<DVPlatformMemory> r) {
      final DVPlatformMemory? a = r.target;
      return a == null || a.isDisposed;
    });
    return <DVPlatformMemory>[
      for (final WeakReference<DVPlatformMemory> r in _live) r.target!,
    ];
  }

  /// Usage summed over [arenas].
  DVMemoryUsage get usage {
    var secured = 0, used = 0, high = 0, fragmented = 0, resets = 0;
    final List<DVPlatformMemory> live = arenas;
    for (final DVPlatformMemory a in live) {
      secured += a.securedBytes;
      used += a.usedBytes;
      high += a.highWaterBytes;
      fragmented += a.fragmentedBytes;
      resets += a.resetCount;
    }
    return DVMemoryUsage(
      arenas: live.length,
      securedBytes: secured,
      usedBytes: used,
      highWaterBytes: high,
      fragmentedBytes: fragmented,
      resets: resets,
    );
  }

  /// Forgets configuration and registered arenas.
  @visibleForTesting
  static void debugReset() {
    _config = DVMemoryConfig.none;
    _target = null;
    _deviceProfile = null;
    _backing = null;
    _live.clear();
    _nextId = 1;
  }
}
