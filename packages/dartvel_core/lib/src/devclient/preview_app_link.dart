/// The link `dartvel dev` prints for Dartvel Preview.
///
/// Dartvel Preview is one app that runs any project a `dartvel dev` on the
/// same network serves, the way Expo Go runs any Expo project: nothing of the
/// project is built for the device first. The link says how to reach the
/// project each way the app can run it:
///
/// * [pairing], the `dartvel-dev://pair` link, for the project's own code.
///   Preview is a development build, so it pairs with the dev server like
///   any development build does, and the pairing hot restarts it onto the
///   project's sources.
/// * [web], the project's web build on the network, for a browser, and for a
///   device whose Preview cannot run code (a release build, or iOS away
///   from Xcode).
///
/// `dartvel-preview://open?name=shop&pair=...&web=http://192.168.1.20:5000`
library dartvel_core.devclient.preview_app_link;

import 'dev_client.dart';

/// What a Dartvel Preview link carries.
class DVPreviewAppLink {
  const DVPreviewAppLink({this.name, this.pairing, this.web});

  /// The scheme Preview registers.
  static const String scheme = 'dartvel-preview';

  /// The project's name, for the list of recent projects.
  final String? name;

  /// The `dartvel-dev://pair` link, already checked the way the tunnel will
  /// check it.
  final Uri? pairing;

  /// The project's web build, http or https.
  final Uri? web;

  bool get canRunCode => pairing != null;
  bool get canOpenWeb => web != null;

  /// What to call the project: its name, or the host it is served from.
  String get label =>
      name ??
      web?.host ??
      (pairing == null
          ? 'Project'
          : (Uri.tryParse(pairing!.queryParameters['server'] ?? '')?.host ??
              'Project'));

  Uri toUri() => Uri(
        scheme: scheme,
        host: 'open',
        queryParameters: <String, String>{
          if (name != null) 'name': name!,
          if (pairing != null) 'pair': pairing.toString(),
          if (web != null) 'web': web.toString(),
        },
      );

  @override
  String toString() => toUri().toString();

  /// Reads a link someone scanned or pasted: a Preview link, a bare pairing
  /// link, or a bare web address. Throws [FormatException] saying what is
  /// wrong with anything else.
  ///
  /// Everything is checked before the app acts on it. The web address is
  /// loaded into the app, so only http and https are accepted: a
  /// `javascript:` or `file:` address would run or read something other than
  /// a dev server's page. The pairing is parsed as the tunnel parses it, so
  /// a link the tunnel would refuse is refused here, where the reader can
  /// see why.
  static DVPreviewAppLink parse(String text) {
    final String trimmed = text.trim();
    final Uri? uri = Uri.tryParse(trimmed);
    if (trimmed.isEmpty || uri == null || !uri.hasScheme) {
      throw const FormatException(
        'Paste the link `dartvel dev` prints: dartvel-preview://..., '
        'dartvel-dev://pair?... or the http address of its web build.',
      );
    }
    switch (uri.scheme) {
      case scheme:
        if (uri.host != 'open') {
          throw const FormatException(
              'A Dartvel Preview link starts dartvel-preview://open.');
        }
        final Map<String, String> q = uri.queryParameters;
        final Uri? pairing = q['pair'] == null ? null : _pairing(q['pair']!);
        final Uri? web = q['web'] == null ? null : _web(q['web']!);
        if (pairing == null && web == null) {
          throw const FormatException(
            'This link names no project to open: it has neither a pairing '
            'nor a web address.',
          );
        }
        final String? name = q['name']?.trim();
        return DVPreviewAppLink(
          name: name == null || name.isEmpty ? null : name,
          pairing: pairing,
          web: web,
        );
      case dvDevClientLinkScheme:
        return DVPreviewAppLink(pairing: _pairing(trimmed));
      case 'http':
      case 'https':
        return DVPreviewAppLink(web: _web(trimmed));
    }
    throw FormatException(
      'A ${uri.scheme}: link is not something Dartvel Preview opens.',
    );
  }

  static Uri _pairing(String text) {
    final Uri? uri = Uri.tryParse(text.trim());
    if (uri == null) throw const FormatException('The pairing is not a link.');
    // Throws with the tunnel's own reason: an http server, a missing key.
    return DVDevClientPairing.parse(uri).link;
  }

  static Uri _web(String text) {
    final Uri? uri = Uri.tryParse(text.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'The web address has to be an http or https address with a host.',
      );
    }
    return uri;
  }
}
