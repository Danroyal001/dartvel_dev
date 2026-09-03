/// `dartvel key generate | rotate | status`: the application key, in the
/// platform key store and never the repo.
///
/// Generated per install and per user. `generate` refuses to replace a key
/// that exists -- a replaced key is every encrypted store on the machine
/// lost -- and points at `rotate`, which is the deliberate version and says
/// both fingerprints. `status` says whether there is a key, where it is
/// held and its fingerprint, never the key.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart' hide Platform;

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
      'The application key: generate, rotate or inspect it in the platform key store.';

  KeyCommand() {
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
