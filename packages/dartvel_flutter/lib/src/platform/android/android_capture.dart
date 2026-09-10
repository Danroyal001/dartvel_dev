/// What the Android capture bridge is asked, and what its answers mean.
///
/// Plain Dart, with no JNI in it, for two reasons. It can be tested on a
/// machine with no Android at all, which is where this framework is written;
/// and the decisions worth testing are all here rather than in the calls.
/// Whether a photo arrived is a JNI question. Whether "no photo" means the
/// person pressed back, the manifest is missing a line, or the camera wrote
/// an empty file is this file's question, and getting it wrong produces an
/// application that looks like it works.
library dartvel_flutter.platform.android.capture;

import 'dart:convert';

/// Why the last permission answer was no.
///
/// A field rather than a thrown value because a refusal is not an error --
/// people are allowed to say no -- and because the reason matters to whoever
/// is debugging rather than to the code path. It follows
/// `DVAndroidBindings.lastFailure`, which exists for the same reason: a
/// registration that failed used to be one line saying it had.
String? dvAndroidLastRefusal;

/// Whether the permission in [json] is held.
///
/// Throws when the answer is not a refusal but a mistake: a name Dartvel has
/// no permission for, or a permission the application's own manifest never
/// declared. Android treats the second as an instant denial -- no dialog is
/// shown and the result is the one a person tapping Deny produces -- so
/// reporting it as an ordinary `false` hides the only fix there is.
bool dvAndroidPermissionGranted(String json) {
  final Map<String, Object?> answer = _decode(json, 'a permission answer');
  final String name = '${answer['permission'] ?? 'the permission'}';

  final Object? error = answer['error'];
  if (error != null) {
    throw StateError('Android could not answer for $name: $error');
  }

  if (answer['declared'] == false) {
    throw StateError(
      'the Android manifest does not declare what "$name" needs '
      '(${(answer['required'] as List<Object?>? ?? const <Object?>[]).join(', ')}). '
      'Android refuses an undeclared permission without showing a dialog, so '
      'asking again cannot help. Add "$name" to dartvel.android.permissions '
      'in pubspec.yaml and run dartvel build android again.',
    );
  }

  final bool granted = answer['granted'] == true;
  if (granted) {
    dvAndroidLastRefusal = null;
    return true;
  }
  dvAndroidLastRefusal = answer['blocked'] == true
      ? 'the person refused "$name" permanently, or a device policy forbids '
          'it. Android shows no dialog for it again, so the only route left '
          'is Settings.'
      : 'the person did not grant "$name".';
  return false;
}

/// Whether a photograph cannot be taken until the camera permission is held.
///
/// It usually can be. `ACTION_IMAGE_CAPTURE` runs the camera application,
/// which holds its own permissions, so an application that never mentions
/// CAMERA may send the intent and get a photograph back.
///
/// The exception is the one that catches people: an application that
/// *declares* CAMERA in its manifest must hold it before it may send the
/// intent at all, and Android answers a violation with a SecurityException
/// on the device. Nothing on a build machine says so, and the crash names
/// the intent rather than the manifest line that caused it.
bool dvAndroidCameraNeedsPermission(String json) {
  final Map<String, Object?> answer = _decode(json, 'a permission answer');
  return answer['declared'] == true && answer['granted'] != true;
}

/// The argument a `permissions.request` or `permissions.isGranted` call
/// carries.
String dvAndroidPermissionRequest(String permission) =>
    jsonEncode(<String, Object?>{'permission': permission});

/// The argument the picker is started with.
///
/// The same two keys `media.pick` takes everywhere else, so the Android and
/// the Linux binding can be called from one piece of application code.
String dvAndroidMediaRequest({
  required String type,
  required bool multiple,
}) =>
    jsonEncode(<String, Object?>{'type': type, 'multiple': multiple});

/// The argument `location.current` carries.
String dvAndroidLocationRequest({
  Duration maxAge = const Duration(minutes: 2),
  Duration timeout = const Duration(seconds: 20),
}) =>
    jsonEncode(<String, Object?>{
      'maxAgeSeconds': maxAge.inSeconds,
      'timeoutSeconds': timeout.inSeconds,
    });

/// The argument `contacts.getContacts` carries.
String dvAndroidContactsRequest({int limit = 0}) =>
    jsonEncode(<String, Object?>{'limit': limit});

/// What was picked or captured, in the shape every other platform answers
/// `media.pick` with.
///
/// Empty means the person cancelled, which is what a closed GTK chooser
/// answers on Linux. A failure throws instead: a camera that reported
/// success and wrote nothing is a broken device, not a change of mind, and
/// an empty list would report it as one.
List<Map<String, Object?>> dvAndroidCaptureItems(String json) {
  final Map<String, Object?> answer = _decode(json, 'a capture result');
  final Object? error = answer['error'];
  if (error != null) {
    throw StateError('the Android capture failed: $error');
  }
  final Object? items = answer['items'];
  if (items is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final Object? entry in items)
      if (entry is Map)
        <String, Object?>{
          ...entry.map((Object? key, Object? value) =>
              MapEntry<String, Object?>('$key', value)),
          // Overwritten rather than defaulted: Android answers with a MIME
          // type and the desktop pickers answer with a kind, and application
          // code that switches on `type` needs one word from both.
          'type': dvAndroidMediaKind(
            entry['mimeType'] as String?,
            '${entry['name'] ?? ''}',
          ),
        },
  ];
}

/// The kind of file a MIME type and a name describe.
///
/// The words are the ones the desktop pickers use -- image, video, audio, and
/// file for everything else -- because a picked `.mkv` that arrives as
/// "video" on a laptop and "file" on a phone is a gallery that is empty on
/// one of them.
String dvAndroidMediaKind(String? mimeType, String name) {
  final String mime = (mimeType ?? '').toLowerCase();
  // octet-stream is what a provider says when it does not know, and it is
  // common enough that trusting it would call half the pictures on a phone
  // "file".
  if (mime.isNotEmpty && mime != 'application/octet-stream') {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
  }
  final int dot = name.lastIndexOf('.');
  final String extension =
      dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  for (final MapEntry<String, List<String>> kind
      in _extensions.entries) {
    if (kind.value.contains(extension)) return kind.key;
  }
  return 'file';
}

/// The same table `linux_dialogs_ffi.dart` filters its chooser with.
///
/// Duplicated deliberately rather than shared: the Linux one is the set of
/// filters a GTK dialog is given, this one is a classification of what came
/// back, and joining them would tie the picker's filters to the naming of
/// its results. The words have to agree, and the test asserts they do.
const Map<String, List<String>> _extensions = <String, List<String>>{
  'image': <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'heic'],
  'video': <String>['mp4', 'webm', 'mkv', 'mov', 'avi'],
  'audio': <String>['mp3', 'wav', 'ogg', 'flac', 'm4a'],
};

/// The address book, with every value a string.
///
/// `DVContacts.getContacts` is `List<Map<String, String>>`, so a number that
/// came back as an integer would reach application code as one on Android
/// and as a string everywhere else.
List<Map<String, String>> dvAndroidContacts(String json) {
  final Map<String, Object?> answer = _decode(json, 'the contacts');
  final Object? error = answer['error'];
  if (error != null) {
    throw StateError('the Android contacts query failed: $error');
  }
  final Object? people = answer['contacts'];
  if (people is! List) return const <Map<String, String>>[];
  return <Map<String, String>>[
    for (final Object? person in people)
      if (person is Map)
        <String, String>{
          for (final MapEntry<Object?, Object?> field in person.entries)
            '${field.key}': '${field.value ?? ''}',
        },
  ];
}

/// Where the device is.
///
/// Throws when there is no fix. `DVLocation.getCoordinates` reads latitude
/// and longitude out of this map and defaults each to zero, so an answer
/// with neither in it would put every caller off the coast of Ghana, on a
/// map, with nothing anywhere to say the number was invented.
Map<String, Object?> dvAndroidLocation(String json) {
  final Map<String, Object?> answer = _decode(json, 'a location');
  final Object? error = answer['error'];
  if (error != null) {
    throw StateError('Android has no position to give: $error');
  }
  final Object? latitude = answer['latitude'];
  final Object? longitude = answer['longitude'];
  if (latitude is! num || longitude is! num) {
    throw StateError(
      'the Android location bridge answered without coordinates '
      '($json). Nothing here is a position, and zero is a place.',
    );
  }
  return <String, Object?>{
    ...answer,
    'latitude': latitude.toDouble(),
    'longitude': longitude.toDouble(),
  };
}

/// Why `begin` refused to start, or null when it did not refuse.
///
/// The two negative answers have different fixes, and both are worse than
/// useless as a null the caller reads as "no photo".
String? dvAndroidBeginFailure(int id) {
  if (id >= 0) return null;
  if (id == -1) {
    return 'the Android capture bridge has no application Context. An APK '
        'built with plain flutter build does not carry the classes '
        'dartvel build android writes, and every platform binding is quiet '
        'without them.';
  }
  if (id == -2) {
    return 'this build of the capture bridge has no such operation. The '
        'generated Java and the Dart that calls it are out of step; '
        'rebuild with dartvel build android.';
  }
  return 'the Android capture bridge refused to start ($id).';
}

Map<String, Object?> _decode(String json, String what) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (error) {
    // The Java builds this string, so anything unparseable means the two
    // halves disagree about the protocol. Said plainly here rather than as a
    // FormatException from inside a decoder, which reads like bad input.
    throw StateError(
      'the Android bridge answered $what with something that is not JSON: '
      '$error',
    );
  }
  if (decoded is! Map) {
    throw StateError('the Android bridge answered $what with $decoded.');
  }
  return decoded.map((Object? key, Object? value) =>
      MapEntry<String, Object?>('$key', value));
}
