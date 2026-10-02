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
///
/// [screen] and [object] are what the address names: which screen, and what
/// is open in it. [onSelect] is how a section says the person chose
/// something else, so the route can put it in the address.
Widget dvStudioAppFor({
  required DVStudioTransport transport,
  required String title,
  String? mount,
  String? screen,
  String? object,
  Uri? location,
  void Function(String path)? open,
  void Function(String screen, String? object)? onSelect,
}) => DVStudioApp(
  client: DVStudioClient(transport),
  title: title,
  mount: mount,
  screen: screen,
  object: object,
  location: location,
  open: open,
  onSelect: onSelect,
);
