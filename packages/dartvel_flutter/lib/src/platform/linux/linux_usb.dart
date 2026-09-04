/// What is plugged into the machine, as the kernel already reports it.
///
/// An embedded device's peripherals are USB: the barcode scanner on a kiosk,
/// the payment terminal, the receipt printer, the serial adapter. A fleet
/// that cannot ask what is plugged in cannot tell "the scanner is unplugged"
/// from "the scanner is broken", which is the difference between somebody
/// walking over with a cable and somebody replacing a unit.
///
/// sysfs answers this already, so this is a reader rather than a driver: no
/// libusb, no permissions to arrange, and nothing to install on a device that
/// ships read-only. Opening a device and talking to it is a different job
/// with a different threat model, and this is the half a fleet actually
/// needs.
library;

import 'dart:async';
import 'dart:io';

import '../../../dartvel_flutter.dart' show DVUsbDevice;

/// The USB bindings.
class DVLinuxUsb {
  DVLinuxUsb._();

  static const String _sysfs = '/sys/bus/usb/devices';

  static const Set<String> bindings = <String>{'device.usb.devices'};

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    bind(
      'device.usb.devices',
      (Object? _) => <Map<String, Object?>>[
        for (final DVUsbDevice device in devicesIn(_sysfs)) device.toMap(),
      ],
    );
  }

  /// The devices under [root], which is sysfs on a running machine.
  ///
  /// An absent directory is no devices rather than an error: a container
  /// without USB passthrough has none, and an application asking what is
  /// plugged in should be told nothing is.
  static List<DVUsbDevice> devicesIn(String root) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) return const <DVUsbDevice>[];
    final List<DVUsbDevice> devices = <DVUsbDevice>[];
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync()..sort((FileSystemEntity a, FileSystemEntity b) =>
          a.path.compareTo(b.path));
    } on FileSystemException {
      return const <DVUsbDevice>[];
    }
    for (final FileSystemEntity entry in entries) {
      final String name = entry.path.split('/').last;
      // sysfs puts interfaces in the same directory: `1-1:1.0` is the
      // keyboard interface of the device `1-1`. Counted as devices they
      // double every peripheral on the bus, and they carry no vendor id, so
      // they would be reported as devices with no identity.
      if (name.contains(':')) continue;
      final int? vendor = _hexAttribute(entry.path, 'idVendor');
      final int? product = _hexAttribute(entry.path, 'idProduct');
      // No identity is not a device with vendor zero, which is a real vendor
      // id as far as anything reading it is concerned.
      if (vendor == null || product == null) continue;
      devices.add(DVUsbDevice(
        path: name,
        vendorId: vendor,
        productId: product,
        manufacturer: _textAttribute(entry.path, 'manufacturer'),
        product: _textAttribute(entry.path, 'product'),
        serial: _textAttribute(entry.path, 'serial'),
        bus: _intAttribute(entry.path, 'busnum'),
        address: _intAttribute(entry.path, 'devnum'),
      ));
    }
    return devices;
  }

  /// One sysfs attribute, without the newline the kernel puts on the end of
  /// every one of them.
  ///
  /// Null when it is not there or cannot be read. A device can be unplugged
  /// between the listing and the read, and on a bus people unplug things from
  /// that is not unusual -- it must not take the whole call down.
  static String? _textAttribute(String dir, String name) {
    try {
      final File file = File('$dir/$name');
      if (!file.existsSync()) return null;
      final String value = file.readAsStringSync().trim();
      return value.isEmpty ? null : value;
    } on FileSystemException {
      return null;
    }
  }

  /// A hexadecimal attribute. USB ids are written in hex without a prefix,
  /// and read as decimal `1d6b` is not a number at all while `0002` is two.
  static int? _hexAttribute(String dir, String name) {
    final String? raw = _textAttribute(dir, name);
    return raw == null ? null : int.tryParse(raw, radix: 16);
  }

  static int? _intAttribute(String dir, String name) {
    final String? raw = _textAttribute(dir, name);
    return raw == null ? null : int.tryParse(raw);
  }
}
