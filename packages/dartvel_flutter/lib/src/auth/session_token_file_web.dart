import 'session_client.dart';

/// A browser keeps no session token: the server's `HttpOnly` cookie is the
/// session, and a token a page could read is the thing it exists to avoid.
class DVFileSessionTokenSink implements DVSessionTokenSink {
  DVFileSessionTokenSink(String path);

  DVFileSessionTokenSink.resolving(String Function() path);

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String? value) async {
    throw UnsupportedError('A browser does not store a session token.');
  }
}

/// Null in a browser, where the cookie is the session.
DVSessionTokenStore? dvSessionTokenStoreFor(String app) => null;
