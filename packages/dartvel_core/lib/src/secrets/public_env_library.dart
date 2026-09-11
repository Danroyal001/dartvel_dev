/// Emitting `env.g.dart`, the file that decides what leaves the server.
///
/// This sits in the runtime package rather than in a generator because there
/// were two generators. The CLI writes the client directly; the retired
/// build_runner router builder still writes it for projects that have not
/// migrated yet, and each carried its own copy of the PUBLIC_ filter. Two
/// implementations of a security boundary, either of which can be edited
/// without the other noticing, is the arrangement that eventually ships a
/// backend credential to a browser. One function, tested once, cannot drift
/// from itself.
library dartvel.secrets.public_env_library;

/// A generated `env.g.dart` and the names left out of it.
class DVPublicEnvLibrary {
  const DVPublicEnvLibrary({required this.source, required this.skipped});

  /// The library, ready to write.
  final String source;

  /// PUBLIC_ names that could not be emitted, in the order they were read.
  ///
  /// Reported rather than dropped in silence: a variable somebody set and
  /// cannot find at runtime is a long afternoon, and the build knows exactly
  /// why it went missing.
  final List<String> skipped;
}

/// The public part of [environment], as a Dart library.
///
/// Only `PUBLIC_`-prefixed names are emitted, and that filter is the whole of
/// structural guarantee one: everything else stays in the environment of the
/// process that runs the code, whether or not any analysis runs.
///
/// Values are stored XOR-scrambled. That is not secrecy and the generated file
/// says so -- the key is written beside the data -- it only keeps a
/// configuration string from turning up in a plain scan over the built bundle.
///
/// Output is deterministic: the same environment gives byte-identical source,
/// in sorted order, however the incoming map was built. The key used to come
/// from `DateTime.now()`, so every regeneration rewrote the file with
/// different numbers for identical input, and a generated file that churns on
/// its own teaches people to ignore its diffs.
DVPublicEnvLibrary dvGeneratePublicEnvLibrary(Map<String, String> environment) {
  final List<String> skipped = <String>[];
  final Map<String, String> emitted = <String, String>{};

  final List<String> names = environment.keys.toList()..sort();
  for (final String name in names) {
    if (!name.startsWith('PUBLIC_')) continue;
    // The names come out of a .env file, which the build reads without any
    // review. A name carrying a quote would close the string it is
    // interpolated into and turn the rest of the line into code in a
    // generated library; a name with a dash would simply not compile.
    if (!_isPublicIdentifier(name)) {
      skipped.add(name);
      continue;
    }
    emitted[name] = environment[name]!;
  }

  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: non_constant_identifier_names, '
        'unused_element')
    ..writeln('library dartvel_client_env;')
    ..writeln('')
    ..writeln('/// Environment variables the application ships to the client.')
    ..writeln('///')
    ..writeln('/// Only PUBLIC_-prefixed variables are here. Everything else '
        'stays in the')
    ..writeln('/// environment of the process that runs the backend, because '
        'a value')
    ..writeln('/// compiled into this file reaches every visitor.')
    ..writeln('class Env {')
    ..writeln('  /// Unpacks a value from the scrambled code units below.')
    ..writeln('  ///')
    ..writeln('  /// Not a cipher: the key sits in this file beside the data, '
        'and these')
    ..writeln('  /// are values chosen to be public anyway. It keeps them out '
        'of a plain')
    ..writeln('  /// scan over the built bundle, and buys nothing else. Do '
        'not put a')
    ..writeln('  /// real secret behind the PUBLIC_ prefix on the strength of '
        'it.')
    ..writeln('  static String _d(List<int> c, int k) =>')
    ..writeln('      String.fromCharCodes(c.map((x) => x ^ k));');

  for (final MapEntry<String, String> entry in emitted.entries) {
    out
      ..writeln('')
      ..writeln('  /// Value of the ${entry.key} environment variable.')
      ..writeln('  static String get ${entry.key} => '
          '${_scramble(entry.value)};');
  }

  out
    ..writeln('}')
    ..writeln('')
    ..writeln('/// Every public environment variable, by name.')
    ..writeln('final Map<String, String> dvPublicEnv = <String, String>{');
  for (final String name in emitted.keys) {
    out.writeln("  '$name': Env.$name,");
  }
  out
    ..writeln('};')
    ..writeln('')
    ..writeln('/// Public environment variable lookup.')
    ..writeln('class DartvelEnv {')
    ..writeln('  /// Map of all public environment variables.')
    ..writeln('  static final Map<String, String> public = dvPublicEnv;')
    ..writeln('')
    ..writeln('  /// Gets a public environment variable by name.')
    ..writeln('  static String? get(String key) => dvPublicEnv[key];')
    ..writeln('}');

  return DVPublicEnvLibrary(source: out.toString(), skipped: skipped);
}

/// Whether [name] can be both a Dart getter and a sane map key.
///
/// `PUBLIC_` on its own passes the identifier test and means nothing, so it is
/// refused separately.
bool _isPublicIdentifier(String name) {
  if (name.length <= 'PUBLIC_'.length) return false;
  return RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name);
}

/// The value as an XOR-scrambled literal plus its key.
///
/// The key is derived from the value, so the same input always produces the
/// same bytes. Zero is avoided because XOR by zero would write the value out
/// in plain code units, which is the one thing this is meant not to do.
String _scramble(String value) {
  int hash = 0x811c9dc5;
  for (final int unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  final int key = 1 + (hash % 254);
  final Iterable<int> scrambled = value.codeUnits.map((int c) => c ^ key);
  return '_d(const [${scrambled.join(', ')}], $key)';
}
