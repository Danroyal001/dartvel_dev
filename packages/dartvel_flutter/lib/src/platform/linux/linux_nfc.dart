/// NFC on Linux: neard, over the bus.
///
/// A tag on a kiosk is how a member taps in, how a technician unlocks staff
/// mode, how a pallet identifies itself at a loading bay. Linux answers that
/// through neard, which exports adapters, the tag currently on the reader and
/// the records written to it -- so, as with BlueZ, this is a reader rather
/// than a stack. Writing a tag is a different job and is not claimed.
///
/// The distinction this file exists to keep is between silences. A machine
/// with no neard and a reader with nobody's card on it are the same absence
/// of an answer, and telling them apart is the difference between "hold your
/// card nearer" and "this unit's reader is not running".
library;

import 'dart:async';

import 'package:dbus/dbus.dart';

/// The neard bindings.
class DVLinuxNfc {
  DVLinuxNfc._();

  static const String _service = 'org.neard';
  static const String _adapter = 'org.neard.Adapter';
  static const String _record = 'org.neard.Record';

  static const Set<String> bindings = <String>{
    'nfc.isAvailable',
    'nfc.readTag',
  };

  /// Why the last read found nothing, when the reason is not "no tag".
  static String? lastError;

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind, {
    DBusClient? bus,
  }) {
    bind('nfc.isAvailable',
        (Object? _) => isAvailableOn(bus ?? DBusClient.system()));
    bind('nfc.readTag', (Object? _) => readTagOn(bus ?? DBusClient.system()));
  }

  /// Whether this machine has a reader that could read something now.
  ///
  /// A powered adapter, not merely a present one: an adapter that exists and
  /// is switched off would otherwise tell somebody to tap a reader that
  /// cannot read.
  static Future<bool> isAvailableOn(DBusClient bus) async {
    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
        await _managedObjects(bus);
    for (final Map<String, Map<String, DBusValue>> interfaces
        in objects.values) {
      final Map<String, DBusValue>? adapter = interfaces[_adapter];
      if (adapter == null) continue;
      final DBusValue? powered = adapter['Powered'];
      if (powered is DBusBoolean && powered.value) return true;
    }
    return false;
  }

  /// What is written on the tag currently on the reader, or null when there
  /// is none.
  ///
  /// Null is the normal state of a reader nobody has tapped, not a fault: an
  /// exception here would make every idle moment look like one.
  static Future<String?> readTagOn(DBusClient bus) async {
    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
        await _managedObjects(bus);
    final List<DBusObjectPath> records = <DBusObjectPath>[
      for (final MapEntry<DBusObjectPath, Map<String, Map<String, DBusValue>>> e
          in objects.entries)
        if (e.value.containsKey(_record)) e.key,
    ]..sort((DBusObjectPath a, DBusObjectPath b) => a.value.compareTo(b.value));
    for (final DBusObjectPath path in records) {
      final Map<String, DBusValue> record = objects[path]![_record]!;
      // A Text record carries its words; a URI record carries the address.
      // Both are what somebody wrote on the tag, which is what a caller
      // asked for.
      final DBusValue? representation =
          record['Representation'] ?? record['URI'];
      if (representation is DBusString && representation.value.isNotEmpty) {
        return representation.value;
      }
    }
    return null;
  }

  static Future<Map<DBusObjectPath, Map<String, Map<String, DBusValue>>>>
      _managedObjects(DBusClient bus) async {
    try {
      final DBusRemoteObjectManager manager = DBusRemoteObjectManager(
        bus,
        name: _service,
        path: DBusObjectPath('/'),
      );
      final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
          await manager.getManagedObjects();
      lastError = null;
      return objects;
    } on DBusServiceUnknownException {
      lastError = 'neard is not on the bus: no NFC service is running.';
      return const <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};
    } on Object catch (error) {
      lastError = 'The neard service could not be read: $error';
      return const <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};
    }
  }
}
