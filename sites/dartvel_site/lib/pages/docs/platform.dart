import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

/// The old address of the page that was split in two, kept so links to it
/// still arrive somewhere useful.
@DVPage(
  title: 'This page moved',
  description: 'Native device access and API keys and OAuth now have pages '
      'of their own.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsPlatformPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsplatform,
      lead: <String>[
        'This page was split in two, because "Platform" named two different '
            'things.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'moved',
          title: 'Where it went',
          children: <Widget>[
            DVNavLink(
              to: DVRoutes.docsnativeaccess,
              child: DVText('Native device access: DV.Platform, '
                  'permissions and native features'),
            ),
            DVNavLink(
              to: DVRoutes.docsplatformapi,
              child: DVText('API keys and OAuth for your app\'s API'),
            ),
          ],
        ),
      ],
    );
