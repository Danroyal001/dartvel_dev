/// The link Preview was started with, if any: a desktop launch argument, or
/// `?open=` on the web build's address.
library;

/// Set by main before the app runs.
String? previewLaunchLink;

/// The first argument that looks like a link Preview reads, or null.
///
/// A `dartvel-dev://pair` argument is not returned: the tunnel reads that
/// one itself when the process starts, and handing it to the app as well
/// would pair twice.
String? previewLinkFromArguments(List<String> arguments) {
  for (final String argument in arguments) {
    final String a = argument.trim();
    if (a.startsWith('dartvel-preview://') ||
        a.startsWith('http://') ||
        a.startsWith('https://')) {
      return a;
    }
  }
  return null;
}
