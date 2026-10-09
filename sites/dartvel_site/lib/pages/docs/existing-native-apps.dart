import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Embed Dartvel in an existing native app: planned',
  description:
      'Native host artifact generation and typed host APIs are '
      'planned. Adopt Dartvel in a Flutter app today with dartvel init.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsExistingNativeAppsPage(BuildContext context) => const DocsArticle(
  page: DVRoutes.docsexistingnativeapps,
  lead: <String>[
    'For an existing Flutter app, run `dartvel init` to adopt Dartvel '
        'without replacing its router.',
    'Generating artifacts that a Kotlin, Swift, desktop or browser host '
        'embeds is planned. The adoption command does not generate '
        'an add-to-app host.',
  ],
  sections: <DocsSection>[
    DocsSection(
      id: 'today',
      title: 'Adopt an existing Flutter application today',
      children: <Widget>[
        DocsShell(<String>['dartvel init', 'dartvel dev']),
        DocsText(
          'init configures a Flutter project and generates the '
          'client barrel. Keep its router or adopt file-based pages. '
          'A Dartvel application can also mount another Dartvel '
          'application with `dartvel add`.',
        ),
        DocsShell(<String>['dartvel add ../checkout']),
      ],
    ),
    DocsSection(
      id: 'planned',
      title: 'Planned native host integration',
      children: <Widget>[
        DocsNote(
          'Planned',
          'Not yet implemented: a build mode that '
              'produces Android AARs, Apple frameworks, desktop host '
              'libraries or browser custom elements with generated host APIs.',
        ),
        Bullets(<String>[
          'Typed mount, unmount and message APIs for native hosts.',
          'Host back navigation, lifecycle and verified session hand-off.',
          'Multiple projects in a host, with version compatibility checks '
              'and isolated or shared engine arrangements.',
          'Vendor embedder integration for TV and embedded hosts.',
        ]),
        DocsText(
          'These design goals are planned. The APIs and commands an '
          'application can use today are described above. The Brownfield section in '
          'NEW_SPEC.md records the draft design.',
        ),
      ],
    ),
  ],
);
