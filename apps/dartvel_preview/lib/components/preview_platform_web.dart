import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// A browser runs no Dart it did not load itself, so a project's code comes
/// in as its web build.
bool get previewRunsCode => false;

bool get previewShowsWeb => true;

Future<String> previewPair(Uri pairing) async =>
    'A browser cannot run a project\'s code through pairing. Open its web '
    'build instead.';

final Set<String> _registered = <String>{};

/// The project's web build in a frame that fills the page.
///
/// The frame gets the address and nothing else from the link: no `srcdoc`,
/// no script, and the link was already refused unless it is http or https.
Widget previewWebFrame(Uri url) {
  final String viewType = 'dartvel-preview-frame:$url';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
      final web.HTMLIFrameElement frame = web.HTMLIFrameElement()
        ..src = url.toString()
        ..allow = 'clipboard-write; fullscreen'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return frame;
    });
  }
  return HtmlElementView(viewType: viewType);
}
