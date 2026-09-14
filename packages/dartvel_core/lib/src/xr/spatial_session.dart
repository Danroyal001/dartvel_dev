/// The XR runtime: presenting in space, and the session that keeps doing so
/// honestly for as long as it lasts.
///
/// What the runtime owns is everything that must be true whichever device is
/// underneath: a presentation that could not be made in space says why; the
/// camera behind passthrough is opened only with permission, and closed when
/// the application leaves the screen, when the permission is withdrawn, and
/// when the session ends; tracking stops with it; a world anchor is written
/// to storage only with consent, and only as the OS's own token; no pose,
/// anchor position or light estimate reaches a report.
library dartvel.xr.session;

import 'dart:async';

import '../diagnostics/diagnostics.dart';
import '../lifecycle/lifecycle.dart';
import '../media/capture_backend.dart' show DVCapturePermissions;
import '../observability/observability.dart';
import '../scene3d/scene_anchor.dart';
import '../scene3d/scene_camera.dart';
import '../scene3d/scene_graph.dart';
import '../scene3d/scene_math.dart';
import 'spatial_capability.dart';
import 'spatial_comfort.dart';
import 'spatial_input.dart';
import 'spatial_pose.dart';
import 'xr_device.dart';

/// Receives an XR diagnostic. Context never carries environment or body data.
typedef DVXRDiagnosticSink = void Function(
    String code, String message, Map<String, Object?> context);

/// Logs [code] at the level the diagnostic registry assigns it.
void dvLogXRDiagnostic(String code, String message, Map<String, Object?> context) {
  final String level = DVDiagnostics.find(code)?.level ?? 'warning';
  DVObservability.log(
    '$code: $message',
    level: switch (level) {
      'debug' => DVLogLevel.debug,
      'info' => DVLogLevel.info,
      'error' => DVLogLevel.error,
      _ => DVLogLevel.warn,
    },
    code: code,
    context: context,
  );
}

/// A use of environment data that needs somebody's agreement.
enum DVSpatialDataUse {
  /// Keeping a world anchor across launches.
  persistAnchors,

  /// Sending an anchor to another device. Nothing sends one yet.
  shareAnchors,
}

/// Whether a use of environment data is agreed to.
abstract interface class DVSpatialConsent {
  bool granted(DVSpatialDataUse use);

  /// Nothing is agreed to: the default.
  static const DVSpatialConsent denyAll = _DenyAll();
}

final class _DenyAll implements DVSpatialConsent {
  const _DenyAll();

  @override
  bool granted(DVSpatialDataUse use) => false;
}

/// Where world anchor tokens are kept between launches, by anchor id.
///
/// Holds the OS's opaque token and never a pose. The Flutter store keeps
/// them under `xr.anchors.*` in the shared window store.
abstract interface class DVSpatialAnchorStore {
  Future<String?> read(String id);
  Future<void> write(String id, String token);
  Future<void> remove(String id);
}

final class DVMemorySpatialAnchorStore implements DVSpatialAnchorStore {
  final Map<String, String> _tokens = <String, String>{};

  @override
  Future<String?> read(String id) async => _tokens[id];

  @override
  Future<void> write(String id, String token) async => _tokens[id] = token;

  @override
  Future<void> remove(String id) async => _tokens.remove(id);
}

/// Why a request was not presented in space.
enum DVSpatialRefusal {
  /// The target has no spatial capability for this kind (`DV-WINDOW-014`,
  /// `DV-WINDOW-015`).
  noCapability,

  /// An immersive space is already open in this application.
  exclusive,

  /// The application was not on screen.
  backgrounded,

  /// The capability was reported and no device binding is there
  /// (`DV-XR-006`).
  bindingMissing,

  /// A binding threw (`DV-XR-006`).
  bindingFailed,

  /// The platform declined (`DV-WINDOW-004`).
  platformRefused,
}

/// The answer to a request to present in space.
final class DVSpatialPresentation {
  const DVSpatialPresentation._(this.session, this.refusal, this.codes);

  /// The session, when the request is presented in space.
  final DVSpatialSession? session;
  final DVSpatialRefusal? refusal;

  /// What was reported: a cause code, if the cause has its own, then the
  /// window code saying the presentation was not honoured.
  final List<String> codes;

  bool get inSpace => session != null;
}

enum DVSpatialSessionState { starting, running, paused, ending, ended }

/// What a scene in space is lit by.
enum DVSpatialLighting { realEnvironment, studio }

/// Where an anchored node's anchor is.
enum DVSpatialAnchorStatus {
  searching,
  tracking,
  lost,

  /// This target cannot make this type of anchor: at the origin (`DV-XR-002`).
  unsupported,

  /// A world anchor from an earlier launch that could not be found again
  /// (`DV-XR-003`). Hidden rather than drifting.
  notRelocalized,
}

/// The XR runtime for one application.
final class DVXRRuntime {
  DVXRRuntime({
    required this.device,
    required this.capability,
    required this.permissions,
    DVLifecycleSignal<DVAppLifecycle>? lifecycle,
    this.consent = DVSpatialConsent.denyAll,
    this.anchorStore,
    DVXRDiagnosticSink? diagnostics,
    this.targetFps = 90,
    this.reducedMotion = false,
  })  : lifecycle = lifecycle ?? dvLifecycle.app,
        diagnostics = diagnostics ?? dvLogXRDiagnostic;

  final DVXRDevice? device;

  /// `capability.spatial`; null where the target is not a headset or glasses.
  final DVSpatialCapability? capability;
  final DVCapturePermissions permissions;
  final DVLifecycleSignal<DVAppLifecycle> lifecycle;
  final DVSpatialConsent consent;
  final DVSpatialAnchorStore? anchorStore;
  final DVXRDiagnosticSink diagnostics;

  /// `xr.performance.targetFps`.
  final double targetFps;
  final bool reducedMotion;

  final List<DVSpatialSession> _sessions = <DVSpatialSession>[];

  /// Sessions not yet ended.
  List<DVSpatialSession> get sessions => List<DVSpatialSession>.unmodifiable(_sessions);

  static bool _inBackground(DVAppLifecycle app) =>
      app == DVAppLifecycle.backgrounded ||
      app == DVAppLifecycle.suspended ||
      app == DVAppLifecycle.shuttingDown;

  /// Presents [request] in space, or says why it cannot.
  ///
  /// Never throws for a device failure: the window presenting the route falls
  /// back, and the returned codes are what it reports.
  Future<DVSpatialPresentation> present(DVSpatialSpaceRequest request) async {
    final String windowCode =
        request.kind == DVSpatialSpaceKind.volume ? 'DV-WINDOW-014' : 'DV-WINDOW-015';

    DVSpatialPresentation refuse(DVSpatialRefusal refusal, {String? binding}) {
      final String? cause = switch (refusal) {
        DVSpatialRefusal.bindingMissing || DVSpatialRefusal.bindingFailed => 'DV-XR-006',
        DVSpatialRefusal.platformRefused => 'DV-WINDOW-004',
        _ => null,
      };
      final Map<String, Object?> context = <String, Object?>{
        'route': request.route,
        'kind': request.kind.name,
        'refusal': refusal.name,
        if (binding != null) 'binding': binding,
      };
      if (cause != null) {
        diagnostics(
          cause,
          switch (refusal) {
            DVSpatialRefusal.bindingMissing =>
              'the target reports ${request.kind.name}s and no XR device binding is registered',
            DVSpatialRefusal.bindingFailed => 'the XR binding ${binding ?? ''} failed',
            _ => 'the platform declined the ${request.kind.name}',
          },
          context,
        );
      }
      diagnostics(
        windowCode,
        request.kind == DVSpatialSpaceKind.volume
            ? 'a volume could not be presented; shown as a viewport'
            : 'an immersive space could not be presented; shown as a fullscreen page',
        context,
      );
      return DVSpatialPresentation._(
          null, refusal, List<String>.unmodifiable(<String>[if (cause != null) cause, windowCode]));
    }

    final DVSpatialCapability? cap = capability;
    if (cap == null || !cap.supports(request.kind)) {
      return refuse(DVSpatialRefusal.noCapability);
    }
    if (request.kind == DVSpatialSpaceKind.immersive &&
        _sessions.any((DVSpatialSession s) => s.request.kind == DVSpatialSpaceKind.immersive)) {
      return refuse(DVSpatialRefusal.exclusive);
    }
    if (_inBackground(lifecycle.value)) return refuse(DVSpatialRefusal.backgrounded);
    final DVXRDevice? dev = device;
    if (dev == null) return refuse(DVSpatialRefusal.bindingMissing);

    final DVSpatialSession session = DVSpatialSession._(this, dev, cap, request);
    _sessions.add(session);
    final (DVSpatialRefusal, String?)? failed = await session._start(initial: true);
    if (failed != null) {
      await session._end();
      return refuse(failed.$1, binding: failed.$2);
    }
    session._watchLifecycle();
    return DVSpatialPresentation._(session, null, const <String>[]);
  }

  /// Ends every session this runtime opened.
  Future<void> dispose() async {
    for (final DVSpatialSession session in List<DVSpatialSession>.of(_sessions)) {
      await session.close();
    }
  }
}

final class _Attachment {
  _Attachment(this.graph, this.onTap, this.onGrab, this.onRelease);

  final DVSceneGraph graph;
  final Map<String, void Function()> onTap;
  final Map<String, void Function()> onGrab;
  final Map<String, void Function()> onRelease;
  final Map<String, DVSpatialAnchorStatus> status = <String, DVSpatialAnchorStatus>{};
  final Set<String> persisted = <String>{};
  final Set<String> reported = <String>{};
}

/// A presentation in space: one volume or immersive space, owned by the
/// window that opened it.
///
/// Every signal is read-only and moved by the runtime from what the device
/// reported: [passthrough] cannot say "off" while the camera is still on,
/// because nothing but the device's own confirmation, or the space closing,
/// moves it.
final class DVSpatialSession {
  DVSpatialSession._(this._runtime, this._device, this.capability, this.request)
      : comfort = request.kind == DVSpatialSpaceKind.immersive
            ? DVComfort.resolve(request.comfort ?? const DVComfortOptions(),
                    reducedMotion: _runtime.reducedMotion)
                .effective
            : (request.comfort ?? const DVComfortOptions()),
        _monitor = DVSpatialFrameMonitor(targetFps: _runtime.targetFps);

  final DVXRRuntime _runtime;
  final DVXRDevice _device;
  final DVSpatialCapability capability;
  final DVSpatialSpaceRequest request;

  /// The comfort options in force, after the policy.
  final DVComfortOptions comfort;
  final DVSpatialFrameMonitor _monitor;

  final DVMutableLifecycleSignal<DVSpatialSessionState> _state =
      DVMutableLifecycleSignal<DVSpatialSessionState>(DVSpatialSessionState.starting);
  final DVMutableLifecycleSignal<DVImmersion?> _immersion =
      DVMutableLifecycleSignal<DVImmersion?>(null);
  final DVMutableLifecycleSignal<bool> _passthrough = DVMutableLifecycleSignal<bool>(false);
  final DVMutableLifecycleSignal<bool> _tracking = DVMutableLifecycleSignal<bool>(false);
  final DVMutableLifecycleSignal<DVSpatialLighting> _lighting =
      DVMutableLifecycleSignal<DVSpatialLighting>(DVSpatialLighting.studio);

  final List<String> _codes = <String>[];
  final List<_Attachment> _attachments = <_Attachment>[];
  final Map<String, (_Attachment, String)> _anchorNodes = <String, (_Attachment, String)>{};

  String? _session;
  String? _space;
  StreamSubscription<DVXRDeviceEvent>? _events;
  StreamSubscription<DVAppLifecycle>? _lifecycle;
  DVSpatialPose? _headPose;
  Future<void> _queue = Future<void>.value();
  bool _comfortReported = false;

  DVLifecycleSignal<DVSpatialSessionState> get state => _state;

  /// The immersion granted: null for a volume, and [DVImmersion.full] where
  /// passthrough was asked for and could not be given.
  DVLifecycleSignal<DVImmersion?> get immersion => _immersion;

  /// Whether the camera feed is on, as the device last confirmed.
  DVLifecycleSignal<bool> get passthrough => _passthrough;

  /// Whether the device is tracking.
  DVLifecycleSignal<bool> get tracking => _tracking;

  DVLifecycleSignal<DVSpatialLighting> get lighting => _lighting;

  /// The XR codes this session reported, in order.
  List<String> get codes => List<String>.unmodifiable(_codes);

  /// The last head pose, in world space. Body data: for drawing frames, and
  /// never reported.
  DVSpatialPose? get headPose => _headPose;

  /// A camera at the head, or null before the device has reported one.
  DVSceneView? view({double fovYDegrees = 90}) => _headPose?.view(fovYDegrees: fovYDegrees);

  DVSpatialAnchorStatus? anchorStatus(String nodeId) {
    for (final _Attachment a in _attachments.reversed) {
      final DVSpatialAnchorStatus? s = a.status[nodeId];
      if (s != null) return s;
    }
    return null;
  }

  /// Whether a world anchor's token is kept for the next launch.
  bool isPersisted(String nodeId) =>
      _attachments.any((_Attachment a) => a.persisted.contains(nodeId));

  bool get _ended =>
      _state.value == DVSpatialSessionState.ending || _state.value == DVSpatialSessionState.ended;

  void _report(String code, String message, [Map<String, Object?> context = const <String, Object?>{}]) {
    _codes.add(code);
    _runtime.diagnostics(code, message, <String, Object?>{
      'route': request.route,
      'kind': request.kind.name,
      ...context,
    });
  }

  void _bindingFailed(String binding, Object error) {
    _report('DV-XR-006', 'the XR binding $binding failed',
        <String, Object?>{'binding': binding, 'error': error.runtimeType.toString()});
  }

  Future<void> _serial(Future<void> Function() op) {
    final Future<void> next = _queue.then((_) => op()).catchError((Object _) {});
    _queue = next;
    return next;
  }

  void _watchLifecycle() {
    _lifecycle = _runtime.lifecycle.listen((DVAppLifecycle app) {
      if (DVXRRuntime._inBackground(app)) {
        return _serial(_pause);
      }
      if (app == DVAppLifecycle.ready || app == DVAppLifecycle.resuming) {
        return _serial(_resume);
      }
    });
  }

  /// Opens the session and space. Returns why not, with the binding at fault.
  Future<(DVSpatialRefusal, String?)?> _start({required bool initial}) async {
    final String? session;
    try {
      session = await _device.openSession();
    } on Object catch (error) {
      if (!initial) _bindingFailed('xr.session.open', error);
      return (DVSpatialRefusal.bindingFailed, 'xr.session.open');
    }
    if (session == null) return (DVSpatialRefusal.platformRefused, 'xr.session.open');
    _session = session;
    try {
      _events = _device.observe(session).listen(_onEvent);
    } on Object catch (error) {
      if (!initial) _bindingFailed('xr.input.observe', error);
      return (DVSpatialRefusal.bindingFailed, 'xr.input.observe');
    }
    _tracking.set(true);

    final bool immersive = request.kind == DVSpatialSpaceKind.immersive;
    final bool wantsPassthrough = immersive && request.immersion == DVImmersion.passthrough;
    String? notPassthrough;
    bool granted = false;
    if (wantsPassthrough) {
      if (!capability.passthrough) {
        notPassthrough = 'this target has no passthrough';
      } else {
        granted = await _runtime.permissions.request('camera');
        if (!granted) notPassthrough = 'the camera permission was refused';
      }
    }
    if (_ended) return null;
    // A permission prompt can outlast the application being on screen.
    if (DVXRRuntime._inBackground(_runtime.lifecycle.value)) {
      return (DVSpatialRefusal.backgrounded, null);
    }

    final DVImmersion? immersion =
        immersive ? (wantsPassthrough && !granted ? DVImmersion.full : request.immersion) : null;
    final String? space;
    try {
      space = await _device.openSpace(
          session, immersion == null ? request : request.withImmersion(immersion));
    } on Object catch (error) {
      if (!initial) _bindingFailed('xr.space.open', error);
      return (DVSpatialRefusal.bindingFailed, 'xr.space.open');
    }
    if (space == null) return (DVSpatialRefusal.platformRefused, 'xr.space.open');
    _space = space;
    _immersion.set(immersion);

    if (granted) {
      try {
        await _device.setPassthrough(space, true);
      } on Object catch (error) {
        _bindingFailed('xr.passthrough.set', error);
        granted = false;
        notPassthrough = 'the passthrough binding failed';
        _immersion.set(DVImmersion.full);
      }
    }

    DVSpatialLightProbe? probe;
    try {
      probe = await _device.probeEnvironment(session);
    } on Object catch (error) {
      _bindingFailed('xr.environment.probe', error);
    }
    _lighting.set(probe != null && _immersion.value != DVImmersion.full
        ? DVSpatialLighting.realEnvironment
        : DVSpatialLighting.studio);
    if (wantsPassthrough && (notPassthrough != null || probe == null)) {
      _report('DV-XR-001', 'passthrough unavailable; the studio environment was used',
          <String, Object?>{'reason': notPassthrough ?? 'no environment probe on this target'});
    }
    if (immersive && !_comfortReported) {
      _comfortReported = true;
      if (DVComfort.resolve(request.comfort ?? const DVComfortOptions()).codes.isNotEmpty) {
        _report('DV-XR-005', 'smooth locomotion offered without comfort options; a vignette was applied');
      }
    }
    _state.set(DVSpatialSessionState.running);
    return null;
  }

  /// Stops the camera, the space and tracking, in that order.
  Future<void> _stopDevice() async {
    final String? space = _space;
    _space = null;
    if (space != null) {
      try {
        await _device.closeSpace(space);
      } on Object catch (error) {
        _bindingFailed('xr.space.close', error);
      }
      // A closed space has no camera feed, whatever event did or did not
      // arrive.
      _passthrough.set(false);
    }
    final String? session = _session;
    _session = null;
    if (session != null) {
      try {
        await _device.closeSession(session);
      } on Object catch (error) {
        _bindingFailed('xr.session.close', error);
      }
    }
    await _events?.cancel();
    _events = null;
    _tracking.set(false);
    _anchorNodes.clear();
    for (final _Attachment a in _attachments) {
      for (final String id in a.graph.anchoredIds) {
        if (a.graph.anchorPlacementOf(id) == DVSceneAnchorPlacement.located) {
          a.graph.hideAnchor(id);
        }
      }
    }
  }

  Future<void> _pause() async {
    if (_state.value != DVSpatialSessionState.running) return;
    await _stopDevice();
    if (!_ended) _state.set(DVSpatialSessionState.paused);
  }

  Future<void> _resume() async {
    if (_state.value != DVSpatialSessionState.paused) return;
    _state.set(DVSpatialSessionState.starting);
    final (DVSpatialRefusal, String?)? failed = await _start(initial: false);
    if (failed == null) {
      for (final _Attachment a in _attachments) {
        await _trackAnchors(a);
      }
      return;
    }
    await _stopDevice();
    if (failed.$1 == DVSpatialRefusal.backgrounded) {
      _state.set(DVSpatialSessionState.paused);
    } else {
      await _end();
    }
  }

  /// Places [graph]'s anchored nodes and routes input to its handlers, for as
  /// long as the session lasts.
  Future<void> attach(
    DVSceneGraph graph, {
    Map<String, void Function()> onTap = const <String, void Function()>{},
    Map<String, void Function()> onGrab = const <String, void Function()>{},
    Map<String, void Function()> onRelease = const <String, void Function()>{},
  }) =>
      _serial(() async {
        if (_ended) return;
        final _Attachment a = _Attachment(graph, onTap, onGrab, onRelease);
        _attachments.add(a);
        if (_state.value == DVSpatialSessionState.running) await _trackAnchors(a);
      });

  Future<void> _trackAnchors(_Attachment a) async {
    final DVSceneGraph graph = a.graph;
    for (final String id in graph.anchoredIds) {
      final String? session = _session;
      if (session == null || _ended) return;
      final DVAnchor anchor = graph.data(id).anchor!;
      if (!capability.anchors.contains(anchor.type)) {
        _unsupported(a, id, anchor);
        continue;
      }
      graph.hideAnchor(id);
      a.status[id] = DVSpatialAnchorStatus.searching;

      if (anchor.type == DVAnchorType.world) {
        final DVSpatialAnchorStore? store = _runtime.anchorStore;
        final bool mayPersist = _runtime.consent.granted(DVSpatialDataUse.persistAnchors);
        String? token = store == null ? null : await store.read(anchor.id!);
        if (token != null && !mayPersist) {
          // Agreement withdrawn since the token was written: it goes, and the
          // anchor lives for this session only.
          await store!.remove(anchor.id!);
          token = null;
        }
        if (token != null) {
          String? handle;
          try {
            handle = await _device.resolveAnchor(session, token);
          } on Object catch (error) {
            _bindingFailed('xr.anchor.resolve', error);
          }
          if (handle == null) {
            a.status[id] = DVSpatialAnchorStatus.notRelocalized;
            _report('DV-XR-003', 'world anchor could not re-localize on relaunch',
                <String, Object?>{'node': id, 'anchor': anchor.id});
          } else {
            _anchorNodes[handle] = (a, id);
            a.persisted.add(id);
          }
          continue;
        }
      }

      String? handle;
      try {
        handle = await _device.createAnchor(session, anchor);
      } on Object catch (error) {
        _bindingFailed('xr.anchor.create', error);
      }
      if (handle == null) {
        _unsupported(a, id, anchor);
      } else {
        _anchorNodes[handle] = (a, id);
      }
    }
  }

  void _unsupported(_Attachment a, String id, DVAnchor anchor) {
    a.graph.anchorAtOrigin(id);
    a.status[id] = DVSpatialAnchorStatus.unsupported;
    if (a.reported.add(id)) {
      _report('DV-XR-002', 'anchor type unsupported; node placed at the scene origin',
          <String, Object?>{'node': id, 'anchorType': anchor.type.name});
    }
  }

  Future<void> _persist(_Attachment a, String id, String handle) async {
    final DVAnchor anchor = a.graph.data(id).anchor!;
    final DVSpatialAnchorStore? store = _runtime.anchorStore;
    final String? session = _session;
    if (anchor.type != DVAnchorType.world ||
        store == null ||
        session == null ||
        a.persisted.contains(id) ||
        !_runtime.consent.granted(DVSpatialDataUse.persistAnchors)) {
      return;
    }
    a.persisted.add(id);
    String? token;
    try {
      token = await _device.persistAnchor(session, handle);
    } on Object catch (error) {
      _bindingFailed('xr.anchor.persist', error);
    }
    if (token == null) {
      a.persisted.remove(id);
      return;
    }
    await store.write(anchor.id!, token);
  }

  void _onEvent(DVXRDeviceEvent event) {
    if (_state.value == DVSpatialSessionState.ended) return;
    switch (event) {
      case DVXRPassthroughChanged(:final bool enabled):
        _passthrough.set(enabled);
      case DVXRTrackingChanged(:final bool tracking):
        _tracking.set(tracking);
      case DVXRPermissionRevoked(:final String permission):
        if (permission == 'camera') unawaited(_serial(_cameraRevoked));
      case DVXRSpaceEnded():
        unawaited(_serial(_end));
      case final DVXRAnchorChanged changed:
        final String anchor = changed.anchor;
        final (_Attachment, String)? target = _anchorNodes[anchor];
        if (target == null) return;
        final (_Attachment a, String id) = target;
        if (!changed.located) {
          a.graph.hideAnchor(id);
          a.status[id] = DVSpatialAnchorStatus.lost;
          return;
        }
        final DVSpatialPose pose =
            _device.convention.poseToWorld(changed.position!, changed.orientation!);
        a.graph.placeAnchor(id, pose.matrix);
        a.status[id] = DVSpatialAnchorStatus.tracking;
        unawaited(_serial(() => _persist(a, id, anchor)));
      case DVXRHeadPoseChanged(:final position, :final orientation):
        _headPose = _device.convention.poseToWorld(position, orientation);
      case DVXRFrameTimed(:final Duration interval, :final bool reprojected):
        if (_monitor.record(interval, reprojected: reprojected)) {
          _report('DV-XR-007', "frame rate below the device profile's target for a sustained window",
              <String, Object?>{
                'targetFps': _runtime.targetFps,
                'measuredFps': _monitor.measuredFps.round(),
              });
        }
      case DVXRInput(event: final DVSpatialInputEvent input):
        _dispatch(input);
    }
  }

  Future<void> _cameraRevoked() async {
    if (_immersion.value != DVImmersion.passthrough) return;
    final String? space = _space;
    if (space != null) {
      try {
        await _device.setPassthrough(space, false);
      } on Object catch (error) {
        _bindingFailed('xr.passthrough.set', error);
        // The feed cannot be trusted to have stopped; close the space rather
        // than leave a camera running that the user just withdrew.
        await _end();
        return;
      }
    }
    _immersion.set(DVImmersion.full);
    _lighting.set(DVSpatialLighting.studio);
    _report('DV-XR-001', 'passthrough unavailable; the studio environment was used',
        const <String, Object?>{'reason': 'the camera permission was revoked'});
  }

  void _dispatch(DVSpatialInputEvent input) {
    for (final _Attachment a in _attachments.reversed) {
      final Map<String, void Function()> handlers = switch (input.action) {
        DVSpatialInputAction.select => a.onTap,
        DVSpatialInputAction.grab => a.onGrab,
        DVSpatialInputAction.release => a.onRelease,
      };
      String? id = input.nodeId;
      if (id != null && !a.graph.contains(id)) continue;
      if (id == null) {
        id = a.graph
            .pick(_worldRay(_device.convention, input.origin!, input.direction!))
            ?.nodeId;
      }
      while (id != null) {
        final void Function()? handler = handlers[id];
        if (handler != null) {
          handler();
          return;
        }
        id = a.graph.parentOf(id);
      }
    }
  }

  Future<void> _end() async {
    if (_state.value == DVSpatialSessionState.ended) return;
    _state.set(DVSpatialSessionState.ending);
    await _stopDevice();
    await _lifecycle?.cancel();
    _lifecycle = null;
    _runtime._sessions.remove(this);
    _state.set(DVSpatialSessionState.ended);
  }

  /// Ends the session: the camera, the space and tracking stop, once.
  Future<void> close() => _serial(_end);
}

/// A ray the device reported, in world space.
DVRay _worldRay(DVSpatialConvention convention, DVVec3 origin, DVVec3 direction) {
  final DVMat4 m = convention.toWorld;
  return DVRay(m.transformPoint(origin), m.transformDirection(direction).normalized());
}
