import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../graph/module_manifest.dart';
import '../graph/module_mounts.dart';
import '../utils/logger.dart';

/// `dartvel modules` — what this application mounts, and what it publishes.
class ModulesCommand extends Command<void> {
  @override
  final String name = 'modules';

  @override
  final String description = 'Inspect mounted modules and publish manifests.';

  ModulesCommand() {
    addSubcommand(_ModulesListCommand());
    addSubcommand(_ModulesManifestCommand());
  }
}

class _ModulesListCommand extends Command<void> {
  @override
  final String name = 'list';

  @override
  final String description = 'The modules this application mounts.';

  @override
  void run() {
    final List<DVModuleMount> mounts =
        dvDiscoverModuleMounts(Directory.current.path);
    if (mounts.isEmpty) {
      Logger.log('This application mounts no modules.');
      return;
    }
    for (final DVModuleMount mount in mounts) {
      Logger.log('${mount.id}  ${mount.mount}  ${mount.deployment.name}  '
          '${mount.routes.length} route(s)');
      for (final String problem in mount.problems) {
        Logger.log('  ⚠️  $problem');
      }
    }
  }
}

class _ModulesManifestCommand extends Command<void> {
  @override
  final String name = 'manifest';

  @override
  final String description =
      'Write the manifest this module publishes about itself.';

  @override
  String get invocation =>
      'dartvel modules manifest [--out path] [--key file --key-id name]';

  _ModulesManifestCommand() {
    argParser
      ..addOption('out',
          help: 'Where to write the manifest.',
          defaultsTo: 'build/module-manifest.json')
      ..addOption('key',
          help: 'A file holding the 32-byte P-256 signing key, base64url. '
              'Without it the manifest is written unsigned.')
      ..addOption('key-id',
          help: 'The name a parent knows the signing key by.');
  }

  @override
  void run() {
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

    Uint8List? key;
    if (keyPath != null) {
      final File file = File(keyPath);
      if (!file.existsSync()) {
        throw UsageException('There is no signing key at $keyPath.', invocation);
      }
      key = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(file.readAsStringSync().trim())),
      );
      if (key.length != 32) {
        throw UsageException(
          'A P-256 signing key is 32 bytes; $keyPath holds ${key.length}.',
          invocation,
        );
      }
    }

    final DVModuleManifestWrite result = dvWriteModuleManifest(
      Directory.current.path,
      out: p.normalize(p.join(Directory.current.path, out)),
      privateKey: key,
      keyId: keyId,
    );

    Logger.log('${result.manifest.id} ${result.manifest.version}: '
        '${result.manifest.routes.length} route(s) → ${result.path}');
    if (!result.signed) {
      // Said every time, because an unsigned manifest that reaches a parent
      // is refused, and finding that out at mount time is finding it out on
      // somebody else's deployment.
      Logger.log('   Unsigned. A parent will refuse it; pass --key and '
          '--key-id to publish one.');
    }
  }
}
