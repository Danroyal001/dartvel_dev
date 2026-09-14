import 'dart:io';

import 'package:args/command_runner.dart';

import '../docs/docs_server.dart';
import '../docs/docs_site.dart';

/// Builds the documentation site for [root] into [output]. Returns the exit
/// code: 0, 1 when [fatalWarnings] is set and the build found drift, 2 when
/// it could not build or write.
///
/// Separated from the command so it can be tested without a CommandRunner.
Future<int> runDocs(
  String root, {
  String output = 'build/docs',
  bool fatalWarnings = false,
  void Function(String line) out = print,
}) async {
  final DVDocsSite site;
  try {
    site = await dvDocsBuildInto(
      root,
      dvDocsOutputPath(root, output),
      out: out,
    );
  } on StateError catch (error) {
    out('dartvel docs: ${error.message}');
    return 2;
  }
  if (fatalWarnings && site.findings.isNotEmpty) {
    out(
      'dartvel docs: failing on ${site.findings.length} warning(s) '
      '(--fatal-warnings)',
    );
    return 1;
  }
  return 0;
}

/// `dartvel docs`: the project's own reference, rendered from the project
/// graph -- models, functions, routes, jobs and cron, policies, modules,
/// the diagnostics glossary and the decision records that name them.
class DocsCommand extends Command<void> {
  DocsCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        defaultsTo: 'build/docs',
        help: 'Where to write the site, relative to the project.',
      )
      ..addFlag(
        'serve',
        negatable: false,
        help:
            'Serve the site on loopback and rebuild it when the project '
            'changes.',
      )
      ..addOption('port', defaultsTo: '4180', help: 'The port for --serve.')
      ..addFlag(
        'fatal-warnings',
        negatable: false,
        help:
            'Exit non-zero when a decision names a node that is gone '
            '(DV-DOCS-001) or a node cannot be mapped to its source '
            '(DV-DOCS-002).',
      );
  }

  @override
  final String name = 'docs';

  @override
  final String description =
      'Build the documentation site from the project graph.';

  @override
  String get invocation =>
      'dartvel docs [--output build/docs] [--serve [--port 4180]] [--fatal-warnings]';

  @override
  Future<void> run() async {
    final String root = Directory.current.path;
    final String output = argResults!.option('output')!;
    if (argResults!.flag('serve')) {
      final int? port = int.tryParse(argResults!.option('port')!);
      if (port == null || port < 0 || port > 65535) {
        throw UsageException('--port must be a port number.', invocation);
      }
      final DVDocsServer server;
      try {
        server = await DVDocsServer.start(
          root: root,
          output: output,
          port: port,
        );
      } on StateError catch (error) {
        stderr.writeln('dartvel docs: ${error.message}');
        exitCode = 2;
        return;
      }
      await ProcessSignal.sigint.watch().first;
      await server.close();
      return;
    }
    exitCode = await runDocs(
      root,
      output: output,
      fatalWarnings: argResults!.flag('fatal-warnings'),
    );
  }
}
