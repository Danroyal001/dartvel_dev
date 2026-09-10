// Sensors, identity and the system services Android reaches through the
// application Context.
//
// Written after the gap was measured rather than guessed: seventy binding
// names are declared, Android registered eight, and `DVNativeBridge.invoke`
// answering null for a name nothing is registered under is indistinguishable
// from the device saying no. So an unbound sensor read and a phone lying flat
// on a table look the same to application code.
//
// What this file tests is the decision each binding makes, not the JNI call
// it makes afterwards. There is no Android device or emulator here and none
// of the calls below cross into Java. A truncated sensor event, a biometric
// status code, whether a notification channel is required: those are the
// places a wrong answer is plausible enough to go unnoticed for months, and
// they are answerable on any machine. The Java side is exercised on a device
// or not at all, and nothing here should be read as saying it was.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sensor samples', () {
    test('an event with fewer than three axes is refused, not padded', () {
      // Zeros are the most plausible wrong answer a motion sensor can give.
      // A device lying still reads near zero on two axes, so a padded sample
      // passes for a real one and nothing downstream can tell them apart.
      expect(dvAndroidSensorSample(const <double>[]), isNull);
      expect(dvAndroidSensorSample(const <double>[0.1]), isNull);
      expect(dvAndroidSensorSample(const <double>[0.1, 0.2]), isNull);
    });

    test('the three axes come back in the order the platform reports them',
        () {
      expect(
        dvAndroidSensorSample(const <double>[1.5, -2.5, 9.81]),
        <String, double>{'x': 1.5, 'y': -2.5, 'z': 9.81},
      );
    });

    test('values past the third axis are dropped rather than mixed in', () {
      // An uncalibrated gyroscope reports six values: three rates, then
      // three drift estimates. Drift is not an axis, and folding it in would
      // move the reading by an amount that still looks like a reading.
      expect(
        dvAndroidSensorSample(const <double>[1, 2, 3, 40, 50, 60]),
        <String, double>{'x': 1, 'y': 2, 'z': 3},
      );
    });
  });

  group('biometric availability', () {
    test('hardware nobody has enrolled on cannot authenticate', () {
      // BIOMETRIC_ERROR_NONE_ENROLLED. This is the answer that has to come
      // back false: the sensor is present, so anything asking "is there
      // hardware" says yes, and then every prompt on that device fails.
      expect(dvAndroidBiometricAvailable(11), isFalse);
    });

    test('only outright success is a yes', () {
      expect(dvAndroidBiometricAvailable(0), isTrue);
      for (final int status in <int>[1, 11, 12, 15, -1, 99]) {
        expect(
          dvAndroidBiometricAvailable(status),
          isFalse,
          reason: 'status $status is not BIOMETRIC_SUCCESS',
        );
      }
    });
  });

  group('local notifications', () {
    test('a channel is needed from Oreo onwards and not before', () {
      // Posting without a channel on API 26+ is dropped by the system with
      // nothing but a log line to show for it. Creating one below 26 calls a
      // method that is not there.
      expect(dvAndroidNotificationNeedsChannel(25), isFalse);
      expect(dvAndroidNotificationNeedsChannel(26), isTrue);
      expect(dvAndroidNotificationNeedsChannel(34), isTrue);
    });

    test('successive notifications do not replace one another', () {
      final Set<int> ids = <int>{
        for (int i = 0; i < 8; i++) dvAndroidNotificationId(i),
      };
      expect(ids, hasLength(8));
    });

    test('the id stays inside a Java int however long the app runs', () {
      // notify() takes an int. A counter that has run past 2^31 arrives as a
      // negative number or does not arrive at all, and the only symptom is a
      // notification that never appears.
      for (final int counter in <int>[0, 1 << 20, 1 << 40, 1 << 62]) {
        final int id = dvAndroidNotificationId(counter);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7fffffff));
      }
    });
  });

  group('where Android is allowed to write', () {
    test('device state goes under the private directory of the app', () {
      // The shared device runtime falls back to $HOME and then to
      // Directory.systemTemp. Android has neither: HOME is unset, and /tmp
      // belongs to no application. device.health would throw on its first
      // call, on the phone, and pass everywhere it was tested.
      const String files = '/data/user/0/dev.dartvel.example/files';
      final String? state = dvAndroidStateDirectory(files);
      expect(state, isNotNull);
      expect(state!.startsWith('$files/'), isTrue);
      expect(state, isNot(contains('/tmp')));
    });

    test('an empty files directory is not turned into a root-level path', () {
      // getFilesDir() answering null or empty is a Context that is not the
      // application's. Building "/dartvel-device" out of it would be a write
      // attempt at the root of the device, refused at run time with an
      // exception from a line that reads as a path join.
      expect(dvAndroidStateDirectory(''), isNull);
    });
  });
}
