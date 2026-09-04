/// `dartvel import openapi <file|url>`: an API description as Dartvel source.
///
/// Dartvel writes an OpenAPI document out of an application already. This is
/// the other direction, and the one people actually start from: an API
/// exists, somebody hands you its spec, and the work is transcribing it into
/// models and calls by hand.
///
/// What it writes is ordinary source — private `@DVModel` inputs and a
/// function per operation — so the import is a starting point rather than a
/// dependency. Nothing reads the spec again afterwards.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../import/openapi_import.dart';
import '../utils/logger.dart';

class ImportCommand extends Command<void> {
  ImportCommand() {
    addSubcommand(ImportOpenApiSubcommand());
  }

  @override
  final String name = 'import';

  @override
  final String description = 'Bring an external description into the project.';
}

class ImportOpenApiSubcommand extends Command<void> {
  ImportOpenApiSubcommand() {
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

  @override
  final String name = 'openapi';

  @override
  String get description =>
      'Generate models and a typed client from an OpenAPI document.';

  @override
  String get invocation => 'dartvel import openapi <file|url>';

  @override
  Future<void> run() async {
    final List<String> rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      Logger.log('❌ Name an OpenAPI document: a file, or a URL.');
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

    final DVOpenApiImport import;
    try {
      import = dvImportOpenApi(document);
    } on FormatException catch (error) {
      Logger.log('❌ $source is not an OpenAPI document Dartvel can read: '
          '${error.message}');
      exitCode = 65; // EX_DATAERR
      return;
    }

    // Printed before anything is written. A problem found after half the
    // files are on disk reads as a bug in the import rather than as a gap in
    // the document.
    for (final String problem in import.problems) {
      Logger.log('⚠️  $problem');
    }
    if (import.sources.isEmpty) {
      Logger.log('❌ There were no schemas and no operations to import.');
      exitCode = 65;
      return;
    }

    final String root = Directory.current.path;
    final bool dryRun = argResults?['dry-run'] == true;
    final bool overwrite = argResults?['overwrite'] == true;
    final List<String> skipped = <String>[];

    for (final MapEntry<String, String> entry in import.sources.entries) {
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
      Logger.log('✅ Imported ${import.sources.length - skipped.length} file(s). '
          'Run `dartvel routes` to generate the clients for the models.');
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
