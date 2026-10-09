/// The names the iOS bindings cover.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies drift, and a drifted capability list is invisible:
/// the set says a binding exists and calling it still throws.
library dartvel_flutter.platform.ios.capabilities;

/// What iOS is bound for, and nothing more.
///
/// Three routes, by what each binding needs:
///
///   * **Straight to the Objective-C runtime and C**, from Dart: the
///     clipboard, haptics (AudioToolbox), the launch link, the home widget
///     container and App Tracking Transparency. These work in any build,
///     plain `flutter build` included.
///   * **Plain Dart**: the file bindings and the device runtime, confined to
///     Application Support, like every other target with a filesystem.
///   * **The Swift shim `dartvel build ios` writes** ([dvIosShimBindings]):
///     everything that presents a view controller, answers through a
///     delegate or a completion block, or returns a struct -- which is why
///     `screen.geometry` could not be reached from Dart and can be now.
///
/// Absent, with reasons rather than "not yet":
///
///   * **`bluetooth.pair`, `connect`, `disconnect`, `forget`**: CoreBluetooth
///     has no pairing call. iOS pairs on the first encrypted read, inside its
///     own dialog, and forgetting a device is Settings' alone.
///   * **`nfc.readTag` and `nfc.writeTag`** need the NFC tag-reading
///     entitlement and a reader session the person starts; neither is wired.
///   * **Window controls** do not exist: an iOS app owns no resizable window.
///   * **`display.enterFullscreen`/`exitFullscreen`**: an iOS app is already
///     full screen; the status bar is the app's own Info.plist decision.
const Set<String> dvIosImplementedBindings = <String>{
  // UIPasteboard through the Objective-C runtime.
  'clipboard.copy',
  'clipboard.paste',
  // AudioToolbox, not UIKit. See dvIosHapticSoundId.
  'haptics.impact',
  'haptics.lightVibrate',
  'haptics.vibrate',
  // The link this launch carried, out of the standard defaults, where the
  // capture dartvel build writes into AppDelegate.swift leaves it.
  'deepLinks.initial',
  // What a home-screen widget shows, into the App Group container.
  'homeWidgets.publish',
  // App Tracking Transparency, answering -1 where the prompt cannot be shown.
  'tracking.requestAuthorization',

  // Plain Dart, under Application Support. See dvIosFilesRoot.
  'files.readBytes',
  'files.writeBytes',
  'files.delete',
  'device.capabilityManifest',
  'device.health',
  'device.watchdog.arm',
  'device.watchdog.heartbeat',
  'device.fleet.provision',
  'device.diagnostics.collect',

  ...dvIosShimBindings,
};

/// The bindings the Swift shim backs. Registered only when the application
/// was built with `dartvel build ios`, which is what compiles the shim in;
/// `DVIosBindings.lastFailure` says so when it was not.
const Set<String> dvIosShimBindings = <String>{
  // UIActivityViewController.
  'share.text',
  // UIScreen.nativeBounds and nativeScale.
  'screen.geometry',
  // AVCaptureDevice, CLLocationManager, CNContactStore, PHPhotoLibrary,
  // UNUserNotificationCenter, CBManager, LAContext -- each checked for its
  // Info.plist key first, since iOS terminates an app that asks without it.
  'permissions.isGranted',
  'permissions.request',
  // UIImagePickerController with the camera, written to tmp as JPEG.
  'camera.takePhoto',
  // PHPickerViewController for images and video, UIDocumentPickerViewController
  // for everything else. Neither needs a permission: picking is the grant.
  'media.pick',
  // CNContactStore.
  'contacts.getContacts',
  // CLLocationManager.requestLocation.
  'location.current',
  // NFCNDEFReaderSession.readingAvailable, with CoreNFC loaded at run time so
  // an iPad without it still launches.
  'nfc.isAvailable',
  // CBCentralManager.
  'bluetooth.isEnabled',
  'bluetooth.adapters',
  'bluetooth.devices',
  'bluetooth.scanDevices',
  // CMMotionManager, one sample. Acceleration converted from g to m/s².
  'sensors.accelerometer',
  'sensors.gyroscope',
  // LocalAuthentication. The prompt too, which Android does not have yet.
  'biometrics.canAuthenticate',
  'biometrics.authenticate',
  // UNUserNotificationCenter, shown in the foreground as well.
  'notifications.sendLocal',
  // Guided Access, which iOS grants only on a supervised device.
  'kiosk.enforce',
  'kiosk.release',
};

/// Where the device runtime keeps its id and provisioning record, given the
/// application's home directory. Null when there is none.
///
/// `$HOME` on iOS is the application's own container. Application Support is
/// backed up and not shown in the Files app, which is right for both of
/// these; Documents would put the device id in front of the person.
String? dvIosStateDirectory(String? home) => _dvIosUnder(home, 'dartvel-device');

/// The one directory `files.*` may touch: a sibling of the state directory,
/// never its parent, so deleting a file cannot unprovision the device.
String? dvIosFilesRoot(String? home) => _dvIosUnder(home, 'dartvel-files');

String? _dvIosUnder(String? home, String name) {
  if (home == null) return null;
  String base = home;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.isEmpty) return null;
  return '$base/Library/Application Support/$name';
}

/// The system sound identifier that produces a given haptic.
///
/// `UIImpactFeedbackGenerator` is the documented API and is unusable here: it
/// must be constructed and called on the main thread, and Flutter's root
/// isolate runs on the UI thread. `AudioServicesPlaySystemSound` is a plain C
/// function in AudioToolbox, safe to call from any thread, and the identifiers
/// in the 1519-1521 range are the Taptic Engine taps rather than sounds.
///
/// Throws for a name this does not cover. A fallback would be worse than an
/// error: identifiers below 1000 are alert sounds, so a mistyped name would
/// play a noise out loud on a device meant to tap silently.
int dvIosHapticSoundId(String name) => switch (name) {
      // Peek: the lightest tap the Taptic Engine produces.
      'haptics.lightVibrate' => 1519,
      // Pop: firmer, the one that reads as an impact.
      'haptics.impact' => 1520,
      // kSystemSoundID_Vibrate. The taps above are silent on a device with a
      // Taptic Engine and do nothing at all on one without, so a full vibrate
      // has to be the real motor.
      'haptics.vibrate' => 4095,
      _ => throw ArgumentError.value(
          name, 'name', 'Not an iOS haptic binding'),
    };
