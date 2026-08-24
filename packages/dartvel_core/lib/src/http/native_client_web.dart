/// Web stand-in for the native HTTP transport.
///
/// The native transport is a Rust client reached through `dart:ffi`, which the
/// web target does not provide. Rather than failing to compile — which is what
/// an unconditional export of the real implementation does — web gets this,
/// and the browser does the work instead.
///
/// That is not a degradation on web. The browser negotiates HTTP/2 and HTTP/3
/// itself and acts on early hints before script is told anything, so there is
/// nothing for a native client to add; see `DVBrowserHttpTransport`.
///
/// Every public name in `native_client.dart` appears here, and a test asserts
/// that, because a name present on one target and absent on the other compiles
/// in one build and not the other.
library dartvel_core.http.native_client_web;

import 'dart:convert';

import 'protocol.dart';
import 'transport.dart';

/// Always throws on web: there is no native library to locate.
Future<String> resolveNativeLibraryPath() async {
  throw UnsupportedError(
    'There is no native HTTP library on web. The browser negotiates HTTP/2 '
    'and HTTP/3 itself; use DVBrowserHttpTransport.',
  );
}

/// Identical to the native encoder, and deliberately duplicated.
///
/// It touches no `dart:ffi` type — it is only here because it is exported from
/// the same library, and moving it to a third file to save eight lines would
/// add an import to every caller.
String encodeNativeRequest(DVHttpRequest request, DVHttpProtocol protocol) {
  return jsonEncode(<String, Object?>{
    'url': request.url.toString(),
    'method': request.method,
    'headers': request.headers,
    'alpn': protocol.alpn,
    'timeout_ms': 0,
  });
}

/// The native transport, as web sees it: never available.
class DVRustHttpTransport implements DVHttpTransport {
  final String libraryPath;

  const DVRustHttpTransport(this.libraryPath);

  /// Always null on web, with the reason recorded.
  ///
  /// Null rather than throwing, for the same reason as the native version: an
  /// application registers this opportunistically and keeps working without it.
  static Future<DVRustHttpTransport?> tryLoad() async {
    dvHttpTransportHint = describeNativeTransportAbsence(null, null);
    return null;
  }

  @override
  String get name => 'rust';

  /// Nothing, on web.
  ///
  /// Not http2 and http3 as the native transport declares: claiming them here
  /// would have the fallback chain route requests into a transport that cannot
  /// serve any of them.
  @override
  Set<DVHttpProtocol> get supportedProtocols => const <DVHttpProtocol>{};

  @override
  Future<DVHttpResponse> send(DVHttpRequest request) =>
      throw UnsupportedError('The native HTTP transport is unavailable on web.');

  @override
  Future<DVHttpStreamedResponse> stream(DVHttpRequest request) =>
      throw UnsupportedError('The native HTTP transport is unavailable on web.');
}

/// Always false on web; nothing is installed.
Future<bool> installNativeHttpTransport() async => false;

/// Why the native transport is unavailable here.
///
/// Phrased as a fact about the platform rather than a fault, because on web it
/// is neither missing nor broken — it does not apply.
String describeNativeTransportAbsence(String? path, Object? error) {
  return 'The native HTTP transport does not exist on web, and is not needed: '
      'the browser negotiates HTTP/2 and HTTP/3 itself and acts on early hints '
      'without being asked.';
}
