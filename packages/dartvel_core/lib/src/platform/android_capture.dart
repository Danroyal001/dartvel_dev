/// What the Android capture bridge is called, and which Android permission
/// each of Dartvel's permission names stands for.
///
/// In core because both halves need it and they are in different packages:
/// `dartvel build android` writes the Java, and the Flutter runtime finds it
/// by name over JNI. Two spellings of a class name is a lookup that answers
/// nothing for ever, on a device, with no build error anywhere -- which is
/// how every Android binding once shipped dead.
///
/// The permission table is here for a sharper reason. It is read twice: the
/// build writes a `<uses-permission>` line from it, and the generated Java
/// resolves a runtime request from it. A permission requested but never
/// declared is denied by Android immediately, with no dialog and no
/// explanation, so a table that disagreed with the manifest would look
/// exactly like a person tapping Deny.
library dartvel.platform.android_capture;

/// The class the capture bindings call, in JNI's slash-separated form.
const String dvAndroidCaptureBridgeClass = 'dev/dartvel/jni/DartvelActivityBridge';

/// The Activity that receives `onRequestPermissionsResult` and
/// `onActivityResult`.
///
/// A Context is not an Activity, and neither of those callbacks is delivered
/// to anything but an Activity. Dartvel does not own the application's
/// `MainActivity` -- Flutter generates it and a developer may edit it -- so
/// the callbacks arrive at a transparent Activity of Dartvel's own that
/// starts, does the one thing it was asked to, and finishes.
const String dvAndroidBridgeActivityClass = 'dev/dartvel/jni/DartvelBridgeActivity';

/// The provider that hands a camera application somewhere to write a photo.
const String dvAndroidCaptureFilesClass = 'dev/dartvel/jni/DartvelCaptureFiles';

/// What is appended to the application id to make the capture provider's
/// authority.
///
/// Per application, because two applications declaring one authority is a
/// package Android refuses to install, with an error that names the
/// authority and neither application.
const String dvAndroidCaptureAuthoritySuffix = '.dartvelcapture';

/// One Android permission, and the API levels it applies to.
class DVAndroidPermission {
  const DVAndroidPermission(this.name, {this.minSdk, this.maxSdk});

  /// The full Android name, as it appears in a manifest.
  final String name;

  /// The first API level that has it, or null when every level does.
  ///
  /// `POST_NOTIFICATIONS` did not exist before API 33. Declaring it is
  /// harmless there and requesting it is not: Android answers denied for a
  /// permission it has never heard of.
  final int? minSdk;

  /// The last API level that needs it, or null when every level does.
  ///
  /// `READ_EXTERNAL_STORAGE` stops being granted at API 33 and the media
  /// permissions replace it. Left undeclared past its level it is a
  /// permission the Play console asks about and nothing uses.
  final int? maxSdk;
}

/// One of Dartvel's permission names, and what Android calls it.
class DVAndroidPermissionGroup {
  const DVAndroidPermissionGroup(this.permissions, {this.anyOf = false});

  final List<DVAndroidPermission> permissions;

  /// Whether holding one of [permissions] is enough.
  ///
  /// Location is the case that needs it. Android lets a person grant the
  /// approximate location and refuse the precise one, and an application
  /// that treats that as a refusal asks again on every launch for something
  /// it has already been given.
  final bool anyOf;
}

/// Every permission name Dartvel understands, and what it means on Android.
///
/// The names are the platform-independent ones `DV.Permissions` takes, so
/// the same call works on a desktop -- where the answer is a fact about the
/// process rather than a dialog -- and on a phone.
const Map<String, DVAndroidPermissionGroup> dvAndroidPermissions =
    <String, DVAndroidPermissionGroup>{
  'camera': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.CAMERA'),
  ]),
  'microphone': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.RECORD_AUDIO'),
  ]),
  // Precise or approximate. Asking for the precise one without declaring the
  // approximate one takes away the person's choice: Android only offers the
  // two-button dialog when both are declared.
  'location': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.ACCESS_FINE_LOCATION'),
    DVAndroidPermission('android.permission.ACCESS_COARSE_LOCATION'),
  ], anyOf: true),
  'contacts': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.READ_CONTACTS'),
  ]),
  'notifications': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.POST_NOTIFICATIONS', minSdk: 33),
  ]),
  // Reading someone else's files. The application's own directory needs
  // nothing at all, which is why `files` below is an empty group rather than
  // an entry here.
  'storage': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.READ_EXTERNAL_STORAGE', maxSdk: 32),
  ]),
  'photos': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.READ_MEDIA_IMAGES', minSdk: 33),
    DVAndroidPermission('android.permission.READ_EXTERNAL_STORAGE', maxSdk: 32),
  ], anyOf: true),
  'bluetooth': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.BLUETOOTH_CONNECT', minSdk: 31),
    DVAndroidPermission('android.permission.BLUETOOTH_SCAN', minSdk: 31),
    DVAndroidPermission('android.permission.BLUETOOTH', maxSdk: 30),
    DVAndroidPermission('android.permission.BLUETOOTH_ADMIN', maxSdk: 30),
  ]),
  // Granted at install once declared, so a request for it answers straight
  // away rather than showing a dialog.
  'nfc': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.NFC'),
  ]),
  'biometrics': DVAndroidPermissionGroup(<DVAndroidPermission>[
    DVAndroidPermission('android.permission.USE_BIOMETRIC'),
  ]),
  // Nothing to ask for. An empty group is granted, and it is not the same as
  // an unknown name -- which is a typo, and answers with an error rather
  // than a refusal nobody can act on.
  'clipboard': DVAndroidPermissionGroup(<DVAndroidPermission>[]),
  'files': DVAndroidPermissionGroup(<DVAndroidPermission>[]),
};

/// The names [dvAndroidPermissions] knows.
Set<String> get dvAndroidPermissionNames => dvAndroidPermissions.keys.toSet();

/// The Android permissions [name] needs on an API level of [sdk], or null
/// when Dartvel has no such permission name.
///
/// Null rather than an empty list for an unknown name: an empty list means
/// "nothing to ask for, so it is granted", and answering that for a typo
/// would grant `camrea` on every device.
List<String>? dvAndroidPermissionsFor(String name, {int sdk = 34}) {
  final DVAndroidPermissionGroup? group = dvAndroidPermissions[name];
  if (group == null) return null;
  return <String>[
    for (final DVAndroidPermission permission in group.permissions)
      if ((permission.minSdk == null || sdk >= permission.minSdk!) &&
          (permission.maxSdk == null || sdk <= permission.maxSdk!))
        permission.name,
  ];
}
