/// Bluetooth on Linux: what BlueZ already knows.
///
/// A kiosk's payment terminal, a scale, a label printer: on an embedded
/// device these are paired Bluetooth peripherals, and when one stops working
/// there are two questions -- is the adapter switched on, and is the thing
/// still paired. BlueZ answers both on the bus, exporting every adapter and
/// every known device through the standard object manager, so this is a
/// reader rather than a stack.
///
/// Pairing, connecting and talking to a device are a different job with a
/// different threat model, and they are not claimed here. Knowing what is
/// there is the half a fleet needs, and the half that can be read without
/// asking anybody for permission.
library;

import 'dart:async';

import 'package:dbus/dbus.dart';

import '../../../dartvel_flutter.dart'
    show DVBluetoothAdapter, DVBluetoothDevice;

/// The BlueZ bindings.
class DVLinuxBluetooth {
  DVLinuxBluetooth._();

  static const String _service = 'org.bluez';
  static const String _adapter = 'org.bluez.Adapter1';
  static const String _device = 'org.bluez.Device1';

  static const Set<String> bindings = <String>{
    'bluetooth.isEnabled',
    'bluetooth.scanDevices',
    'bluetooth.adapters',
    'bluetooth.devices',
  };

  /// Why the last read found nothing.
  ///
  /// A machine with no BlueZ running and a machine with nothing paired both
  /// answer with an empty list, and they are different faults: one needs a
  /// service started, the other needs somebody to pair a device.
  static String? lastError;

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind, {
    DBusClient? bus,
  }) {
    bind('bluetooth.isEnabled', (Object? _) async {
      final List<DVBluetoothAdapter> found =
          await adaptersOn(bus ?? DBusClient.system());
      return found.any((DVBluetoothAdapter a) => a.powered);
    });
    bind('bluetooth.scanDevices', (Object? _) async {
      // The names of what is already known, which is what the stream-shaped
      // surface has always meant here: turning the radio on and waiting is a
      // different operation with a different cost.
      final List<DVBluetoothDevice> found =
          await devicesOn(bus ?? DBusClient.system());
      return <String>[
        for (final DVBluetoothDevice device in found) device.name ?? device.address,
      ];
    });
    bind('bluetooth.adapters', (Object? _) async {
      final List<DVBluetoothAdapter> found =
          await adaptersOn(bus ?? DBusClient.system());
      return <Map<String, Object?>>[
        for (final DVBluetoothAdapter adapter in found) adapter.toMap(),
      ];
    });
    bind('bluetooth.devices', (Object? _) async {
      final List<DVBluetoothDevice> found =
          await devicesOn(bus ?? DBusClient.system());
      return <Map<String, Object?>>[
        for (final DVBluetoothDevice device in found) device.toMap(),
      ];
    });
  }

  /// The adapters this machine has.
  static Future<List<DVBluetoothAdapter>> adaptersOn(DBusClient bus) async {
    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
        await _managedObjects(bus);
    final List<DVBluetoothAdapter> adapters = <DVBluetoothAdapter>[];
    objects.forEach((DBusObjectPath path,
        Map<String, Map<String, DBusValue>> interfaces) {
      final Map<String, DBusValue>? properties = interfaces[_adapter];
      if (properties == null) return;
      adapters.add(DVBluetoothAdapter(
        path: path.value,
        address: _string(properties['Address']) ?? '',
        name: _string(properties['Name']),
        powered: _bool(properties['Powered']) ?? false,
        discovering: _bool(properties['Discovering']) ?? false,
      ));
    });
    adapters.sort((DVBluetoothAdapter a, DVBluetoothAdapter b) =>
        a.path.compareTo(b.path));
    return adapters;
  }

  /// Every device BlueZ knows about: paired, connected, or merely seen.
  static Future<List<DVBluetoothDevice>> devicesOn(DBusClient bus) async {
    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
        await _managedObjects(bus);
    final List<DVBluetoothDevice> devices = <DVBluetoothDevice>[];
    objects.forEach((DBusObjectPath path,
        Map<String, Map<String, DBusValue>> interfaces) {
      final Map<String, DBusValue>? properties = interfaces[_device];
      if (properties == null) return;
      devices.add(DVBluetoothDevice(
        path: path.value,
        address: _string(properties['Address']) ?? '',
        // A peripheral out of range advertises an address and nothing else.
        // Dropped for having no name, a fleet would be told a paired thing
        // is not there at all.
        name: _string(properties['Name']),
        paired: _bool(properties['Paired']) ?? false,
        connected: _bool(properties['Connected']) ?? false,
        rssi: _int(properties['RSSI']),
        adapter: _path(properties['Adapter']),
      ));
    });
    devices.sort((DVBluetoothDevice a, DVBluetoothDevice b) =>
        a.path.compareTo(b.path));
    return devices;
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
      lastError = 'BlueZ is not on the bus: no bluetooth service is running.';
      return const <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};
    } on DBusMethodResponseException catch (error) {
      lastError = 'BlueZ refused the request: ${error.response.signature}.';
      return const <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};
    } on Object catch (error) {
      lastError = 'The bluetooth service could not be read: $error';
      return const <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};
    }
  }

  static String? _string(DBusValue? value) =>
      value is DBusString ? value.value : null;

  static bool? _bool(DBusValue? value) =>
      value is DBusBoolean ? value.value : null;

  static int? _int(DBusValue? value) => switch (value) {
        DBusInt16() => value.value,
        DBusInt32() => value.value,
        DBusInt64() => value.value,
        _ => null,
      };

  static String? _path(DBusValue? value) =>
      value is DBusObjectPath ? value.value : null;
}
