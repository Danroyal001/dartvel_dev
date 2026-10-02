/// What a build keeps for Studio: its data, never a page.
///
/// Studio is routes of the application, rendered by the server like every
/// other page, and its code is the application's deferred Studio library. What
/// a build writes for it beside that is only what Studio reads through its
/// API, behind the Studio grant: the project graph -- the application's
/// routes, functions, jobs and modules -- and each page's captured
/// structure. None of it is a document, and none of it is served as a file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvStudioStructureDirectory;

/// The files of Studio's data, by path under its data root.
///
/// [graph] is `DartvelProjectGraph.toJson()`, written back byte for byte
/// rather than reshaped: a builder that rearranged it would be a second
/// definition of the graph, and the two would disagree the first time either
/// changed.
Map<String, String> dvStudioData({required Map<String, Object?> graph}) =>
    <String, String>{
      'graph.json': const JsonEncoder.withIndent('  ').convert(graph),
    };

/// Copies each route's captured semantics tree from [semantics] into the
/// admin root's `structure` directory, where Studio's site endpoint reads
/// it, and answers how many it copied.
///
/// The trees are the ones the build already captured for the crawler HTML;
/// the prefetch lists beside them are not structure and stay behind. The
/// directory is emptied first, so a page that no longer exists is not
/// opened from a tree an earlier build left.
int dvCopyPageStructures({
  required String semantics,
  required String adminRoot,
}) {
  final Directory source = Directory(semantics);
  final Directory target = Directory(
    '$adminRoot${Platform.pathSeparator}$dvStudioStructureDirectory',
  );
  if (target.existsSync()) target.deleteSync(recursive: true);
  if (!source.existsSync()) return 0;
  target.createSync(recursive: true);
  int copied = 0;
  for (final FileSystemEntity entity in source.listSync()) {
    if (entity is! File) continue;
    final String name = entity.uri.pathSegments.last;
    if (!name.endsWith('.json') || name.endsWith('.images.json')) continue;
    entity.copySync('${target.path}${Platform.pathSeparator}$name');
    copied++;
  }
  return copied;
}
