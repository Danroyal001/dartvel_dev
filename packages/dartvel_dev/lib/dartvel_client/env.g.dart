// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: non_constant_identifier_names, unused_element
library dartvel_client_env;

/// Environment variables the application ships to the client.
///
/// Only PUBLIC_-prefixed variables are here. Everything else stays in the
/// environment of the process that runs the backend, because a value
/// compiled into this file reaches every visitor.
class Env {
  /// Unpacks a value from the scrambled code units below.
  ///
  /// Not a cipher: the key sits in this file beside the data, and these
  /// are values chosen to be public anyway. It keeps them out of a plain
  /// scan over the built bundle, and buys nothing else. Do not put a
  /// real secret behind the PUBLIC_ prefix on the strength of it.
  static String _d(List<int> c, int k) =>
      String.fromCharCodes(c.map((x) => x ^ k));
}

/// Every public environment variable, by name.
final Map<String, String> dvPublicEnv = <String, String>{
};

/// Public environment variable lookup.
class DartvelEnv {
  /// Map of all public environment variables.
  static final Map<String, String> public = dvPublicEnv;

  /// Gets a public environment variable by name.
  static String? get(String key) => dvPublicEnv[key];
}
