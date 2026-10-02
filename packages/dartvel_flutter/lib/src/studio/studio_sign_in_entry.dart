/// Studio's sign-in, as the deferred library `<mount>/login` loads.
///
/// Its own library, apart from Studio's screens: the sign-in is served to
/// anybody, and nothing in it may reach the code of a screen behind the
/// grant, or that code would land in a part a stranger is handed.
library;

import 'package:flutter/widgets.dart';

import 'studio_server.dart' show DVStudioClient, DVStudioTransport;
import 'studio_first_run.dart';
import 'studio_sign_in.dart';

/// Studio's sign-in page, in Studio's own frame.
Widget dvStudioSignInFor({
  required DVStudioTransport transport,
  required String mount,
  String? from,
  required String title,
  required void Function(String path) open,
  List<String> returns = const <String>[],
}) => DVStudioFrame(
  title: title,
  home: DVStudioSignInScreen(
    client: DVStudioClient(transport),
    mount: mount,
    from: from,
    title: title,
    open: open,
    returns: returns,
  ),
);

/// Studio's first-run setup page, in Studio's own frame. Public like the
/// sign-in: the server sends every page of the mount here, to anybody, until
/// the owner has replaced the printed password and set up a second factor.
Widget dvStudioSetupFor({
  required DVStudioTransport transport,
  required String mount,
  required String title,
  required void Function(String path) open,
}) => DVStudioFrame(
  title: title,
  home: DVStudioFirstRunScreen(
    client: DVStudioClient(transport),
    mount: mount,
    title: title,
    open: open,
  ),
);
