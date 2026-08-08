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
      'models.page.dart': _modelsPage(_discoverModels(root)),
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

  /// The models an application declared, read the same way the model
  /// generator reads them.
  ///
  /// Scanned rather than configured: an admin that had to be told which
  /// models exist would silently omit every model added afterwards.
  static List<String> _discoverModels(Directory root) {
    final modelsDir = Directory(p.join(root.path, 'lib', 'models'));
    if (!modelsDir.existsSync()) return const <String>[];
    final pattern = RegExp(
      r'@DVModel\s*\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*class\s+_([A-Za-z0-9_]+)\b',
      dotAll: true,
    );
    final names = <String>{};
    for (final entity in modelsDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final match in pattern.allMatches(entity.readAsStringSync())) {
        names.add(match.group(1)!);
      }
    }
    return names.toList(growable: false)..sort();
  }

  /// The model CRUD page, one section per declared model.
  static String _modelsPage(List<String> models) {
    final buffer = StringBuffer()
      ..writeln("import '../../dartvel_client/dartvel_client.dart';")
      ..writeln("import 'package:flutter/widgets.dart';")
      ..writeln()
      ..writeln("@DVPage(title: 'Dartvel Models', path: '/_dartvel_admin/models')")
      ..writeln("@pragma('vm:entry-point')")
      ..writeln('Widget _dartvelAdminModelsPage(BuildContext context) => '
          'buildDartvelAdminModelsPage(context);')
      ..writeln()
      ..writeln('Widget buildDartvelAdminModelsPage(BuildContext context) => '
          'DVBox.list([');
    buffer.writeln("    const DVText('Models').modifier(");
    buffer.writeln('      const DVModifier().fontSize(24)'
        '.fontWeight(FontWeight.bold),');
    buffer.writeln('    ),');
    if (models.isEmpty) {
      // An app with no models is a real state, and an empty page with no
      // explanation reads as a broken one.
      buffer.writeln("    const DVText('No @DVModel classes found in "
          "lib/models.'),");
    }
    for (final model in models) {
      buffer.writeln('    $model.Admin(),');
    }
    buffer.writeln('  ]).modifier(const DVModifier().padding(24));');
    return buffer.toString();
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
      dartvelAdminCard(context, 'Models', '/_dartvel_admin/models'),
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

/// Jobs are stored per queue and nothing enumerates the names, so an
/// application lists the queues it dispatches to here.
const List<String> dartvelAdminQueues = <String>['default'];

Widget buildDartvelAdminQueuesPage(BuildContext context) =>
    const DVBox(DVQueueAdmin(queues: dartvelAdminQueues))
        .modifier(const DVModifier().padding(24));
'''; 

  static const String _cachePage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Cache', path: '/_dartvel_admin/cache')
@pragma('vm:entry-point')
Widget _dartvelAdminCachePage(BuildContext context) => buildDartvelAdminCachePage(context);

Widget buildDartvelAdminCachePage(BuildContext context) =>
    const DVBox(DVCacheAdmin()).modifier(const DVModifier().padding(24));
''';

  static const String _routesPage = '''
import '../../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Dartvel Routes', path: '/_dartvel_admin/routes')
@pragma('vm:entry-point')
Widget _dartvelAdminRoutesPage(BuildContext context) => buildDartvelAdminRoutesPage(context);

/// Reads the generated manifest rather than a hand-kept list, so a page added
/// later shows up here without anyone remembering to register it.
Widget buildDartvelAdminRoutesPage(BuildContext context) =>
    const DVBox(DVRouteAdmin(routes: dartvelRouteManifest))
        .modifier(const DVModifier().padding(24));
''';
}
