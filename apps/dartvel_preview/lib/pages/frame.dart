import 'package:flutter/material.dart';

import '../components/preview_platform.dart';
import '../dartvel_client/dartvel_client.dart';

/// A project's web build, inside Preview, with the way back above it.
@DVPage(title: 'Dartvel Preview', showAppBar: false)
@pragma('vm:entry-point')
Widget _framePage(BuildContext context) {
  final String asked =
      GoRouterState.of(context).uri.queryParameters['url'] ?? '';
  DVPreviewAppLink? link;
  try {
    link = DVPreviewAppLink.parse(asked);
  } on FormatException {
    link = null;
  }
  final Uri? url = link?.web;
  return Scaffold(
    appBar: AppBar(
      toolbarHeight: 44,
      title: Semantics(
        headingLevel: 1,
        child: Text(url?.host ?? 'Dartvel Preview',
            style: const TextStyle(fontSize: 15)),
      ),
      leading: IconButton(
        tooltip: 'Projects',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(DVRoutes.index.path),
      ),
    ),
    body: url == null
        ? const Center(child: Text('That is not a web address Preview opens.'))
        : previewWebFrame(url),
  );
}
