import 'dart:io';

import 'package:args/command_runner.dart';

import '../utils/chunked_artifact.dart';
import '../utils/logger.dart';

/// `dartvel artifact split|join` — moving large binaries through a repository.
///
/// A Flutter engine or an embedder library does not fit in git: GitHub hard-
/// blocks anything over 100 MB, and Git LFS gives 1 GB free, which two engine
/// builds exhaust. CI splits the artifact into committable chunks; this puts
/// them back together where they are used.
class ArtifactCommand extends Command<void> {
  @override
  final String name = 'artifact';

  @override
  final String description =
      'Split a large build artifact into committable chunks, or rejoin them.';

  ArtifactCommand() {
    addSubcommand(_SplitCommand());
    addSubcommand(_JoinCommand());
  }
}

class _SplitCommand extends Command<void> {
  @override
  final String name = 'split';

  @override
  final String description =
      'Split a file into chunks plus a manifest, for committing.';

  @override
  String get invocation => 'dartvel artifact split <file> --out <dir>';

  _SplitCommand() {
    argParser
      ..addOption('out',
          abbr: 'o',
          help: 'Directory to write the chunks and manifest into.',
          defaultsTo: '.')
      ..addOption('chunk-size',
          help: 'Bytes per chunk. The default is under GitHub\'s 100 MB '
              'hard block.',
          defaultsTo: '$defaultChunkSize');
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageException('Pass exactly one file to split.', invocation);
    }
    final size = int.tryParse(argResults!['chunk-size'] as String);
    if (size == null || size <= 0) {
      throw UsageException(
          'chunk-size must be a positive number of bytes.', invocation);
    }

    final out = Directory(argResults!['out'] as String);
    final manifest =
        splitArtifact(File(rest.single), into: out, chunkSize: size);
    File('${out.path}/${manifest.name}.manifest.json')
        .writeAsStringSync(manifest.toJson());

    Logger.log('Split ${manifest.name} (${manifest.totalBytes} bytes) into '
        '${manifest.parts.length} chunk(s) in ${out.path}');
    Logger.log('  sha256 ${manifest.sha256}');
  }
}

class _JoinCommand extends Command<void> {
  @override
  final String name = 'join';

  @override
  final String description = 'Rebuild a file from its chunks and manifest.';

  @override
  String get invocation => 'dartvel artifact join <manifest.json> --out <file>';

  _JoinCommand() {
    argParser.addOption('out',
        abbr: 'o',
        help: 'Where to write the rebuilt file. Defaults to the manifest\'s '
            'own name, beside it.');
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageException('Pass exactly one manifest.', invocation);
    }
    final manifestFile = File(rest.single);
    if (!manifestFile.existsSync()) {
      throw UsageException('No such manifest: ${rest.single}', invocation);
    }

    final manifest = ArtifactManifest.fromJson(manifestFile.readAsStringSync());
    final from = manifestFile.parent;
    final target = File((argResults!['out'] as String?) ??
        '${from.path}/${manifest.name}');

    // Any failure throws rather than writing a plausible-looking binary; see
    // chunked_artifact.dart for why that matters more than usual here.
    joinArtifact(manifest, from: from, into: target);
    Logger.log('Rebuilt ${target.path} '
        '(${manifest.totalBytes} bytes, sha256 verified)');
  }
}
