@TestOn('linux')
library;

// The USB devices a machine has, as the kernel reports them.
//
// An embedded device's peripherals are USB: the barcode scanner on a kiosk,
// the payment terminal, the receipt printer, the serial adapter. A fleet that
// cannot ask what is plugged in cannot tell "the scanner is unplugged" from
// "the scanner is broken", which is the difference between somebody walking
// over with a cable and somebody replacing a unit.
//
// The kernel already answers this in sysfs, so the binding is a reader, and
// the failures are a reader's: an interface directory counted as a device, a
// hex id read as decimal, a name with the trailing newline still on it, and a
// device that vanished between listing and reading taking the whole call down
// with it -- which on a bus people unplug things from is not unusual.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_usb.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sysfs tree shaped like the kernel's.
Directory sysfs(Map<String, Map<String, String>> devices) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_usb_');
  addTearDown(() => root.deleteSync(recursive: true));
  devices.forEach((String name, Map<String, String> attributes) {
    final Directory dir = Directory('${root.path}/$name')..createSync(recursive: true);
    attributes.forEach((String file, String value) {
      File('${dir.path}/$file').writeAsStringSync(value);
    });
  });
  return root;
}

void main() {
  setUpAll(() => DVLinuxUsb.register(DVNativeBridge.register));

  test('a plugged-in device is reported, with what it says about itself', () async {
    final Directory root = sysfs(<String, Map<String, String>>{
      'usb1': <String, String>{
        'idVendor': '1d6b\n',
        'idProduct': '0002\n',
        'manufacturer': 'Linux Foundation\n',
        'product': '2.0 root hub\n',
        'serial': '0000:00:14.0\n',
        'busnum': '1\n',
        'devnum': '1\n',
      },
    });

    final List<DVUsbDevice> devices = DVLinuxUsb.devicesIn(root.path);

    expect(devices, hasLength(1));
    final DVUsbDevice device = devices.single;
    // Hex, as the kernel writes it and as every USB id is quoted.
    expect(device.vendorId, 0x1d6b);
    expect(device.productId, 0x0002);
    // Without the newline the kernel puts on the end of every attribute.
    expect(device.manufacturer, 'Linux Foundation');
    expect(device.product, '2.0 root hub');
    expect(device.serial, '0000:00:14.0');
    expect(device.bus, 1);
    expect(device.address, 1);
  });

  test('an interface is not a device', () {
    // sysfs puts interfaces in the same directory -- `1-1:1.0` is the
    // keyboard interface of the device `1-1`. Counted as devices they double
    // every peripheral on the bus, and they carry no idVendor, so they would
    // be reported as devices with no identity at all.
    final Directory root = sysfs(<String, Map<String, String>>{
      '1-1': <String, String>{'idVendor': '046d', 'idProduct': 'c31c'},
      '1-1:1.0': <String, String>{'bInterfaceClass': '03'},
      '1-1:1.1': <String, String>{'bInterfaceClass': '03'},
    });

    final List<DVUsbDevice> devices = DVLinuxUsb.devicesIn(root.path);

    expect(devices.map((DVUsbDevice d) => d.path), <String>['1-1']);
  });

  test('a device that says nothing about itself is still a device', () {
    // A hub or a cheap adapter often has no manufacturer or product string.
    // Dropping it would hide something that is plugged in.
    final Directory root = sysfs(<String, Map<String, String>>{
      '2-1': <String, String>{'idVendor': '0403', 'idProduct': '6001'},
    });

    final List<DVUsbDevice> devices = DVLinuxUsb.devicesIn(root.path);

    expect(devices, hasLength(1));
    expect(devices.single.manufacturer, isNull);
    expect(devices.single.product, isNull);
  });

  test('an unreadable id is not a device with a wrong one', () {
    // A truncated read or a directory that went away mid-listing must not
    // become a device reported with vendor zero, which is a real vendor id
    // as far as anything reading it is concerned.
    final Directory root = sysfs(<String, Map<String, String>>{
      '3-1': <String, String>{'idVendor': 'zzzz', 'idProduct': '0001'},
    });

    expect(DVLinuxUsb.devicesIn(root.path), isEmpty);
  });

  test('no bus at all is no devices, not an error', () {
    // A container without USB passthrough has no such directory, and an
    // application asking what is plugged in should be told nothing is.
    expect(DVLinuxUsb.devicesIn('/nonexistent/usb'), isEmpty);
  });

  test('the binding answers with the same devices', () async {
    final List<Object?> reported =
        await DVNativeBridge.require<List<Object?>>('device.usb.devices');

    // Whatever this machine has -- a container usually has nothing -- every
    // entry has to be a device with an identity.
    for (final Object? entry in reported) {
      expect(entry, isA<Map<Object?, Object?>>());
      final Map<Object?, Object?> device = entry! as Map<Object?, Object?>;
      expect(device['vendorId'], isA<int>());
      expect(device['productId'], isA<int>());
    }
  });

  test('the running machine is read without throwing', () {
    // The real sysfs, whatever is in it: the reader must survive a bus with
    // devices being added and removed under it.
    expect(DVLinuxUsb.devicesIn('/sys/bus/usb/devices'), isA<List<DVUsbDevice>>());
  });
}
