/// `location.current`, `sensors.accelerometer` and `sensors.gyroscope`.
///
/// Geolocation is in every browser and behind a permission prompt in all of
/// them. The Generic Sensor API is Chromium only and needs the hardware to be
/// there as well, so the two motion bindings are registered only where the
/// constructors exist — on Firefox and Safari the names stay unregistered and
/// `DVNativeBridge.isRegistered` says so, rather than a call returning zeroes
/// that look like a device lying still.
///
/// The zeroes are the point. `DVLocation.getCoordinates` reads `latitude` and
/// `longitude` out of the answer and falls back to 0 for each, and 0,0 is a
/// spot in the Gulf of Guinea that a map will happily draw a pin on. A
/// refusal here throws [DVWebPermissionDenied] instead, which nothing can
/// mistake for a position.
library dartvel_flutter.platform.web.sensors;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_capabilities.dart';
import 'web_interop.dart';

class DVWebSensors {
  const DVWebSensors._();

  static const Set<String> locationBindings = <String>{'location.current'};
  static const Set<String> motionBindings = <String>{
    'sensors.accelerometer',
    'sensors.gyroscope',
  };

  /// Whether this browser has Geolocation.
  ///
  /// Absent outside a secure context, which is the case worth catching: the
  /// same page served over http has no location API at all, and registering
  /// the binding there would promise something the origin can never deliver.
  static bool get locationAvailable {
    final JSObject? navigator = dvNavigator;
    return navigator != null && dvJsObject(navigator, 'geolocation') != null;
  }

  /// Whether the Generic Sensor constructor [name] is defined.
  static bool motionAvailable(String name) =>
      dvJsMethod(globalContext, name) != null;

  static void registerLocation(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('location.current', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final Object? timeout = map['timeoutMs'];
      return currentPosition(
        highAccuracy: map['highAccuracy'] == true,
        timeout: Duration(milliseconds: timeout is int ? timeout : 15000),
      );
    });
  }

  /// Where the device is, or a refusal that says which kind it was.
  ///
  /// The three failures the browser distinguishes are kept apart. Denial is
  /// permanent until somebody changes a setting; an unavailable position and
  /// a timeout are both worth retrying, and an application that treats them
  /// the same either nags or gives up too early.
  static Future<Map<String, Object?>> currentPosition({
    bool highAccuracy = false,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final Completer<Map<String, Object?>> done =
        Completer<Map<String, Object?>>();

    void succeed(web.GeolocationPosition position) {
      if (done.isCompleted) return;
      final web.GeolocationCoordinates coords = position.coords;
      done.complete(<String, Object?>{
        'latitude': coords.latitude,
        'longitude': coords.longitude,
        'accuracy': coords.accuracy,
        if (coords.altitude != null) 'altitude': coords.altitude,
        if (coords.heading != null) 'heading': coords.heading,
        if (coords.speed != null) 'speed': coords.speed,
        'timestamp': position.timestamp,
      });
    }

    void fail(web.GeolocationPositionError error) {
      if (done.isCompleted) return;
      final String message = error.message.isEmpty
          ? 'the browser gave no reason'
          : error.message;
      done.completeError(switch (error.code) {
        1 => const DVWebPermissionDenied(
            'location.current',
            'the person denied this page access to their location',
          ),
        2 => StateError('location.current failed: no position is available '
            'right now ($message).'),
        _ => StateError('location.current failed: the browser gave up '
            'waiting for a fix ($message).'),
      });
    }

    web.window.navigator.geolocation.getCurrentPosition(
      succeed.toJS,
      fail.toJS,
      web.PositionOptions(
        enableHighAccuracy: highAccuracy,
        timeout: timeout.inMilliseconds,
        // Zero, so a position is read now rather than handed back from a
        // cache. A binding named "current" that answers with where the device
        // was an hour ago is the sort of wrong value that still looks right.
        maximumAge: 0,
      ),
    );

    return done.future;
  }

  static void registerMotion(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    if (motionAvailable('Accelerometer')) {
      register(
        'sensors.accelerometer',
        (Object? _) => reading('sensors.accelerometer', 'Accelerometer'),
      );
    }
    if (motionAvailable('Gyroscope')) {
      register(
        'sensors.gyroscope',
        (Object? _) => reading('sensors.gyroscope', 'Gyroscope'),
      );
    }
  }

  /// One reading from the sensor built by the global constructor [type].
  ///
  /// Started, read once and stopped. A sensor left running keeps the hardware
  /// awake, and the surface that calls this yields a single value, so holding
  /// it open would cost battery for a reading nobody is waiting for.
  static Future<Map<String, Object?>> reading(
    String binding,
    String type,
  ) async {
    final JSFunction constructor = dvJsMethod(globalContext, type)!;
    final JSObject sensor = constructor.callAsConstructor<JSObject>(
      JSObject()..setProperty('frequency'.toJS, 60.toJS),
    );

    final Completer<Map<String, Object?>> done =
        Completer<Map<String, Object?>>();

    void onReading(web.Event _) {
      if (done.isCompleted) return;
      done.complete(<String, Object?>{
        'x': dvJsNum(sensor, 'x') ?? 0,
        'y': dvJsNum(sensor, 'y') ?? 0,
        'z': dvJsNum(sensor, 'z') ?? 0,
      });
    }

    void onError(web.Event event) {
      if (done.isCompleted) return;
      final JSObject? error = dvJsObject(event as JSObject, 'error');
      final String name =
          error == null ? '' : dvJsString(error, 'name') ?? '';
      final String message =
          error == null ? '' : dvJsString(error, 'message') ?? '';
      // NotAllowedError is a permissions-policy or a person saying no.
      // NotReadableError is hardware that is present and not answering, which
      // no amount of asking will fix.
      done.completeError(
        name == 'NotAllowedError'
            ? DVWebPermissionDenied(
                binding,
                message.isEmpty ? 'the browser refused the sensor' : message,
              )
            : StateError('$binding failed: ${name.isEmpty ? 'the sensor '
                'reported an error with no name' : name}'
                '${message.isEmpty ? '' : ' ($message)'}.'),
      );
    }

    final JSFunction readingHandler = onReading.toJS;
    final JSFunction errorHandler = onError.toJS;
    await dvJsCall(sensor, 'addEventListener',
        <JSAny?>['reading'.toJS, readingHandler]);
    await dvJsCall(
        sensor, 'addEventListener', <JSAny?>['error'.toJS, errorHandler]);

    try {
      await dvJsCall(sensor, 'start');
      return await done.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError(
          '$binding failed: the sensor started and sent no reading within '
          'five seconds, which usually means the hardware is not there.',
        ),
      );
    } finally {
      await dvJsCall(sensor, 'removeEventListener',
          <JSAny?>['reading'.toJS, readingHandler]);
      await dvJsCall(sensor, 'removeEventListener',
          <JSAny?>['error'.toJS, errorHandler]);
      await dvJsCall(sensor, 'stop');
    }
  }
}
