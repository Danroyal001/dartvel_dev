import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

class AdminCommand extends Command<void> {
  @override
  final String name = 'admin';

  @override
  String get description => 'Generate Dartvel admin surfaces.';

  AdminCommand() {
    addSubcommand(AdminGenerateCommand());
  }
}

class AdminGenerateCommand extends Command<void> {
  @override
  final String name = 'generate';

  @override
  String get description => 'Generate Dartvel admin and devtools pages.';

  AdminGenerateCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      defaultsTo: false,
      help: 'Overwrite generated admin files.',
    );
  }

  @override
  void run() {
    final result = DartvelAdminGenerator.generate(
      root: Directory.current,
      force: argResults?['force'] == true,
    );
    for (final file in result.writtenFiles) {
      stdout.writeln(
          'generated ${p.relative(file.path, from: Directory.current.path)}');
    }
    if (result.skippedFiles.isNotEmpty) {
      for (final file in result.skippedFiles) {
        stdout.writeln(
            'exists ${p.relative(file.path, from: Directory.current.path)}');
      }
    }
  }
}

class DevtoolsCommand extends Command<void> {
  @override
  final String name = 'devtools';

  @override
  String get description =>
      'Generate and open Dartvel devtools metadata pages.';

  DevtoolsCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      defaultsTo: false,
      help: 'Overwrite generated devtools files.',
    );
  }

  @override
  void run() {
    final result = DartvelAdminGenerator.generate(
      root: Directory.current,
      force: argResults?['force'] == true,
    );
    stdout.writeln('Dartvel devtools generated at /_dartvel_admin');
    stdout.writeln('Run dartvel dev and open /_dartvel_admin in the app.');
    stdout.writeln(
        'files=${result.writtenFiles.length}, skipped=${result.skippedFiles.length}');
  }
}

class DartvelAdminGenerationResult {
  final List<File> writtenFiles;
  final List<File> skippedFiles;

  const DartvelAdminGenerationResult({
    required this.writtenFiles,
    required this.skippedFiles,
  });
}

class DartvelAdminGenerator {
  const DartvelAdminGenerator._();

  static DartvelAdminGenerationResult generate({
    required Directory root,
    required bool force,
  }) {
    final adminDir =
        Directory(p.join(root.path, 'lib', 'pages', '_dartvel_admin'))
          ..createSync(recursive: true);
    final files = <String, String>{
      'index.page.dart': _indexPage,
      'queues.page.dart': _queuesPage,
      'cache.page.dart': _cachePage,
      'routes.page.dart': _routesPage,
      'studio.page.dart': _studioPage,
    };
    final written = <File>[];
    final skipped = <File>[];
    for (final entry in files.entries) {
      final file = File(p.join(adminDir.path, entry.key));
      if (file.existsSync() && !force) {
        skipped.add(file);
        continue;
      }
      file.writeAsStringSync(entry.value);
      written.add(file);
    }
    return DartvelAdminGenerationResult(
      writtenFiles: List<File>.unmodifiable(written),
      skippedFiles: List<File>.unmodifiable(skipped),
    );
  }

  static const String _indexPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Admin', path: '/_dartvel_admin')
@pragma('vm:entry-point')
Widget _dartvelAdminIndexPage(BuildContext context) => buildDartvelAdminIndexPage(context);

Widget buildDartvelAdminIndexPage(BuildContext context) => DVBox.list([
    const DVText('Dartvel Admin').modifier(
      const DVModifier().fontSize(28).fontWeight(FontWeight.bold),
    ),
    DVText('Generated model, route, queue, cache, policy, and notification tools.'),
    DVBox.grid([
      dartvelAdminCard(context, 'Studio', '/_dartvel_admin/studio'),
      dartvelAdminCard(context, 'Queues and Jobs', '/_dartvel_admin/queues'),
      dartvelAdminCard(context, 'Cache Tags', '/_dartvel_admin/cache'),
      dartvelAdminCard(context, 'Routes and Pages', '/_dartvel_admin/routes'),
    ], columns: 2),
  ]).modifier(const DVModifier().padding(24));

/// A card that opens the surface it names. Cards that named a page without
/// going to it left the admin unnavigable.
Widget dartvelAdminCard(BuildContext context, String label, String path) =>
    DVBox(DVText(label)).modifier(
      const DVModifier().card().padding(16).semanticButton().onTap(
        () => context.navigateToPage(DVRouteTarget(path)),
      ),
    );
''';

  static const String _studioPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Studio', path: '/_dartvel_admin/studio')
@pragma('vm:entry-point')
Widget _dartvelAdminStudioPage(BuildContext context) => buildDartvelAdminStudioPage(context);

/// The page builder itself. DVStudioScreen is a tested widget in
/// dartvel_flutter rather than source emitted here, so what the generator
/// writes cannot drift from the editor it opens.
Widget buildDartvelAdminStudioPage(BuildContext context) => const DVStudioScreen();
''';

  static const String _queuesPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Queues', path: '/_dartvel_admin/queues')
@pragma('vm:entry-point')
Widget _dartvelAdminQueuesPage(BuildContext context) => buildDartvelAdminQueuesPage(context);

Widget buildDartvelAdminQueuesPage(BuildContext context) => DVBox.list([
    const DVText('Queues and Jobs').modifier(
      const DVModifier().fontSize(24).fontWeight(FontWeight.bold),
    ),
    DVText('Inspect pending jobs, failed jobs, retries, and worker health.'),
    DVBox.row([
      const DVBox(DVText('Pending jobs')).modifier(const DVModifier().card().padding(16)),
      const DVBox(DVText('Failed jobs')).modifier(const DVModifier().card().padding(16)),
      const DVBox(DVText('Workers')).modifier(const DVModifier().card().padding(16)),
    ]),
  ]).modifier(const DVModifier().padding(24));
''';

  static const String _cachePage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Cache', path: '/_dartvel_admin/cache')
@pragma('vm:entry-point')
Widget _dartvelAdminCachePage(BuildContext context) => buildDartvelAdminCachePage(context);

Widget buildDartvelAdminCachePage(BuildContext context) => DVBox.list([
    const DVText('Cache Tags').modifier(
      const DVModifier().fontSize(24).fontWeight(FontWeight.bold),
    ),
    DVText('Inspect cache tags, keys, revalidation, and stale-while-revalidate state.'),
    DVBox.row([
      const DVBox(DVText('Tagged keys')).modifier(const DVModifier().card().padding(16)),
      const DVBox(DVText('Revalidation')).modifier(const DVModifier().card().padding(16)),
      const DVBox(DVText('Locks')).modifier(const DVModifier().card().padding(16)),
    ]),
  ]).modifier(const DVModifier().padding(24));
''';

  static const String _routesPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Routes', path: '/_dartvel_admin/routes')
@pragma('vm:entry-point')
Widget _dartvelAdminRoutesPage(BuildContext context) => buildDartvelAdminRoutesPage(context);

Widget buildDartvelAdminRoutesPage(BuildContext context) => DVBox.list([
    const DVText('Routes and Pages').modifier(
      const DVModifier().fontSize(24).fontWeight(FontWeight.bold),
    ),
    DVText('Inspect generated route metadata, deferred pages, policies, and middleware.'),
    DVBox.row([
      const DVBox(DVText('Pages')).modifier(const DVModifier().card().padding(16)),
      const DVBox(DVText('Middleware')).modifier(const DVModifier().card().padding(16)),
      const DVBox(DVText('Policies')).modifier(const DVModifier().card().padding(16)),
    ]),
  ]).modifier(const DVModifier().padding(24));
''';
}
