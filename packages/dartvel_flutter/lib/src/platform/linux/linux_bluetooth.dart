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
    'bluetooth.pair',
    'bluetooth.connect',
    'bluetooth.disconnect',
    'bluetooth.forget',
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
    // Doing something to a device, rather than reading about one. Each takes
    // the address a caller holds; resolving it to the object path BlueZ
    // wants is this layer's job, since the path is an implementation detail
    // of the daemon and the address is what is written on the label.
    for (final MapEntry<String, Future<bool> Function(DBusClient, String)> e
        in <String, Future<bool> Function(DBusClient, String)>{
      'bluetooth.pair': pairOn,
      'bluetooth.connect': connectOn,
      'bluetooth.disconnect': disconnectOn,
      'bluetooth.forget': forgetOn,
    }.entries) {
      bind(e.key, (Object? arguments) {
        final Map<Object?, Object?> a =
            arguments is Map ? arguments : const <Object?, Object?>{};
        return e.value(bus ?? DBusClient.system(), '${a['address'] ?? ''}');
      });
    }
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


  /// Pairs the device at [address].
  ///
  /// True when the device is paired at the end of the call, which includes
  /// the case where it already was: BlueZ answers `AlreadyExists`, and a
  /// caller told that is a failure retries forever against a reader that
  /// works.
  static Future<bool> pairOn(DBusClient bus, String address) =>
      _onDevice(bus, address, 'Pair');

  /// Connects to the device at [address].
  static Future<bool> connectOn(DBusClient bus, String address) =>
      _onDevice(bus, address, 'Connect');

  /// Disconnects the device at [address].
  static Future<bool> disconnectOn(DBusClient bus, String address) =>
      _onDevice(bus, address, 'Disconnect');

  /// Unpairs the device at [address] and forgets it.
  ///
  /// `RemoveDevice` belongs to the adapter rather than to the device, and it
  /// is the only way to unpair -- so this asks the adapter the device says it
  /// is on. On a machine with two, asking the other one removes nothing and
  /// answers success.
  static Future<bool> forgetOn(DBusClient bus, String address) async {
    final DVBluetoothDevice? device = await _find(bus, address);
    if (device == null) return false;
    final String? adapter = device.adapter;
    if (adapter == null) {
      lastError = 'BlueZ does not say which adapter ${device.address} is on, '
          'so there is nothing to ask to forget it.';
      return false;
    }
    return _call(bus, DBusObjectPath(adapter), _adapter, 'RemoveDevice',
        <DBusValue>[DBusObjectPath(device.path)]);
  }

  /// One of Device1's no-argument methods, on the device at [address].
  static Future<bool> _onDevice(
      DBusClient bus, String address, String method) async {
    final DVBluetoothDevice? device = await _find(bus, address);
    if (device == null) return false;
    return _call(
        bus, DBusObjectPath(device.path), _device, method, const <DBusValue>[]);
  }

  /// The known device at [address], or null with [lastError] saying why.
  ///
  /// Matched case-insensitively. BlueZ spells its object paths in upper case
  /// and a caller holds whatever was on the label or in a configuration file;
  /// comparing the two literally answers "no such device" for one sitting on
  /// the desk.
  static Future<DVBluetoothDevice?> _find(
      DBusClient bus, String address) async {
    final List<DVBluetoothDevice> known = await devicesOn(bus);
    // devicesOn has already said why it found nothing, and "BlueZ is not
    // running" must not be replaced by "no such device": those send somebody
    // to two different places.
    if (lastError != null) return null;

    final String wanted = address.trim().toUpperCase();
    for (final DVBluetoothDevice device in known) {
      if (device.address.toUpperCase() == wanted) return device;
    }
    lastError = 'This machine does not know a device at $address. Bring it '
        'into range, or check the address.';
    return null;
  }

  static Future<bool> _call(
    DBusClient bus,
    DBusObjectPath path,
    String interface,
    String method,
    List<DBusValue> values,
  ) async {
    try {
      await bus.callMethod(
        destination: _service,
        path: path,
        interface: interface,
        name: method,
        values: values,
        replySignature: DBusSignature(''),
      );
      lastError = null;
      return true;
    } on DBusMethodResponseException catch (error) {
      return _refused(error, method);
    } on Object catch (error) {
      lastError = 'BlueZ could not $method: $error';
      return false;
    }
  }

  /// What BlueZ said, turned into something worth acting on.
  ///
  /// Its error names are specific and its worst answers look like ordinary
  /// failures, so flattening them into one is throwing away the only part
  /// that tells anybody what to do next.
  static bool _refused(DBusMethodResponseException error, String method) {
    // .response is declared as the error response, so its name and its
    // values are both here without a cast. An earlier version of this read
    // it through a local typed as the parent, to be safe against the
    // package declaring it either way -- which was not safe, it was a guess,
    // and the parent has no values getter. It broke every target that
    // compiles this file.
    final DBusMethodErrorResponse response = error.response;
    final String name = response.errorName;
    // Already paired is the outcome the caller asked for.
    if (name.endsWith('.AlreadyExists')) {
      lastError = null;
      return true;
    }
    if (name.endsWith('.AuthenticationCanceled') ||
        name.endsWith('.AuthenticationFailed') ||
        name.endsWith('.AuthenticationRejected')) {
      lastError = 'Pairing needs an agent to answer for it and there is none '
          'registered. On a device with nobody standing at it, pair from the '
          'fleet console or register an agent that accepts automatically.';
      return false;
    }
    if (name.endsWith('.NotReady')) {
      lastError = 'The device is not ready to connect. Pair it first: a '
          'connection to something unpaired is refused before the radio is '
          'used at all.';
      return false;
    }
    if (name.endsWith('.NotConnected')) {
      // Asked to disconnect something already disconnected.
      lastError = null;
      return true;
    }
    final String detail = response.values
        .whereType<DBusString>()
        .map((DBusString v) => v.value)
        .join('; ');
    lastError = 'BlueZ refused $method'
        '${name.isEmpty ? '' : ' ($name)'}'
        '${detail.isEmpty ? '' : ': $detail'}';
    return false;
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
