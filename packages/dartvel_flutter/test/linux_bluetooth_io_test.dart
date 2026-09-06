@TestOn('linux')
library;

// Pairing, connecting and forgetting a Bluetooth device, through BlueZ.
//
// Reading was built -- the radio, the adapters, everything the machine knows
// about -- and doing anything was named a different job and left. It is a
// different job, and it is the one a fleet needs: a card reader that has come
// unpaired in a lobby is a kiosk somebody has to drive to unless the
// application can pair it again.
//
// Almost none of this is a plain call, because BlueZ's failures are specific
// and its worst answers look like ordinary ones:
//
//   * pairing something already paired is an error, and the right answer to
//     it is "yes, it is paired". An application that treated it as a failure
//     would retry forever against a device that is working.
//   * Pair() with no agent registered does not fail loudly. On a headless
//     kiosk -- which is every device this exists for -- there is nobody to
//     answer a passkey prompt, and "pairing failed" sends somebody to look at
//     the wrong thing.
//   * connecting before pairing is refused for a reason worth passing on.
//   * a caller holds an address; BlueZ wants an object path. Its paths spell
//     the address in upper case, so a lookup that matched what the caller
//     typed would report "not known" for a device sitting right there.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_bluetooth.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

/// BlueZ, exported as the objects BlueZ actually exports.
///
/// Shaped like the daemon rather than flattened into one node, because a
/// method call is routed to the object registered at its path and
/// DBusMethodCall does not carry the path with it. A single object at `/`
/// answers GetManagedObjects and nothing else: a Pair on a device path would
/// reach nobody, and the test would be asserting against a client that never
/// got an answer rather than against a daemon that gave one.
class _BlueZ {
  _BlueZ({this.paired = false, this.agent = true});

  /// Whether the reader is already paired, which changes what Pair answers.
  final bool paired;

  /// Whether a pairing agent is registered. Without one there is nobody to
  /// answer a passkey, which is the state a headless kiosk is always in.
  final bool agent;

  /// What every object was asked to do, in order.
  final List<String> calls = <String>[];

  static const String adapterPath = '/org/bluez/hci0';
  static const String devicePath = '/org/bluez/hci0/dev_11_22_33_44_55_66';

  List<DBusObject> get objects => <DBusObject>[
        _Root(this),
        _Adapter(this),
        _Device(this),
      ];
}

class _Root extends DBusObject {
  _Root(this.bluez) : super(DBusObjectPath('/'));

  final _BlueZ bluez;

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface('org.freedesktop.DBus.ObjectManager',
            methods: <DBusIntrospectMethod>[
              DBusIntrospectMethod('GetManagedObjects'),
            ]),
      ];

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
          DBusObjectPath(_BlueZ.adapterPath):
              _interfaces(<String, Map<String, DBusValue>>{
            'org.bluez.Adapter1': <String, DBusValue>{
              'Address': const DBusString('AA:BB:CC:DD:EE:FF'),
              'Powered': const DBusBoolean(true),
            },
          }),
          DBusObjectPath(_BlueZ.devicePath):
              _interfaces(<String, Map<String, DBusValue>>{
            'org.bluez.Device1': <String, DBusValue>{
              'Address': const DBusString('11:22:33:44:55:66'),
              'Name': const DBusString('Card reader'),
              'Paired': DBusBoolean(bluez.paired),
              'Connected': const DBusBoolean(false),
              'Adapter': DBusObjectPath(_BlueZ.adapterPath),
            },
          }),
        },
      ),
    ]);
  }
}

class _Device extends DBusObject {
  _Device(this.bluez) : super(DBusObjectPath(_BlueZ.devicePath));

  final _BlueZ bluez;

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface('org.bluez.Device1',
            methods: <DBusIntrospectMethod>[
              DBusIntrospectMethod('Pair'),
              DBusIntrospectMethod('Connect'),
              DBusIntrospectMethod('Disconnect'),
            ]),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.Device1') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    bluez.calls.add('${methodCall.name} ${path.value}');
    switch (methodCall.name) {
      case 'Pair':
        if (bluez.paired) {
          return DBusMethodErrorResponse('org.bluez.Error.AlreadyExists',
              <DBusValue>[const DBusString('Already Exists')]);
        }
        if (!bluez.agent) {
          return DBusMethodErrorResponse(
              'org.bluez.Error.AuthenticationCanceled',
              <DBusValue>[const DBusString('Authentication Canceled')]);
        }
        return DBusMethodSuccessResponse(<DBusValue>[]);
      case 'Connect':
        if (!bluez.paired) {
          return DBusMethodErrorResponse('org.bluez.Error.NotReady',
              <DBusValue>[const DBusString('Resource Not Ready')]);
        }
        return DBusMethodSuccessResponse(<DBusValue>[]);
      case 'Disconnect':
        return DBusMethodSuccessResponse(<DBusValue>[]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

class _Adapter extends DBusObject {
  _Adapter(this.bluez) : super(DBusObjectPath(_BlueZ.adapterPath));

  final _BlueZ bluez;

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface('org.bluez.Adapter1',
            methods: <DBusIntrospectMethod>[
              DBusIntrospectMethod('RemoveDevice'),
            ]),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.Adapter1' ||
        methodCall.name != 'RemoveDevice') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    final DBusValue argument = methodCall.values.first;
    bluez.calls.add('RemoveDevice ${path.value} '
        '${argument is DBusObjectPath ? argument.value : argument}');
    return DBusMethodSuccessResponse(<DBusValue>[]);
  }
}

DBusValue _interfaces(Map<String, Map<String, DBusValue>> interfaces) =>
    DBusDict(
      DBusSignature('s'),
      DBusSignature('a{sv}'),
      <DBusValue, DBusValue>{
        for (final MapEntry<String, Map<String, DBusValue>> e
            in interfaces.entries)
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

void main() {
  final bool hasBus =
      (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty;
  if (!hasBus) {
    test('linux bluetooth io (skipped: no session bus)', () {},
        skip: 'Run under a session bus (dbus-run-session works).');
    return;
  }

  late _BlueZ bluez;

  Future<void> serving(_BlueZ it) async {
    bluez = it;
    final DBusClient bus = DBusClient.session();
    for (final DBusObject object in it.objects) {
      await bus.registerObject(object);
    }
    await bus.requestName('org.bluez');
    addTearDown(() async => bus.close());
  }

  group('finding the device a caller named', () {
    test('an address is matched however it was typed', () async {
      // BlueZ spells its object paths in upper case. A caller holds whatever
      // was on the label or in a config file, and a lookup that compared the
      // two literally would answer "no such device" for one sitting on the
      // desk.
      await serving(_BlueZ());

      expect(
          await DVLinuxBluetooth.pairOn(
              DBusClient.session(), '11:22:33:44:55:66'),
          isTrue);
      expect(
          await DVLinuxBluetooth.pairOn(
              DBusClient.session(), '11:22:33:44:55:66'.toLowerCase()),
          isTrue);
    });

    test('an address nothing knows about says so, by address', () async {
      await serving(_BlueZ());

      expect(
          await DVLinuxBluetooth.pairOn(
              DBusClient.session(), '00:00:00:00:00:01'),
          isFalse);
      expect(bluez.calls, isEmpty);
      expect(DVLinuxBluetooth.lastError, contains('00:00:00:00:00:01'));
    });

    test('no BlueZ at all says that, rather than "no such device"', () async {
      // One needs a service started and the other needs somebody to bring a
      // device into range. They are not the same errand.
      expect(
          await DVLinuxBluetooth.pairOn(
              DBusClient.session(), '11:22:33:44:55:66'),
          isFalse);
      expect(DVLinuxBluetooth.lastError!.toLowerCase(), contains('bluez'));
    });
  });

  group('pairing', () {
    test('a device already paired is a success, not a failure', () async {
      // BlueZ answers AlreadyExists. The caller asked for the device to be
      // paired and it is paired -- reporting failure would have a kiosk
      // retrying forever against a reader that works.
      await serving(_BlueZ(paired: true));

      expect(
          await DVLinuxBluetooth.pairOn(
              DBusClient.session(), '11:22:33:44:55:66'),
          isTrue);
      expect(DVLinuxBluetooth.lastError, isNull);
    });

    test('no pairing agent is said to be no pairing agent', () async {
      // The state every headless device is in. There is nobody standing at
      // the kiosk to type a passkey, and "pairing failed" sends whoever
      // reads it to look at the radio, the range and the battery first.
      await serving(_BlueZ(agent: false));

      expect(
          await DVLinuxBluetooth.pairOn(
              DBusClient.session(), '11:22:33:44:55:66'),
          isFalse);
      expect(DVLinuxBluetooth.lastError!.toLowerCase(), contains('agent'));
    });
  });

  group('connecting', () {
    test('an unpaired device is refused with the reason', () async {
      await serving(_BlueZ());

      expect(
          await DVLinuxBluetooth.connectOn(
              DBusClient.session(), '11:22:33:44:55:66'),
          isFalse);
      expect(DVLinuxBluetooth.lastError!.toLowerCase(), contains('pair'));
    });

    test('a paired device connects, and disconnects again', () async {
      await serving(_BlueZ(paired: true));

      expect(
          await DVLinuxBluetooth.connectOn(
              DBusClient.session(), '11:22:33:44:55:66'),
          isTrue);
      expect(
          await DVLinuxBluetooth.disconnectOn(
              DBusClient.session(), '11:22:33:44:55:66'),
          isTrue);
      expect(bluez.calls,
          contains('Connect /org/bluez/hci0/dev_11_22_33_44_55_66'));
      expect(bluez.calls,
          contains('Disconnect /org/bluez/hci0/dev_11_22_33_44_55_66'));
    });
  });

  group('forgetting', () {
    test('it is the adapter that is asked, with the device as the argument',
        () async {
      // RemoveDevice is Adapter1's, not Device1's, and it is the only way to
      // unpair. Asking the device would be an unknown method -- and on a
      // machine with two adapters, asking the wrong adapter removes nothing
      // and reports success.
      await serving(_BlueZ(paired: true));

      expect(
          await DVLinuxBluetooth.forgetOn(
              DBusClient.session(), '11:22:33:44:55:66'),
          isTrue);
      expect(
          bluez.calls,
          contains('RemoveDevice /org/bluez/hci0 '
              '/org/bluez/hci0/dev_11_22_33_44_55_66'));
    });
  });

  test('the bindings answer through the bridge', () async {
    await serving(_BlueZ(paired: true));
    DVLinuxBluetooth.register(DVNativeBridge.register, bus: DBusClient.session());
    for (final String name in DVLinuxBluetooth.bindings) {
      addTearDown(() => DVNativeBridge.unregister(name));
    }

    expect(
        await DVNativeBridge.require<bool>('bluetooth.connect',
            <String, Object?>{'address': '11:22:33:44:55:66'}),
        isTrue);
  });
}
