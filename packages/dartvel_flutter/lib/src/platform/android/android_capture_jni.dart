/// The permission-gated Android bindings: the dialog, the camera, the
/// picker, the address book and the device's position.
///
/// All five need an Activity, and the application `Context` that
/// `DartvelContext` holds is not one. `requestPermissions` is an Activity
/// method; `onRequestPermissionsResult` and `onActivityResult` are delivered
/// to an Activity and to nothing else. That is why this group of bindings
/// was the one Android had nothing for while the clipboard and the vibrator
/// worked.
///
/// The Activity is `DartvelBridgeActivity`, which `dartvel build android`
/// writes: transparent, excluded from recents, started with one operation in
/// its Intent and finished the moment the answer is in. This file starts an
/// operation and waits for it.
///
/// Waiting is polling rather than a callback into Dart. A JNI callback from
/// an arbitrary Android thread is the piece of this that is hardest to get
/// right and hardest to see going wrong, and nothing here needs one: whether
/// a person has finished with the camera is a string that either exists yet
/// or does not.
library dartvel_flutter.platform.android.capture_jni;

import 'dart:async';
import 'dart:io' show File;

import 'package:dartvel_core/dartvel.dart' show dvAndroidCaptureBridgeClass;
import 'package:jni/jni.dart';

import 'android_capture.dart';

/// The camera, the picker, contacts, location, and the permission dialog
/// they all go through.
class DVAndroidCapture {
  const DVAndroidCapture._();

  /// The names registered here.
  static const Set<String> implemented = <String>{
    'permissions.isGranted',
    'permissions.request',
    'camera.takePhoto',
    'media.pick',
    'contacts.getContacts',
    'location.current',
  };

  /// Why the bridge cannot be reached, or null when it can.
  ///
  /// Set once at registration. An APK built with plain `flutter build` has
  /// none of the generated classes, and that is the one failure worth
  /// naming before anybody presses a button.
  static String? lastFailure;

  static JClass? _bridge;

  /// How long a person is given.
  ///
  /// Long, because the wait includes reading a permission dialog, framing a
  /// photograph and finding a file. Not unbounded, because a process Android
  /// killed behind the camera takes the pending answer with it and something
  /// has to end the wait with a reason rather than never returning.
  static const Duration _patience = Duration(minutes: 5);

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    try {
      _bridge = JClass.forName(dvAndroidCaptureBridgeClass);
      lastFailure = null;
    } on Object catch (error) {
      _bridge = null;
      lastFailure = 'the class $dvAndroidCaptureBridgeClass is not in this '
          'application ($error). `dartvel build android` writes it; an APK '
          'built with plain `flutter build` has no Activity for a permission '
          'result to come back to.';
    }

    // Registered whether or not the class was found. A binding that throws
    // and says the APK is missing its generated classes is worth more than
    // an unregistered name, which reaches the caller as the same null a
    // platform that has no camera returns.
    bind('permissions.isGranted', (Object? arguments) {
      return dvAndroidPermissionGranted(_granted(_permissionIn(arguments)));
    });

    bind('permissions.request', (Object? arguments) async {
      final String permission = _permissionIn(arguments);
      // Asked first. Requesting a permission that is already held still
      // starts an Activity, and an application that checks a permission on
      // every screen would flash a transparent one each time.
      if (dvAndroidPermissionGranted(_granted(permission))) return true;
      return dvAndroidPermissionGranted(
        await _await('permissions', dvAndroidPermissionRequest(permission)),
      );
    });

    bind('camera.takePhoto', (Object? _) async {
      // ACTION_IMAGE_CAPTURE needs no permission -- the camera application
      // takes the photograph, not this one -- with one exception that
      // throws a SecurityException on the device: an application that
      // declares CAMERA in its own manifest must hold it before it may send
      // the intent at all.
      if (dvAndroidCameraNeedsPermission(_granted('camera'))) {
        final bool allowed = dvAndroidPermissionGranted(
          await _await('permissions', dvAndroidPermissionRequest('camera')),
        );
        if (!allowed) {
          throw StateError('the camera permission was refused: '
              '${dvAndroidLastRefusal ?? 'no reason was given'}');
        }
      }
      final List<Map<String, Object?>> taken =
          dvAndroidCaptureItems(await _await('camera', '{}'));
      // Cancelled. An empty list of bytes rather than an exception, because
      // pressing back is not a failure -- and it is the same answer the
      // picker gives for the same gesture.
      if (taken.isEmpty) return const <int>[];
      final String path = '${taken.first['path']}';
      final File photo = File(path);
      if (!photo.existsSync()) {
        throw StateError('the camera reported writing $path and there is no '
            'file there.');
      }
      final List<int> bytes = photo.readAsBytesSync();
      // The capture directory is a cache, and a photograph left in it is a
      // few megabytes nobody will ever look for. The bytes are the answer.
      try {
        photo.deleteSync();
      } on Object {
        // A cache Android cleared underneath us. Nothing to report: the
        // bytes are already read.
      }
      return bytes;
    });

    bind('media.pick', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      // The system picker needs no permission of any kind: it hands back a
      // grant on what was chosen rather than access to the storage it came
      // from. So this asks for nothing, which is also why it works on an
      // application that declares no permissions at all.
      return dvAndroidCaptureItems(await _await(
        'media',
        dvAndroidMediaRequest(
          type: '${map['type'] ?? 'image'}',
          multiple: map['multiple'] == true,
        ),
      ));
    });

    bind('contacts.getContacts', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      await _ensure('contacts');
      final Object? limit = map['limit'];
      return dvAndroidContacts(await _await(
        'contacts',
        dvAndroidContactsRequest(limit: limit is int ? limit : 0),
      ));
    });

    bind('location.current', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      await _ensure('location');
      final Object? seconds = map['timeoutSeconds'];
      return dvAndroidLocation(await _await(
        'location',
        dvAndroidLocationRequest(
          timeout: Duration(seconds: seconds is int ? seconds : 20),
        ),
      ));
    });
  }

  /// The permission an argument map names.
  static String _permissionIn(Object? arguments) {
    final Map<Object?, Object?> map =
        arguments is Map ? arguments : const <Object?, Object?>{};
    return '${map['permission'] ?? ''}';
  }

  /// Holds [permission], asking for it if it is not held.
  ///
  /// Throws when it is refused. A refusal is not "there are no contacts": an
  /// empty list there would be an address book that silently looks empty on
  /// a phone with four hundred people in it, which is the failure this whole
  /// slice keeps running into.
  static Future<void> _ensure(String permission) async {
    if (dvAndroidPermissionGranted(_granted(permission))) return;
    final bool allowed = dvAndroidPermissionGranted(
      await _await('permissions', dvAndroidPermissionRequest(permission)),
    );
    if (allowed) return;
    throw StateError('Android refused "$permission": '
        '${dvAndroidLastRefusal ?? 'no reason was given'}');
  }

  /// What Android says about [permission], as the bridge's JSON.
  static String _granted(String permission) {
    final JClass bridge = _class();
    final JStaticMethodId method = bridge.staticMethodId(
        'granted', '(Ljava/lang/String;)Ljava/lang/String;');
    final JString? answer = method.callNullable(
      bridge,
      JString.type,
      <dynamic>[permission.toJString()],
    );
    if (answer == null) {
      throw StateError('the Android permission bridge answered nothing for '
          '"$permission".');
    }
    return answer.toDartString(releaseOriginal: true);
  }

  /// Starts [op] and waits for its answer.
  static Future<String> _await(String op, String argument) async {
    final JClass bridge = _class();
    final JStaticMethodId begin = bridge.staticMethodId(
        'begin', '(Ljava/lang/String;Ljava/lang/String;)I');
    final int id = begin.call(
      bridge,
      jint.type,
      <dynamic>[op.toJString(), argument.toJString()],
    );
    final String? refused = dvAndroidBeginFailure(id);
    if (refused != null) throw StateError(refused);

    final JStaticMethodId poll =
        bridge.staticMethodId('poll', '(I)Ljava/lang/String;');
    final DateTime deadline = DateTime.now().add(_patience);
    // Short at first and then slower. An already-granted permission answers
    // within a frame or two, and a person choosing a photograph does not.
    Duration gap = const Duration(milliseconds: 25);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(gap);
      final JString? answer =
          poll.callNullable(bridge, JString.type, <dynamic>[id]);
      if (answer != null) return answer.toDartString(releaseOriginal: true);
      if (gap < const Duration(milliseconds: 250)) gap = gap * 2;
    }
    throw StateError(
      'Android never answered the $op request. Either it is still waiting '
      'for the person, or the process was killed behind whatever was in '
      'front and the pending answer went with it.',
    );
  }

  static JClass _class() {
    final JClass? bridge = _bridge;
    if (bridge != null) return bridge;
    throw StateError(lastFailure ??
        'the Android capture bridge was never registered.');
  }

  /// Test-only: forgets the class it found.
  static void reset() {
    _bridge = null;
    lastFailure = null;
  }
}
