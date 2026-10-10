/// The contract between the Swift `dartvel build ios` writes and the Dart
/// runtime that calls it over `dart:ffi`.
///
/// In core because both halves need it and they live in different packages:
/// the CLI writes the Swift, and `dartvel_flutter` looks its symbols up in the
/// running process. Two spellings of one symbol is a lookup that answers
/// nothing on a phone, with no build error anywhere -- the same way every
/// Android binding once shipped dead.
///
/// Why a Swift shim at all, when clipboard and haptics reach the Objective-C
/// runtime straight from Dart: everything else on this list needs something
/// `objc_msgSend` from Dart cannot give safely. The share sheet, the pickers
/// and the camera are view controllers presented on the main thread; the
/// permission prompts, location and LocalAuthentication answer through
/// delegates or completion blocks; `UIScreen.nativeBounds` returns a struct.
/// Swift compiled into the application does each of those in its own terms
/// and hands the answer back through one C function pointer. No platform
/// channel is involved: Dart calls a C symbol and is called back through a
/// `NativeCallable`.
library dartvel.platform.ios_platform_shim;

/// The protocol version the Swift and the Dart must agree on.
///
/// Raised whenever an operation's arguments or answer change shape. The Dart
/// side refuses a shim whose version differs rather than calling into it,
/// because a mismatched shim answers in the old shape and that decodes as a
/// plausible wrong value rather than an error.
const int dvIosShimVersion = 1;

/// `int32_t dartvel_ios_shim_version(void)`.
const String dvIosShimVersionSymbol = 'dartvel_ios_shim_version';

/// `void dartvel_ios_set_completion(void (*)(int64_t id, char *json))`.
///
/// Every answer arrives here, as JSON the Dart side frees with `free`.
const String dvIosShimCompletionSymbol = 'dartvel_ios_set_completion';

/// `void dartvel_ios_call(int64_t id, const char *op, const char *json)`.
const String dvIosShimCallSymbol = 'dartvel_ios_call';

/// `int64_t dartvel_ios_disk_free(const char *path)`: synchronous, for the
/// device runtime's health probe, which is not allowed to wait.
const String dvIosShimDiskFreeSymbol = 'dartvel_ios_disk_free';

/// The request id the shim reports a connectivity change under.
///
/// Negative, so it can never collide with a request the Dart side made: those
/// count up from one.
const int dvIosShimNetworkEventId = -1;

/// The operations the shim answers. The generated Swift has one case per
/// name, and a test asserts it.
const Set<String> dvIosShimOperations = <String>{
  'share.text',
  'screen.geometry',
  'permissions.status',
  'permissions.request',
  'camera.takePhoto',
  'media.pick',
  'contacts.list',
  'location.current',
  'nfc.available',
  'bluetooth.state',
  'bluetooth.scan',
  'bluetooth.known',
  'sensors.sample',
  'biometrics.can',
  'biometrics.authenticate',
  'notifications.send',
  'kiosk.guidedAccess',
  'network.watch',
};

/// One of Dartvel's permission names, as iOS understands it.
class DVIosPermission {
  const DVIosPermission(this.usageKeys, {this.supported = true});

  /// The Info.plist keys iOS requires before the prompt may be shown.
  ///
  /// iOS does not refuse a request for a protected resource whose key is
  /// missing: it terminates the application. So the shim reads each key
  /// before asking, and the build writes them from `dartvel.ios.permissions`.
  final List<String> usageKeys;

  /// False for a name iOS has no grant for at all.
  final bool supported;
}

/// Every permission name Dartvel understands, and what it needs on iOS.
///
/// The same names as `dvAndroidPermissions`, so one call works on both
/// phones; a test asserts the two tables agree.
const Map<String, DVIosPermission> dvIosPermissions = <String, DVIosPermission>{
  'camera': DVIosPermission(<String>['NSCameraUsageDescription']),
  'microphone': DVIosPermission(<String>['NSMicrophoneUsageDescription']),
  'location': DVIosPermission(<String>['NSLocationWhenInUseUsageDescription']),
  'contacts': DVIosPermission(<String>['NSContactsUsageDescription']),
  // UNUserNotificationCenter asks with no key.
  'notifications': DVIosPermission(<String>[]),
  // Another application's files are reached through the document picker,
  // and picking is the grant.
  'storage': DVIosPermission(<String>[]),
  'photos': DVIosPermission(<String>['NSPhotoLibraryUsageDescription']),
  'media': DVIosPermission(<String>['NSPhotoLibraryUsageDescription']),
  // No iOS application can read every file on the device.
  'allFiles': DVIosPermission(<String>[], supported: false),
  'bluetooth': DVIosPermission(<String>['NSBluetoothAlwaysUsageDescription']),
  'nfc': DVIosPermission(<String>['NFCReaderUsageDescription']),
  'biometrics': DVIosPermission(<String>['NSFaceIDUsageDescription']),
  'clipboard': DVIosPermission(<String>[]),
  'files': DVIosPermission(<String>[]),
};

/// The Info.plist keys [name] needs, or null when Dartvel has no such name.
///
/// Null rather than empty for a typo: empty means nothing to ask for, which
/// is granted.
List<String>? dvIosUsageKeysFor(String name) => dvIosPermissions[name]?.usageKeys;
