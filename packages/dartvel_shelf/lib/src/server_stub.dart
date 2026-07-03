import 'wintercg.dart';

/// Stub class for ServerHandle on unsupported platforms (like web).
class ServerHandle {
  /// Server host.
  final String host;
  /// Server port.
  final int port;

  /// Default constructor.
  ServerHandle(this.host, this.port);

  /// Stops the server.
  Future<void> stop() async {}
}

/// Stub class for TlsConfig on unsupported platforms.
class TlsConfig {
  /// Certificate PEM string.
  final String certPem;
  /// Key PEM string.
  final String keyPem;

  /// Default constructor.
  const TlsConfig({required this.certPem, required this.keyPem});
}

/// Stub class for CorsOptions on unsupported platforms.
class CorsOptions {
  /// Allowed origins.
  final List<String> allowedOrigins;
  /// Allowed methods.
  final List<String> allowedMethods;
  /// Allowed headers.
  final List<String> allowedHeaders;
  /// Allow credentials flag.
  final bool allowCredentials;
  /// Max age cache in seconds.
  final int? maxAge;

  /// Default constructor.
  const CorsOptions({
    this.allowedOrigins = const ['*'],
    this.allowedMethods = const ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    this.allowedHeaders = const ['*'],
    this.allowCredentials = false,
    this.maxAge,
  });
}

/// Serves the handler configuration.
Future<ServerHandle> serve(
  Future<Response> Function(Request) handler, {
  String host = '127.0.0.1',
  int port = 8080,
  TlsConfig? tls,
  bool h2c = false,
  CorsOptions? cors,
  String? staticDir,
  String? spaRoot,
  bool compression = true,
}) async {
  throw UnsupportedError('Server is not supported on this platform.');
}
