import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel file storage: S3, Google Cloud Storage and Azure',
  description: 'Store uploads and generated files with one API on S3, Google '
      'Cloud Storage or Azure Blob Storage. Swap the adapter and your '
      'code stays the same.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsStoragePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsstorage,
      lead: <String>[
        'Store uploads and generated files with one API on S3, Google Cloud '
            'Storage or Azure Blob Storage.',
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
              'On the web there is no such filesystem. The adapter still '
                  'exists and says so, so code that names it compiles for '
                  'every target.',
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
                'DV.Storage is the old name and is removed in the next minor '
                'release.'),
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
