// One answer about an update, from every rule that has a say in it.
//
// A device is offered a version by its channel and its staged rollout; the
// application may have pinned a version or skipped one; and a kiosk decides
// when it is allowed to restart at all. Those were three separate decisions
// with nothing joining them, and the kiosk's was the worst off: a function
// nobody called, so a kiosk that declared a maintenance window applied its
// updates at midday like everything else, and the declaration was a sentence
// in a file.
//
// So `check()` answers the question the caller actually has -- should this
// device apply this now -- and says why not when the answer is no, and when
// it will be yes. `apply()` refuses what the check held back, because an
// application that ignores a declared policy is a bug and a silent no-op is
// how it stays one.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVKioskPolicy kioskWith(Map<String, Object?> updates) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': '/welcome',
        'updates': updates,
      },
    });

void serverOffers({bool required = false, String version = '1.4.0'}) {
  DVNativeBridge.register(
    'updates.check',
    (Object? _) => <Object?, Object?>{
      'available': true,
      'version': version,
      'required': required,
    },
  );
}

DateTime at(int hour) => DateTime(2026, 9, 4, hour);

void main() {
  setUp(() async {
    await DVPlatform.uninstallKioskPolicy();
    DVNativeBridge.register('kiosk.enforce', (Object? _) => <String, Object?>{});
    DVNativeBridge.register('kiosk.release', (Object? _) => true);
    const DVUpdates().unlockVersion();
    DVUpdates.identifyDevice(null);
    DVUpdates.now = () => at(12);
  });

  tearDown(() async {
    await DVPlatform.uninstallKioskPolicy();
    DVUpdates.now = DateTime.now;
    DVNativeBridge.unregister('updates.check');
    DVNativeBridge.unregister('updates.apply');
    DVNativeBridge.unregister('kiosk.enforce');
    DVNativeBridge.unregister('kiosk.release');
  });

  group('a kiosk with a maintenance window', () {
    Future<void> install() => DVPlatform.installKioskPolicy(
          kioskWith(<String, Object?>{
            'apply': 'maintenanceWindow',
            'window': '02:00-04:00',
          }),
        );

    test('holds an update back outside it, and says when it will run', () async {
      await install();
      serverOffers();

      final DVUpdateInfo update = await const DVUpdates().check();

      expect(update.available, isFalse);
      expect(update.hold, DVUpdateHold.maintenanceWindow);
      expect(update.notBefore, DateTime(2026, 9, 5, 2));
      expect(update.version, '1.4.0', reason: 'the release is still nameable');
    });

    test('applies it inside the window', () async {
      await install();
      serverOffers();
      DVUpdates.now = () => at(3);

      expect((await const DVUpdates().check()).available, isTrue);
    });

    test('a required update does not wait, and resets the session first', () async {
      await install();
      serverOffers(required: true);

      final DVUpdateInfo update = await const DVUpdates().check();

      expect(update.available, isTrue);
      expect(update.resetsSession, isTrue);
    });
  });

  test('with no kiosk, the window is nobody\'s business',
      () async {
    serverOffers();

    final DVUpdateInfo update = await const DVUpdates().check();

    expect(update.available, isTrue);
    expect(update.hold, isNull);
  });

  test('a pinned version holds another one back, and says so',
      () async {
    // The lock and the skip were a separate gate nothing called either. They
    // are the same question -- should this device apply this -- so they are
    // the same answer.
    serverOffers();
    const DVUpdates().lockVersion('1.3.0');

    final DVUpdateInfo update = await const DVUpdates().check();

    expect(update.available, isFalse);
    expect(update.hold, DVUpdateHold.versionLock);
  });

  test('a skipped version is held back until the next one',
      () async {
    serverOffers();
    const DVUpdates().skipImmediateNextVersion('1.4.0');
    addTearDown(() => const DVUpdates().skipImmediateNextVersion(''));

    expect((await const DVUpdates().check()).hold, DVUpdateHold.skipped);
  });

  group('apply', () {
    test('refuses what the check held back, with the reason', () async {
      // Not a silent no-op: an application applying an update its own
      // declaration forbids is a bug, and a call that quietly does nothing
      // is how it stays one.
      await DVPlatform.installKioskPolicy(kioskWith(<String, Object?>{
        'apply': 'maintenanceWindow',
        'window': '02:00-04:00',
      }));
      serverOffers();
      var applied = false;
      DVNativeBridge.register('updates.apply', (Object? _) {
        applied = true;
        return true;
      });

      final DVUpdateInfo update = await const DVUpdates().check();

      await expectLater(
        const DVUpdates().apply(update: update),
        throwsA(predicate((Object e) => '$e'.contains('02:00-04:00'))),
      );
      expect(applied, isFalse, reason: 'it must not reach the binding');
    });

    test('resets the session before a required update lands', () async {
      // The specification is explicit, and the point is the order: applying
      // it on top of whatever the customer was doing is the thing being
      // avoided.
      await DVPlatform.installKioskPolicy(kioskWith(<String, Object?>{
        'apply': 'maintenanceWindow',
        'window': '02:00-04:00',
      }));
      serverOffers(required: true);
      final List<String> order = <String>[];
      DVNativeBridge.register('updates.apply', (Object? _) {
        order.add('apply');
        return true;
      });
      DV.Platform.display.kiosk!.runtime.resets.listen((_) => order.add('reset'));

      final DVUpdateInfo update = await const DVUpdates().check();
      await const DVUpdates().apply(update: update);

      expect(order, <String>['reset', 'apply']);
    });

    test('an update nothing held back is applied', () async {
      serverOffers();
      var applied = false;
      DVNativeBridge.register('updates.apply', (Object? _) {
        applied = true;
        return true;
      });

      await const DVUpdates().apply(update: await const DVUpdates().check());

      expect(applied, isTrue);
    });
  });
}
