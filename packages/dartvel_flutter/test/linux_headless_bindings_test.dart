@TestOn('linux')
library;

// The device APIs on a machine with no desktop.
//
// An embedded device is the reason these exist: a kiosk on an eLinux image
// with DRM and no X server, reading a barcode scanner over the serial port,
// asking what is plugged in, checking whether the payment terminal is still
// paired, watching its own health for the fleet.
//
// Every one of them was registered inside the block that opens libX11 and
// GTK first and gives up if either is missing -- so on exactly the machines
// they were written for, they were not there at all, and the call came back
// "binding not registered". None of them touches X11: they are libc, sysfs
// and the system bus.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DVLinuxBindings.unregister);

  test('the device APIs come up without a desktop', () {
    // The headless path on its own: what an eLinux image gets.
    DVLinuxBindings.registerDeviceBindings();

    expect(
      DVNativeBridge.registered,
      containsAll(<String>[
        'device.serial.open',
        'device.serial.read',
        'device.serial.write',
        'device.serial.close',
        'device.serial.ports',
        'device.usb.devices',
        'bluetooth.isEnabled',
        'bluetooth.adapters',
        'bluetooth.devices',
        'nfc.isAvailable',
        'nfc.readTag',
        'device.capabilityManifest',
        'device.health',
        'device.watchdog.arm',
        'device.watchdog.heartbeat',
        'device.fleet.provision',
        'device.diagnostics.collect',
      ]),
    );
  });

  test('and it claims nothing that needs one', () {
    // The other half of the same rule: a headless device must not be told it
    // has a clipboard, a window or a tray. A binding that answers where
    // there is nothing to answer with is worse than one that is absent.
    DVLinuxBindings.registerDeviceBindings();

    for (final String desktop in <String>[
      'clipboard.copy',
      'clipboard.paste',
      'window.setTitle',
      'window.setSize',
      'menus.setApplicationMenu',
      'tray.show',
      'dialogs.openFile',
      'screen.geometry',
    ]) {
      expect(DVNativeBridge.isRegistered(desktop), isFalse,
          reason: '$desktop was claimed on a machine with no desktop');
    }
  });

  test('a full registration has them too', () {
    // The desktop path must not lose them: it is the same device underneath,
    // and an X server does not take the serial port away.
    DVLinuxBindings.register();

    expect(DVNativeBridge.isRegistered('device.serial.open'), isTrue);
    expect(DVNativeBridge.isRegistered('device.usb.devices'), isTrue);
    expect(DVNativeBridge.isRegistered('nfc.readTag'), isTrue);
  });

  test('registering twice leaves one of each', () {
    DVLinuxBindings.registerDeviceBindings();
    DVLinuxBindings.registerDeviceBindings();

    expect(
      DVNativeBridge.registered.where((String n) => n == 'device.usb.devices'),
      hasLength(1),
    );
  });
}
