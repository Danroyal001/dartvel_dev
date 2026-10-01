import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Terms of use',
  description: 'The terms for using dartvel.dev, Dartvel Studio on it, and '
      'the Dartvel software, from SigmaDev Digital.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.3,
    changeFrequency: DVSitemapChangeFrequency.yearly,
  ),
)
@pragma('vm:entry-point')
Widget _termsPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          grain: true,
          children: <Widget>[
            Eyebrow('TERMS OF USE'),
            Heading('The terms for dartvel.dev and Dartvel.', level: 1),
            Body('Last updated 1 October 2026.'),
            Body('Dartvel and dartvel.dev are made by SigmaDev Digital, a '
                'business registered in Nigeria with the Corporate Affairs '
                'Commission (BN 8969161). Contact us at info@sigmadev.digital. '
                'By using the site you agree to these terms.'),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('THE SOFTWARE'),
            Heading('Its licence decides what you can do with Dartvel.'),
            Body('The Dartvel framework, CLI and packages are published under '
                'the FSL-1.1-MIT licence, which you can read in each package and '
                'in the repository. That licence, not this page, sets what you '
                'may do with the code. Apps you build with Dartvel are yours.'),
            Body('Dartvel is provided as it is, as the licence says. We work to '
                'keep it correct and secure, but you are responsible for testing '
                'what you build with it before you rely on it.'),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('THIS WEBSITE'),
            Heading('Using dartvel.dev.'),
            Bullets(<String>[
              'The documentation and examples are there to help you build with '
                  'Dartvel. Code samples on the site may be used in your own '
                  'projects.',
              'The site\'s name, logo, design and text belong to SigmaDev '
                  'Digital, except where they are credited to someone else.',
              'Do not attack or overload the site, try to get into accounts '
                  'that are not yours, scrape it in bulk, or use it to send spam. '
                  'We may block access that does.',
              'Studio access on dartvel.dev is given by invitation. Keep your '
                  'sign-in details private; you are responsible for what is done '
                  'with your account.',
            ]),
            Body('Dartvel Cloud and Studio Pro are not open yet. Their planned '
                'pricing is on the Cloud page and may be reviewed before launch; '
                'payment and refund terms will be published here before anyone '
                'can buy them.'),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('LIABILITY AND LAW'),
            Heading('The usual limits, stated plainly.'),
            Body('We work to keep the site available and accurate, but we cannot '
                'promise it will always be online or free of errors. To the '
                'extent the law allows, we are not liable for indirect losses '
                'from using the site or the software. Nothing here limits rights '
                'you have under consumer protection law.'),
            Body('These terms are governed by the laws of the Federal Republic '
                'of Nigeria. We may update them; the version on this page, with '
                'the date at the top, is the one that applies.'),
          ],
        ),
      ]),
    );
