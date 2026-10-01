/// What Preview does with a link, decided from what the link carries and
/// what this build of Preview can do. Plain Dart, so every case is a test.
library;

import 'package:dartvel_core/dartvel.dart';

enum PreviewAction {
  /// Hand the pairing to the tunnel: dartvel dev attaches and restarts this
  /// app into the project's code.
  pair,

  /// Show the project's web build inside Preview.
  showWeb,

  /// Show the address, for a browser on this device.
  openInBrowser,

  /// Nothing this Preview can do with the link; the message says why.
  cannot,
}

class const PreviewDecision(
  final PreviewAction action, {
  final Uri? url,
  final String message = '',
});

PreviewDecision previewDecide(
  DVPreviewAppLink link, {
  required bool runsCode,
  required bool showsWeb,
}) {
  if (link.canRunCode && runsCode) {
    return PreviewDecision(PreviewAction.pair, url: link.pairing);
  }
  if (link.canOpenWeb && showsWeb) {
    return PreviewDecision(PreviewAction.showWeb, url: link.web);
  }
  if (link.canOpenWeb) {
    return PreviewDecision(
      PreviewAction.openInBrowser,
      url: link.web,
      message: runsCode
          ? '${link.label} has no pairing in this link. Its web build is at '
              'this address.'
          : 'This Preview cannot run code, so open the web build of '
              '${link.label} in a browser on this device.',
    );
  }
  return PreviewDecision(
    PreviewAction.cannot,
    message: showsWeb
        ? 'This link only pairs, and a browser cannot run a project\'s code. '
            'Run dartvel dev with -d web-server so its code also carries the '
            'web build.'
        : 'This Preview is not a development build, so it cannot pair. '
            'Build it with dartvel build <target> --profile development.',
  );
}
