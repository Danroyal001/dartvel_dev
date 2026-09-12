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
      code: 'DV-WINDOW-014',
      reason: 'volume requested where none can be presented; shown as a viewport',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-WINDOW-015',
      reason: 'immersive space requested where none can be presented; '
          'shown as a fullscreen page',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-XR-001',
      reason: 'passthrough unavailable; the studio environment was used',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-XR-002',
      reason: 'anchor type unsupported; node placed at the scene origin',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-XR-003',
      reason: 'world anchor could not re-localize on relaunch',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-XR-004',
      reason: 'pinned-panel persistence bounded or absent on this platform',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-XR-005',
      reason: 'smooth locomotion offered without comfort options',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-XR-006',
      reason: 'native XR binding missing or refused the request',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-XR-007',
      reason: "frame rate below the device profile's target for a sustained window",
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-HTTP-001',
      reason: 'request to an undeclared host',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-HTTP-002',
      reason: 'circuit breaker open; request failed fast',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-HTTP-003',
      reason: 'non-idempotent request retried without an idempotency key',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-HTTP-004',
      reason: 'a test reached the network with no fake configured',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-HTTP-005',
      reason: 'declared host used from client code with a backend-scoped secret',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-SESSION-001',
      reason: 'multi-factor required by policy and not yet satisfied',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-SESSION-002',
      reason: 'session revoked elsewhere; this device was signed out',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-SESSION-003',
      reason: 'cookie configuration weaker than the deployment allows',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-SESSION-004',
      reason: 'recovery codes generated but never downloaded',
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
      code: 'DV-SCHEMA-001',
      reason: 'a blocking change was written where an expand/contract plan exists',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-SCHEMA-002',
      reason: 'blocking migration against production without an override',
      level: 'error',
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
      code: 'DV-SCHEMA-005',
      reason: 'contract phase requested while clients inside the protocol window '
          'read the old shape',
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
      code: 'DV-OFFLINE-005',
      reason: 'offline model has no conflict strategy for a field type it merges',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-OFFLINE-006',
      reason: 'local store schema behind the protocol; store rebuilt from the server',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PROTO-001',
      reason: 'contract shape changed without incrementing the protocol version',
      level: 'error',
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
      code: 'DV-PROTO-004',
      reason: 'a lossy adaptation was requested with no declared adapter',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PROTO-005',
      reason: 'deploy would strand clients above the threshold',
      level: 'error',
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
      code: 'DV-3D-002',
      reason: 'asset failed to import or is missing at build',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-3D-003',
      reason: 'shader failed to compile for a configured target',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-3D-004',
      reason: '`scene3d` API used without `scene3d.enabled`',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-3D-005',
      reason: 'physics backend needs a toolchain the machine lacks',
      level: 'error',
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
      code: 'DV-3D-008',
      reason: '`syncTransform` bound to a non-synced model',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-EXPORT-001',
      reason: 'PDF export requested for a route with no generated document',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-EXPORT-002',
      reason: 'no PDF renderer available in this deployment',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-EXPORT-003',
      reason: 'document exceeded the configured page or byte budget',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-LINKS-001',
      reason: 'deep-link domains declared with no application identifier for a target',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-LINKS-002',
      reason: 'verification file unreachable, redirected, or not served as JSON',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-LINKS-003',
      reason: 'fingerprint in the served file does not match the signing certificate',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-LINKS-004',
      reason: 'a route the application handles is not covered by the served patterns',
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
      code: 'DV-MODULE-001',
      reason: 'a module uses a capability the parent did not grant',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-MODULE-002',
      reason: 'the same, reached at runtime where the build could not resolve '
          'it',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-MODULE-003',
      reason: "the installed module's capabilities differ from what was "
          'granted',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-MODULE-004',
      reason: "a module archive's digest does not match the lockfile",
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-MODULE-005',
      reason: "a module's publisher or signing key changed since it was pinned",
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-MODULE-006',
      reason: "egress to a domain outside the module's allowlist",
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-MODULE-007',
      reason: 'a manifest declares a capability the code never uses',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-MODULE-008',
      reason: 'a module opens its own socket or `HttpClient` instead of a '
          'generated call',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-MEDIA-001',
      reason: 'an image could not be decoded at build; no variants were written',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-MEDIA-002',
      reason: 'a variant was requested at a width outside the configured set; '
          'refused',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-MEDIA-003',
      reason: 'a remote image host is not allowed, or a redirect left the '
          'allowed host',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-MEDIA-004',
      reason: "an upload's decoded format or dimensions do not match what it "
          'declared; rejected',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-MEDIA-005',
      reason: 'the upload scan hook refused a file; it was never served',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-MEDIA-006',
      reason: 'a signed transformation URL failed verification or had expired',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-MEDIA-007',
      reason: 'a media field declares video and no encoder adapter is '
          'configured',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-AIOPS-001',
      reason: 'a stored prompt version has no counterpart in the repository; '
          'the next deploy reverts it',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-AIOPS-002',
      reason: 'feature over its token budget; the declared behaviour was taken',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-AIOPS-003',
      reason: 'a fallback step was taken (provider outage, budget, or refusal)',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-AIOPS-004',
      reason: 'provider failed and no fallback is declared; the feature is '
          'unavailable',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-AIOPS-005',
      reason: 'a context manifest names a model or field the policy forbids',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-AIOPS-006',
      reason: 'a prompt changed without incrementing its version',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-AIOPS-007',
      reason: 'eval scored below the declared threshold',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-WEBHOOK-001',
      reason: 'a payload names a field the model marks sensitive',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-WEBHOOK-002',
      reason: 'endpoint resolved to a private, loopback, link-local or '
          'metadata address; refused',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WEBHOOK-003',
      reason: 'endpoint disabled after the configured run of failures',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WEBHOOK-004',
      reason: 'delivery exhausted its retries and moved to dead letters',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WEBHOOK-005',
      reason: 'replay requested after the payload retention window',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-WEBHOOK-006',
      reason: 'an emitted event name is not in the declared catalog',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-WEBHOOK-007',
      reason: 'signing key rotated; both signatures are sent until the '
          'overlap ends',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-SEMANTIC-001',
      reason: 'a `semantic: true` field with no declared embedder',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-SEMANTIC-002',
      reason: 'the vector adapter cannot filter; semantic search refused on a '
          'scoped model',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-SEMANTIC-003',
      reason: 'embedder or chunking changed; a new index is building and '
          'queries use the previous one',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-SEMANTIC-004',
      reason: 'an embedding job failed permanently; the record is absent from '
          'the index',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-SEMANTIC-005',
      reason: 'refill bound reached; fewer results returned than asked for',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-SEMANTIC-006',
      reason: 'on-device index over its declared budget; keyword only',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-SEMANTIC-007',
      reason: 'embedding budget exhausted for this tenant; the search was '
          'refused',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PURCHASE-001',
      reason:
          'a `billable: true` model is sold on a store target without being '
          'classified digital or physical',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PURCHASE-002',
      reason:
          'a digital product has no store product identifier for a target '
          'being built',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PURCHASE-003',
      reason:
          'the store refused a receipt or purchase token; no entitlement was '
          'written',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PURCHASE-004',
      reason:
          'a store server notification named a product the project does not '
          'declare',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PURCHASE-005',
      reason:
          'an entitlement snapshot passed its `notAfter` while offline; '
          'access refused',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PURCHASE-006',
      reason:
          'a purchase was granted and not acknowledged to the store within '
          'its window',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PURCHASE-007',
      reason:
          'store prices could not be read; no price is shown rather than a '
          'converted one',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PURCHASE-008',
      reason:
          'an offline conflict strategy is declared on a server-authored '
          'entitlement model',
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
    DVDiagnostic(
      code: 'DV-ORG-001',
      reason: 'a policy names a role the application does not declare',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-ORG-002',
      reason: 'invitation refused: the address is already a member',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-ORG-003',
      reason: 'the last owner cannot leave or be demoted without a successor',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-ORG-004',
      reason: 'organization closed; restorable until the declared grace period expires',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-ORG-005',
      reason: 'SSO domain auto-join declined: the identity\'s domain is not verified',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-ORG-006',
      reason: 'membership resolved on a tenant that has no organization',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-ANALYTICS-001',
      reason: 'event dropped on the device: its category has no consent',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-ANALYTICS-002',
      reason: 'a declared consent category has no way to ask on a target the application builds for',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-ANALYTICS-003',
      reason: 'per-session event cap reached; further events dropped',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-ANALYTICS-004',
      reason: 'an event payload names a sensitive field',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-ANALYTICS-005',
      reason: 'an analytics provider is configured with no consent category declared',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-ANALYTICS-006',
      reason: 'a consent choice could not be recorded; it is not treated as consent',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-APIKEY-001',
      reason: 'a scope names a policy action that does not exist',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-APIKEY-002',
      reason: 'call refused: the key\'s scopes do not cover the action',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-APIKEY-003',
      reason: 'rotation overlap expired; the previous key no longer authenticates',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-APIKEY-004',
      reason: 'an OAuth client registration asked for an undefined scope',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-APIKEY-005',
      reason: 'a key was issued with no expiry where the configuration requires one',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-APIKEY-006',
      reason: 'a key exceeded its rate plan; the call was throttled',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-001',
      reason:
          'no rule set has synced; flags answered with the defaults compiled '
          'into the build',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-002',
      reason: 'the synced rule set names a flag this build does not declare',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-003',
      reason: 'the rule set is newer than this build understands; unreadable '
          'rules were skipped',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-004',
      reason: 'a flag is past its declared expiry',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-005',
      reason: 'a percentage rollout was evaluated with no subject identifier; '
          'the flag held its default',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-006',
      reason: "a rule's value type differs from the flag's declared type; the "
          'flag held its default',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-007',
      reason: 'exposure not recorded: consent was withheld for the declared '
          'analytics category',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-008',
      reason: 'a local override is in force; this build is not answering from '
          'the rules',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-FLAGS-009',
      reason: 'the rule set is older than `flags.maxAge` and is still in use',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-001',
      reason: 'a report was recovered from the previous run and sent at launch',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-002',
      reason: 'the build obfuscates and kept no symbols; its reports could '
          'never be read',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-003',
      reason: 'no symbols for the release a report names; the stack is '
          'unsymbolicated',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-004',
      reason: 'reports from this device were rate-limited for this release',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-005',
      reason: 'a report was dropped: the on-disk record was truncated by the '
          'crash that wrote it',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-006',
      reason: 'the native crash handler could not be installed; only '
          'Dart-level errors are captured',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-007',
      reason: 'an application hang exceeded the declared threshold',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-008',
      reason: 'a non-fatal error was dropped by the declared sampling rate',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-009',
      reason: 'crash reporting is disabled for this build',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-CRASH-010',
      reason: 'release health crossed its declared threshold; the rollout was '
          'held',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-001',
      reason: 'preview created; it is destroyed when the branch merges or its '
          'TTL expires',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-002',
      reason: 'a secret required for previews has no value; the preview was '
          'not deployed',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-003',
      reason: 'database branching refused: the source holds sensitive fields '
          'and no sanitization is declared',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-004',
      reason: 'the concurrent preview cap was reached; the oldest idle preview '
          'was suspended',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-005',
      reason: 'preview suspended after the declared idle interval',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-006',
      reason: 'an outbound notification was captured rather than sent, because '
          'this is a preview',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-007',
      reason: 'the preview is declared publicly visible; it is excluded from '
          'indexing but not from visitors',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-008',
      reason: 'a scheduled job did not run: schedules are off in previews '
          'unless declared',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-009',
      reason: 'preview destroyed; its database and storage went with it',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PREVIEW-010',
      reason: 'the deployment adapter cannot host previews',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-001',
      reason: 'a model carries a sensitive field and declares no subject path; '
          'erasure cannot reach it',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-002',
      reason: 'a model carrying personal data declares no retention; it is '
          'kept indefinitely',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-003',
      reason: 'rows were kept under a declared retention; their personal '
          'fields were anonymized',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-004',
      reason: 'an erasure passed its declared deadline',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-005',
      reason: 'a restore replayed the erasure tombstone log',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-006',
      reason: 'an exported record names another subject; only the requesting '
          "subject's contribution was included",
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-007',
      reason: 'a retention sweep deleted rows',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-008',
      reason: 'a retention sweep would delete rows a longer retention holds; '
          'the longer one won',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-009',
      reason: 'an erasure could not reach a configured adapter; the subject\'s '
          'data there was not removed',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-PRIVACY-010',
      reason: 'a consent record was retained after erasure as evidence, '
          'carrying no personal fields',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-METER-001',
      reason: 'a meter is recorded from client-reachable code',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-METER-002',
      reason: 'a duplicate recording was discarded by its idempotency key',
      level: 'debug',
    ),
    DVDiagnostic(
      code: 'DV-METER-003',
      reason: 'a meter passed a declared notification threshold',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-METER-004',
      reason: 'a meter reached its limit; the declared behaviour was applied',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-METER-005',
      reason: 'a meter declares a limit and no behaviour at the limit',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-METER-006',
      reason: 'usage could not be reported to the billing provider; it is '
          'queued, not dropped',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-METER-007',
      reason: 'a record arrived after its period closed and was accepted into '
          'it under the declared grace',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-METER-008',
      reason: 'a record arrived after the grace; it counts in the open period',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-METER-009',
      reason: 'a metered entitlement has no price on the plan; usage is '
          'counted and not billed',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-METER-010',
      reason: "the tenant has no billing period; the deployment's calendar "
          'period was used',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-001',
      reason: 'an inbound `traceparent` was malformed; a new trace was started',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-002',
      reason: 'the export queue was full; spans were dropped',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-003',
      reason: 'the collector could not be reached; spans were dropped after '
          'the declared retries',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-004',
      reason: 'a span attribute names a sensitive model field',
      level: 'error',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-005',
      reason: "a job ran outside its originating trace's window; its span is "
          'linked rather than nested',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-006',
      reason: 'no exporter is configured; spans stay in the in-process buffer',
      level: 'info',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-007',
      reason: 'the trace diagnostics endpoint is enabled; it is off by default',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-008',
      reason: 'a client span was refused: client ingest is not enabled on this '
          'deployment',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-009',
      reason: 'a span passed its maximum duration and was closed as incomplete',
      level: 'warning',
    ),
    DVDiagnostic(
      code: 'DV-TRACE-010',
      reason: 'a span reached its attribute limit; further attributes were '
          'dropped',
      level: 'warning',
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
