/// The one file the build writes into the admin root.
///
/// Everything around this existed already: `dvAdminMount` decides whether a
/// build has an admin and where it is mounted, `dvAdminFor` decides whether a
/// request may see it and answers a hidden one with the same nothing a
/// nonexistent route gets, and the web server serves files out of the admin
/// root.
///
/// This wrote four files. Three of them were a dashboard: a page, a stylesheet
/// and a script, authored here, hand-written HTML in a build step. The very
/// next step of the same build compiled `DVStudioApp` into this root and
/// deleted all three by name -- `index.html`, `admin.css`, `admin.js` -- so
/// they were written and thrown away in one function and could never be
/// opened by anybody. A build that authors a UI it never serves is two UIs for
/// one thing, one of which is dead on arrival, so the page is gone and what
/// was left is data.
///
/// `graph.json` is what survives, because three things read it and none of
/// them is a file on disk: Studio's site map, task and module sections fetch
/// it at runtime through `DVStudioClient.manifest()`, and the backend takes
/// its worker queue names from it through `dvAdminGraphQueues`. The columns
/// those sections show moved into `dartvel_flutter` with the sections that
/// read them, and the test here now holds the producer side of that contract
/// -- that a real `DartvelProjectGraph` has the keys its readers ask for --
/// because the CLI does not depend on the package that reads them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvStudioStructureDirectory;

/// The files to write under the admin root, by path relative to it.
///
/// [graph] is `DartvelProjectGraph.toJson()` -- the whole application, not
/// one build target. There is one Studio per application and it manages every
/// platform that application ships to, so nothing here is per-target and the
/// graph has no target in it to be.
///
/// Written back byte for byte rather than reshaped. A builder that rearranged
/// it would be a second definition of the graph, and the two would disagree
/// the first time either changed.
Map<String, String> dvAdminArtifact({required Map<String, Object?> graph}) {
  return <String, String>{
    'graph.json': const JsonEncoder.withIndent('  ').convert(graph),
  };
}

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

