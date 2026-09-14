import 'dart:io';

import 'env_format.dart';

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

/// The credentials directory a test pointed at, when [_credentialsSet].
String? _credentialsDirectory;
bool _credentialsSet = false;

void useCredentialsDirectory(String? path) {
  _credentialsDirectory = path;
  _credentialsSet = true;
}

void resetCredentialsDirectory() {
  _credentialsDirectory = null;
  _credentialsSet = false;
}

/// A key is a file name in the credentials directory only when it is a plain
/// variable name. Anything else -- `../x`, `a/b`, an absolute path -- would
/// read a file the supervisor never put there.
final RegExp _credentialName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// The value systemd decrypted for this unit, from `$CREDENTIALS_DIRECTORY`.
///
/// `dartvel infra` delivers secrets as encrypted credentials rather than an
/// environment file, so a secret is only plaintext in a private in-memory
/// directory while the unit runs. Read exactly as written: the provisioner
/// sends the value's bytes, and trimming here would make a value with
/// meaningful whitespace differ from the one declared.
String? _readCredential(String key) {
  if (!_credentialName.hasMatch(key)) return null;
  final String? directory = _credentialsSet
      ? _credentialsDirectory
      : Platform.environment['CREDENTIALS_DIRECTORY'];
  if (directory == null || directory.isEmpty) return null;
  try {
    final File file = File('$directory/$key');
    if (!file.existsSync()) return null;
    final String value = file.readAsStringSync();
    return value.isEmpty ? null : value;
  } on FileSystemException {
    return null;
  }
}

/// The process environment first, then the supervisor's credentials, then
/// the `.env` file.
///
/// That order is not arbitrary. A `.env` checked into a repository outlives
/// the branch it was written on, and letting it shadow what an operator set
/// on the machine actually running the process -- in its environment or as a
/// credential provisioned for the unit -- is how a production deploy picks up
/// a development credential without anyone noticing.
String? readEnvironment(String key) {
  final String? fromProcess = Platform.environment[key];
  if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
  final String? fromCredential = _readCredential(key);
  if (fromCredential != null) return fromCredential;
  return _readEnvFile()[key];
}

Map<String, String> _readEnvFile() {
  final File file = File(_envFilePath);
  // A project with no .env is the normal case, not a problem to report.
  final Map<String, String> cached = _envFile ??
      (file.existsSync()
          ? dvParseEnvContents(file.readAsStringSync())
          : const <String, String>{});
  return _envFile = cached;
}

String missingSecretReason(String key) =>
    'no environment variable "$key" is set for this process, nothing was '
    'registered with DVSecrets.configure(...), and $_envFilePath does not '
    'supply it either.';
