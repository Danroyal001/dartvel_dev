import 'package:flutter/material.dart';

import '../components/open_panel.dart';
import '../components/preview_platform.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel Preview', showAppBar: false)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final String how = previewRunsCode
      ? 'Run dartvel dev in a project on the same network and scan the '
          'Dartvel Preview code it prints, or paste its link. This app '
          'restarts into the project, and every save reloads it.'
      : previewShowsWeb
          ? 'Run dartvel dev -d web-server in a project on the same network '
              'and paste the Dartvel Preview link it prints. The project\'s '
              'web build opens here.'
          : 'This build of Preview cannot run code. Paste a link to open the '
              'project\'s web build in a browser.';
  return Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: DVBox(
          DVBox.list(<Widget>[
            const DVText('Dartvel Preview').modifier(const DVModifier()
                .fontSize(28)
                .fontWeight(.w800)
                .semanticHeading(1)),
            DVText(how).modifier(const DVModifier()
                .fontSize(16)
                .lineHeight(1.5)
                .color(colors.onSurfaceVariant)),
            const PreviewOpenPanel(),
          ], spacing: 18, crossAlign: .stretch),
          const DVModifier().padding(24).maxWidth(560).centered(),
        ),
      ),
    ),
  );
}
