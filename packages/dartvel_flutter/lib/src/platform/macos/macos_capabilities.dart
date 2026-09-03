/// The names the macOS bindings cover.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies drift, and a drifted capability list is invisible:
/// the set says a binding exists and calling it still throws.
library dartvel_flutter.platform.macos.capabilities;

/// What macOS is bound for, and nothing more.
///
/// Notifications are absent deliberately. `UNUserNotificationCenter` requires a
/// bundled, signed application with the right entitlement, and the old
/// `NSUserNotification` is removed. A binding that worked in a signed bundle
/// and silently did nothing elsewhere would be worse than the "not registered"
/// error, because it would look like it worked in development.
///
/// Window maximise and minimise are absent for a smaller reason: they need
/// `NSApp.keyWindow`, and reading it through the Objective-C runtime from
/// Dart's isolate is not reliably on the main thread. Getting that wrong
/// crashes rather than misbehaves, so it is left out until it can be done
/// through the engine's platform thread.
const Set<String> dvMacosImplementedBindings = <String>{
  // NSPasteboard through the Objective-C runtime.
  'clipboard.copy',
  'clipboard.paste',

  // CoreGraphics, which is plain C and needs no Objective-C messaging.
  'screen.geometry',

  // NSApplication's presentation options: the Dock and menu bar hidden,
  // process switching, force quit, session termination and hiding disabled.
  // The one AppKit state the bindings touch, and only from the platform
  // thread, which is where Flutter runs the root isolate on macOS.
  'kiosk.enforce',
  'kiosk.release',

  // Carbon RegisterEventHotKey, the one system-wide hot key API, delivered
  // by id from the main run loop; a refusal carries the OSStatus.
  'shortcuts.register',
  'shortcuts.unregister',

  // The shared device runtime -- manifest, health, watchdog, provisioning,
  // diagnostics -- reading through this platform's probes.
  'device.capabilityManifest',
  'device.health',
  'device.watchdog.arm',
  'device.watchdog.heartbeat',
  'device.fleet.provision',
  'device.diagnostics.collect',

  // NSMenu as the application's main menu, every item's target one object
  // defined at runtime, activated by id.
  'menus.setApplicationMenu',

  // NSStatusBar's status item: the icon or a title, the tooltip, an NSMenu
  // whose chosen item is dispatched by id.
  'tray.show',
  'tray.hide',

  // CoreGraphics: pictures onto the pages of a PDF. The dialog and the
  // printer are NSPrintOperation's, which needs the application's event
  // loop, so printing.print is not claimed.
  'printing.toFile',
};
