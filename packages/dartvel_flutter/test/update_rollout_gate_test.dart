// A staged rollout, from the application's point of view.
//
// The server says a release is at twenty-five per cent. Every device in the
// fleet asks the same question and most of them have to be told no -- and
// told *why*, because "no update" and "not your turn yet" look identical
// from a support desk and are hours apart to diagnose.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void serverOffers({required String version, String? rollout, bool required = false}) {
  DVNativeBridge.register('updates.check', (Object? args) {
    return <Object?, Object?>{
      'available': true,
      'version': version,
      'required': required,
      if (rollout != null) 'metadata': <Object?, Object?>{'rollout': rollout},
    };
  });
}

void main() {
  tearDown(() {
    DVNativeBridge.unregister('updates.check');
    DVUpdates.identifyDevice(null);
  });

  test('a release at full rollout is offered to everyone', () async {
    serverOffers(version: '1.4.0', rollout: '100');
    DVUpdates.identifyDevice('kiosk-7');

    final DVUpdateInfo info = await const DVUpdates().check();

    expect(info.available, isTrue);
    expect(info.heldBackByRollout, isFalse);
    expect(info.rolloutPercent, 100);
  });

  test('a release the rollout has not reached is not offered, and says so', () async {
    // Pick a device the rollout genuinely excludes rather than asserting on
    // whichever one the hash happens to place low.
    final String excluded = <String>[for (var i = 0; i < 200; i++) 'kiosk-$i']
        .firstWhere((String d) => !DVUpdateRollout.includes(
            deviceId: d, version: '1.4.0', percent: 25));
    serverOffers(version: '1.4.0', rollout: '25');
    DVUpdates.identifyDevice(excluded);

    final DVUpdateInfo info = await const DVUpdates().check();

    expect(info.available, isFalse, reason: 'its turn has not come');
    expect(info.heldBackByRollout, isTrue, reason: 'and the app can tell why');
    expect(info.version, '1.4.0', reason: 'the release is still nameable');
    expect(info.rolloutPercent, 25);
  });

  test('a device inside the rollout is offered the same release', () async {
    final String included = <String>[for (var i = 0; i < 200; i++) 'kiosk-$i']
        .firstWhere((String d) => DVUpdateRollout.includes(
            deviceId: d, version: '1.4.0', percent: 25));
    serverOffers(version: '1.4.0', rollout: '25');
    DVUpdates.identifyDevice(included);

    final DVUpdateInfo info = await const DVUpdates().check();

    expect(info.available, isTrue);
    expect(info.heldBackByRollout, isFalse);
  });

  test('the answer does not change between checks', () async {
    serverOffers(version: '1.4.0', rollout: '40');
    DVUpdates.identifyDevice('store-front-2');

    final bool first = (await const DVUpdates().check()).available;
    for (var i = 0; i < 20; i++) {
      expect((await const DVUpdates().check()).available, first);
    }
  });

  test('a forced release ignores the rollout', () async {
    // A staged rollout is for releases that can wait. One marked required is
    // a release the fleet is broken without, and holding it back by a hash
    // would be the framework overruling that.
    final String excluded = <String>[for (var i = 0; i < 200; i++) 'kiosk-$i']
        .firstWhere((String d) => !DVUpdateRollout.includes(
            deviceId: d, version: '2.0.0', percent: 10));
    serverOffers(version: '2.0.0', rollout: '10', required: true);
    DVUpdates.identifyDevice(excluded);

    final DVUpdateInfo info = await const DVUpdates().check();

    expect(info.available, isTrue);
    expect(info.required, isTrue);
    expect(info.heldBackByRollout, isFalse);
  });

  test('a server that names no rollout is offering the release to everyone', () async {
    serverOffers(version: '1.4.0');
    DVUpdates.identifyDevice('kiosk-7');

    final DVUpdateInfo info = await const DVUpdates().check();

    expect(info.available, isTrue);
    expect(info.rolloutPercent, 100);
  });
}
