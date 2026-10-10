import 'dart:io' show Platform, Process;

/// The desktop's own opener, or null on a phone, where a digital good never
/// reaches a checkout page: it goes to the store.
Future<void> Function(Uri url)? dvExternalUrlOpener() {
  final (String, List<String>)? opener = Platform.isMacOS
      ? ('open', const <String>[])
      : Platform.isLinux
          ? ('xdg-open', const <String>[])
          : Platform.isWindows
              ? ('rundll32', const <String>['url.dll,FileProtocolHandler'])
              : null;
  if (opener == null) return null;
  return (Uri url) async {
    if (url.scheme != 'https') {
      // Only a gateway's own page. Anything else handed to the operating
      // system's opener could be a file or a program.
      throw ArgumentError.value(url, 'url', 'a checkout page is https');
    }
    final result =
        await Process.run(opener.$1, <String>[...opener.$2, url.toString()]);
    if (result.exitCode != 0) {
      throw StateError('${opener.$1} could not open the checkout page');
    }
  };
}
