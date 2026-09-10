// Android display geometry and the two short-range radios.
//
// There is no device and no emulator behind this suite, so nothing here can
// prove a JNI call reaches Android. What it can prove is the part that goes
// wrong quietly: the values these bindings hand back. A binding that answers
// with a plausible wrong number is worse than one that throws, because
// nothing downstream can tell the difference -- a 0x0 screen reads as a
// screen, an unpaired peripheral reads as a peripheral that is simply out of
// range, and the adapter address Android hands every ordinary app is a real
// MAC address belonging to nobody.
//
// So each test below fixes an answer, not a call shape. The JNI side is
// exercised on a device, and the report says which names have and have not
// been.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('screen geometry', () {
    test('it answers in the keys the web binding already answers in', () {
      // Linux says width/height/screen and the web says
      // width/height/devicePixelRatio. Android has a density and no X screen
      // number, so it matches the web -- and matching matters more than the
      // shape being pretty, because application code that reads
      // screen.geometry has to work on both without a branch.
      expect(
        dvAndroidGeometry(widthPixels: 1080, heightPixels: 2400, density: 2.75),
        <String, Object?>{
          'width': 1080,
          'height': 2400,
          'devicePixelRatio': 2.75,
        },
      );
    });

    test('a zero-sized screen is refused rather than reported', () {
      // DisplayMetrics read before the display is up gives zeroes, and a
      // caller handed {width: 0, height: 0} cannot tell that from a screen.
      // Every layout computed from it is silently wrong.
      expect(
        dvAndroidGeometry(widthPixels: 0, heightPixels: 2400, density: 2.75),
        isNull,
      );
      expect(
        dvAndroidGeometry(widthPixels: 1080, heightPixels: 0, density: 2.75),
        isNull,
      );
      expect(
        dvAndroidGeometry(widthPixels: -1, heightPixels: -1, density: 2.75),
        isNull,
      );
    });

    test('a density of zero is left out rather than passed on', () {
      // The pixels are still worth having. The ratio is not: every dp
      // conversion built on a zero divides by it, and the crash lands far
      // from here.
      final Map<String, Object?>? geometry =
          dvAndroidGeometry(widthPixels: 1080, heightPixels: 2400, density: 0);
      expect(geometry, isNotNull);
      expect(geometry!['width'], 1080);
      expect(geometry.containsKey('devicePixelRatio'), isFalse);
    });
  });

  group('nfc availability', () {
    test('a reader that is switched off is not available', () {
      // Linux answers this from a *powered* adapter for the same reason: a
      // true here puts "hold your card against the reader" on screen in front
      // of somebody whose reader cannot read.
      expect(dvAndroidNfcAvailable(hasAdapter: true, enabled: false), isFalse);
    });

    test('a device with no NFC hardware is not available', () {
      expect(dvAndroidNfcAvailable(hasAdapter: false, enabled: true), isFalse);
      expect(dvAndroidNfcAvailable(hasAdapter: false, enabled: false), isFalse);
    });

    test('a powered adapter is available', () {
      expect(dvAndroidNfcAvailable(hasAdapter: true, enabled: true), isTrue);
    });
  });

  group('the bluetooth adapter', () {
    test('the address Android redacts is reported as unknown, not as a MAC', () {
      // Since API 26 getAddress() hands every ordinary app
      // 02:00:00:00:00:00 -- a syntactically perfect MAC address that is not
      // this adapter's and not anybody's. Passed through, a fleet console
      // keys its records on it and every device in the fleet collides.
      final Map<String, Object?> adapter = dvAndroidBluetoothAdapterMap(
        address: dvAndroidRedactedBluetoothAddress,
        name: 'Pixel 8',
        powered: true,
        discovering: false,
      );
      expect(adapter['address'], '');
    });

    test('a real address is passed through', () {
      final Map<String, Object?> adapter = dvAndroidBluetoothAdapterMap(
        address: 'A4:C1:38:12:34:56',
        name: 'Pixel 8',
        powered: true,
        discovering: false,
      );
      expect(adapter['address'], 'A4:C1:38:12:34:56');
    });

    test('it survives the trip through DVBluetoothAdapter', () {
      // The map is not the contract; what DV.Platform.bluetooth.adapters()
      // hands an application is. Linux is read through the same fromMap, so
      // a key spelled differently here is a field that silently reads false
      // on Android and true on Linux.
      final DVBluetoothAdapter adapter = DVBluetoothAdapter.fromMap(
        dvAndroidBluetoothAdapterMap(
          address: 'A4:C1:38:12:34:56',
          name: 'Pixel 8',
          powered: true,
          discovering: true,
        ),
      );
      expect(adapter.name, 'Pixel 8');
      expect(adapter.powered, isTrue);
      expect(adapter.discovering, isTrue);
      expect(adapter.path, isNotEmpty);
    });
  });

  group('a bluetooth device', () {
    Map<String, Object?> device({
      String address = 'A4:C1:38:AA:BB:CC',
      String? name = 'Zebra ZQ511',
      int bondState = dvAndroidBondBonded,
      Set<String> connected = const <String>{},
    }) =>
        dvAndroidBluetoothDeviceMap(
          address: address,
          name: name,
          bondState: bondState,
          connectedAddresses: connected,
        );

    test('only BOND_BONDED counts as paired', () {
      // BOND_BONDING is a pairing dialog somebody has not answered yet.
      // Counted as paired, a queue of work starts against a printer that is
      // not bonded and fails one job at a time.
      expect(DVBluetoothDevice.fromMap(device(bondState: dvAndroidBondBonded))
          .paired, isTrue);
      expect(DVBluetoothDevice.fromMap(device(bondState: dvAndroidBondBonding))
          .paired, isFalse);
      expect(DVBluetoothDevice.fromMap(device(bondState: dvAndroidBondNone))
          .paired, isFalse);
    });

    test('the address is the identity, because Android exports no path', () {
      // BlueZ gives every device an object path and Linux keys on it. Android
      // has nothing of the sort, and the MAC address is the one identifier
      // that survives a reboot. An empty or invented path would make two
      // peripherals compare equal.
      final DVBluetoothDevice parsed =
          DVBluetoothDevice.fromMap(device(address: 'A4:C1:38:AA:BB:CC'));
      expect(parsed.path, 'A4:C1:38:AA:BB:CC');
    });

    test('a device with no name reads as nameless, not as an empty string', () {
      // getName() is null for a peripheral that has never said its name, and
      // '' would render as a blank row somebody cannot pick out of a list.
      expect(DVBluetoothDevice.fromMap(device(name: null)).name, isNull);
    });

    test('connected is read from the live set, matched without case', () {
      // Android spells addresses in upper case and a configuration file holds
      // whatever somebody typed. Compared literally, a connected scanner
      // reads as disconnected and the operator is sent to look at the wrong
      // thing.
      expect(
        DVBluetoothDevice.fromMap(device(connected: <String>{'a4:c1:38:aa:bb:cc'}))
            .connected,
        isTrue,
      );
      expect(
        DVBluetoothDevice.fromMap(device(connected: <String>{'11:22:33:44:55:66'}))
            .connected,
        isFalse,
      );
    });

    test('no RSSI is claimed for a device nobody has just heard', () {
      // Bonded devices carry no signal strength; it comes from a scan result.
      // A number here would be made up.
      expect(DVBluetoothDevice.fromMap(device()).rssi, isNull);
    });
  });

  group('watching a bond through', () {
    test('a device already bonded is paired at once', () {
      expect(DVAndroidBondWatch().observe(dvAndroidBondBonded),
          DVAndroidBondOutcome.paired);
    });

    test('BOND_NONE before any bonding is still waiting', () {
      // createBond() returns before the state moves. Read as a refusal, every
      // pairing would report failure and then succeed a second later, which
      // is the worst of both.
      expect(DVAndroidBondWatch().observe(dvAndroidBondNone),
          DVAndroidBondOutcome.waiting);
    });

    test('BOND_NONE after bonding began is a refusal', () {
      // Somebody pressed cancel, or the PIN was wrong. Waiting the full
      // timeout for that leaves a screen spinning for half a minute after the
      // answer is already known.
      final DVAndroidBondWatch watch = DVAndroidBondWatch();
      expect(watch.observe(dvAndroidBondNone), DVAndroidBondOutcome.waiting);
      expect(watch.observe(dvAndroidBondBonding), DVAndroidBondOutcome.waiting);
      expect(watch.observe(dvAndroidBondNone), DVAndroidBondOutcome.refused);
    });

    test('bonding that completes is paired', () {
      final DVAndroidBondWatch watch = DVAndroidBondWatch();
      watch.observe(dvAndroidBondNone);
      watch.observe(dvAndroidBondBonding);
      expect(watch.observe(dvAndroidBondBonded), DVAndroidBondOutcome.paired);
    });
  });

  group('what Android now binds, and what it does not', () {
    test('the display and radio names it binds', () {
      expect(
        DVAndroidBindings.implemented,
        containsAll(<String>[
          'screen.geometry',
          'nfc.isAvailable',
          'bluetooth.isEnabled',
          'bluetooth.adapters',
          'bluetooth.devices',
          'bluetooth.scanDevices',
          'bluetooth.pair',
        ]),
      );
    });

    test('reading and writing a tag stay absent', () {
      // Both need the tag object, and a tag reaches an application only
      // through foreground dispatch or reader mode -- an Activity callback,
      // delivered whenever somebody taps. A one-shot call has nowhere to wait
      // and nothing to wait on, so a binding here would answer null for ever
      // or hand back whatever was tapped last.
      for (final String name in <String>['nfc.readTag', 'nfc.writeTag']) {
        expect(DVAndroidBindings.implemented, isNot(contains(name)), reason: name);
      }
    });

    test('connect, disconnect and forget stay absent', () {
      // Android has no device-level connect: a connection is made per profile
      // and asynchronously, through connectGatt with a callback or a socket
      // for the classic profiles. removeBond() is hidden and blocked for
      // ordinary apps. Registering these would put three names in the
      // capability list that can only ever answer false.
      for (final String name in <String>[
        'bluetooth.connect',
        'bluetooth.disconnect',
        'bluetooth.forget',
      ]) {
        expect(DVAndroidBindings.implemented, isNot(contains(name)), reason: name);
      }
    });

    test('the kiosk display names stay absent, because kiosk.enforce answers', () {
      // DVDisplayControls.enableKiosk() falls back to kiosk.enforce when
      // display.enableKiosk is unregistered, and Android binds kiosk.enforce.
      // A second registration would be two answers to one question, and the
      // one that wins would be whichever was registered.
      for (final String name in <String>[
        'display.enableKiosk',
        'display.disableKiosk',
      ]) {
        expect(DVAndroidBindings.implemented, isNot(contains(name)), reason: name);
      }
    });
  });
}
