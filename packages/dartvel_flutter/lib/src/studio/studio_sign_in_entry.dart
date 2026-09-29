/// Studio's sign-in, as the deferred library `<mount>/login` loads.
///
/// Its own library, apart from Studio's screens: the sign-in is served to
/// anybody, and nothing in it may reach the code of a screen behind the
/// grant, or that code would land in a part a stranger is handed.
library;

import 'package:flutter/widgets.dart';

import 'studio_server.dart' show DVStudioClient;
import 'studio_sign_in.dart';

/// Studio's sign-in page, in Studio's own frame.
Widget dvStudioSignInFor({
  required DVStudioClient client,
  required String mount,
  String? from,
  required String title,
  required void Function(String path) open,
}) => DVStudioFrame(
  title: title,
  home: DVStudioSignInScreen(
    client: client,
    mount: mount,
    from: from,
    title: title,
    open: open,
  ),
);
