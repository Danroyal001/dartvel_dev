import 'dart:io';

/// Where the local-development file lives, relative to the working directory
/// unless something points this somewhere else.
const String defaultEnvFilePath = '.env';

String _envFilePath = defaultEnvFilePath;

/// Parsed contents of [_envFilePath], or null when it has not been read yet.
///
/// Cached because resolution happens on every `DV.Secrets.get`, and a server
/// under load must not stat and re-parse a file per request.
Map<String, String>? _envFile;

void useEnvFile(String path) {
  _envFilePath = path;
  _envFile = null;
}

void resetEnvFile() {
  _envFilePath = defaultEnvFilePath;
  _envFile = null;
}

/// The process environment first, then the `.env` file.
///
/// That order is not arbitrary. A `.env` checked into a repository outlives
/// the branch it was written on, and letting it shadow what an operator set
/// on the machine actually running the process is how a production deploy
/// picks up a development credential without anyone noticing.
String? readEnvironment(String key) {
  final String? fromProcess = Platform.environment[key];
  if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
  return _readEnvFile()[key];
}

Map<String, String> _readEnvFile() {
  final Map<String, String> cached = _envFile ?? _parseEnvFile();
  return _envFile = cached;
}

Map<String, String> _parseEnvFile() {
  final File file = File(_envFilePath);
  // A project with no .env is the normal case, not a problem to report.
  if (!file.existsSync()) return const <String, String>{};

  final Map<String, String> out = <String, String>{};
  for (final String raw in file.readAsLinesSync()) {
    String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    // People paste these files straight into a shell. A line the shell reads
    // and the framework ignores is a secret that is set everywhere except
    // where the code goes looking for it.
    if (line.startsWith('export ')) line = line.substring(7).trim();

    final int separator = line.indexOf('=');
    if (separator <= 0) continue;

    final String name = line.substring(0, separator).trim();
    String value = line.substring(separator + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty) continue;
    out[name] = value;
  }
  return out;
}

String missingSecretReason(String key) =>
    'no environment variable "$key" is set for this process, nothing was '
    'registered with DVSecrets.configure(...), and $_envFilePath does not '
    'supply it either.';
