/// `dartvel import <kind> <file|url>`: somebody else's API as Dartvel source.
///
/// Dartvel writes an OpenAPI document out of an application already. This is
/// the other direction, and the one people actually start from: an API
/// exists, somebody hands you its spec — or, just as often, their Postman
/// collection — and the work is transcribing it into models and calls by
/// hand.
///
/// What it writes is ordinary source, so the import is a starting point
/// rather than a dependency. Nothing reads the document again afterwards.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../import/openapi_import.dart';
import '../import/postman_import.dart';
import '../utils/logger.dart';

class ImportCommand extends Command<void> {
  ImportCommand() {
    addSubcommand(ImportOpenApiSubcommand());
    addSubcommand(ImportPostmanSubcommand());
  }

  @override
  final String name = 'import';

  @override
  final String description = 'Bring an external description into the project.';
}

/// What a document turned into: files to write, and what could not be read.
typedef DVImportResult = ({Map<String, String> sources, List<String> problems});

/// The half of an import that is the same whatever the document is.
///
/// Reading a file or a URL, writing what came out, leaving alone what is
/// already there. Only the parsing differs between kinds, so only the parsing
/// is overridden — two copies of the overwrite rule would be two chances to
/// get it wrong, and the one that got it wrong would destroy somebody's work.
abstract class DVImportSubcommand extends Command<void> {
  DVImportSubcommand() {
    argParser
      ..addFlag('dry-run',
          defaultsTo: false,
          negatable: false,
          help: 'List what would be written, and write nothing.')
      ..addFlag('overwrite',
          defaultsTo: false,
          negatable: false,
          help: 'Replace files that are already there.');
  }

  /// What this kind of document is called, with its article, for the
  /// messages -- "a Postman collection", "an OpenAPI document".
  String get documentKind;

  /// Reads [document]. Throws [FormatException] when it cannot.
  DVImportResult parse(String document);

  @override
  String get invocation => 'dartvel import $name <file|url>';

  @override
  Future<void> run() async {
    final List<String> rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      Logger.log('❌ Name $documentKind: a file, or a URL.');
      exitCode = 64; // EX_USAGE
      return;
    }

    final String source = rest.first;
    final String document;
    try {
      document = await _read(source);
    } on Object catch (error) {
      Logger.log('❌ Could not read $source: $error');
      exitCode = 66; // EX_NOINPUT
      return;
    }

    final DVImportResult result;
    try {
      result = parse(document);
    } on FormatException catch (error) {
      Logger.log('❌ $source is not $documentKind Dartvel can read: '
          '${error.message}');
      exitCode = 65; // EX_DATAERR
      return;
    }

    // Printed before anything is written. A problem found after half the
    // files are on disk reads as a bug in the import rather than as a gap in
    // the document.
    for (final String problem in result.problems) {
      Logger.log('⚠️  $problem');
    }
    if (result.sources.isEmpty) {
      Logger.log('❌ There was nothing in $source to import.');
      exitCode = 65;
      return;
    }

    final String root = Directory.current.path;
    final bool dryRun = argResults?['dry-run'] == true;
    final bool overwrite = argResults?['overwrite'] == true;
    final List<String> skipped = <String>[];

    for (final MapEntry<String, String> entry in result.sources.entries) {
      final File file = File(p.join(root, entry.key));
      if (file.existsSync() && !overwrite) {
        skipped.add(entry.key);
        continue;
      }
      Logger.log('   ${dryRun ? 'would write' : 'writing'} ${entry.key}');
      if (dryRun) continue;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }

    if (skipped.isNotEmpty) {
      // Never silently: an import that overwrote a file somebody had edited
      // would be the last time they ran it.
      Logger.log('⚠️  Left alone, because they are already there: '
          '${skipped.join(', ')}');
      Logger.log('   Pass --overwrite to replace them.');
    }
    if (!dryRun) {
      Logger.log('✅ Imported ${result.sources.length - skipped.length} '
          'file(s). Run `dartvel routes` to generate the clients for the '
          'models.');
    }
  }

  Future<String> _read(String source) async {
    final Uri? url = Uri.tryParse(source);
    if (url != null && (url.scheme == 'http' || url.scheme == 'https')) {
      // dart:io rather than package:http. The CLI does not depend on http
      // today, and one GET is not worth a dependency the whole tool then
      // carries.
      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest request = await client.getUrl(url);
        final HttpClientResponse response = await request.close();
        if (response.statusCode != 200) {
          throw StateError('the server answered ${response.statusCode}');
        }
        return await utf8.decodeStream(response);
      } finally {
        client.close();
      }
    }
    return File(source).readAsStringSync();
  }
}

class ImportOpenApiSubcommand extends DVImportSubcommand {
  @override
  final String name = 'openapi';

  @override
  String get description =>
      'Generate models and a typed client from an OpenAPI document.';

  @override
  String get documentKind => 'an OpenAPI document';

  @override
  DVImportResult parse(String document) {
    final DVOpenApiImport imported = dvImportOpenApi(document);
    return (sources: imported.sources, problems: imported.problems);
  }
}

class ImportPostmanSubcommand extends DVImportSubcommand {
  @override
  final String name = 'postman';

  @override
  String get description =>
      'Generate a typed client from a Postman collection export.';

  @override
  String get documentKind => 'a Postman collection';

  @override
  DVImportResult parse(String document) {
    final DVPostmanImport imported = dvImportPostman(document);
    return (sources: imported.sources, problems: imported.problems);
  }
}
