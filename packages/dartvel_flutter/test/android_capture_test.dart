// The Dart half of Android's permission-gated capture bindings.
//
// The Java runs on a phone and this does not, so what is checked here is
// everything between the two: the arguments each binding sends, and what it
// makes of the answer that comes back. That is where the failures are silent.
// A binding that returns an empty list for "the person cancelled" and the
// same empty list for "this application never declared the permission" is
// indistinguishable from working, which is the bug class this platform has
// already shipped once.
//
// The JNI call itself needs a device. The emulator job in
// runtime-verification runs
// examples/dartvel_example/integration_test/android_capture_test.dart, which
// is where "the binding is registered and answers" is established.
import 'package:dartvel_flutter/src/platform/android/android_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('asking for a permission', () {
    test('a manifest that never declared it is not a refusal', () {
      // Android refuses an undeclared permission instantly: no dialog, and
      // the same denied result a person tapping Deny produces. Reported as
      // an ordinary refusal, the fix -- one line in pubspec.yaml -- is
      // invisible, and the application asks again on every launch for
      // something that can never be granted.
      expect(
        () => dvAndroidPermissionGranted(
          '{"permission":"camera","granted":false,"declared":false,'
          '"required":["android.permission.CAMERA"]}',
        ),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
            allOf(contains('camera'), contains('pubspec.yaml')))),
      );
    });

    test('a person saying no is a plain false', () {
      expect(
        dvAndroidPermissionGranted(
          '{"permission":"camera","granted":false,"declared":true,'
          '"blocked":false,"required":["android.permission.CAMERA"]}',
        ),
        isFalse,
      );
    });

    test('a permission that needs nothing is granted', () {
      // The clipboard asks Android for nothing at all, and an empty
      // requirement list is not the same as an unknown name.
      expect(
        dvAndroidPermissionGranted(
          '{"permission":"clipboard","granted":true,"declared":true,'
          '"required":[]}',
        ),
        isTrue,
      );
    });

    test('a name Dartvel does not have throws rather than answering no', () {
      // A typo answered `false` is a permission screen no button gets past.
      expect(
        () => dvAndroidPermissionGranted(
            '{"permission":"camrea","error":"Dartvel has no permission '
            'called camrea"}'),
        throwsA(isA<StateError>()),
      );
    });

    test('a permanent refusal is remembered so it can be explained', () {
      // "Don't ask again" cannot be undone by asking again. An application
      // that knows the difference can send the person to Settings; one that
      // does not shows the same dialog request forever, and Android shows
      // nothing.
      dvAndroidPermissionGranted(
        '{"permission":"location","granted":false,"declared":true,'
        '"blocked":true,"required":["android.permission.ACCESS_FINE_LOCATION"]}',
      );
      expect(dvAndroidLastRefusal, contains('Settings'));
    });
  });

  group('the camera and the permission it may or may not need', () {
    test('an application that never declared CAMERA does not ask for it', () {
      // ACTION_IMAGE_CAPTURE takes the photograph in the camera application,
      // not in this one, so the permission is not needed to send it. Asking
      // anyway would put a dialog in front of somebody for nothing.
      expect(
        dvAndroidCameraNeedsPermission(
            '{"permission":"camera","granted":false,"declared":false,'
            '"required":["android.permission.CAMERA"]}'),
        isFalse,
      );
    });

    test('an application that declared it must hold it before it asks', () {
      // The rule that catches everybody: declaring CAMERA and then sending
      // ACTION_IMAGE_CAPTURE without holding it throws a SecurityException
      // on the device. Nothing on the build machine says so.
      expect(
        dvAndroidCameraNeedsPermission(
            '{"permission":"camera","granted":false,"declared":true,'
            '"required":["android.permission.CAMERA"]}'),
        isTrue,
      );
    });

    test('one already held is not asked for again', () {
      expect(
        dvAndroidCameraNeedsPermission(
            '{"permission":"camera","granted":true,"declared":true,'
            '"required":["android.permission.CAMERA"]}'),
        isFalse,
      );
    });
  });

  group('what the picker and the camera answer with', () {
    test('cancelling is an empty list rather than an error', () {
      // The Linux picker answers a cancelled chooser with no paths. Android
      // has to agree, or the same application code has to be written twice.
      expect(dvAndroidCaptureItems('{"cancelled":true,"items":[]}'), isEmpty);
    });

    test('a failure is not an empty list', () {
      // A camera that reported success and wrote nothing, a provider that
      // could not be opened: each of those is a broken device and not a
      // person changing their mind, and an empty list would say the second.
      expect(
        () => dvAndroidCaptureItems(
            '{"error":"the camera reported success and wrote no file"}'),
        throwsA(isA<StateError>()),
      );
    });

    test('every item carries the three keys Linux answers with', () {
      final List<Map<String, Object?>> items = dvAndroidCaptureItems(
        '{"items":[{"path":"/data/cache/dartvel-picked/1-holiday.JPG",'
        '"name":"holiday.JPG","mimeType":"image/jpeg","bytes":812}]}',
      );
      expect(items, hasLength(1));
      expect(items.single['path'], '/data/cache/dartvel-picked/1-holiday.JPG');
      expect(items.single['name'], 'holiday.JPG');
      // Derived here rather than trusted from the platform: Android answers
      // with a MIME type and Linux answers with a kind, and application code
      // that switches on `type` has to get the same word from both.
      expect(items.single['type'], 'image');
    });

    test('the kind is the same word Linux would use for the same file', () {
      // linux_dialogs_ffi.dart maps extensions to image, video, audio, and
      // calls everything else a file. A picked .mkv that arrived as "video"
      // on a desktop and "file" on a phone is a gallery that shows nothing
      // on one of them.
      expect(dvAndroidMediaKind('image/jpeg', 'a.jpg'), 'image');
      expect(dvAndroidMediaKind(null, 'clip.mkv'), 'video');
      expect(dvAndroidMediaKind(null, 'song.flac'), 'audio');
      expect(dvAndroidMediaKind('application/pdf', 'report.pdf'), 'file');
      // A provider that lies about the type is overruled by the extension
      // only when it says nothing useful. octet-stream is the usual nothing.
      expect(dvAndroidMediaKind('application/octet-stream', 'a.png'), 'image');
    });

    test('the picker is asked for the kind that was requested', () {
      expect(dvAndroidMediaRequest(type: 'video', multiple: true),
          '{"type":"video","multiple":true}');
      expect(dvAndroidMediaRequest(type: 'image', multiple: false),
          '{"type":"image","multiple":false}');
    });
  });

  group('contacts', () {
    test('they arrive as strings, because that is what the API returns', () {
      // DVContacts.getContacts is List<Map<String, String>>. A number that
      // arrived as an int would be stringified by the caller as "1234" or
      // crash the cast, depending on which platform it came from.
      final List<Map<String, String>> people = dvAndroidContacts(
        '{"contacts":[{"id":"14","name":"Ada","phone":"+44 20 7946 0000"}]}',
      );
      expect(people.single['name'], 'Ada');
      expect(people.single['phone'], '+44 20 7946 0000');
      expect(people.single['id'], '14');
    });

    test('an empty address book is empty, and a refusal is not', () {
      expect(dvAndroidContacts('{"contacts":[]}'), isEmpty);
      expect(
        () => dvAndroidContacts('{"error":"READ_CONTACTS is not granted"}'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('location', () {
    test('a fix comes back as numbers', () {
      final Map<String, Object?> fix = dvAndroidLocation(
        '{"latitude":51.5074,"longitude":-0.1278,"accuracy":12.0,'
        '"provider":"fused","ageSeconds":4}',
      );
      expect(fix['latitude'], closeTo(51.5074, 0.0001));
      expect(fix['longitude'], closeTo(-0.1278, 0.0001));
      expect(fix['accuracy'], closeTo(12.0, 0.0001));
      expect(fix['ageSeconds'], 4);
    });

    test('no fix is never the null island', () {
      // DVLocation.getCoordinates defaults a missing latitude to 0. An
      // answer with no coordinates in it would put every user of this
      // binding in the Gulf of Guinea, on a map, with nothing to say it was
      // made up.
      expect(() => dvAndroidLocation('{}'), throwsA(isA<StateError>()));
      expect(
        () => dvAndroidLocation(
            '{"error":"every location provider is turned off"}'),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
            contains('turned off'))),
      );
    });

    test('a coordinate that is not a number is not a coordinate', () {
      // The bridge builds this JSON, so a string here means something went
      // wrong on the way. Parsing it as zero would be the null island again.
      expect(() => dvAndroidLocation('{"latitude":"north","longitude":2.0}'),
          throwsA(isA<StateError>()));
    });

    test('the request says how stale an answer may be', () {
      expect(dvAndroidLocationRequest(maxAge: const Duration(minutes: 2)),
          contains('"maxAgeSeconds":120'));
      expect(dvAndroidLocationRequest(timeout: const Duration(seconds: 30)),
          contains('"timeoutSeconds":30'));
    });
  });

  group('answers that are not answers', () {
    test('a bridge that could not start says which of its reasons it was', () {
      // -1 and -2 are different problems with different fixes: one is an APK
      // built with plain flutter build, the other a build of Dartvel that
      // does not have the operation. Both are worse than useless as "null".
      expect(dvAndroidBeginFailure(-1), contains('dartvel build android'));
      expect(dvAndroidBeginFailure(-2), contains('operation'));
      expect(dvAndroidBeginFailure(7), isNull);
    });

    test('a truncated answer is reported as one', () {
      // JNI hands back a String. Something that is not JSON means the Java
      // and the Dart disagree about the protocol, which is worth saying
      // plainly rather than throwing a FormatException from a decoder.
      expect(() => dvAndroidCaptureItems('not json at all'),
          throwsA(isA<StateError>()));
    });
  });
}
