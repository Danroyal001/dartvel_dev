import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel file storage: device disk, S3, Google Cloud Storage and Azure',
  description: 'Store files with one API on the device\'s own disk, a '
      'server\'s disk, S3, Google Cloud Storage or Azure Blob Storage. Swap '
      'the adapter and your code stays the same.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsStoragePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsstorage,
      lead: <String>[
        'Store files with one API on the device\'s own disk, a server\'s '
            'disk, S3, Google Cloud Storage or Azure Blob Storage.',
        'Swap the adapter and your code stays the same.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'configure',
          title: 'Configure a storage adapter',
          children: <Widget>[
            DocsText('The same calls wherever the files are. On a server '
                'that can be the server\'s own disk; on a device it is the '
                'directory the application owns, which is what a file manager '
                'writes into. A bucket is one more adapter behind them.'),
            DocsCode('storage-local'),
            DocsCode('storage-s3'),
            DocsTable(columns: <String>[
              'Adapter',
              'Stores files in',
            ], rows: <List<String>>[
              <String>['DVLocalFileStorageAdapter', 'The filesystem: a server\'s '
                  'disk, or the directory an app owns on a device'],
              <String>['DVMemoryFileStorageAdapter', 'Memory, the default'],
              <String>['S3FileStorageAdapter', 'Amazon S3, or any S3 API with '
                  'endpoint:'],
              <String>['GcsFileStorageAdapter', 'Google Cloud Storage'],
              <String>['AzureBlobFileStorageAdapter', 'Azure Blob Storage'],
            ]),
            Bullets(<String>[
              'A key is a path inside the root, and often comes from a '
                  'request. One that climbs out of the root is refused, so a '
                  '../ in a key cannot read or overwrite anything else the '
                  'process can reach.',
              'A browser has no such filesystem, so DVLocalFileStorageAdapter '
                  'there answers every call with a 501. On a device in a '
                  'browser, use DV.Platform.fileStorage below, which is the '
                  'origin private file system.',
            ]),
          ],
        ),
        DocsSection(
          id: 'use',
          title: 'Put, get, list and delete files',
          children: <Widget>[
            DocsCode('storage-use'),
            Bullets(<String>[
              'Keys are paths you choose, such as avatars/ada.png.',
              'There is no public URL or signed URL method. Serve files through '
                  'a backend function.',
            ]),
            DocsNote('Use DV.FileStorage',
                'DV.Storage is the old name. It still works and is '
                'deprecated, so new code should not use it.'),
          ],
        ),
        DocsSection(
          id: 'device',
          title: 'Files on the device: DV.Platform.fileStorage',
          children: <Widget>[
            DocsText('DV.Platform.fileStorage is DV.FileStorage on the '
                'device\'s own disk: the same calls, bound to the local adapter '
                'whatever DV.FileStorage is configured with. Keys go in the '
                'directory each platform gives an app for its own files, which '
                'needs no permission anywhere.'),
            DocsCode('storage-device'),
            DocsTable(columns: <String>[
              'Target',
              'App files',
              'Files the person picks',
            ], rows: <List<String>>[
              <String>['Android', 'dartvel-files in the app\'s files directory; '
                  'cache in its cache directory', 'The system picker, a private '
                  'copy by path. No folders yet.'],
              <String>['iOS', 'Documents in the app container (in the Files '
                  'app with shareAppFiles)', 'Not bound yet'],
              <String>['macOS', '~/Library/Application Support/<app>',
                  'Open panel and folder panel'],
              <String>['Windows', '%LOCALAPPDATA%\\<app>\\Files',
                  'Open dialog and folder dialog'],
              <String>['Linux and embedded Linux',
                  '\$XDG_DATA_HOME/<app> (~/.local/share/<app>)',
                  'GTK file and folder chooser'],
              <String>['Web', 'The origin private file system',
                  'A file input in every browser. Folders: showDirectoryPicker '
                      'in Chromium (read and write); a folder input elsewhere '
                      '(read only)'],
            ]),
            DocsSubheading('Access beyond the app\'s own files'),
            DocsText('Declare it once under dartvel.fileStorage in '
                'pubspec.yaml, or in your DartvelConfig class. The build '
                'writes it the way each platform expects, and '
                'requestAccess asks for it at run time.'),
            DocsCode('yaml-file-storage'),
            DocsTable(columns: <String>[
              'access',
              'Android (written to the manifest)',
              'iOS and macOS',
            ], rows: <List<String>>[
              <String>['photos', 'READ_MEDIA_IMAGES (13+), '
                  'READ_MEDIA_VISUAL_USER_SELECTED (14+), READ_EXTERNAL_STORAGE '
                  '(12 and below)', 'NSPhotoLibraryUsageDescription with your '
                  'reason; macOS: pictures read-only entitlement'],
              <String>['media', 'Photos plus READ_MEDIA_VIDEO and '
                  'READ_MEDIA_AUDIO', 'As photos; macOS also movies and music '
                  'entitlements'],
              <String>['documents', 'Nothing: the picker is the grant',
                  'macOS: user-selected read-write entitlement'],
              <String>['allFiles', 'MANAGE_EXTERNAL_STORAGE (11+): a Settings '
                  'switch, and Google Play allows it only for apps that need it',
                  'iOS has none; macOS sandbox has none (the build says so)'],
            ]),
            Bullets(<String>[
              'shareAppFiles: true adds UIFileSharingEnabled and '
                  'LSSupportsOpeningDocumentsInPlace on iOS.',
              'Windows, Linux and the web need nothing at build time: a '
                  'desktop process reads what its user can, and a browser '
                  'asks when the person picks.',
              'Keys you already set in Info.plist or the entitlements are '
                  'yours: the build keeps them and does not write a second copy.',
              'requestAccess throws DVFileAccessDenied when the person refuses, '
                  'and a StateError naming the pubspec key when the access was '
                  'never declared.',
            ]),
            DocsNote('DV.Platform.files is deprecated',
                'Use DV.Platform.fileStorage: put, get and delete in the same '
                'directory on Android and the web, and every other target too.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('File Storage', missing: <String>[
              'No putStream or getStream, so a file is read and written whole.',
            ]),
          ],
        ),
      ],
    );
