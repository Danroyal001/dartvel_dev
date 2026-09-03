// Staged rollouts.
//
// A release goes to a fraction of the fleet first. The decision has to be
// the same every time a device asks: a device offered an update at nine
// o'clock and not at ten has an update that appears and disappears, and
// nobody can tell that from a broken server. So it is computed from the
// device and the version rather than drawn at random, and a new version
// deals the fleet again -- otherwise the same devices are always last, and
// the same devices are always the ones that find the bad release.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('the same device and version answer the same every time', () {
    final bool first = DVUpdateRollout.includes(deviceId: 'kiosk-7', version: '1.4.0', percent: 30);

    for (var i = 0; i < 50; i++) {
      expect(DVUpdateRollout.includes(deviceId: 'kiosk-7', version: '1.4.0', percent: 30), first);
    }
  });

  test('everyone is in a full rollout and nobody is in an empty one', () {
    for (final String device in <String>['a', 'b', 'kiosk-7', 'store-front-2']) {
      expect(DVUpdateRollout.includes(deviceId: device, version: '1.4.0', percent: 100), isTrue);
      expect(DVUpdateRollout.includes(deviceId: device, version: '1.4.0', percent: 0), isFalse);
    }
  });

  test('a percent outside the range is treated as its nearest end', () {
    expect(DVUpdateRollout.includes(deviceId: 'a', version: '1', percent: 140), isTrue);
    expect(DVUpdateRollout.includes(deviceId: 'a', version: '1', percent: -10), isFalse);
  });

  test('about the right share of a fleet is included', () {
    final List<String> fleet = <String>[for (var i = 0; i < 2000; i++) 'kiosk-$i'];

    final int included = fleet
        .where((String d) => DVUpdateRollout.includes(deviceId: d, version: '2.0.0', percent: 25))
        .length;

    // Not exact, and it must not be: a hash spreads, it does not deal.
    expect(included, greaterThan(2000 * 0.20));
    expect(included, lessThan(2000 * 0.30));
  });

  test('a new version deals the fleet again', () {
    // Otherwise the same devices are always last, and the same devices are
    // always the ones that find the bad release.
    final List<String> fleet = <String>[for (var i = 0; i < 500; i++) 'kiosk-$i'];
    Set<String> firstOf(String version) => fleet
        .where((String d) => DVUpdateRollout.includes(deviceId: d, version: version, percent: 20))
        .toSet();

    final Set<String> one = firstOf('1.0.0');
    final Set<String> two = firstOf('1.1.0');

    expect(one, isNotEmpty);
    expect(two, isNotEmpty);
    expect(one.intersection(two).length, lessThan(one.length),
        reason: 'the same devices cannot be first every time');
  });

  test('a device that cannot be identified is not silently left behind', () {
    // A rollout that excluded everything it could not name would stall
    // without saying so.
    expect(DVUpdateRollout.includes(deviceId: '', version: '1.4.0', percent: 50), isTrue);
  });
}
