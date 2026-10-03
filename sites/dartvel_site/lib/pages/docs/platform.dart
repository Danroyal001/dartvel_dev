import 'package:flutter/material.dart';

import '../../components/site.dart' show Palette;
import '../../dartvel_client/dartvel_client.dart';

/// The old address of the page that was split in two, kept so links to it
/// still arrive somewhere useful. Not in the docs sidebar.
@DVPage(
  title: 'This page moved',
  description: 'Native device access and API keys and OAuth now have pages '
      'of their own.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsPlatformPage(BuildContext context) {
  final Palette palette = Palette.of(context);
  return SingleChildScrollView(
    child: DVBox(
      DVBox.list(<Widget>[
        const Eyebrow('DOCS'),
        Prose('This page moved', const DVModifier()
            .fontSize(34)
            .fontWeight(.w700)
            .color(palette.ink)
            .semanticHeading(1)),
        Prose('It was split in two, because "Platform" named two different '
            'things:', const DVModifier().fontSize(17).color(palette.ink)),
        const DVNavLink(
          to: DVRoutes.docsnativeaccess,
          child: DVText('Native device access: DV.Platform, permissions '
              'and native features'),
        ),
        const DVNavLink(
          to: DVRoutes.docsplatformapi,
          child: DVText('API keys and OAuth for your app\'s API'),
        ),
      ], spacing: 18),
    ).modifier(const DVModifier().padding(40)),
  );
}
