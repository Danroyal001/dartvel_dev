@TestOn('linux')
library;

// NFC on Linux: neard, over the bus.
//
// A tag on a kiosk is how a member taps in, how a technician unlocks staff
// mode, how a pallet identifies itself at a loading bay. Linux answers that
// through neard, which exports adapters, the tag currently on the reader and
// the records written to it -- so, like BlueZ, this is a reader rather than a
// stack.
//
// The failures worth catching are about honesty. A machine with no neard and
// a reader with no tag on it are the same silence, and telling them apart is
// the difference between "hold your card nearer" and "this unit's reader is
// not running".
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_nfc.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for neard: an adapter, a tag on it, and a record.
class _Neard extends DBusObject {
  _Neard({this.powered = true, this.tag = true, this.text = 'member-4417'})
      : super(DBusObjectPath('/'));

  final bool powered;
  final bool tag;
  final String text;

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
          DBusObjectPath('/org/neard/nfc0'): _interfaces(<String, Map<String, DBusValue>>{
            'org.neard.Adapter': <String, DBusValue>{
              'Powered': DBusBoolean(powered),
              'Polling': const DBusBoolean(true),
            },
          }),
          if (tag)
            DBusObjectPath('/org/neard/nfc0/tag0'):
                _interfaces(<String, Map<String, DBusValue>>{
              'org.neard.Tag': <String, DBusValue>{
                'Type': const DBusString('Type2'),
                'ReadOnly': const DBusBoolean(false),
              },
            }),
          if (tag)
            DBusObjectPath('/org/neard/nfc0/tag0/record0'):
                _interfaces(<String, Map<String, DBusValue>>{
              'org.neard.Record': <String, DBusValue>{
                'Type': const DBusString('Text'),
                'Representation': DBusString(text),
                'Encoding': const DBusString('UTF-8'),
              },
            }),
        },
      ),
    ]);
  }

  DBusValue _interfaces(Map<String, Map<String, DBusValue>> interfaces) => DBusDict(
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
    test('linux nfc (skipped: no session bus)', () {},
        skip: 'Run under a session bus (dbus-run-session works).');
    return;
  }

  Future<DBusClient> serving(_Neard neard) async {
    final DBusClient bus = DBusClient.session();
    await bus.registerObject(neard);
    await bus.requestName('org.neard');
    addTearDown(() async => bus.close());
    return bus;
  }

  test('a powered reader is an NFC that is available', () async {
    await serving(_Neard());

    expect(await DVLinuxNfc.isAvailableOn(DBusClient.session()), isTrue);
  });

  test('a reader that is switched off is not available', () async {
    // Present and powered down: an application that treated the adapter's
    // existence as availability would tell somebody to tap a reader that
    // cannot read.
    await serving(_Neard(powered: false));

    expect(await DVLinuxNfc.isAvailableOn(DBusClient.session()), isFalse);
  });

  test('no neard at all is not available, and says why', () async {
    // The difference between "hold your card nearer" and "this unit's reader
    // is not running", which is the whole of what a support desk needs.
    expect(await DVLinuxNfc.isAvailableOn(DBusClient.session()), isFalse);
    expect(DVLinuxNfc.lastError, isNotNull);
    expect(DVLinuxNfc.lastError, contains('neard'));
  });

  test('the tag on the reader reads as what was written to it', () async {
    await serving(_Neard(text: 'member-4417'));

    expect(await DVLinuxNfc.readTagOn(DBusClient.session()), 'member-4417');
  });

  test('a reader with no tag on it reads as nothing, not as an error', () async {
    // Nobody has tapped yet. That is the normal state of a reader, not a
    // fault, and an exception here would make every idle moment look like one.
    await serving(_Neard(tag: false));

    expect(await DVLinuxNfc.readTagOn(DBusClient.session()), isNull);
    expect(DVLinuxNfc.lastError, isNull);
  });

  test('the bindings answer through the bridge', () async {
    await serving(_Neard());
    DVLinuxNfc.register(DVNativeBridge.register, bus: DBusClient.session());
    addTearDown(() => DVNativeBridge.unregister('nfc.isAvailable'));
    addTearDown(() => DVNativeBridge.unregister('nfc.readTag'));

    expect(await DVNativeBridge.require<bool>('nfc.isAvailable'), isTrue);
    expect(await DVNativeBridge.invoke<String>('nfc.readTag'), 'member-4417');
  });
}
