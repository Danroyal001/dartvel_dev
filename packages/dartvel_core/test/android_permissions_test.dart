// What each of Dartvel's permission names asks Android for.
//
// This table is read twice and by two languages: `dartvel build android`
// writes a `<uses-permission>` line from it, and the Java it generates
// resolves a runtime request from it. Android denies a permission the
// manifest never declared instantly, with no dialog, and reports it exactly
// as it reports a person tapping Deny -- so a wrong entry here is invisible
// on the device and looks like a refusal.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('what a permission name asks for', () {
    test('an unknown name is not quietly granted', () {
      // The empty list means "nothing to ask for, so it is held" -- which is
      // the right answer for the clipboard and the wrong one for a typo.
      // They have to be different values or `camrea` is granted everywhere.
      expect(dvAndroidPermissionsFor('camrea'), isNull);
      expect(dvAndroidPermissionsFor('clipboard'), isEmpty);
    });

    test('a modern phone is not asked for a permission it retired', () {
      // READ_EXTERNAL_STORAGE stops being granted at API 33. Requesting it
      // there returns denied for ever, and an application that treats that
      // as the person refusing shows a "please allow storage" screen that
      // no button can get past.
      expect(dvAndroidPermissionsFor('storage', sdk: 34), isEmpty);
      expect(dvAndroidPermissionsFor('storage', sdk: 32),
          contains('android.permission.READ_EXTERNAL_STORAGE'));
    });

    test('an old phone is not asked for a permission it never had', () {
      // POST_NOTIFICATIONS arrived in API 33. Before it, notifications are
      // granted by installing the application, and asking for a permission
      // Android has never heard of is answered denied.
      expect(dvAndroidPermissionsFor('notifications', sdk: 30), isEmpty);
      expect(dvAndroidPermissionsFor('notifications', sdk: 33),
          <String>['android.permission.POST_NOTIFICATIONS']);
    });

    test('photos asks for the media permission that exists on the device', () {
      expect(dvAndroidPermissionsFor('photos', sdk: 34),
          <String>['android.permission.READ_MEDIA_IMAGES']);
      expect(dvAndroidPermissionsFor('photos', sdk: 30),
          <String>['android.permission.READ_EXTERNAL_STORAGE']);
    });

    test('bluetooth uses the split permissions from API 31 and not before',
        () {
      expect(dvAndroidPermissionsFor('bluetooth', sdk: 33), <String>[
        'android.permission.BLUETOOTH_CONNECT',
        'android.permission.BLUETOOTH_SCAN',
      ]);
      expect(dvAndroidPermissionsFor('bluetooth', sdk: 30), <String>[
        'android.permission.BLUETOOTH',
        'android.permission.BLUETOOTH_ADMIN',
      ]);
    });

    test('approximate location counts as location', () {
      // Android offers "precise" and "approximate" in one dialog, and only
      // when both are declared. A person who picks approximate has granted
      // location; treating that as a refusal asks again on every launch.
      expect(dvAndroidPermissions['location']!.anyOf, isTrue);
      expect(dvAndroidPermissionsFor('location'), <String>[
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
      ]);
    });

    test('every name resolves on every API level Dartvel supports', () {
      // A group whose entries are all filtered out at some level reads as
      // "granted, nothing to ask for" at that level. That is true of storage
      // on 34 and it is a bug anywhere else, so the exceptions are named.
      const Set<String> mayBeEmpty = <String>{
        'clipboard',
        'files',
        'storage',
        'notifications',
      };
      for (int sdk = 21; sdk <= 36; sdk++) {
        for (final String name in dvAndroidPermissionNames) {
          final List<String>? resolved =
              dvAndroidPermissionsFor(name, sdk: sdk);
          expect(resolved, isNotNull, reason: '$name at API $sdk');
          if (mayBeEmpty.contains(name)) continue;
          expect(resolved, isNotEmpty, reason: '$name at API $sdk');
        }
      }
    });
  });

  group('the classes the build writes and the runtime looks up', () {
    test('they are JNI names rather than Java ones', () {
      // JClass.forName takes the slash-separated form. A dotted name is not
      // an error at compile time and not found at run time, which on a
      // device is a binding that answers nothing.
      for (final String name in <String>[
        dvAndroidCaptureBridgeClass,
        dvAndroidBridgeActivityClass,
        dvAndroidCaptureFilesClass,
      ]) {
        expect(name, isNot(contains('.')), reason: name);
        expect(name, startsWith('dev/dartvel/jni/'), reason: name);
      }
    });
  });
}
