import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel images: resized variants for fast web pages',
  description: 'A phone downloads the 640-pixel image and a large screen gets '
      'the 1920, from one asset you declared. The build writes the '
      'sizes for you.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsMediaPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsmedia,
      lead: <String>[
        'A phone downloads the 640-pixel image and a large screen gets the '
            '1920, from one asset you declared.',
        'The build writes the sizes, and DVBox.image asks for the one its '
            'slot needs.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'variants',
          title: 'Serve each image at the width it needs',
          children: <Widget>[
            DocsYaml('yaml-images'),
            DocsText('Name the file through DVAsset, which `dartvel routes` '
                'generates from what your pubspec bundles. A renamed file '
                'then stops the build. With a path in a string it shows an '
                'empty box on somebody\'s phone.'),
            DocsCode('media-image-view'),
            DocsText('The same asset behind a box, as a background:'),
            DocsCode('media-background'),
            Bullets(<String>[
              '`dartvel build web` writes each declared raster asset at every '
                  'configured width narrower than the image.',
              'DVBox.image asks for its laid-out width times the device '
                  'pixel ratio, rounded up to a configured width.',
              'Leave out widths and you get 16, then the default image and '
                  'device sizes of Next.js 16, from 32 to 3840.',
            ]),
          ],
        ),
        DocsSection(
          id: 'server',
          title: 'Resize on request with web-server',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel build web-server',
            ]),
            Bullets(<String>[
              'The server answers /_dartvel/image, resizes on first request and '
                  'caches the result.',
              'A PNG or WebP source is sent as WebP to a browser that accepts '
                  'it.',
              'It refuses widths outside your list and hosts missing from '
                  'remoteHosts.',
            ]),
          ],
        ),
        DocsSection(
          id: 'prefetch',
          title: 'Paint the image on the first frame',
          children: <Widget>[
            DocsText('A link that prefetches its page also fetches the variant '
                'for the visitor\'s pixel ratio, into the cache the widget reads. '
                'The image is downloaded once and is there when the page opens.'),
            DocsNote('GIFs are sent as they are',
                'Resizing an animated GIF would keep only its first frame, so '
                'GIFs are never resized.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Media Pipeline', missing: <String>[
              'Nothing for uploads: no resizing, validation or size limits for '
                  'files users send.',
              'No AVIF, and WebP only from a web-server build.',
              'Variants are written for web builds only. Apps on devices ship '
                  'their original assets.',
              'No video processing.',
            ]),
          ],
        ),
      ],
    );
