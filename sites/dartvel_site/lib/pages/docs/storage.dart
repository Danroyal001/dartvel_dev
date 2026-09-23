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
            DocsCode('storage-s3'),
            DocsTable(columns: <String>[
              'Adapter',
              'Stores files in',
            ], rows: <List<String>>[
              <String>['DVMemoryFileStorageAdapter', 'Memory, the default'],
              <String>['S3FileStorageAdapter', 'Amazon S3, or any S3 API with '
                  'endpoint:'],
              <String>['GcsFileStorageAdapter', 'Google Cloud Storage'],
              <String>['AzureBlobFileStorageAdapter', 'Azure Blob Storage'],
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
              'No adapter for the local disk.',
              'No putStream or getStream, so a file is read and written whole.',
            ]),
          ],
        ),
      ],
    );
