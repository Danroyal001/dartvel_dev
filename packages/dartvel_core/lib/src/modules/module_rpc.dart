/// A module operation carried to the backend over RPC.
///
/// The placement matrix's carrier of last resort: where a source cannot run
/// in the environment that calls it but can on the backend, the operation is
/// declared `{ compat: backend }`. The client half of the generated module
/// calls [DVModuleRpc.call]; the backend half is a dispatcher the generated
/// backend serves at [DVModuleRpc.path], behind the policy the application
/// names for the module.
///
/// Values cross as JSON. Bytes cross as base64 in a one-key map, so a
/// `Uint8List` comes back as one rather than as a list of numbers.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Sends one module call to the backend and answers with its JSON result.
///
/// The generated client installs one that goes through the same request
/// path as a backend function, so the call carries the session, the CSRF
/// token and the step-up handling every other call does.
typedef DVModuleRpcTransport = Future<Object?> Function(
    String path, Map<String, Object?> arguments);

/// The client and wire halves of a module call carried to the backend.
abstract final class DVModuleRpc {
  /// The route a module operation is served at, under the API base path.
  static String path(String module, String operation) =>
      '/_dv/modules/$module/$operation';

  /// How a call reaches the backend. Installed by the generated client.
  static DVModuleRpcTransport? transport;

  /// Sends [operation] of [module] to the backend with [arguments].
  static Future<Object?> call(
    String module,
    String operation,
    Map<String, Object?> arguments,
  ) {
    final DVModuleRpcTransport? send = transport;
    if (send == null) {
      throw DVModuleRpcRefused(module, operation,
          'no backend transport is installed; the generated client installs '
          'one when the application starts');
    }
    return send(path(module, operation), <String, Object?>{
      for (final MapEntry<String, Object?> a in arguments.entries)
        a.key: encode(a.value),
    });
  }

  static const String _bytesKey = r'$bytes';

  /// [value] as JSON carries it: bytes as base64, the rest unchanged.
  static Object? encode(Object? value) => switch (value) {
        final Uint8List bytes => <String, Object?>{
            _bytesKey: base64Encode(bytes),
          },
        final List<Object?> list => <Object?>[for (final Object? v in list) encode(v)],
        final Map<String, Object?> map => <String, Object?>{
            for (final MapEntry<String, Object?> e in map.entries)
              e.key: encode(e.value),
          },
        _ => value,
      };

  /// Bytes sent by [encode].
  static Uint8List bytes(Object? value) {
    if (value is Map && value[_bytesKey] is String) {
      return base64Decode(value[_bytesKey] as String);
    }
    throw FormatException('expected bytes, got ${value.runtimeType}');
  }
}

/// A module call the backend would not run: an operation that is not
/// carried to the backend, arguments of the wrong shape, or a client with no
/// transport.
class DVModuleRpcRefused implements Exception {
  const DVModuleRpcRefused(this.module, this.operation, this.reason);

  final String module;
  final String operation;
  final String reason;

  /// The diagnostic this failure carries.
  String get code => 'DV-MODULE-021';

  @override
  String toString() => '$code: $module.$operation was not run on the '
      'backend: $reason.';
}
