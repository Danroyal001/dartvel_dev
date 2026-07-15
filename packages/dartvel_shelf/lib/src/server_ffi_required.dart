import 'wintercg.dart';

/// Server handle for builds where the native FFI server is not linked.
class ServerHandle {
  /// Server host.
  final String host;

  /// Server port.
  final int port;
  bool _stopped = false;

  /// Default constructor.
  ServerHandle(this.host, this.port);

  /// Stops the server.
  Future<void> stop() async {
    _stopped = true;
  }

  bool get isStopped => _stopped;
}

/// TLS configuration.
class TlsConfig {
  /// Certificate PEM string.
  final String certPem;

  /// Key PEM string.
  final String keyPem;

  /// Default constructor.
  const TlsConfig({required this.certPem, required this.keyPem});
}

/// CORS options.
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
  throw StateError(
    'Dartvel Shelf server requires the FFI native backend. Build with dart.library.ffi and the ffigen-generated server bindings.',
  );
}
