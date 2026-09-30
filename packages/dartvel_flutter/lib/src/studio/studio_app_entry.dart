/// Studio's screens, as the deferred library the Studio route loads.
///
/// Only [dvStudioAppFor] is reached from outside, through the deferred
/// import in `studio_routes.dart`, so everything Studio draws is in this
/// library's parts and none of it is in `main.dart.js`. The server serves
/// those parts to a caller with the Studio grant and to nobody else.
library;

import 'package:flutter/widgets.dart';

import 'studio_server.dart' show DVStudioApp, DVStudioClient, DVStudioTransport;

/// Studio for a caller the route's guard let through. [DVStudioApp] asks
/// the server once more, and draws the sign-in rather than Studio if the
/// grant has gone in the meantime.
Widget dvStudioAppFor({
  required DVStudioTransport transport,
  required String title,
  Uri? location,
  void Function(String path)? open,
}) => DVStudioApp(
  client: DVStudioClient(transport),
  title: title,
  location: location,
  open: open,
);
