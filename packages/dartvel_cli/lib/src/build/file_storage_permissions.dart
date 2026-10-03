/// `dartvel.fileStorage`, written into each platform's own files at build
/// time: the manifest permissions Android reads, the Info.plist keys iOS and
/// macOS read, and the sandbox entitlements macOS reads.
///
/// Nothing here asks a developer to edit `android/`, `ios/` or `macos/`. What
/// goes into a file Dartvel does not own is a marked block that a later build
/// replaces, and a key the developer already wrote outside the block is
/// theirs: the build leaves it alone and says so rather than writing a second
/// copy of it.
library dartvel_cli.build.file_storage_permissions;

import 'package:dartvel_core/dartvel.dart' show DVDeviceFileAccess, DVFileStorageConfig;

/// The Dartvel permission names `dartvel.fileStorage` adds to
/// `dartvel.android.permissions`, so the manifest declares them.
List<String> dvFileStorageAndroidPermissionNames(DVFileStorageConfig config) =>
    config.permissionNames;

/// What a build says about `dartvel.fileStorage` on Android.
List<String> dvFileStorageAndroidNotes(DVFileStorageConfig config) => <String>[
      if (config.allows(DVDeviceFileAccess.allFiles))
        'dartvel.fileStorage.access includes allFiles: MANAGE_EXTERNAL_STORAGE is declared. '
            'From Android 11 a person grants it in Settings, not in a dialog, and Google Play '
            'only allows it for apps whose core purpose needs it (file managers, backup).',
    ];

const String _blockStart = '\t<!-- dartvel.fileStorage: begin -->';
const String _blockEnd = '\t<!-- dartvel.fileStorage: end -->';

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// The Info.plist keys [config] needs on [platform] (`ios` or `macos`), in
/// order, each with its plist value.
Map<String, String> dvFileStorageInfoPlistEntries(DVFileStorageConfig config, String platform) {
  final bool library = config.allows(DVDeviceFileAccess.photos) || config.allows(DVDeviceFileAccess.media);
  final String reason = _xml(config.reason ?? '');
  return <String, String>{
    // Full photo-library access. The system photo picker needs no key, but
    // reading the library itself does, and iOS ends the app without it.
    if (library) 'NSPhotoLibraryUsageDescription': '<string>$reason</string>',
    if (library && platform == 'ios') 'NSPhotoLibraryAddUsageDescription': '<string>$reason</string>',
    // The app's own Documents directory in the Files app, opened in place.
    if (config.shareAppFiles && platform == 'ios') 'UIFileSharingEnabled': '<true/>',
    if (config.shareAppFiles && platform == 'ios') 'LSSupportsOpeningDocumentsInPlace': '<true/>',
  };
}

/// The macOS App Sandbox entitlements [config] needs.
Map<String, String> dvFileStorageMacosEntitlements(DVFileStorageConfig config) {
  final bool picked = config.allows(DVDeviceFileAccess.documents) ||
      config.allows(DVDeviceFileAccess.photos) ||
      config.allows(DVDeviceFileAccess.media);
  return <String, String>{
    // Files and folders the person picks in an open or save panel.
    if (picked) 'com.apple.security.files.user-selected.read-write': '<true/>',
    if (config.allows(DVDeviceFileAccess.photos) || config.allows(DVDeviceFileAccess.media))
      'com.apple.security.assets.pictures.read-only': '<true/>',
    if (config.allows(DVDeviceFileAccess.media)) 'com.apple.security.assets.movies.read-only': '<true/>',
    if (config.allows(DVDeviceFileAccess.media)) 'com.apple.security.assets.music.read-only': '<true/>',
  };
}

/// What a build says about `dartvel.fileStorage` on macOS.
List<String> dvFileStorageMacosNotes(DVFileStorageConfig config) => <String>[
      if (config.allows(DVDeviceFileAccess.allFiles))
        'dartvel.fileStorage.access includes allFiles, which the macOS App Sandbox has no entitlement for: '
            'a sandboxed app reaches files the person picks (declared) and its own container. '
            'Full Disk Access is a person granting it in System Settings, not something an app can declare.',
    ];

/// [plist] (an Info.plist or an .entitlements file) with [entries] in a marked
/// block in its top dictionary. A key already present outside the block is
/// the developer's: it is kept, left out of the block, and named in
/// [skipped]. With no entries the block is removed.
String dvWithFileStorageBlock(String plist, Map<String, String> entries, {List<String>? skipped}) {
  final RegExp block = RegExp('\n${RegExp.escape(_blockStart)}.*?${RegExp.escape(_blockEnd)}', dotAll: true);
  final String stripped = plist.replaceAll(block, '');
  final StringBuffer out = StringBuffer()..writeln(_blockStart);
  var wrote = false;
  for (final MapEntry<String, String> entry in entries.entries) {
    if (stripped.contains('<key>${entry.key}</key>')) {
      skipped?.add(entry.key);
      continue;
    }
    out
      ..writeln('\t<key>${entry.key}</key>')
      ..writeln('\t${entry.value}');
    wrote = true;
  }
  if (!wrote) return stripped;
  out.write(_blockEnd);
  final int close = stripped.lastIndexOf('</dict>');
  if (close < 0) return stripped;
  return '${stripped.substring(0, close)}$out\n${stripped.substring(close)}';
}
