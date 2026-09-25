import 'package:flutter/material.dart';

import '../../components/versus.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel compared with Expo, Laravel, Hasura, Rails, Bubble, '
      'PocketBase and Qt',
  description: 'How Dartvel compares with the tools people already use: Expo '
      'for Flutter, Laravel for Flutter, Hasura for Flutter, Ruby on Rails '
      'for Flutter, Bubble, PocketBase and Qt. Each page says where the '
      'other one wins.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsIndexPage(BuildContext context) => SingleChildScrollView(
      child: DVBox.list(<Widget>[
        const Section(
          grain: true,
          children: <Widget>[
            Eyebrow('COMPARED'),
            Heading(
              'Dartvel next to the tools you already know.',
              level: 1,
            ),
            Body('Nobody adopts a framework in the abstract. These pages put '
                'Dartvel beside the thing you would otherwise reach for, in '
                'the terms that tool uses about itself. Each one ends with '
                'where the other one is still ahead, because a comparison '
                'that never concedes anything is an advertisement. Each one '
                'also says the date its claims were last checked against the '
                "other project's own documentation, and links to it, so you "
                'can see when a page has gone stale.'),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            const Eyebrow('THE PAGES'),
            const Heading('Seven comparisons.'),
            DVBox.wrapLine(<Widget>[
              for (final VersusPage page in kVersusPages)
                SiteCard(page.phrase, page.summary, href: page.path),
            ], spacing: 16),
          ],
        ),
        const Section(
          children: <Widget>[
            Eyebrow('ALSO ASKED'),
            Heading('Can I build a Flutter app without a Mac?'),
            Body('Mostly yes, and the honest answer has a shape: everything '
                'except an iOS or macOS build runs on any computer today, '
                'and the two that do not have a route that is not buying a '
                'Mac.'),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Flutter without a Mac', '/flutter-without-a-mac'),
              GhostLink('What ships today', '/features'),
            ], spacing: 12),
          ],
        ),
        const SiteFooter(),
      ], spacing: 0),
    );
