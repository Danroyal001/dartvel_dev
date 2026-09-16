/// `dartvel key generate | rotate | status`: the application key, in the
/// platform key store and never the repo. `dartvel key cloud`: signing and
/// store credentials, into the repository's Actions secrets.
///
/// Generated per install and per user. `generate` refuses to replace a key
/// that exists -- a replaced key is every encrypted store on the machine
/// lost -- and points at `rotate`, which is the deliberate version and says
/// both fingerprints. `status` says whether there is a key, where it is
/// held and its fingerprint, never the key.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../cloud/github_repository.dart';
import '../utils/logger.dart';

class DVKeyResult {
  final bool ok;
  final String message;

  /// The first 16 hex digits of the key's SHA-256: enough to tell two keys
  /// apart in a log, nothing anyone can turn back into the key.
  final String? fingerprint;

  const DVKeyResult({required this.ok, required this.message, this.fingerprint});
}

/// The operations, apart from the command line, so they can be tested and
/// reused by whatever else needs to mint a key.
class DVKeyTool {
  final DVAppKeyStore store;

  const DVKeyTool(this.store);

  static String fingerprintOf(Uint8List key) =>
      sha256.convert(key).toString().substring(0, 16);

  String get _where => DVAppKeyStores.describe(store);

  Future<DVKeyResult> generate() async {
    final Uint8List? existing = await store.read();
    if (existing != null) {
      return DVKeyResult(
        ok: false,
        fingerprint: fingerprintOf(existing),
        message: 'An application key already exists (${fingerprintOf(existing)}) '
            'in $_where. Replacing it would make every store encrypted with it '
            'unreadable; if that is what you mean, `dartvel key rotate` does it '
            'deliberately and records both fingerprints.',
      );
    }
    final Uint8List key = DVAppKey.generate();
    await store.write(key);
    final String fp = fingerprintOf(key);
    return DVKeyResult(
      ok: true,
      fingerprint: fp,
      message: 'Generated application key $fp, held in $_where.',
    );
  }

  Future<DVKeyResult> rotate() async {
    final Uint8List? existing = await store.read();
    final Uint8List next = DVAppKey.generate();
    await store.write(next);
    final String fp = fingerprintOf(next);
    if (existing == null) {
      return DVKeyResult(
        ok: true,
        fingerprint: fp,
        message: 'There was no key to rotate; generated $fp, held in $_where.',
      );
    }
    return DVKeyResult(
      ok: true,
      fingerprint: fp,
      message: 'Rotated application key ${fingerprintOf(existing)} -> $fp, '
          'held in $_where. Stores encrypted with the old key are re-encrypted '
          'by the application on its next start.',
    );
  }

  Future<DVKeyResult> status() async {
    final Uint8List? existing = await store.read();
    if (existing == null) {
      return DVKeyResult(
        ok: false,
        message: 'No application key. `dartvel key generate` makes one, in $_where.',
      );
    }
    final String fp = fingerprintOf(existing);
    return DVKeyResult(
      ok: true,
      fingerprint: fp,
      message: 'Application key $fp, held in $_where.',
    );
  }
}

class KeyCommand extends Command<void> {
  @override
  final String name = 'key';

  @override
  final String description =
      'The application key in the platform key store, and cloud build credentials in the repository\'s secrets.';

  KeyCommand({KeyCloudCommand? cloud}) {
    addSubcommand(cloud ?? KeyCloudCommand());
    addSubcommand(_KeySubcommand('generate', 'Generate the application key. Refuses if one exists.', (DVKeyTool t) => t.generate()));
    addSubcommand(_KeySubcommand('rotate', 'Replace the application key, recording both fingerprints.', (DVKeyTool t) => t.rotate()));
    addSubcommand(_KeySubcommand('status', 'Say whether there is a key, where it is held, and its fingerprint.', (DVKeyTool t) => t.status()));
  }

  /// The app name from a pubspec's text, or `dartvel` when it has none.
  static String appNameFrom(String pubspec) {
    final RegExpMatch? m = RegExp(r'^name:\s*([A-Za-z0-9_]+)\s*$', multiLine: true).firstMatch(pubspec);
    return m?.group(1) ?? 'dartvel';
  }
}

class _KeySubcommand extends Command<void> {
  @override
  final String name;

  @override
  final String description;

  final Future<DVKeyResult> Function(DVKeyTool tool) _run;

  _KeySubcommand(this.name, this.description, this._run) {
    argParser
      ..addOption('store',
          allowed: <String>['auto', 'secret-service', 'file'],
          defaultsTo: 'auto',
          help: 'Where the key is held. auto uses the Secret Service when one answers, else a file only you can read.')
      ..addOption('home', help: 'The home directory for the file store. Defaults to yours.')
      ..addOption('app', help: 'The application the key belongs to. Defaults to the pubspec name here.');
  }

  Future<DVAppKeyStore> _store() async {
    final String home = (argResults!['home'] as String?) ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final String app = (argResults!['app'] as String?) ?? _appName();
    final String choice = argResults!['store'] as String;
    final bool secretService = switch (choice) {
      'file' => false,
      'secret-service' => true,
      _ => await DVSecretServiceAppKeyStore.isAvailable(),
    };
    if (choice == 'secret-service' && !await DVSecretServiceAppKeyStore.isAvailable()) {
      usageException('No Secret Service answers on this session bus; use --store file or start a keyring.');
    }
    return DVAppKeyStores.choose(
      app: app,
      home: home,
      platform: Platform.operatingSystem,
      secretService: secretService,
    );
  }

  static String _appName() {
    final File pubspec = File('pubspec.yaml');
    return pubspec.existsSync() ? KeyCommand.appNameFrom(pubspec.readAsStringSync()) : 'dartvel';
  }

  @override
  Future<void> run() async {
    final DVKeyResult result = await _run(DVKeyTool(await _store()));
    if (!result.ok) usageException(result.message);
    Logger.log(result.message);
  }
}

/// Sets one Actions secret on [repo]; the exit code of doing so.
typedef DVSecretSetter = Future<int> Function(String name, String value, String repo);

/// `dartvel key cloud`: the credentials a cloud build signs and publishes
/// with, set as the repository's encrypted Actions secrets.
///
/// Dartvel holds no signing key and no store credential, and this does not
/// change that: the values go from the files named here to GitHub through
/// `gh secret set`, on standard input so they are never in a process list,
/// and are neither stored nor printed. What is printed is the secret names,
/// which are what `.github/workflows/dartvel-cloud.yml` reads.
class KeyCloudCommand extends Command<void> {
  KeyCloudCommand({
    this._root,
    Map<String, String>? environment,
    void Function(String message)? log,
    Future<String?> Function(String dir)? remote,
    DVSecretSetter? setSecret,
  })  : _environment = environment ?? Platform.environment,
        _log = log ?? Logger.log,
        _remote = remote ?? _originRemote,
        _setSecret = setSecret ?? _ghSecretSet {
    argParser
      ..addOption('android-keystore',
          valueHelp: 'file',
          help: 'The upload keystore release builds are signed with. Its '
              'password is read from DARTVEL_ANDROID_KEYSTORE_PASSWORD, and '
              'the key\'s from DARTVEL_ANDROID_KEY_PASSWORD when it differs.')
      ..addOption('android-key-alias', help: 'The alias of the key in that keystore.')
      ..addOption('firebase-service-account',
          valueHelp: 'file',
          help: 'A service account JSON key that dartvel publish firebase '
              'uploads with.')
      ..addOption('repo',
          valueHelp: 'owner/name',
          help: 'The repository whose secrets are set. Defaults to the origin remote.')
      ..addFlag('dry-run',
          negatable: false,
          help: 'Name the secrets that would be set, and set none.');
  }

  final String? _root;
  final Map<String, String> _environment;
  final void Function(String) _log;
  final Future<String?> Function(String dir) _remote;
  final DVSecretSetter _setSecret;

  @override
  final String name = 'cloud';

  @override
  final String description =
      'Set the credentials cloud builds sign and publish with as the repository\'s Actions secrets.';

  static Future<String?> _originRemote(String dir) async {
    try {
      final ProcessResult r = await Process.run('git', <String>['remote', 'get-url', 'origin'],
          workingDirectory: dir);
      return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
    } on ProcessException {
      return null;
    }
  }

  static Future<int> _ghSecretSet(String name, String value, String repo) async {
    final Process process = await Process.start(
        'gh', <String>['secret', 'set', name, '--repo', repo],
        runInShell: Platform.isWindows);
    process.stdin.write(value);
    await process.stdin.close();
    await process.stdout.drain<void>();
    final String error = await utf8.decodeStream(process.stderr);
    final int code = await process.exitCode;
    if (code != 0) stderr.write(error);
    return code;
  }

  @override
  Future<void> run() async {
    exitCode = await _run();
  }

  Future<int> _run() async {
    final String root = _root ?? Directory.current.path;
    final String? keystore = argResults!['android-keystore'] as String?;
    final String? alias = argResults!['android-key-alias'] as String?;
    final String? firebase = argResults!['firebase-service-account'] as String?;

    if (keystore == null && firebase == null) {
      _log('❌ Name something to set: --android-keystore or --firebase-service-account.');
      return 64;
    }
    if (keystore != null && (alias == null || alias.trim().isEmpty)) {
      _log('❌ --android-keystore needs --android-key-alias, the key in it to sign with.');
      return 64;
    }

    File resolve(String path) => File(p.isAbsolute(path) ? path : p.join(root, path));
    for (final String? path in <String?>[keystore, firebase]) {
      if (path != null && !resolve(path).existsSync()) {
        _log('❌ There is nothing at $path.');
        return 66;
      }
    }

    final Map<String, String> secrets = <String, String>{};
    if (keystore != null) {
      final String? storePassword = _environment['DARTVEL_ANDROID_KEYSTORE_PASSWORD'];
      if (storePassword == null || storePassword.isEmpty) {
        _log('❌ Set DARTVEL_ANDROID_KEYSTORE_PASSWORD to the keystore\'s password. '
            'It is read from the environment so it is not in your shell history.');
        return 78;
      }
      secrets['DARTVEL_ANDROID_KEYSTORE_BASE64'] = base64.encode(resolve(keystore).readAsBytesSync());
      secrets['DARTVEL_ANDROID_KEYSTORE_PASSWORD'] = storePassword;
      secrets['DARTVEL_ANDROID_KEY_ALIAS'] = alias!.trim();
      final String? keyPassword = _environment['DARTVEL_ANDROID_KEY_PASSWORD'];
      if (keyPassword != null && keyPassword.isNotEmpty) {
        secrets['DARTVEL_ANDROID_KEY_PASSWORD'] = keyPassword;
      }
    }
    if (firebase != null) {
      secrets['DARTVEL_FIREBASE_SERVICE_ACCOUNT'] = resolve(firebase).readAsStringSync();
    }

    String? repo = argResults!['repo'] as String?;
    if (repo == null) {
      final String? remote = await _remote(root);
      final DVGitHubRepository? parsed =
          remote == null ? null : DVGitHubRepository.fromRemote(remote);
      if (parsed == null) {
        _log('❌ No GitHub remote named origin here. Pass --repo owner/name.');
        return 78;
      }
      repo = parsed.host == 'github.com' ? parsed.slug : '${parsed.host}/${parsed.slug}';
    }

    if (argResults!['dry-run'] == true) {
      _log('Would set on $repo: ${secrets.keys.join(', ')}');
      return 0;
    }
    for (final MapEntry<String, String> secret in secrets.entries) {
      final int code;
      try {
        code = await _setSecret(secret.key, secret.value, repo);
      } on ProcessException {
        _log('❌ gh is not installed, and the secrets are set with it: '
            'gh secret set encrypts each value with the repository\'s key. '
            'Install it from https://cli.github.com and run gh auth login.');
        return 69;
      }
      if (code != 0) {
        _log('❌ gh secret set ${secret.key} --repo $repo exited $code.');
        return code;
      }
      _log('🔐 Set ${secret.key} on $repo.');
    }
    return 0;
  }
}
