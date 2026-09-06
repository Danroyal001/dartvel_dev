@TestOn('linux')
library;

// Writing a tag, through neard.
//
// Reading was built and writing was named as a different job and left. It is
// a different job, and it is the half a kiosk needs to hand somebody a card:
// a locker key, a visitor badge, a pallet label. neard exposes it as
// org.neard.Tag.Write, taking the record as a dictionary.
//
// What makes it worth its own suite is that almost every way it goes wrong
// still looks like it worked. A URI written into a Text record is a tag that
// reads back as the right characters and does nothing when a phone touches
// it. An NDEF Text record with no language code is one some readers show as
// empty. A read-only tag refuses the write at the chip, and a caller told
// only "failed" will keep presenting it. And a write with nothing on the
// reader at all has to say so, because that is the one the person holding
// the card can fix.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_nfc.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for neard that remembers what it was asked to write.
class _Neard extends DBusObject {
  _Neard({
    this.powered = true,
    this.tag = true,
    this.readOnly = false,
    this.refuse,
  }) : super(DBusObjectPath('/'));

  final bool powered;
  final bool tag;
  final bool readOnly;

  /// A message neard answers the write with, the way a chip that will not
  /// take the record does.
  final String? refuse;

  /// The attributes the last Write carried, flattened for reading.
  Map<String, String> written = <String, String>{};
  int writes = 0;

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface('org.freedesktop.DBus.ObjectManager',
            methods: <DBusIntrospectMethod>[
              DBusIntrospectMethod('GetManagedObjects'),
            ]),
        DBusIntrospectInterface('org.neard.Tag',
            methods: <DBusIntrospectMethod>[DBusIntrospectMethod('Write')]),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.neard.Tag' &&
        methodCall.name == 'Write') {
      writes++;
      final DBusValue argument = methodCall.values.first;
      written = <String, String>{
        if (argument is DBusDict)
          for (final MapEntry<DBusValue, DBusValue> e in argument.children.entries)
            (e.key as DBusString).value:
                _plain((e.value as DBusVariant).value),
      };
      if (refuse != null) {
        return DBusMethodErrorResponse('org.neard.Error.Failed',
            <DBusValue>[DBusString(refuse!)]);
      }
      return DBusMethodSuccessResponse(<DBusValue>[]);
    }
    if (methodCall.interface != 'org.freedesktop.DBus.ObjectManager' ||
        methodCall.name != 'GetManagedObjects') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse(<DBusValue>[
      DBusDict(
        DBusSignature('o'),
        DBusSignature('a{sa{sv}}'),
        <DBusValue, DBusValue>{
          DBusObjectPath('/org/neard/nfc0'):
              _interfaces(<String, Map<String, DBusValue>>{
            'org.neard.Adapter': <String, DBusValue>{
              'Powered': DBusBoolean(powered),
            },
          }),
          if (tag)
            DBusObjectPath('/org/neard/nfc0/tag0'):
                _interfaces(<String, Map<String, DBusValue>>{
              'org.neard.Tag': <String, DBusValue>{
                'Type': const DBusString('Type2'),
                'ReadOnly': DBusBoolean(readOnly),
              },
            }),
        },
      ),
    ]);
  }

  static String _plain(DBusValue value) =>
      value is DBusString ? value.value : value.toString();

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
}

void main() {
  final bool hasBus =
      (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty;
  if (!hasBus) {
    test('linux nfc write (skipped: no session bus)', () {},
        skip: 'Run under a session bus (dbus-run-session works).');
    return;
  }

  late _Neard neard;

  Future<void> serving(_Neard it) async {
    neard = it;
    final DBusClient bus = DBusClient.session();
    await bus.registerObject(it);
    await bus.requestName('org.neard');
    addTearDown(() async => bus.close());
  }

  group('what reaches the tag', () {
    test('text is written as a Text record, with a language', () async {
      // An NDEF Text record carries a language code. Without one some
      // readers show the record as empty, which is a tag that was written
      // and reads as blank -- the write reported success either way.
      await serving(_Neard());

      expect(await DVLinuxNfc.writeTagOn(DBusClient.session(), 'locker-12'),
          isTrue);
      expect(neard.written['Type'], 'Text');
      expect(neard.written['Representation'], 'locker-12');
      expect(neard.written['Language'], isNotNull);
      expect(neard.written['Encoding'], 'UTF-8');
    });

    test('a URI is written as a URI record, not as text that looks like one',
        () async {
      // The failure this exists for: a Text record containing
      // "https://example.com" reads back as exactly those characters and
      // does nothing at all when a phone is held against it. Nothing errors
      // -- the tag is written, and it is the wrong kind of tag.
      await serving(_Neard());

      expect(
          await DVLinuxNfc.writeTagOn(
              DBusClient.session(), 'https://dartvel.dev/locker/12'),
          isTrue);
      expect(neard.written['Type'], 'URI');
      expect(neard.written['URI'], 'https://dartvel.dev/locker/12');
      expect(neard.written.containsKey('Representation'), isFalse);
    });

    test('a scheme it does not know is text, not a broken URI', () async {
      // "member-4417" has a colon in nothing and is not a URI. Guessing
      // otherwise would write a URI record no reader can follow.
      await serving(_Neard());

      await DVLinuxNfc.writeTagOn(DBusClient.session(), 'member-4417');

      expect(neard.written['Type'], 'Text');
    });
  });

  group('what it refuses, and what it says', () {
    test('nothing on the reader is said to be nothing on the reader',
        () async {
      // The one failure the person holding the card can fix. A bus error
      // about a missing object tells them nothing.
      await serving(_Neard(tag: false));

      expect(await DVLinuxNfc.writeTagOn(DBusClient.session(), 'x'), isFalse);
      expect(neard.writes, 0);
      expect(DVLinuxNfc.lastError, isNotNull);
      expect(DVLinuxNfc.lastError!.toLowerCase(), contains('tag'));
    });

    test('a read-only tag is refused before the write, and says so', () async {
      // A locked tag refuses at the chip. Told only "failed", somebody
      // presents the same card again, and again.
      await serving(_Neard(readOnly: true));

      expect(await DVLinuxNfc.writeTagOn(DBusClient.session(), 'x'), isFalse);
      expect(neard.writes, 0);
      expect(DVLinuxNfc.lastError!.toLowerCase(), contains('read-only'));
    });

    test('neard refusing the write is reported, not swallowed', () async {
      await serving(_Neard(refuse: 'tag was removed'));

      expect(await DVLinuxNfc.writeTagOn(DBusClient.session(), 'x'), isFalse);
      expect(neard.writes, 1);
      expect(DVLinuxNfc.lastError, contains('tag was removed'));
    });

    test('no neard at all says that, rather than "no tag"', () async {
      // The same distinction reading keeps: "hold your card nearer" against
      // "this unit's reader is not running".
      expect(await DVLinuxNfc.writeTagOn(DBusClient.session(), 'x'), isFalse);
      expect(DVLinuxNfc.lastError, contains('neard'));
    });

    test('an empty record is refused rather than written', () async {
      // A tag written with nothing on it reads as a tag with nothing on it,
      // which is indistinguishable from a tag that was never written.
      await serving(_Neard());

      expect(await DVLinuxNfc.writeTagOn(DBusClient.session(), '  '), isFalse);
      expect(neard.writes, 0);
    });
  });

  test('a successful write clears the error the last failure left', () async {
    // lastError outlives the call that set it. A write that succeeds after
    // one that failed would otherwise leave a stale reason on screen.
    expect(await DVLinuxNfc.writeTagOn(DBusClient.session(), 'x'), isFalse);
    expect(DVLinuxNfc.lastError, isNotNull);

    await serving(_Neard());

    expect(await DVLinuxNfc.writeTagOn(DBusClient.session(), 'ok'), isTrue);
    expect(DVLinuxNfc.lastError, isNull);
  });

  test('the binding answers through the bridge', () async {
    await serving(_Neard());
    DVLinuxNfc.register(DVNativeBridge.register, bus: DBusClient.session());
    for (final String name in DVLinuxNfc.bindings) {
      addTearDown(() => DVNativeBridge.unregister(name));
    }

    expect(
        await DVNativeBridge.require<bool>(
            'nfc.writeTag', <String, Object?>{'value': 'locker-12'}),
        isTrue);
    expect(neard.written['Representation'], 'locker-12');
  });
}
