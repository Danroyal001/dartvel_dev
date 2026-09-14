import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../graph/module_manifest.dart';
import '../graph/module_mounts.dart';
import '../module_trust/module_lock.dart';
import '../module_trust/module_publish.dart';
import '../module_trust/module_trust.dart';
import '../module_trust/package_digest.dart';
import '../utils/logger.dart';

/// Runs a process; replaceable so a test can see what would have run.
typedef ModulesProcessRun =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
    });

Future<ProcessResult> _defaultRun(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell = false,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  runInShell: runInShell,
);

/// `dartvel modules` — what this application mounts, and what it publishes.
class ModulesCommand extends Command<void> {
  @override
  final String name = 'modules';

  @override
  final String description =
      'Inspect mounted modules, publish a signed module, and pin what is '
      'mounted.';

  /// [root] is the project the subcommands act on; the current directory
  /// when null, read when a subcommand runs rather than when this is built.
  ModulesCommand({String? root, ModulesProcessRun? processRun}) {
    String rootOf() => root ?? Directory.current.path;
    addSubcommand(_ModulesListCommand(rootOf));
    addSubcommand(_ModulesManifestCommand(rootOf));
    addSubcommand(_ModulesPublishCommand(rootOf, processRun ?? _defaultRun));
    addSubcommand(_ModulesPinCommand(rootOf));
  }
}

/// The 32-byte P-256 signing key in the file at [path], base64url.
Uint8List _readSigningKey(String root, String path, String invocation) {
  final File file = File(p.normalize(p.join(root, path)));
  if (!file.existsSync()) {
    throw UsageException('There is no signing key at $path.', invocation);
  }
  final Uint8List key;
  try {
    key = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(file.readAsStringSync().trim())),
    );
  } on FormatException {
    throw UsageException('$path does not hold a base64url key.', invocation);
  }
  if (key.length != 32) {
    throw UsageException(
      'A P-256 signing key is 32 bytes; $path holds ${key.length}.',
      invocation,
    );
  }
  return key;
}

class _ModulesListCommand extends Command<void> {
  _ModulesListCommand(this._root);

  final String Function() _root;

  @override
  final String name = 'list';

  @override
  final String description = 'The modules this application mounts.';

  @override
  void run() {
    final List<DVModuleMount> mounts = dvDiscoverModuleMounts(_root());
    if (mounts.isEmpty) {
      Logger.log('This application mounts no modules.');
      return;
    }
    for (final DVModuleMount mount in mounts) {
      Logger.log(
        '${mount.id}  ${mount.mount}  ${mount.deployment.name}  '
        '${mount.routes.length} route(s)',
      );
      for (final String problem in mount.problems) {
        Logger.log('  ⚠️  $problem');
      }
    }
  }
}

class _ModulesManifestCommand extends Command<void> {
  _ModulesManifestCommand(this._root) {
    argParser
      ..addOption(
        'out',
        help: 'Where to write the manifest.',
        defaultsTo: 'build/module-manifest.json',
      )
      ..addOption(
        'key',
        help:
            'A file holding the 32-byte P-256 signing key, base64url. '
            'Without it the manifest is written unsigned.',
      )
      ..addOption(
        'key-id',
        help: 'The name a parent knows the signing key by.',
      );
  }

  final String Function() _root;

  @override
  final String name = 'manifest';

  @override
  final String description =
      'Write the manifest this module publishes about itself.';

  @override
  String get invocation =>
      'dartvel modules manifest [--out path] [--key file --key-id name]';

  @override
  void run() {
    final String root = _root();
    final String out = argResults!['out'] as String;
    final String? keyPath = argResults!['key'] as String?;
    final String? keyId = argResults!['key-id'] as String?;

    if ((keyPath == null) != (keyId == null)) {
      // Half a signature is not a signature: a key with no id cannot be
      // looked up by the parent, and an id with no key signs nothing.
      throw UsageException(
        'Signing needs both --key and --key-id.',
        invocation,
      );
    }

    final Uint8List? key = keyPath == null
        ? null
        : _readSigningKey(root, keyPath, invocation);

    final DVModuleManifestWrite result = dvWriteModuleManifest(
      root,
      out: p.normalize(p.join(root, out)),
      privateKey: key,
      keyId: keyId,
    );

    Logger.log(
      '${result.manifest.id} ${result.manifest.version}: '
      '${result.manifest.routes.length} route(s) → ${result.path}',
    );
    final String? trust = result.trustDeclaration;
    if (trust != null) {
      // What the parent has to add to accept it. Signing without a way to
      // learn the public key leaves the publisher with a manifest nobody
      // can be told to trust.
      Logger.log('   The parent trusts this publisher with:');
      Logger.log('     dartvel.modules.${result.manifest.id}.$trust');
    }
    if (!result.signed) {
      // Said every time, because an unsigned manifest that reaches a parent
      // is refused, and finding that out at mount time is finding it out on
      // somebody else's deployment.
      Logger.log(
        '   Unsigned. A parent will refuse it; pass --key and '
        '--key-id to publish one.',
      );
    }
  }
}

/// `dartvel modules publish`: derive the capabilities, refuse a manifest that
/// disagrees with the code, sign, then `dart pub publish`.
class _ModulesPublishCommand extends Command<void> {
  _ModulesPublishCommand(this._root, this._processRun) {
    argParser
      ..addOption(
        'key',
        help: 'A file holding the 32-byte P-256 signing key, base64url.',
      )
      ..addOption('key-id', help: 'Your name for the signing key.')
      ..addOption(
        'publisher',
        help:
            'The verified pub.dev publisher, as a claim. Parents never '
            'trust it for itself: they pin what the registry verifies.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Sign, then run dart pub publish --dry-run.',
      )
      ..addFlag(
        'sign-only',
        negatable: false,
        help: 'Sign, and leave publishing to you.',
      );
  }

  final String Function() _root;
  final ModulesProcessRun _processRun;

  @override
  final String name = 'publish';

  @override
  final String description =
      'Check a module\'s declared capabilities against its code, sign it, and '
      'publish it to pub.dev.';

  @override
  String get invocation =>
      'dartvel modules publish --key file --key-id name [--publisher domain] '
      '[--dry-run | --sign-only]';

  @override
  Future<void> run() async {
    final String root = _root();
    final String? keyPath = argResults!['key'] as String?;
    final String? keyId = argResults!['key-id'] as String?;
    if (keyPath == null || keyId == null) {
      // A module is signed by its publisher. An unsigned one is refused by
      // every parent that mounts it as a dependency, so publishing one would
      // be publishing something nobody can use.
      throw UsageException(
        'Publishing a module signs it, and signing needs --key and --key-id.',
        invocation,
      );
    }
    final Uint8List key = _readSigningKey(root, keyPath, invocation);

    final DVModulePublishResult result = dvPrepareModulePublish(
      root,
      privateKey: key,
      keyId: keyId,
      publisher: argResults!['publisher'] as String?,
    );
    if (!result.ok) {
      for (final DVModuleTrustFinding finding in result.findings) {
        Logger.error('   $finding');
      }
      Logger.log('❌ Not published: the manifest and the code disagree.');
      exitCode = 1;
      return;
    }

    Logger.log(
      '🔏 Signed ${result.statement!.package} '
      '${result.statement!.version}: sha256 ${result.statement!.sha256}',
    );
    Logger.log(
      '   Key fingerprint ${result.fingerprint}. Parents pin this '
      'key on first use.',
    );
    Logger.log(
      '   $dvModuleSignatureFile must be published with the package: '
      'keep it out of .gitignore and .pubignore.',
    );
    if (argResults!['sign-only'] == true) return;

    final ProcessResult published = await _processRun('dart', <String>[
      'pub',
      'publish',
      if (argResults!['dry-run'] == true) '--dry-run',
    ], workingDirectory: root);
    if (published.exitCode != 0) {
      Logger.error('${published.stderr}'.trim());
      Logger.log('❌ dart pub publish exited ${published.exitCode}.');
      exitCode = published.exitCode;
    }
  }
}

/// `dartvel modules pin`: trust on first use, and the explicit re-pin.
class _ModulesPinCommand extends Command<void> {
  _ModulesPinCommand(this._root) {
    argParser.addFlag(
      'allow-downgrade',
      negatable: false,
      help:
          'Pin a version older than the current pin. Without it, a '
          'rollback is refused.',
    );
  }

  final String Function() _root;

  @override
  final String name = 'pin';

  @override
  final String description =
      'Pin the version, digest, signing key and publisher of mounted modules '
      'into dartvel.module.lock.';

  @override
  String get invocation =>
      'dartvel modules pin [module id ...] [--allow-downgrade]';

  @override
  void run() {
    final List<String> ids = argResults!.rest;
    final DVModulePinResult result = dvPinModules(
      _root(),
      only: ids.isEmpty ? null : ids.toSet(),
      allowDowngrade: argResults!['allow-downgrade'] == true,
    );
    for (final String line in result.pinned) {
      Logger.log('📌 $line');
    }
    for (final DVModuleTrustFinding finding in result.refused) {
      Logger.error('   $finding');
    }
    if (!result.ok) {
      Logger.log('❌ ${result.refused.length} module(s) not pinned.');
      exitCode = 1;
      return;
    }
    if (result.pinned.isEmpty) {
      Logger.log('Nothing to pin.');
    } else {
      Logger.log(
        '   Commit $dvModuleLockFile. Pinning is identity, not '
        'permission: run dartvel doctor --modules to compare the grants.',
      );
    }
  }
}
