import 'package:web/web.dart' as web;

/// The browser goes to the checkout page and the gateway sends it back to
/// the application's own return URL.
Future<void> Function(Uri url)? dvExternalUrlOpener() =>
    (Uri url) async => web.window.location.assign(url.toString());
