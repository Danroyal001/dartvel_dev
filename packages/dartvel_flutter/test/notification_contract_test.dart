// One binding name, one answer shape, on every platform that has it.
//
// notifications.sendLocal answered with the freedesktop notification id on
// Linux and a bool everywhere else, while DVNotifications.sendLocalNotification
// asks through require<bool>. So the facade threw "returned int, expected bool"
// on the one desktop where the binding is most complete -- and threw again when
// a kiosk suppressed the banner, because a suppressed send answered null.
//
// The id is not lost. It is real information the daemon gave us, it is what a
// future close-by-id needs, and the Linux suite asserts it to prove the D-Bus
// round trip happened -- so it moved to where a caller can ask for it rather
// than being the answer to a question about delivery.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => DVNativeBridge.unregister('notifications.sendLocal'));

  test('the facade accepts what a delivering platform answers', () async {
    DVNativeBridge.register('notifications.sendLocal', (Object? _) => true);
    await expectLater(
      const DVNotifications().sendLocalNotification('Build', 'green'),
      completes,
    );
  });

  test('and a refusal is a refusal rather than a crash', () async {
    // A kiosk holding the screen suppresses the banner. That is a "no", and
    // the caller should hear no rather than a type error.
    DVNativeBridge.register('notifications.sendLocal', (Object? _) => false);
    await expectLater(
      const DVNotifications().sendLocalNotification('Build', 'green'),
      throwsA(isA<StateError>()),
    );
  });
  test('a platform that answers with more than yes is still a yes', () async {
    // Linux answers with the notification id the daemon assigned -- a number,
    // and a useful one. require<bool> turned that into "returned int, expected
    // bool" and made the whole feature unusable on the desktop where it is
    // best implemented.
    DVNativeBridge.register('notifications.sendLocal', (Object? _) => 42);
    await expectLater(
      const DVNotifications().sendLocalNotification('Build', 'green'),
      completes,
    );
  });

  test('but nothing at all is not', () async {
    // A suppressed banner answers null. That is a no, and it must not read as
    // a yes just because it is not false.
    DVNativeBridge.register('notifications.sendLocal', (Object? _) => null);
    await expectLater(
      const DVNotifications().sendLocalNotification('Build', 'green'),
      throwsA(isA<StateError>()),
    );
  });
}
