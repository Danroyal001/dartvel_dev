/// `permissions.isGranted` and `permissions.request` in a browser.
///
/// Reading a state is one API and asking for a grant is not an API at all.
/// `navigator.permissions.query` tells you where a capability stands;
/// there is no `navigator.permissions.request`, on purpose — the browser
/// makes a page ask through the feature it wants, so the prompt appears
/// attached to something the person just did. `request` here therefore runs
/// the real asking path for each capability that has one: `requestPermission`
/// for notifications, `getUserMedia` for the camera and microphone, a
/// position fix for location, `storage.persist()` for durable storage.
///
/// Where no asking path exists, this answers with the current state rather
/// than pretending to have asked, and says so in the doc comment on
/// [request]. A `true` that was never earned is the failure this whole
/// directory is arranged against.
library dartvel_flutter.platform.web.permissions;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_files_js.dart';
import 'web_interop.dart';

class DVWebPermissions {
  const DVWebPermissions._();

  static const Set<String> implemented = <String>{
    'permissions.isGranted',
    'permissions.request',
  };

  /// Whether this browser has the Permissions API.
  static bool get available {
    final JSObject? navigator = dvNavigator;
    if (navigator == null) return false;
    final JSObject? permissions = dvJsObject(navigator, 'permissions');
    return permissions != null && dvJsMethod(permissions, 'query') != null;
  }

  /// What Dartvel's permission names are called in a browser.
  ///
  /// The left-hand names are the ones the desktop bindings answer for, so an
  /// application asking for `location` gets the same question answered on
  /// every target. The right-hand names are from the Permissions API
  /// registry, which is why several look nothing like their Dartvel spelling.
  static const Map<String, String> browserNames = <String, String>{
    'notifications': 'notifications',
    'camera': 'camera',
    'microphone': 'microphone',
    'location': 'geolocation',
    'geolocation': 'geolocation',
    'clipboard': 'clipboard-read',
    'clipboard-read': 'clipboard-read',
    'clipboard-write': 'clipboard-write',
    'storage': 'persistent-storage',
    'persistent-storage': 'persistent-storage',
    'bluetooth': 'bluetooth',
    'nfc': 'nfc',
    'accelerometer': 'accelerometer',
    'gyroscope': 'gyroscope',
    'magnetometer': 'magnetometer',
    'midi': 'midi',
    'push': 'push',
    'screen-wake-lock': 'screen-wake-lock',
    'window-management': 'window-management',
  };

  /// Capabilities a browser gives a page without a prompt.
  ///
  /// `files` is the origin-private file system, which belongs to the origin
  /// and is never asked about. `photos` is the file picker, which is a grant
  /// the person makes by choosing a file rather than one they are asked for
  /// in advance. Both answer true where the mechanism exists, which is a
  /// statement about this browser rather than a default.
  static const Set<String> implicit = <String>{'files', 'photos'};

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('permissions.isGranted', (Object? arguments) async {
      final String permission = _named(arguments);
      if (implicit.contains(permission)) return _implicitlyGranted(permission);
      return await state(permission) == 'granted';
    });

    register('permissions.request', (Object? arguments) async {
      final String permission = _named(arguments);
      if (implicit.contains(permission)) return _implicitlyGranted(permission);
      return request(permission);
    });
  }

  static bool _implicitlyGranted(String permission) =>
      permission == 'files' ? DVWebFiles.available : true;

  static String _named(Object? arguments) {
    final Map<Object?, Object?> map =
        arguments is Map ? arguments : const <Object?, Object?>{};
    final String permission = '${map['permission'] ?? ''}'.toLowerCase();
    if (permission.isEmpty) {
      throw ArgumentError('A permissions.* binding needs a "permission".');
    }
    return permission;
  }

  /// `granted`, `denied` or `prompt` for [permission].
  ///
  /// Throws for a name this browser has never heard of rather than answering
  /// `denied`. The two are worlds apart to whoever is reading the code: one
  /// is a person's decision and the other is a typo, and both used to arrive
  /// as false.
  static Future<String> state(String permission) async {
    final String? name = browserNames[permission];
    if (name == null) {
      throw ArgumentError(
        'A browser has no "$permission" permission. The names it answers for '
        'are ${browserNames.keys.join(', ')}.',
      );
    }
    try {
      final web.PermissionStatus status = await web.window.navigator.permissions
          .query(JSObject()..setProperty('name'.toJS, name.toJS))
          .toDart;
      return status.state;
    } on Object catch (error) {
      // Chrome, Firefox and Safari each recognise a different subset of the
      // registry, and querying one the engine does not know throws a
      // TypeError. Saying which name was refused is what turns a stack trace
      // into a fix.
      throw StateError(
        'This browser does not answer permission queries for "$name": '
        '${dvJsReason(error)}',
      );
    }
  }

  /// Asks for [permission] and answers whether it ended up granted.
  ///
  /// For the four capabilities with a real asking path this runs it, which
  /// means a prompt appears. For everything else the browser offers no way to
  /// ask ahead of time — the grant happens when the API is first used — so
  /// this reports the current state instead. That is the honest answer, and
  /// it is why a caller should treat a false from those as "not yet" rather
  /// than as a refusal.
  static Future<bool> request(String permission) async {
    switch (permission) {
      case 'notifications':
        final JSFunction? ask = _notificationRequest();
        if (ask == null) return false;
        final JSAny? outcome = await dvJsAwait(ask.callAsFunction(
          dvJsObject(globalContext, 'Notification'),
        ));
        return outcome.dartify() == 'granted';

      case 'camera':
      case 'microphone':
        return _media(video: permission == 'camera');

      case 'location':
      case 'geolocation':
        return _location();

      case 'storage':
      case 'persistent-storage':
        final JSObject? navigator = dvNavigator;
        final JSObject? storage =
            navigator == null ? null : dvJsObject(navigator, 'storage');
        if (storage == null || dvJsMethod(storage, 'persist') == null) {
          return false;
        }
        return await dvJsCall(storage, 'persist').then(
          (JSAny? value) => value.dartify() == true,
        );

      default:
        return await state(permission) == 'granted';
    }
  }

  static JSFunction? _notificationRequest() {
    final JSObject? notification = dvJsObject(globalContext, 'Notification');
    return notification == null
        ? null
        : dvJsMethod(notification, 'requestPermission');
  }

  /// Opens the device, then closes it again.
  ///
  /// The stream has to be stopped: asking for the camera and leaving it on
  /// puts the recording light next to a page that only wanted to know
  /// whether it was allowed.
  static Future<bool> _media({required bool video}) async {
    final JSObject? navigator = dvNavigator;
    final JSObject? devices =
        navigator == null ? null : dvJsObject(navigator, 'mediaDevices');
    if (devices == null || dvJsMethod(devices, 'getUserMedia') == null) {
      return false;
    }
    web.MediaStream? stream;
    try {
      stream = await web.window.navigator.mediaDevices
          .getUserMedia(video
              ? web.MediaStreamConstraints(video: true.toJS)
              : web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      return true;
    } on Object {
      // Denied, dismissed, or no such device. All three mean the application
      // does not have it, which is what was asked.
      return false;
    } finally {
      final web.MediaStream? open = stream;
      if (open != null) {
        final JSArray<web.MediaStreamTrack> tracks = open.getTracks();
        for (int i = 0; i < tracks.length; i++) {
          tracks.toDart[i].stop();
        }
      }
    }
  }

  /// One position fix, purely to make the browser ask.
  ///
  /// A position that is unavailable or slow is not a refusal: the prompt was
  /// answered yes and the satellites are the problem. Only code 1, the
  /// person saying no, is false.
  static Future<bool> _location() {
    final Completer<bool> done = Completer<bool>();
    void succeed(web.GeolocationPosition _) {
      if (!done.isCompleted) done.complete(true);
    }

    void fail(web.GeolocationPositionError error) {
      if (!done.isCompleted) done.complete(error.code != 1);
    }

    final JSObject? navigator = dvNavigator;
    if (navigator == null || dvJsObject(navigator, 'geolocation') == null) {
      return Future<bool>.value(false);
    }
    web.window.navigator.geolocation.getCurrentPosition(
      succeed.toJS,
      fail.toJS,
      web.PositionOptions(timeout: 15000),
    );
    return done.future;
  }
}
