@TestOn('linux')
library;

// Bluetooth on Linux: BlueZ, over the bus.
//
// A kiosk's payment terminal, a scale, a label printer: on an embedded device
// these are paired Bluetooth peripherals, and a fleet that cannot ask about
// them cannot answer the two questions that matter when one stops working --
// is the adapter switched on, and is the thing still paired. Both are on the
// bus already; BlueZ exports every adapter and every known device through the
// standard object manager.
//
// A runner has no Bluetooth hardware, so the suite stands up a BlueZ of its
// own on the session bus, the way the tray suite stands up a watcher. What
// that proves is the reading: the object tree walked correctly, an adapter
// told apart from a device, and a machine with no BlueZ at all answered
// honestly rather than with an empty list that means something else.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_bluetooth.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for BlueZ: one adapter, one paired device, one that is merely
/// in range, and an unrelated object that is neither.
class _BlueZ extends DBusObject {
  _BlueZ() : super(DBusObjectPath('/'));

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface('org.freedesktop.DBus.ObjectManager',
            methods: <DBusIntrospectMethod>[
              DBusIntrospectMethod('GetManagedObjects'),
            ]),
      ];

  DBusValue _string(String value) => DBusString(value);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.freedesktop.DBus.ObjectManager' ||
        methodCall.name != 'GetManagedObjects') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse(<DBusValue>[
      DBusDict(
        DBusSignature('o'),
        DBusSignature('a{sa{sv}}'),
        <DBusValue, DBusValue>{
          DBusObjectPath('/org/bluez/hci0'): _interfaces(<String, Map<String, DBusValue>>{
            'org.bluez.Adapter1': <String, DBusValue>{
              'Address': _string('AA:BB:CC:DD:EE:FF'),
              'Name': _string('kiosk-3'),
              'Powered': const DBusBoolean(true),
              'Discovering': const DBusBoolean(false),
            },
          }),
          DBusObjectPath('/org/bluez/hci0/dev_11_22_33_44_55_66'):
              _interfaces(<String, Map<String, DBusValue>>{
            'org.bluez.Device1': <String, DBusValue>{
              'Address': _string('11:22:33:44:55:66'),
              'Name': _string('Card reader'),
              'Paired': const DBusBoolean(true),
              'Connected': const DBusBoolean(true),
              'RSSI': const DBusInt16(-52),
              'Adapter': DBusObjectPath('/org/bluez/hci0'),
            },
          }),
          DBusObjectPath('/org/bluez/hci0/dev_99_88_77_66_55_44'):
              _interfaces(<String, Map<String, DBusValue>>{
            'org.bluez.Device1': <String, DBusValue>{
              'Address': _string('99:88:77:66:55:44'),
              'Paired': const DBusBoolean(false),
              'Connected': const DBusBoolean(false),
            },
          }),
          // Neither an adapter nor a device: BlueZ exports these too.
          DBusObjectPath('/org/bluez'): _interfaces(<String, Map<String, DBusValue>>{
            'org.bluez.AgentManager1': <String, DBusValue>{},
          }),
        },
      ),
    ]);
  }

  DBusValue _interfaces(Map<String, Map<String, DBusValue>> interfaces) =>
      DBusDict(
        DBusSignature('s'),
        DBusSignature('a{sv}'),
        <DBusValue, DBusValue>{
          for (final MapEntry<String, Map<String, DBusValue>> e in interfaces.entries)
            DBusString(e.key): DBusDict(
              DBusSignature('s'),
              DBusSignature('v'),
              <DBusValue, DBusValue>{
                for (final MapEntry<String, DBusValue> p in e.value.entries)
                  DBusString(p.key): DBusVariant(p.value),
              },
            ),
        },
      );
}

void main() {
  final bool hasBus =
      (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty;
  if (!hasBus) {
    test('linux bluetooth (skipped: no session bus)', () {},
        skip: 'Run under a session bus (dbus-run-session works).');
    return;
  }

  late DBusClient bus;
  late _BlueZ bluez;

  setUp(() async {
    bus = DBusClient.session();
    bluez = _BlueZ();
    await bus.registerObject(bluez);
    await bus.requestName('org.bluez');
  });

  tearDown(() async => bus.close());

  test('the adapters are the adapters, not everything on the bus', () async {
    final List<DVBluetoothAdapter> adapters =
        await DVLinuxBluetooth.adaptersOn(DBusClient.session());

    expect(adapters, hasLength(1));
    expect(adapters.single.address, 'AA:BB:CC:DD:EE:FF');
    expect(adapters.single.name, 'kiosk-3');
    expect(adapters.single.powered, isTrue);
    expect(adapters.single.discovering, isFalse);
  });

  test('the devices are the devices, with what BlueZ knows about each', () async {
    final List<DVBluetoothDevice> devices =
        await DVLinuxBluetooth.devicesOn(DBusClient.session());

    expect(devices.map((DVBluetoothDevice d) => d.address),
        containsAll(<String>['11:22:33:44:55:66', '99:88:77:66:55:44']));
    final DVBluetoothDevice reader = devices
        .firstWhere((DVBluetoothDevice d) => d.address == '11:22:33:44:55:66');
    expect(reader.name, 'Card reader');
    expect(reader.paired, isTrue);
    expect(reader.connected, isTrue);
    expect(reader.rssi, -52);
  });

  test('a device that has never said its name is still a device', () async {
    // A peripheral out of range advertises an address and nothing else.
    // Dropped, a fleet would be told a paired thing is not there at all.
    final List<DVBluetoothDevice> devices =
        await DVLinuxBluetooth.devicesOn(DBusClient.session());

    final DVBluetoothDevice far = devices
        .firstWhere((DVBluetoothDevice d) => d.address == '99:88:77:66:55:44');
    expect(far.name, isNull);
    expect(far.paired, isFalse);
    expect(far.rssi, isNull);
  });

  test('the binding answers with the same devices', () async {
    DVLinuxBluetooth.register(DVNativeBridge.register, bus: DBusClient.session());
    addTearDown(() => DVNativeBridge.unregister('bluetooth.devices'));
    addTearDown(() => DVNativeBridge.unregister('bluetooth.adapters'));

    final List<Object?> reported =
        await DVNativeBridge.require<List<Object?>>('bluetooth.devices');

    expect(reported, hasLength(2));
    expect((reported.first! as Map<Object?, Object?>)['address'], isA<String>());
  });

  test('a powered adapter is a bluetooth that is on', () async {
    DVLinuxBluetooth.register(DVNativeBridge.register, bus: DBusClient.session());
    addTearDown(() => DVNativeBridge.unregister('bluetooth.isEnabled'));

    expect(await DVNativeBridge.require<bool>('bluetooth.isEnabled'), isTrue);
  });

  test('with no BlueZ on the bus it says so rather than saying nothing', () async {
    // An empty list means "nothing is paired" and a missing service means
    // "there is no bluetooth here". A fleet told the first when the second is
    // true sends somebody to pair a device to a machine that cannot.
    await bus.releaseName('org.bluez');

    final List<DVBluetoothDevice> devices =
        await DVLinuxBluetooth.devicesOn(DBusClient.session());

    expect(devices, isEmpty);
    expect(DVLinuxBluetooth.lastError, isNotNull);
    expect(DVLinuxBluetooth.lastError, contains('bluetooth'));
  });
}
