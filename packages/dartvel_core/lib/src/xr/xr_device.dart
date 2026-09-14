/// The XR device adapter: the contract a native binding implements, and a
/// headless device that implements it for tests.
///
/// One method per binding the specification names, and nothing else. A
/// device reports what happened; the session decides what that means. The
/// real adapters are generated FFI/JNI bindings (never platform channels) and
/// do not exist yet: `DVXRDevice.bindingNames` is the whole surface they owe.
library dartvel.xr.device;

import 'dart:async';

import '../scene3d/scene_anchor.dart';
import '../scene3d/scene_math.dart';
import 'spatial_capability.dart';
import 'spatial_comfort.dart';
import 'spatial_input.dart';
import 'spatial_pose.dart';

/// What a window asked to present in space.
final class DVSpatialSpaceRequest {
  const DVSpatialSpaceRequest({
    required this.kind,
    required this.route,
    this.immersion = DVImmersion.full,
    this.volume,
    this.comfort,
  });

  final DVSpatialSpaceKind kind;
  final String route;

  /// For an immersive space. Ignored for a volume.
  final DVImmersion immersion;
  final DVVolumeOptions? volume;

  /// For an immersive space: the locomotion it offers.
  final DVComfortOptions? comfort;

  DVSpatialSpaceRequest withImmersion(DVImmersion immersion) => DVSpatialSpaceRequest(
        kind: kind,
        route: route,
        immersion: immersion,
        volume: volume,
        comfort: comfort,
      );
}

/// Lighting estimated from the real environment. Environment data: it never
/// prints its values.
final class DVSpatialLightProbe {
  const DVSpatialLightProbe({
    required this.intensity,
    this.sphericalHarmonics = const <double>[],
  });

  final double intensity;

  /// Nine RGB coefficients, when the device estimates them.
  final List<double> sphericalHarmonics;

  @override
  String toString() => 'DVSpatialLightProbe(<redacted>)';
}

/// A binding that is present and failed, or absent where a capability said
/// it would be there. Reported as `DV-XR-006`, an error: an integration
/// defect, not a capability limit.
final class DVXRBindingException implements Exception {
  const DVXRBindingException(this.binding, [this.reason]);

  final String binding;
  final String? reason;

  @override
  String toString() =>
      'DVXRBindingException: $binding${reason == null ? '' : ': $reason'} (DV-XR-006)';
}

/// Something the device reports.
sealed class DVXRDeviceEvent {
  const DVXRDeviceEvent();
}

/// The camera feed behind a space turned on or off.
final class DVXRPassthroughChanged extends DVXRDeviceEvent {
  const DVXRPassthroughChanged(this.enabled);
  final bool enabled;
}

final class DVXRTrackingChanged extends DVXRDeviceEvent {
  const DVXRTrackingChanged(this.tracking);
  final bool tracking;
}

/// A permission was withdrawn while the session ran -- from system settings,
/// or by the OS.
final class DVXRPermissionRevoked extends DVXRDeviceEvent {
  const DVXRPermissionRevoked(this.permission);
  final String permission;
}

/// The system closed the space: the user left it with the home gesture, or
/// another application took the immersive space.
final class DVXRSpaceEnded extends DVXRDeviceEvent {
  const DVXRSpaceEnded();
}

/// An anchor moved, in the device's convention; no pose means it was lost.
final class DVXRAnchorChanged extends DVXRDeviceEvent {
  const DVXRAnchorChanged(this.anchor, {this.position, this.orientation});

  final String anchor;
  final DVVec3? position;
  final DVQuat? orientation;

  bool get located => position != null && orientation != null;

  @override
  String toString() => 'DVXRAnchorChanged($anchor, located: $located)';
}

/// Where the head is, in the device's convention. Body data.
final class DVXRHeadPoseChanged extends DVXRDeviceEvent {
  const DVXRHeadPoseChanged(this.position, this.orientation);

  final DVVec3 position;
  final DVQuat orientation;

  @override
  String toString() => 'DVXRHeadPoseChanged(<redacted>)';
}

/// One displayed frame.
final class DVXRFrameTimed extends DVXRDeviceEvent {
  const DVXRFrameTimed(this.interval, {this.reprojected = false});

  final Duration interval;

  /// The compositor reprojected an old frame because this one was late.
  final bool reprojected;
}

final class DVXRInput extends DVXRDeviceEvent {
  const DVXRInput(this.event);
  final DVSpatialInputEvent event;
}

/// An XR device.
///
/// Null from a method that returns a handle is the designed way of saying the
/// platform declined (`DV-WINDOW-004` for a space). A thrown exception is the
/// binding breaking (`DV-XR-006`).
abstract interface class DVXRDevice {
  /// Every binding a device is reached through, as the specification names
  /// them.
  static const Set<String> bindingNames = <String>{
    'xr.session.open',
    'xr.session.close',
    'xr.space.open',
    'xr.space.close',
    'xr.anchor.create',
    'xr.anchor.persist',
    'xr.anchor.resolve',
    'xr.input.observe',
    'xr.passthrough.set',
    'xr.environment.probe',
    'xr.capability.query',
  };

  /// The convention poses, anchors and rays are reported in.
  DVSpatialConvention get convention;

  /// `xr.capability.query`. Null on a target that is not a headset or glasses.
  Future<DVSpatialCapability?> queryCapability();

  /// `xr.session.open`: tracking starts.
  Future<String?> openSession();

  /// `xr.session.close`: tracking stops.
  Future<void> closeSession(String session);

  /// `xr.space.open`.
  Future<String?> openSpace(String session, DVSpatialSpaceRequest request);

  /// `xr.space.close`. The camera feed of a closed space is off.
  Future<void> closeSpace(String space);

  /// `xr.passthrough.set`. The device confirms with [DVXRPassthroughChanged].
  Future<void> setPassthrough(String space, bool enabled);

  /// `xr.anchor.create`. Null when the platform could not make one.
  Future<String?> createAnchor(String session, DVAnchor anchor);

  /// `xr.anchor.persist`: an opaque OS token for a located anchor, or null.
  Future<String?> persistAnchor(String session, String anchor);

  /// `xr.anchor.resolve`: the anchor a token names, or null when it could not
  /// be re-localized.
  Future<String?> resolveAnchor(String session, String token);

  /// `xr.environment.probe`: real-world lighting, or null where none.
  Future<DVSpatialLightProbe?> probeEnvironment(String session);

  /// `xr.input.observe`: everything the device reports for [session].
  Stream<DVXRDeviceEvent> observe(String session);
}

/// A headless device, and what `DV.Test.fakeXR` installs.
///
/// Stricter than a real device on purpose: closing a session or space twice,
/// closing a session that still has a space open, or using a closed handle
/// throws, so a lifetime bug fails a test rather than leaving a camera on in
/// somebody's headset. [cameraOn] and [openSessions] are what a test asserts
/// the camera and tracking against.
final class DVXRFakeDevice implements DVXRDevice {
  DVXRFakeDevice({
    this.capability,
    this.convention = DVSpatialConvention.openXR,
    Set<String> failing = const <String>{},
    Set<String> refusing = const <String>{},
    this.probe,
    Set<String> relocalizable = const <String>{},
  })  : failing = Set<String>.of(failing),
        refusing = Set<String>.of(refusing),
        relocalizable = Set<String>.of(relocalizable);

  final DVSpatialCapability? capability;

  @override
  final DVSpatialConvention convention;

  /// Bindings that throw, as a broken binding does.
  final Set<String> failing;

  /// Bindings that answer null, as a platform that declines does.
  final Set<String> refusing;
  final DVSpatialLightProbe? probe;

  /// Tokens [resolveAnchor] can re-localize.
  final Set<String> relocalizable;

  /// Every binding called, in order.
  final List<String> calls = <String>[];

  /// Every anchor handle created or resolved, in order.
  final List<String> anchors = <String>[];

  final Set<String> _sessions = <String>{};
  final Map<String, String> _spaces = <String, String>{};
  final Set<String> _passthrough = <String>{};
  final StreamController<DVXRDeviceEvent> _events =
      StreamController<DVXRDeviceEvent>.broadcast(sync: true);
  int _next = 1;

  int get openSessions => _sessions.length;
  int get openSpaces => _spaces.length;

  /// Whether any space has its camera feed on.
  bool get cameraOn => _passthrough.isNotEmpty;

  /// Delivers [event] to every observer.
  void emit(DVXRDeviceEvent event) => _events.add(event);

  /// Breaks the event stream, as a binding that failed mid-session does.
  void emitError(Object error) => _events.addError(error);

  Future<T?> _call<T>(String binding, T? Function() body) async {
    calls.add(binding);
    if (failing.contains(binding)) {
      throw DVXRBindingException(binding, 'the fake was told to fail');
    }
    if (refusing.contains(binding)) return null;
    return body();
  }

  void _session(String session) {
    if (!_sessions.contains(session)) {
      throw StateError('$session is not open.');
    }
  }

  @override
  Future<DVSpatialCapability?> queryCapability() =>
      _call('xr.capability.query', () => capability);

  @override
  Future<String?> openSession() => _call('xr.session.open', () {
        final String id = 'session-${_next++}';
        _sessions.add(id);
        return id;
      });

  @override
  Future<void> closeSession(String session) => _call<void>('xr.session.close', () {
        if (_spaces.values.contains(session)) {
          throw StateError('$session was closed with a space still open.');
        }
        if (!_sessions.remove(session)) {
          throw StateError('$session was closed twice or never opened.');
        }
      });

  @override
  Future<String?> openSpace(String session, DVSpatialSpaceRequest request) =>
      _call('xr.space.open', () {
        _session(session);
        final String id = 'space-${_next++}';
        _spaces[id] = session;
        return id;
      });

  @override
  Future<void> closeSpace(String space) => _call<void>('xr.space.close', () {
        if (_spaces.remove(space) == null) {
          throw StateError('$space was closed twice or never opened.');
        }
        if (_passthrough.remove(space)) emit(const DVXRPassthroughChanged(false));
      });

  @override
  Future<void> setPassthrough(String space, bool enabled) =>
      _call<void>('xr.passthrough.set', () {
        if (!_spaces.containsKey(space)) throw StateError('$space is not open.');
        final bool changed = enabled ? _passthrough.add(space) : _passthrough.remove(space);
        if (changed) emit(DVXRPassthroughChanged(enabled));
      });

  @override
  Future<String?> createAnchor(String session, DVAnchor anchor) =>
      _call('xr.anchor.create', () {
        _session(session);
        final String id = 'anchor-${_next++}';
        anchors.add(id);
        return id;
      });

  @override
  Future<String?> persistAnchor(String session, String anchor) =>
      _call('xr.anchor.persist', () {
        _session(session);
        return 'token-$anchor';
      });

  @override
  Future<String?> resolveAnchor(String session, String token) =>
      _call('xr.anchor.resolve', () {
        _session(session);
        if (!relocalizable.contains(token)) return null;
        final String id = 'anchor-${_next++}';
        anchors.add(id);
        return id;
      });

  @override
  Future<DVSpatialLightProbe?> probeEnvironment(String session) =>
      _call('xr.environment.probe', () {
        _session(session);
        return probe;
      });

  @override
  Stream<DVXRDeviceEvent> observe(String session) {
    calls.add('xr.input.observe');
    _session(session);
    return _events.stream;
  }
}
