/// The diagnostic codes Dartvel emits, and what they mean.
///
/// The codes are a published contract -- they never change meaning between
/// releases -- and `dartvel explain` reads them, so a developer who finds one
/// in a log can look it up instead of searching the specification by hand.
///
/// Kept here, in the package with no Flutter dependency, because both the CLI
/// and the runtime need it and the CLI cannot depend on Flutter. A test reads
/// the tables out of NEW_SPEC.md and fails when this list and the document
/// disagree, in either direction: an unregistered code, a registered one the
/// document does not list, or a level that differs. Without that check a
/// registry is just a second place to be wrong -- which is how DV-WINDOW-006
/// came to be emitted for a display-hint miss while the specification reserved
/// it for a missing native binding.
library dartvel.diagnostics;

/// One diagnostic code.
final class DVDiagnostic {
  const DVDiagnostic({
    required this.code,
    required this.reason,
    required this.level,
  });

  /// The stable code, e.g. `DV-WINDOW-001`.
  final String code;

  /// What happened, in the specification's own words.
  final String reason;

  /// One of `debug`, `info`, `warning`, `error`.
  ///
  /// Calibrated to whether the developer can act on it, not to how unusual it
  /// is: a phone having no windows is the intended behaviour, and warning on
  /// every call would train people to ignore the channel.
  final String level;

  @override
  String toString() => '$code ($level): $reason';
}

/// The registry.
final class DVDiagnostics {
  const DVDiagnostics._();

  /// Every registered diagnostic, by family then number.
  static const List<DVDiagnostic> all = <DVDiagnostic>[
    DVDiagnostic(
      code: 'DV-KIOSK-001',
      reason: 'requested enforcement reduced (e.g. `device` → `supervised`)',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-002',
      reason: 'exit method degraded (e.g. `gesture+pin` → `pin` on touchless device)',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-003',
      reason: 'exit attempt failed; lockout after `maxAttempts`',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-004',
      reason: 'kiosk requested on a target without kiosk capability',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-005',
      reason: 'runtime kiosk call with no declared policy',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-006',
      reason: 'route outside `routes.allow` requested and blocked',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-007',
      reason: 'native kiosk binding missing or refused',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-008',
      reason: 'restart loop detected; diagnostics screen shown',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-009',
      reason: '`onIdle: home` with sensitive fields reachable from allowed routes',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-KIOSK-010',
      reason: 'display-scoped input confinement is device-wide on this platform',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-001',
      reason: 'target has no multi-window capability',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-002',
      reason: 'kiosk mode active; the surface stays locked',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-003',
      reason: 'web popup blocked — called outside a user gesture',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-004',
      reason: 'platform refused (OS window limit, task creation denied)',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-005',
      reason: '`windowing.enabled: false` in configuration',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-006',
      reason: 'native binding missing or refused the request',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-007',
      reason: 'owned window requested with a closed owner',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-008',
      reason: 'application modality reduced to window modality',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-009',
      reason: 'restored route missing, unauthorized, or unresolvable',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-010',
      reason: 'kiosk window\'s display unavailable; presented in place, fullscreen',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-011',
      reason: 'window requested on a kiosk-owned display; placed elsewhere',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-012',
      reason: 'move/resize/minimize/close refused on a pinned kiosk window',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-013',
      reason: '`display:` hint matched no connected display; the OS placed the window',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-CRON-001',
      reason: 'declared interval finer than the target\'s granularity; coalesced to it',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-CRON-002',
      reason: 'client schedule on a target that runs nothing in the background',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-CRON-003',
      reason: 'a run was skipped because the previous one was still running',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-CRON-004',
      reason: 'the platform refused to register background work (permission or battery policy)',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-SCHEMA-003',
      reason: 'backfill throttled below its floor for longer than the configured patience',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-SCHEMA-004',
      reason: 'chunk verification mismatch; the read switch is refused',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-SCHEMA-006',
      reason: 'adapter cannot classify a change; treated as blocking',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-SCHEMA-007',
      reason: 'dual-write discrepancy detected during verification',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-OFFLINE-001',
      reason: 'no writable storage; the store is memory-backed for this session',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-OFFLINE-002',
      reason: 'mutation log at its bound; the write was refused',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-OFFLINE-003',
      reason: 'mutation permanently rejected by the server; moved to dead letters',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-OFFLINE-004',
      reason: 'device clock skew beyond the configured tolerance',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-OFFLINE-006',
      reason: 'local store schema behind the protocol; store rebuilt from the server',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PROTO-002',
      reason: 'a client outside the window called; upgrade required',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PROTO-003',
      reason: 'response degraded for a windowed client',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-PROTO-006',
      reason: 'enum member added with no declared fallback, narrowing the window',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-3D-001',
      reason: 'scene presented as poster (unsupported target / disabled / GPU init failed)',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-3D-006',
      reason: 'texture/mesh over the device-profile budget',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-3D-007',
      reason: 'per-frame allocation detected in a scene callback',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-EXPORT-003',
      reason: 'document exceeded the configured page or byte budget',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-STORE-001',
      reason: 'a declared store credential is not resolvable in this environment',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-STORE-002',
      reason: 'privacy declaration drift between the application and the store form',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-STORE-003',
      reason: 'a store screenshot size has no declared golden',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-STORE-004',
      reason: 'a store-supported locale has no metadata written for it',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-STORE-005',
      reason: 'the store does not support an option the publish asked for',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-STORE-006',
      reason: 'required-reason API used by a binding that declares no reason',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-RELEASE-001',
      reason: 'health gate tripped; the rollout was rolled back',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-RELEASE-002',
      reason: 'the adapter cannot weight traffic; canary degraded to blue-green',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-RELEASE-003',
      reason: 'no previous release to compare against; the gate held the rollout',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-RELEASE-004',
      reason: 'per-function rollback requested; the release is the unit',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-RELEASE-005',
      reason: 'contract step refused while a windowed client still reads the old shape',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-RELEASE-006',
      reason: 'a release was deployed with no provenance record; rollback cannot name it',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-HISTORY-001',
      reason: 'write refused: the record changed since it was read',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-HISTORY-002',
      reason: '`DVConflict.ask` declared as an offline strategy, where nobody is present to ask',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-HISTORY-003',
      reason: 'revert could not restore a sensitive field; history records the change, not the value',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-HISTORY-004',
      reason: 'history entries removed by the declared retention',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-HISTORY-005',
      reason: 'history entry could not be written; the transaction was rolled back',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-HISTORY-006',
      reason: 'restore refused: a unique field is held by a live record',
      level: 'error',
    ),
  ];

  /// The diagnostic for [code], or null if nothing is registered under it.
  ///
  /// Case-insensitive and tolerant of surrounding whitespace, because the code
  /// usually arrives pasted out of a log.
  static DVDiagnostic? find(String code) {
    final String wanted = code.trim().toUpperCase();
    if (wanted.isEmpty) return null;
    for (final DVDiagnostic entry in all) {
      if (entry.code == wanted) return entry;
    }
    return null;
  }

  /// Every diagnostic in [family], e.g. `DV-WINDOW`, in numeric order.
  ///
  /// Numeric, not lexicographic: as text '10' sorts before '2', and a
  /// developer reading the list would see it out of order.
  static List<DVDiagnostic> family(String family) {
    final String prefix = '${family.trim().toUpperCase()}-';
    return <DVDiagnostic>[
      for (final DVDiagnostic entry in all)
        if (entry.code.startsWith(prefix)) entry,
    ];
  }

  /// Every family name, in the order they appear.
  static List<String> families() {
    final List<String> names = <String>[];
    for (final DVDiagnostic entry in all) {
      final String name =
          entry.code.substring(0, entry.code.lastIndexOf('-'));
      if (!names.contains(name)) names.add(name);
    }
    return names;
  }
}
