import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('dartvel.fileStorage', () {
    test('no section is the default: the app directory and nothing else', () {
      final DVFileStorageConfig config = DVFileStorageConfig.parse(null);
      expect(config.isEmpty, isTrue);
      expect(config.problems, isEmpty);
      expect(config.toDeclaration(), isEmpty);
    });

    test('pubspec -> class -> pubspec gives back every field', () {
      final Map<String, Object?> declared = <String, Object?>{
        'access': <String>['photos', 'media', 'documents', 'allFiles'],
        'reason': 'Attach receipts to orders.',
        'shareAppFiles': true,
      };
      final DVFileStorageConfig config = DVFileStorageConfig.parse(declared);
      expect(config.problems, isEmpty);
      expect(config.toDeclaration(), declared);
    });

    test('class -> pubspec -> class gives back an equal class', () {
      for (final DVFileStorageConfig config in <DVFileStorageConfig>[
        const DVFileStorageConfig(),
        const DVFileStorageConfig(access: <DVDeviceFileAccess>[DVDeviceFileAccess.documents]),
        const DVFileStorageConfig(shareAppFiles: true),
        const DVFileStorageConfig(
          access: DVDeviceFileAccess.values,
          reason: 'Back up your library.',
          shareAppFiles: true,
        ),
      ]) {
        final DVFileStorageConfig again = DVFileStorageConfig.parse(config.toDeclaration());
        expect(again, config);
        expect(again.problems, isEmpty);
      }
    });

    test('every DVDeviceFileAccess has a pubspec name that reads back', () {
      for (final DVDeviceFileAccess kind in DVDeviceFileAccess.values) {
        expect(DVDeviceFileAccess.fromKey(kind.key), kind);
      }
    });

    test('mistakes are named, not dropped', () {
      final DVFileStorageConfig config = DVFileStorageConfig.parse(<String, Object?>{
        'access': <String>['photos', 'videos'],
        'shareAppFiles': 'yes',
        'acess': <String>['media'],
      });
      expect(config.problems.join('\n'), contains('"videos"'));
      expect(config.problems.join('\n'), contains('shareAppFiles must be true or false'));
      expect(config.problems.join('\n'), contains('dartvel.fileStorage.acess is not a setting'));
      expect(config.problems.join('\n'), contains('reason is required'));
    });

    test('documents need no runtime permission name; photos and media do', () {
      final DVFileStorageConfig config = DVFileStorageConfig.parse(<String, Object?>{
        'access': <String>['documents', 'photos', 'media'],
        'reason': 'x',
      });
      expect(config.permissionNames, <String>['photos', 'media']);
      for (final String name in config.permissionNames) {
        expect(dvAndroidPermissions.containsKey(name), isTrue, reason: name);
      }
      expect(dvAndroidPermissions.containsKey('allFiles'), isTrue);
    });
  });

  group('Android storage permissions by API level', () {
    test('media on Android 13+ asks for the three media permissions, not storage', () {
      final List<String> names = <String>[
        for (final DVAndroidPermission permission in dvAndroidPermissions['media']!.permissions)
          if ((permission.minSdk ?? 0) <= 33 && (permission.maxSdk == null || 33 <= permission.maxSdk!))
            permission.name,
      ];
      expect(names, containsAll(<String>[
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VIDEO',
        'android.permission.READ_MEDIA_AUDIO',
      ]));
      expect(names, isNot(contains('android.permission.READ_EXTERNAL_STORAGE')));
    });

    test('all files is special access from API 30', () {
      final DVAndroidPermission manage = dvAndroidPermissions['allFiles']!.permissions
          .firstWhere((DVAndroidPermission permission) => permission.name.endsWith('MANAGE_EXTERNAL_STORAGE'));
      expect(manage.minSdk, 30);
    });
  });
}
