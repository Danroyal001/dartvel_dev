// The contract between the Swift `dartvel build ios` writes and the Dart that
// calls it.
//
// Both halves read these names, and neither compiler checks the other: an
// operation the Dart sends that the Swift has no case for answers "unknown
// operation" on a phone, and a usage-description key the build does not
// write is a permission request iOS answers by terminating the application.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('iOS permission table', () {
    test('every name Android knows has an iOS answer', () {
      // One permission vocabulary for DV.Platform.permissions. A name that
      // means something on Android and is unknown on iOS is a call that
      // works on one phone and throws on the other.
      expect(dvIosPermissions.keys.toSet(), dvAndroidPermissions.keys.toSet());
    });

    test('the ones iOS terminates the app over name their Info.plist key', () {
      expect(dvIosUsageKeysFor('camera'), <String>['NSCameraUsageDescription']);
      expect(dvIosUsageKeysFor('microphone'),
          <String>['NSMicrophoneUsageDescription']);
      expect(dvIosUsageKeysFor('location'),
          <String>['NSLocationWhenInUseUsageDescription']);
      expect(dvIosUsageKeysFor('contacts'), <String>['NSContactsUsageDescription']);
      expect(dvIosUsageKeysFor('bluetooth'),
          <String>['NSBluetoothAlwaysUsageDescription']);
      expect(dvIosUsageKeysFor('biometrics'), <String>['NSFaceIDUsageDescription']);
      expect(dvIosUsageKeysFor('photos'), <String>['NSPhotoLibraryUsageDescription']);
      expect(dvIosUsageKeysFor('nfc'), <String>['NFCReaderUsageDescription']);
    });

    test('the ones with nothing to declare are empty, not unknown', () {
      for (final String name in <String>['notifications', 'clipboard', 'files']) {
        expect(dvIosUsageKeysFor(name), isEmpty, reason: name);
      }
    });

    test('a typo is null rather than an empty list', () {
      // Empty means "nothing to ask for, so granted". Answering that for
      // `camrea` would grant it on every device.
      expect(dvIosUsageKeysFor('camrea'), isNull);
    });

    test('allFiles is a name iOS has no grant for', () {
      // No iOS application reads another's files; the picker is the grant.
      // Reported as unsupported rather than as an empty group, which would
      // read as held.
      expect(dvIosPermissions['allFiles']!.supported, isFalse);
      expect(dvIosPermissions['camera']!.supported, isTrue);
    });
  });

  group('shim operations', () {
    test('are unique and non-empty', () {
      expect(dvIosShimOperations, isNotEmpty);
      expect(dvIosShimOperations.every((String op) => op.isNotEmpty), isTrue);
    });

    test('the symbols are C identifiers', () {
      final RegExp c = RegExp(r'^[a-z_][a-z0-9_]*$');
      for (final String symbol in <String>[
        dvIosShimVersionSymbol,
        dvIosShimCallSymbol,
        dvIosShimCompletionSymbol,
        dvIosShimDiskFreeSymbol,
      ]) {
        expect(c.hasMatch(symbol), isTrue, reason: symbol);
      }
    });

    test('the version is positive, so an absent shim cannot match it', () {
      // A missing symbol and a version of zero must not look alike.
      expect(dvIosShimVersion, greaterThan(0));
    });
  });
}
