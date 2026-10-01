import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Privacy policy',
  description: 'What dartvel.dev and the Dartvel software collect, why, and '
      'what you can ask SigmaDev Digital to do with it.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.3,
    changeFrequency: DVSitemapChangeFrequency.yearly,
  ),
)
@pragma('vm:entry-point')
Widget _privacyPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          grain: true,
          children: <Widget>[
            Eyebrow('PRIVACY POLICY'),
            Heading('What dartvel.dev and Dartvel collect, and why.', level: 1),
            Body('Last updated 1 October 2026.'),
            Body('Dartvel and dartvel.dev are made by SigmaDev Digital, a '
                'business registered in Nigeria with the Corporate Affairs '
                'Commission (BN 8969161). For anything in this policy, email '
                'info@sigmadev.digital.'),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('THE SOFTWARE'),
            Heading('The Dartvel framework and CLI send us nothing.'),
            Body('Dartvel runs on your machines and your servers. The CLI has no '
                'telemetry, and apps you build with Dartvel do not report to us. '
                'What your app collects from its own users is up to you, and '
                'your own privacy policy covers it.'),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('THIS WEBSITE'),
            Heading('What dartvel.dev keeps.'),
            Bullets(<String>[
              'Server logs: the address requested, the time, your IP address '
                  'and browser type, kept for a short time to run and secure '
                  'the site.',
              'Site search: the words you search for are used to answer the '
                  'search, and your IP address is used briefly to stop abuse. '
                  'Searches are not tied to you.',
              'Studio sign-in: if you have a Studio account, your email '
                  'address, name, the sign-in sessions on your devices and the '
                  'changes you make in Studio.',
              'Messages you send us by email.',
            ]),
            Body('The site sets cookies only to keep you signed in to Studio and '
                'to protect forms. It has no advertising or third-party '
                'tracking.'),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('SHARING AND KEEPING'),
            Heading('Who sees it, and for how long.'),
            Body('We do not sell your data or share it for advertising. It is '
                'shared only with the services that host the site and send '
                'email, with professional advisers where needed, and with '
                'authorities where the law requires it.'),
            Body('Server logs and abuse records are deleted within weeks. A '
                'Studio account is kept until you ask us to delete it. Emails '
                'are kept while they are relevant.'),
            Body('Dartvel Cloud and Studio Pro are not open yet. When they open, '
                'this policy will say what they collect and how payment works '
                'before you can sign up.'),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('YOUR RIGHTS'),
            Heading('Ask us, and we will act on it.'),
            Body('Under the Nigeria Data Protection Act 2023 and, where it applies '
                'to you, the GDPR, you can ask to see the data we hold about '
                'you, have it corrected or deleted, object to how we use it, or '
                'get a copy to take elsewhere. Email info@sigmadev.digital and '
                'we will respond within 30 days. You can also complain to the '
                'Nigeria Data Protection Commission.'),
            Body('If this policy changes we will update this page and the date '
                'at the top.'),
          ],
        ),
        SiteFooter(),
      ]),
    );
