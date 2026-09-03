/// What a desktop grants without asking.
///
/// Anything a process may do on its own -- notify, read and write files,
/// use the camera and microphone the OS already lets it use, the clipboard
/// -- is granted. What needs a system service Dartvel has no desktop
/// binding for -- location, bluetooth, contacts, NFC, biometrics -- is
/// answered false rather than with a prompt that never comes. The same
/// answer on Linux, Windows and macOS, because it is a fact about a desktop
/// process rather than about the desktop.
library;

class DVDesktopPermissions {
  const DVDesktopPermissions._();

  static const Set<String> granted_ = <String>{
    'notifications',
    'storage',
    'photos',
    'files',
    'camera',
    'microphone',
    'clipboard',
  };

  static bool granted(String permission) => granted_.contains(permission.toLowerCase());

  /// The `permissions.isGranted` and `permissions.request` answer.
  static bool answer(Object? arguments) {
    final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
    return granted('${map['permission'] ?? ''}');
  }
}
