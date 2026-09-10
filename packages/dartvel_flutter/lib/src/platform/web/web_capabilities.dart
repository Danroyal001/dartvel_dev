/// What the browser bindings cover, and why the rest is missing.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies would drift, and a drifted capability list is
/// invisible: the set says a binding exists and calling it still throws.
///
/// There are two lists rather than one, and the second is the important one.
/// `DVNativeBridge.invoke` answers null for a name nothing registered, so an
/// application cannot tell "the browser has no such API" from "Dartvel never
/// wrote this one". Every declared name is therefore in exactly one of
/// [dvWebImplementedBindings] and [dvWebUnavailableBindings], and a test
/// fails until a newly declared name joins one of them. A missing web binding
/// now has to be a written sentence rather than a silence.
library dartvel_flutter.platform.web.capabilities;

/// What a browser can genuinely do, given a browser that has the API.
///
/// Membership here is a fact about the web platform, not about the tab this
/// is running in. Web NFC, Web Bluetooth and the Contact Picker are Chromium
/// only; the Generic Sensor API needs hardware; Geolocation and the camera
/// are permission-gated. Registration is decided at runtime by probing for
/// the API, and a browser that lacks it leaves the name **unregistered** so
/// `DVNativeBridge.isRegistered` keeps telling the truth. Read
/// [dvWebUnconditionalBindings] for the ones that need no probe.
const Set<String> dvWebImplementedBindings = <String>{
  // Fullscreen, Keyboard Lock and Pointer Lock, each needing a user gesture
  // and reported refused, with the browser's reason, when it is absent.
  'kiosk.enforce',
  'kiosk.release',

  // The Fullscreen API on its own, which is what a page that only wants the
  // whole screen is asking for. Registered so isRegistered stops saying the
  // browser cannot go fullscreen while the kiosk path does exactly that.
  'display.enterFullscreen',
  'display.exitFullscreen',

  // navigator.clipboard, which needs a secure context and a user gesture for
  // reads — the failure is reported rather than swallowed.
  'clipboard.copy',
  'clipboard.paste',

  // window.screen.
  'screen.geometry',

  // The Notification API, subject to permission.
  'notifications.sendLocal',

  // navigator.share, which Firefox on the desktop does not have. Probed, so
  // that browser leaves the name unregistered rather than throwing a
  // TypeError from inside the binding.
  'share.text',

  // navigator.vibrate. One primitive serves all three: the web has no notion
  // of impact weight, so the distinction is expressed as duration. Safari
  // has no vibrate at all, on any device.
  'haptics.vibrate',
  'haptics.lightVibrate',
  'haptics.impact',

  // document.title.
  'window.setTitle',

  // The browser's own install dialog, and the answer the person gave it.
  'install.prompt',

  // The URL the tab was opened with. A deep link on the web is the address
  // bar, which is the one target where this needs no plumbing at all.
  'deepLinks.initial',

  // Three availability questions the browser can answer, through
  // PublicKeyCredential, navigator.bluetooth and NDEFReader. Each answers
  // false when the browser lacks the API, which is a true statement about
  // the platform rather than a plausible default.
  'biometrics.canAuthenticate',
  'bluetooth.isEnabled',
  'nfc.isAvailable',

  // WebAuthn with userVerification required, which is the browser's platform
  // biometric flow. It throws when there is no authenticator or the person
  // declines; it never reports success it did not get.
  'biometrics.authenticate',

  // The Geolocation API. Denial is a DVWebPermissionDenied rather than a
  // pair of zeroes, because 0,0 is in the Gulf of Guinea and looks like an
  // answer.
  'location.current',

  // The Permissions API for reading a state, and each capability's own
  // request path for asking. There is no navigator.permissions.request();
  // the browser makes you ask through the API you want.
  'permissions.isGranted',
  'permissions.request',

  // <input type="file">, which every browser has had for twenty years. The
  // picked files come back as bytes rather than as paths — see the note on
  // dialogs.openFile below for why a fabricated path would be worse.
  'media.pick',

  // The origin-private file system, through navigator.storage.getDirectory.
  // A real filesystem with real paths, private to the origin, and present in
  // Chrome, Firefox and Safari.
  'files.readBytes',
  'files.writeBytes',
  'files.delete',

  // getUserMedia, one frame, encoded by a canvas. ImageCapture would give a
  // better frame and is Chromium-only, so it is used when it is there.
  'camera.takePhoto',

  // The Generic Sensor API. Chromium only, and only where the hardware is.
  'sensors.accelerometer',
  'sensors.gyroscope',

  // The Contact Picker API: Chrome on Android, and nowhere else at all.
  'contacts.getContacts',

  // Web NFC, which is also Chrome on Android alone.
  'nfc.readTag',
  'nfc.writeTag',

  // Web Bluetooth. What it has is a chooser and the devices already granted
  // through one; what it has no concept of is an adapter or a pairing, so
  // those two names are in the unavailable list with their reasons.
  'bluetooth.scanDevices',
  'bluetooth.devices',
  'bluetooth.connect',
  'bluetooth.disconnect',
  'bluetooth.forget',

  // What the browser will say about the machine: cores, memory, storage,
  // the battery and the network. Less than sysfs gives, and honest about
  // which parts this browser withheld.
  'device.capabilityManifest',
  'device.health',
  'device.diagnostics.collect',

  // window.alert, which is the browser's message dialog whether or not
  // anybody likes it.
  'dialogs.message',
};

/// The bindings registered with no feature probe at all.
///
/// Everything else in [dvWebImplementedBindings] is registered only where the
/// API is present, so a browser suite that demanded it would be asserting
/// which browser the runner installed. These are the ones any engine running
/// Flutter web has, and a browser test may insist on them.
const Set<String> dvWebUnconditionalBindings = <String>{
  'screen.geometry',
  'window.setTitle',
  'install.prompt',
  'kiosk.enforce',
  'kiosk.release',
  'deepLinks.initial',
  'media.pick',
  'dialogs.message',
  'device.capabilityManifest',
  'device.health',
  'device.diagnostics.collect',
  // Availability questions. False is the right answer where the API is
  // missing, so these answer rather than disappear.
  'biometrics.canAuthenticate',
  'bluetooth.isEnabled',
  'nfc.isAvailable',
};

/// Every declared binding the web cannot serve, and the obstacle.
///
/// Not a to-do list. Each of these is a thing a browser is not allowed to do
/// or has no API for, and the sentence is what stops the name being tried
/// again in six months. Where a browser API exists but answers a different
/// question than the binding asks — Web Serial listing only the ports a
/// person already granted, when the binding means "what is attached" — the
/// name stays out, because a shorter list that is true is worth more than a
/// longer one that is not.
const Map<String, String> dvWebUnavailableBindings = <String, String>{
  'tray.show': 'A page has no system tray. The tray belongs to the desktop '
      'shell, and nothing in a tab reaches it.',
  'tray.hide': 'The other half of a tray icon a browser cannot create in the '
      'first place.',

  'homeWidgets.publish': 'A home-screen widget is drawn by a launcher or by '
      'the system shell, in its own process. A browser has no way to hand '
      'anything to either, and the PWA manifest has no widget surface that '
      'ships in a stable browser.',

  'window.open': 'Registered by the dartvel_windowing package, not by a '
      'platform binding. window.open() in a tab is a popup the browser will '
      'usually block, and it is not a second application window.',
  'window.close': 'window.close() is ignored unless the script opened the '
      'window itself, so a binding would work in a popup and silently do '
      'nothing everywhere else.',
  'window.maximize': 'A tab cannot resize the browser around it. Only the '
      'person at the keyboard can maximise a window.',
  'window.minimize': 'Same wall as maximize: the window belongs to the '
      'browser and a page is not allowed to move it.',
  'window.restore': 'The undo of a maximise a page was never able to do.',
  'window.setSize': 'window.resizeTo() is refused for any window the script '
      'did not open, which is every tab a person navigated to.',
  'window.displays': 'The Window Management API can enumerate screens, but '
      'it is Chromium-only, permission-gated, and the multi-window surface '
      'this feeds belongs to the dartvel_windowing package rather than here.',

  'display.enableKiosk': 'A browser cannot lock itself down; only the machine '
      'that launched it can. What a page can hold is fullscreen, Keyboard '
      'Lock and Pointer Lock, which is what kiosk.enforce does — and '
      'DV.Platform.display falls back to it, so enableKiosk() still works.',
  'display.disableKiosk': 'Released through kiosk.release, for the same '
      'reason enableKiosk is: what is held is fullscreen and two locks, not '
      'a kiosk mode the page was ever given.',

  'updates.check': 'The service worker is the browser update mechanism, and '
      'it reports that a new bundle is waiting without saying what version '
      'it is. Answering DVUpdateInfo from that would be inventing the '
      'version, the channel and the notes.',
  'updates.apply': 'A waiting service worker is activated by the PWA layer, '
      'which owns skipWaiting and the reload. Routing it through a native '
      'binding would give two owners for one sequence.',
  'updates.rollback': 'There is no previous bundle to go back to: the '
      'browser keeps one active service worker and one waiting, and the old '
      'one is gone the moment the new one activates.',

  'device.fleet.provision': 'Provisioning has to survive, and every store a '
      'page can write to is the person clearing site data. A fleet identity '
      'that a browser setting erases is worse than none.',
  'device.watchdog.arm': 'A watchdog has to outlive the thing it watches. A '
      'Dart timer runs on the event loop that a wedged application has '
      'already stopped turning, so it would fire only when it was not '
      'needed.',
  'device.watchdog.heartbeat': 'The feed for a watchdog a page cannot arm.',

  'device.serial.ports': 'Web Serial lists only the ports somebody has '
      'already granted through the browser chooser. The binding asks what is '
      'attached, and answering with an empty list on a machine with four '
      'ports is the wrong answer rather than a small one.',
  'device.serial.open': 'Opening needs a port from the chooser, which needs '
      'a user gesture; the binding takes a device path, and a browser is '
      'never told one.',
  'device.serial.write': 'Rides on an open port this platform has no path '
      'to open.',
  'device.serial.read': 'Rides on an open port this platform has no path to '
      'open.',
  'device.serial.close': 'Closes a handle nothing here can hand out.',

  'device.usb.devices': 'WebUSB returns the devices a person already granted '
      'through the chooser, not the bus. "Nothing is plugged in" and "you '
      'have not been given anything" are different answers, and only one of '
      'them is true.',
  'device.usb.open': 'The binding identifies a device by bus and address. '
      'WebUSB deliberately never reveals either, so the two arguments could '
      'only be made up.',
  'device.usb.claim': 'Needs the handle from an open this platform cannot '
      'perform.',
  'device.usb.write': 'Needs the handle from an open this platform cannot '
      'perform.',
  'device.usb.read': 'Needs the handle from an open this platform cannot '
      'perform.',
  'device.usb.close': 'Closes a handle nothing here can hand out.',

  'bluetooth.adapters': 'Web Bluetooth has no adapter object. '
      'getAvailability() answers whether a radio exists and nothing further, '
      'so a list here could only hold one invented entry.',
  'bluetooth.pair': 'Pairing happens inside the browser chooser, where the '
      'person picks the device. A page never drives it and is never told '
      'whether it happened.',

  'menus.setApplicationMenu': 'The menu bar is the browser own. A page can '
      'draw a menu, and that is a widget rather than a native binding.',
  'shortcuts.register': 'A global shortcut fires while the application is in '
      'the background, which for a page means a tab nobody is looking at. '
      'The browser gives keys to the focused document only.',
  'shortcuts.unregister': 'Releases a grab no page was able to take.',

  'printing.toFile': 'The browser can print to a PDF, and the file goes '
      'where the person chooses without the page ever seeing the bytes. '
      'There is nothing to return and no path to return.',
  'printing.print': 'window.print() prints the document, not the page images '
      'this binding is handed, and afterprint fires the same way whether the '
      'job was sent or cancelled. Every answer it could give would be a '
      'guess.',

  'dialogs.openFile': 'The picker hands back an opaque handle, never a path. '
      'A path-shaped answer that files.readBytes then could not open is '
      'exactly the plausible lie this layer refuses; media.pick returns the '
      'bytes instead.',
  'dialogs.saveFile': 'Same absent path. Saving is showSaveFilePicker or a '
      'download, and neither tells the page where the file went.',
  'dialogs.chooseDirectory': 'A directory handle is not a directory path, '
      'and the handle is meaningless to every other binding that takes one.',

  'dragDrop.accept': 'A drop on a page carries File objects with names and '
      'no paths, and DVDropEvent is a list of paths. Text drops would work '
      'and file drops would arrive empty, which reads as a broken window '
      'rather than as an unsupported one.',
  'dragDrop.stop': 'Stops an acceptance this platform never starts.',

  'associations.register': 'A PWA declares its file handlers in the manifest '
      'at install time. There is no runtime call, so this could only edit a '
      'file the browser already read.',
  'associations.unregister': 'The other half of a manifest entry that is '
      'fixed when the app is installed.',
  'associations.handlerFor': 'A page is not told what else on the machine '
      'opens a file type. That would be a fingerprinting surface, and no '
      'browser exposes it.',
};

/// The browser had the API and the answer was no.
///
/// The distinction this whole file is built around. A capability the browser
/// does not have leaves its binding **unregistered**, so `DVNativeBridge`
/// throws its own "not registered" message and `isRegistered` reports false.
/// A capability the browser has and refuses — the person clicked Deny, the
/// call came from no user gesture, the page is not on a secure origin —
/// throws this instead, carrying what the browser said.
///
/// An application that treats the two the same offers to turn on a feature
/// that can never work, or hides one that a second tap would enable.
class DVWebPermissionDenied implements Exception {
  const DVWebPermissionDenied(this.binding, this.reason);

  /// The binding name that was refused, so a log line is greppable.
  final String binding;

  /// What the browser said, as near to verbatim as it gave it.
  final String reason;

  @override
  String toString() =>
      'DVWebPermissionDenied: the browser refused $binding — $reason';
}
