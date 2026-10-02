import 'package:dartvel_cli/src/build/android_capture_bridge.dart';
import 'package:dartvel_cli/src/build/file_storage_permissions.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String infoPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>shop</string>
</dict>
</plist>
''';

const String entitlements = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>com.apple.security.app-sandbox</key>
\t<true/>
</dict>
</plist>
''';

DVFileStorageConfig config(Map<String, Object?> raw) {
  final DVFileStorageConfig parsed = DVFileStorageConfig.parse(raw);
  expect(parsed.problems, isEmpty);
  return parsed;
}

void main() {
  test('the default needs nothing on any Apple platform', () {
    const DVFileStorageConfig none = DVFileStorageConfig();
    expect(dvFileStorageInfoPlistEntries(none, 'ios'), isEmpty);
    expect(dvFileStorageMacosEntitlements(none), isEmpty);
    expect(dvWithFileStorageBlock(infoPlist, dvFileStorageInfoPlistEntries(none, 'ios')), infoPlist);
  });

  test('photos on iOS writes the usage descriptions inside the top dictionary', () {
    final String out = dvWithFileStorageBlock(infoPlist,
        dvFileStorageInfoPlistEntries(config(<String, Object?>{'access': <String>['photos'], 'reason': 'Receipts & photos.'}), 'ios'));
    expect(out, contains('<key>NSPhotoLibraryUsageDescription</key>\n\t<string>Receipts &amp; photos.</string>'));
    expect(out, contains('NSPhotoLibraryAddUsageDescription'));
    expect(out.indexOf('dartvel.fileStorage: begin'), lessThan(out.lastIndexOf('</dict>')));
    expect(out, contains('<key>CFBundleName</key>'));
  });

  test('shareAppFiles shows the app documents in the Files app', () {
    final Map<String, String> entries =
        dvFileStorageInfoPlistEntries(config(<String, Object?>{'shareAppFiles': true}), 'ios');
    expect(entries.keys, <String>['UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace']);
    expect(dvFileStorageInfoPlistEntries(config(<String, Object?>{'shareAppFiles': true}), 'macos'), isEmpty);
  });

  test('a second build replaces its block instead of adding one', () {
    final Map<String, String> entries =
        dvFileStorageInfoPlistEntries(config(<String, Object?>{'access': <String>['media'], 'reason': 'x'}), 'ios');
    final String once = dvWithFileStorageBlock(infoPlist, entries);
    final String twice = dvWithFileStorageBlock(once, entries);
    expect(twice, once);
    expect(dvWithFileStorageBlock(once, const <String, String>{}), infoPlist);
  });

  test("a key the developer already set is theirs: kept, not duplicated", () {
    final String own = infoPlist.replaceFirst('</dict>',
        '\t<key>NSPhotoLibraryUsageDescription</key>\n\t<string>Our words.</string>\n</dict>');
    final List<String> skipped = <String>[];
    final String out = dvWithFileStorageBlock(own,
        dvFileStorageInfoPlistEntries(config(<String, Object?>{'access': <String>['photos'], 'reason': 'Theirs.'}), 'ios'),
        skipped: skipped);
    expect('<key>NSPhotoLibraryUsageDescription</key>'.allMatches(out), hasLength(1));
    expect(out, contains('Our words.'));
    expect(skipped, contains('NSPhotoLibraryUsageDescription'));
  });

  test('macOS sandbox entitlements follow what is asked for', () {
    expect(dvFileStorageMacosEntitlements(config(<String, Object?>{'access': <String>['documents']})).keys,
        <String>['com.apple.security.files.user-selected.read-write']);
    final Map<String, String> media =
        dvFileStorageMacosEntitlements(config(<String, Object?>{'access': <String>['media'], 'reason': 'x'}));
    expect(media.keys, containsAll(<String>[
      'com.apple.security.files.user-selected.read-write',
      'com.apple.security.assets.pictures.read-only',
      'com.apple.security.assets.movies.read-only',
      'com.apple.security.assets.music.read-only',
    ]));
    final String out = dvWithFileStorageBlock(entitlements, media);
    expect(out, contains('com.apple.security.app-sandbox'));
    expect(out, contains('<key>com.apple.security.assets.movies.read-only</key>\n\t<true/>'));
  });

  test('all files is named for what it costs on Android and macOS', () {
    final DVFileStorageConfig everything = config(<String, Object?>{'access': <String>['allFiles']});
    expect(dvFileStorageAndroidPermissionNames(everything), <String>['allFiles']);
    expect(dvFileStorageAndroidNotes(everything).single, contains('Google Play'));
    expect(dvFileStorageMacosNotes(everything).single, contains('no entitlement'));
  });

  test('Android declares each permission once, over its widest API range', () {
    final List<String> lines = dvAndroidUsesPermissions(<String>['photos', 'media', 'allFiles']);
    final List<String> external = lines.where((String line) => line.contains('READ_EXTERNAL_STORAGE')).toList();
    expect(external, hasLength(1));
    expect(external.single, contains('maxSdkVersion="32"'));
    expect(lines.where((String line) => line.contains('READ_MEDIA_VIDEO')), hasLength(1));
    expect(lines.where((String line) => line.contains('MANAGE_EXTERNAL_STORAGE')).single, isNot(contains('maxSdkVersion')));
    expect(lines.where((String line) => line.contains('WRITE_EXTERNAL_STORAGE')).single, contains('maxSdkVersion="29"'));
  });
}
