import 'package:flutter/widgets.dart';

/// Whether this Preview can run a project's code: a development build on a
/// platform with a pairing tunnel.
bool get previewRunsCode => false;

/// Whether this Preview can show a project's web build inside itself.
bool get previewShowsWeb => false;

/// Hands [pairing] to the development build's tunnel. Returns what happens
/// next, for the reader.
Future<String> previewPair(Uri pairing) async =>
    'This Preview cannot run a project\'s code.';

/// The project's web build at [url], inside the app.
Widget previewWebFrame(Uri url) => const SizedBox.shrink();
