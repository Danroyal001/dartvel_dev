/// The Dartvel Preview link `dartvel dev` prints beside its other codes.
library dartvel_cli.devclient.dev_preview_link;

import 'package:dartvel_core/dartvel.dart';

/// The link for this run, or null when Preview could open it neither way.
///
/// A web address that is this machine's own -- localhost, a loopback
/// address -- is left out: on a phone it names the phone.
DVPreviewAppLink? dvDevPreviewLink({
  required String? name,
  required Uri? pairing,
  required Uri? web,
}) {
  final Uri? reachable =
      web != null && !_loopback(web.host) ? web : null;
  if (pairing == null && reachable == null) return null;
  return DVPreviewAppLink(name: name, pairing: pairing, web: reachable);
}

bool _loopback(String host) =>
    host == 'localhost' ||
    host == '::1' ||
    host == '[::1]' ||
    host.startsWith('127.') ||
    host == '0.0.0.0';
