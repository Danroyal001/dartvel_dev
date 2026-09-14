/// XR on Flutter: the runtime `DV.Window` presents volumes and immersive
/// spaces through, the device reached through generated native bindings,
/// anchor tokens in the shared window store, and `DV.Test.fakeXR`.
///
/// Native integration is `DVNativeBridge` only, which generated FFI/ffigen
/// and JNI/jnigen bindings register into. There are no platform channels
/// here, and there will not be.
library dartvel_flutter.xr;

import 'dart:async';

import '../../dartvel_flutter.dart';

/// Where `DV.Window` gets its XR runtime.
///
/// Nothing is installed by default, and that is the honest default: until a
/// target registers `xr.capability.query` and reports a headset,
/// `capability.spatial` is null and every volume or immersive request
/// presents as a page and says so.
abstract final class DVXR {
  static DVSpatialCapability? _capability;
  static DVXRDevice? _device;
  static DVCapturePermissions? _permissions;
  static DVSpatialConsent _consent = DVSpatialConsent.denyAll;
  static DVSpatialAnchorStore? _anchorStore;
  static double _targetFps = 90;
  static DVXRRuntime? _runtime;
  static String? _lastBindingFailure;

  /// `DV.Window.capability.spatial`.
  static DVSpatialCapability? get capability => _capability;

  /// The binding that last failed in [refresh], for a doctor to name.
  static String? get lastBindingFailure => _lastBindingFailure;

  /// The runtime, created on first use from what was installed.
  static DVXRRuntime get runtime => _runtime ??= DVXRRuntime(
        device: _device,
        capability: _capability,
        permissions: _permissions ?? const DVPlatformXRPermissions(),
        lifecycle: DV.lifecycle.app,
        consent: _consent,
        anchorStore: _anchorStore ?? DVSharedStoreAnchorStore(DVWindowManager.shared),
        targetFps: _targetFps,
      );

  /// Installs what this target can do in space and the device behind it.
  ///
  /// A runtime already made is disposed, which ends its sessions: a space
  /// kept open against a device that is no longer the installed one would
  /// be a camera nobody can close.
  static void install({
    required DVSpatialCapability? capability,
    DVXRDevice? device,
    DVCapturePermissions? permissions,
    DVSpatialConsent? consent,
    DVSpatialAnchorStore? anchorStore,
    double? targetFps,
  }) {
    _discard();
    _capability = capability;
    _device = device;
    _permissions = permissions;
    _consent = consent ?? DVSpatialConsent.denyAll;
    _anchorStore = anchorStore;
    _targetFps = targetFps ?? 90;
  }

  /// Asks `xr.capability.query` what this target is, and installs the
  /// answer with the binding device behind it.
  ///
  /// No binding registered is not a headset. A binding that throws or
  /// answers something that is not a capability report is `DV-XR-006`, and
  /// is also not a headset: offering a spatial control on the strength of a
  /// broken report would be a promise the next call breaks.
  static Future<DVSpatialCapability?> refresh({
    DVSpatialConvention convention = DVSpatialConvention.openXR,
  }) async {
    _lastBindingFailure = null;
    if (!DVNativeBridge.isRegistered('xr.capability.query')) {
      install(capability: null);
      return null;
    }
    try {
      final DVSpatialCapability? found =
          await DVXRBindingDevice(convention: convention).queryCapability();
      install(
        capability: found,
        device: found == null ? null : DVXRBindingDevice(convention: convention),
      );
      return found;
    } on DVXRBindingException catch (error) {
      _lastBindingFailure = error.binding;
      dvLogXRDiagnostic(
        'DV-XR-006',
        'the XR binding ${error.binding} failed',
        <String, Object?>{'binding': error.binding},
      );
      install(capability: null);
      return null;
    }
  }

  static void _discard() {
    final DVXRRuntime? runtime = _runtime;
    _runtime = null;
    if (runtime != null) unawaited(runtime.dispose());
  }

  /// Forgets everything installed without waiting for sessions to close.
  /// `DVWindowManager.reset` calls this.
  static void clear() {
    _discard();
    _capability = null;
    _device = null;
    _permissions = null;
    _consent = DVSpatialConsent.denyAll;
    _anchorStore = null;
    _targetFps = 90;
    _lastBindingFailure = null;
  }

  /// Ends every session, then forgets everything installed.
  static Future<void> reset() async {
    final DVXRRuntime? runtime = _runtime;
    _runtime = null;
    clear();
    await runtime?.dispose();
  }
}

/// Camera permission through `DV.Platform.permissions`.
///
/// A permissions binding that is not registered answers "not granted": the
/// session then presents without passthrough and says so (`DV-XR-001`),
/// rather than throwing out of `open()`, which never fails.
final class DVPlatformXRPermissions implements DVCapturePermissions {
  const DVPlatformXRPermissions();

  @override
  Future<bool> request(String permission) async {
    try {
      return await DV.Platform.permissions.request(permission);
    } on StateError {
      return false;
    }
  }
}

/// World anchor tokens under `xr.anchors.*` in the shared window store.
///
/// The store encrypts that namespace under the application key whatever
/// cipher it was given, and when no key can be had a token is refused
/// ([DVSpatialAnchorNotStored]) rather than kept in plaintext. `xr.` is a
/// reserved namespace, so an application key can neither read nor forge one.
final class DVSharedStoreAnchorStore implements DVSpatialAnchorStore {
  DVSharedStoreAnchorStore(this.store);

  static const String prefix = 'xr.anchors.';

  final DVWindowSharedStore store;

  @override
  Future<String?> read(String id) async {
    final DVJsonValue? value = await store.getReserved('$prefix$id');
    return value is DVJsonString ? value.value : null;
  }

  @override
  Future<void> write(String id, String token) async {
    try {
      await store.setReserved('$prefix$id', DVJsonString(token));
    } on DVSharedStoreSealUnavailable catch (refused) {
      throw DVSpatialAnchorNotStored(id, refused.reason);
    }
  }

  @override
  Future<void> remove(String id) => store.setReserved('$prefix$id', null);

  @override
  Future<List<String>> ids() async => <String>[
        for (final String key in await store.keys())
          if (key.startsWith(prefix)) key.substring(prefix.length),
      ];
}

/// The XR device reached through generated native bindings.
///
/// A binding that is not registered, throws, or answers the wrong shape is a
/// [DVXRBindingException] (`DV-XR-006`), never a silent null: null is kept
/// for the platform declining, which a binding says on purpose.
final class DVXRBindingDevice implements DVXRDevice {
  const DVXRBindingDevice({this.convention = DVSpatialConvention.openXR});

  @override
  final DVSpatialConvention convention;

  static Future<T> _guard<T>(String binding, Future<T> Function() call) async {
    try {
      return await call();
    } on DVXRBindingException {
      rethrow;
    } on StateError catch (error) {
      throw DVXRBindingException(binding, error.message);
    } on Object catch (error) {
      throw DVXRBindingException(binding, error.runtimeType.toString());
    }
  }

  @override
  Future<DVSpatialCapability?> queryCapability() => _guard('xr.capability.query', () async {
        final Object? payload = await DVNativeBridge.require<Object?>('xr.capability.query');
        return payload == null ? null : DVSpatialCapability.fromJson(payload);
      });

  @override
  Future<String?> openSession() => _guard(
      'xr.session.open', () => DVNativeBridge.require<String?>('xr.session.open'));

  @override
  Future<void> closeSession(String session) => _guard('xr.session.close',
      () => DVNativeBridge.require<Object?>('xr.session.close', <String, Object?>{'session': session}));

  @override
  Future<String?> openSpace(String session, DVSpatialSpaceRequest request) =>
      _guard('xr.space.open', () {
        final DVVec3? size = request.volume?.size;
        return DVNativeBridge.require<String?>('xr.space.open', <String, Object?>{
          'session': session,
          'kind': request.kind.name,
          'route': request.route,
          if (request.kind == DVSpatialSpaceKind.immersive) 'immersion': request.immersion.name,
          if (size != null) 'size': size.toList(),
        });
      });

  @override
  Future<void> closeSpace(String space) => _guard('xr.space.close',
      () => DVNativeBridge.require<Object?>('xr.space.close', <String, Object?>{'space': space}));

  @override
  Future<void> setPassthrough(String space, bool enabled) => _guard(
      'xr.passthrough.set',
      () => DVNativeBridge.require<Object?>(
          'xr.passthrough.set', <String, Object?>{'space': space, 'enabled': enabled}));

  @override
  Future<String?> createAnchor(String session, DVAnchor anchor) => _guard(
      'xr.anchor.create',
      () => DVNativeBridge.require<String?>(
          'xr.anchor.create', <String, Object?>{'session': session, 'anchor': anchor.toJson()}));

  @override
  Future<String?> persistAnchor(String session, String anchor) => _guard(
      'xr.anchor.persist',
      () => DVNativeBridge.require<String?>(
          'xr.anchor.persist', <String, Object?>{'session': session, 'anchor': anchor}));

  @override
  Future<String?> resolveAnchor(String session, String token) => _guard(
      'xr.anchor.resolve',
      () => DVNativeBridge.require<String?>(
          'xr.anchor.resolve', <String, Object?>{'session': session, 'token': token}));

  @override
  Future<DVSpatialLightProbe?> probeEnvironment(String session) =>
      _guard('xr.environment.probe', () async {
        final Object? payload = await DVNativeBridge.require<Object?>(
            'xr.environment.probe', <String, Object?>{'session': session});
        if (payload == null) return null;
        if (payload is! Map || payload['intensity'] is! num) {
          throw const FormatException('a light probe needs a numeric intensity');
        }
        final Object? sh = payload['sphericalHarmonics'];
        return DVSpatialLightProbe(
          intensity: (payload['intensity']! as num).toDouble(),
          sphericalHarmonics: sh is List
              ? <double>[for (final Object? v in sh) if (v is num) v.toDouble()]
              : const <double>[],
        );
      });

  /// Events from `xr.input.observe`, which answers with a stream of payloads.
  ///
  /// A malformed payload breaks the stream, which ends the session: a device
  /// whose events cannot be read cannot be heard revoking the camera.
  @override
  Stream<DVXRDeviceEvent> observe(String session) async* {
    final Object? source = await _guard('xr.input.observe',
        () => DVNativeBridge.require<Object?>('xr.input.observe', <String, Object?>{'session': session}));
    if (source is! Stream) {
      throw const DVXRBindingException('xr.input.observe', 'did not answer with a stream');
    }
    await for (final Object? payload in source) {
      final DVXRDeviceEvent? event = decodeEvent(payload);
      if (event != null) yield event;
    }
  }

  /// One event payload. An event type this version does not know is null
  /// and skipped; a known type with the wrong shape throws.
  static DVXRDeviceEvent? decodeEvent(Object? payload) {
    if (payload is! Map) throw FormatException('an XR event must be an object, not $payload');
    DVVec3 vec3(Object? v) {
      if (v is List && v.length == 3 && v.every((Object? n) => n is num)) {
        return DVVec3((v[0]! as num).toDouble(), (v[1]! as num).toDouble(), (v[2]! as num).toDouble());
      }
      throw const FormatException('expected three numbers');
    }

    DVQuat quat(Object? v) {
      if (v is List && v.length == 4 && v.every((Object? n) => n is num)) {
        return DVQuat((v[0]! as num).toDouble(), (v[1]! as num).toDouble(),
            (v[2]! as num).toDouble(), (v[3]! as num).toDouble());
      }
      throw const FormatException('expected four numbers');
    }

    T field<T>(String key) {
      final Object? v = payload[key];
      if (v is T) return v;
      throw FormatException("'$key' is missing or the wrong type in a ${payload['type']} event");
    }

    T pick<T extends Enum>(List<T> values, String key) {
      final String name = field<String>(key);
      for (final T v in values) {
        if (v.name == name) return v;
      }
      throw FormatException("'$name' is not a ${T.toString()}");
    }

    switch (payload['type']) {
      case 'passthrough':
        return DVXRPassthroughChanged(field<bool>('enabled'));
      case 'tracking':
        return DVXRTrackingChanged(field<bool>('tracking'));
      case 'permissionRevoked':
        return DVXRPermissionRevoked(field<String>('permission'));
      case 'spaceEnded':
        return const DVXRSpaceEnded();
      case 'anchor':
        final bool located = payload['position'] != null;
        return DVXRAnchorChanged(
          field<String>('anchor'),
          position: located ? vec3(payload['position']) : null,
          orientation: located ? quat(payload['orientation']) : null,
        );
      case 'headPose':
        return DVXRHeadPoseChanged(vec3(payload['position']), quat(payload['orientation']));
      case 'frame':
        return DVXRFrameTimed(
          Duration(microseconds: field<int>('intervalMicros')),
          reprojected: payload['reprojected'] == true,
        );
      case 'input':
        final DVSpatialInputAction action = pick(DVSpatialInputAction.values, 'action');
        final DVSpatialInputSource source = pick(DVSpatialInputSource.values, 'source');
        final Object? node = payload['node'];
        if (node is String) {
          return DVXRInput(DVSpatialInputEvent.target(action, source, node));
        }
        return DVXRInput(DVSpatialInputEvent.ray(action, source,
            origin: vec3(payload['origin']), direction: vec3(payload['direction'])));
      default:
        return null;
    }
  }
}

final class _FakeCameraPermission implements DVCapturePermissions {
  const _FakeCameraPermission(this.granted);
  final bool granted;

  @override
  Future<bool> request(String permission) async => granted;
}

/// `DV.Test.fakeXR(...)`.
extension DVXRTestHarness on DVTestHarness {
  /// Installs [capability] with a headless device behind it, and returns the
  /// device; null installs a phone -- no capability, no device -- and returns
  /// null.
  ///
  /// Explicit for the same reason `fakeWindowing` is: a test asserting that a
  /// volume presents as a page must not pass because nothing was installed
  /// on the host it happened to run on. [grantCamera] is what the camera
  /// permission prompt answers. Anchor tokens go to memory, and nothing is
  /// consented to unless [consent] says so. `DVXR.reset()` takes it away.
  DVXRFakeDevice? fakeXR(
    DVSpatialCapability? capability, {
    bool grantCamera = true,
    DVSpatialConsent? consent,
    DVSpatialConvention convention = DVSpatialConvention.openXR,
  }) {
    final DVXRFakeDevice? device = capability == null
        ? null
        : DVXRFakeDevice(capability: capability, convention: convention);
    DVXR.install(
      capability: capability,
      device: device,
      permissions: _FakeCameraPermission(grantCamera),
      consent: consent,
      anchorStore: DVMemorySpatialAnchorStore(),
    );
    return device;
  }
}
