/// Every native binding name Dartvel calls, in one place.
///
/// A binding name is a bare string on both sides of the bridge, and
/// `DVNativeBridge.invoke` returns null when nothing is registered under the
/// name it was given. That is right -- an unbound capability degrades rather
/// than throws, which is the whole capability model -- and it means a typo is
/// indistinguishable from an unsupported platform. `window.setTitel` compiles,
/// registers nothing, invokes nothing, and returns null on every target for
/// ever.
///
/// So the names are declared here and a test checks the source against this
/// list, in both directions: a name used but not declared is more often a typo
/// than a new binding, and a name declared but never used reads as support
/// that exists.
///
/// Being in this list does not mean a platform implements it. Most of these
/// are bound on some targets and not others, which is what
/// `DVNativeBridge.isRegistered` is for.
library dartvel.platform.binding_names;

/// The canonical binding names.
const Set<String> dvNativeBindingNames = <String>{
  // Device and sensors.
  'biometrics.authenticate',
  'biometrics.canAuthenticate',
  'bluetooth.isEnabled',
  'bluetooth.scanDevices',
  'camera.takePhoto',
  'contacts.getContacts',
  'device.health',
  'location.current',
  'nfc.isAvailable',
  'nfc.readTag',
  'sensors.accelerometer',
  'sensors.gyroscope',

  // Feedback and system integration.
  'clipboard.copy',
  'clipboard.paste',
  'deepLinks.initial',
  'haptics.impact',
  'haptics.lightVibrate',
  'haptics.vibrate',
  'media.pick',
  'notifications.sendLocal',
  'permissions.isGranted',
  'permissions.request',
  'share.text',
  'tray.hide',
  'tray.show',

  // Files. Bound on every target with a filesystem.
  'files.delete',
  'files.readBytes',
  'files.writeBytes',

  // Screen.
  'screen.geometry',

  // Over-the-air updates.
  'updates.apply',
  'updates.check',
  'updates.rollback',

  // Fleet and embedded device management. Three segments rather than two,
  // because the namespace is the subsystem and these are its own surface.
  'device.capabilityManifest',
  'device.diagnostics.collect',
  'device.fleet.provision',
  'device.watchdog.arm',
  'device.watchdog.heartbeat',
  // The serial port: the one bus an embedded device is most likely to have,
  // and the one a Flutter application has had no way to reach.
  'device.serial.ports',
  'device.serial.open',
  'device.serial.write',
  'device.serial.read',
  'device.serial.close',
  // What is plugged in, which sysfs already answers.
  'device.usb.devices',
  // Bluetooth, which BlueZ already knows about.
  'bluetooth.adapters',
  'bluetooth.devices',

  // Desktop shell integration, beyond the window itself.
  'menus.setApplicationMenu',
  'shortcuts.register',
  'shortcuts.unregister',
  'printing.toFile',
  'printing.print',
  'dialogs.openFile',
  'dialogs.saveFile',
  'dialogs.chooseDirectory',
  'dialogs.message',

  // Drag and drop: the window takes drops of the kinds it says it takes,
  // and each one arrives as what was dropped and where.
  'dragDrop.accept',
  'dragDrop.stop',

  // File associations: what this application opens, registered with the
  // desktop for the user running it rather than by an installer.
  'associations.register',
  'associations.unregister',
  'associations.handlerFor',

  // Kiosk enforcement: hold the policy on the device, and let go.
  'kiosk.enforce',
  'kiosk.release',

  // Desktop windowing. Registered by the dartvel_windowing package rather than
  // by a platform binding file here: depending on that package is what opts an
  // application into real OS windows, and what flips
  // DVWindowingCapability.multiWindow true.
  'window.close',
  'window.displays',
  'window.maximize',
  'window.minimize',
  'window.open',
  'window.restore',
  'window.setSize',
  'window.setTitle',
};
