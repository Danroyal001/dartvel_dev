/// What a build leaves in build/web, without the indentation.
///
/// `dartvel build web` and `dartvel build web-server` both finish by writing
/// HTML, CSS and JavaScript that a reader downloads on the first request. The
/// pass here takes the whitespace and the comments back out of them. The
/// web-server target is covered by the same pass: it renders a page from
/// build/web/index.html on request, so a minified shell is a minified page.
///
/// It is deliberately a whitespace-and-comments minifier and not a compressor.
/// It does not rename a variable, fold a constant or drop dead code, because
/// doing any of that safely needs a parser for the whole language and the
/// files it is pointed at are small: a shell, a service worker, a stylesheet.
/// The one file where compression would pay -- main.dart.js -- arrives already
/// minified by dart2js and is skipped.
///
/// Every scanner here is written around the cases where a wrong answer still
/// looks like the language: a descendant selector whose space was taken, a
/// `calc()` whose operators lost theirs, a `//` inside a string read as a
/// comment, two statements joined across the newline that was standing in for
/// a semicolon. A minifier that throws is a bug that gets fixed; one that
/// silently changes what a page means is a bug that ships.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvMinifyCss, dvMinifyHtml, dvMinifyJs;
import 'package:path/path.dart' as p;

export 'package:dartvel_core/dartvel.dart' show dvMinifyCss, dvMinifyHtml, dvMinifyJs;

/// What a pass over a built web output changed.
class DVMinifyReport {
  const DVMinifyReport({required this.files, required this.saved});

  /// How many files were rewritten. A file that was already as small as the
  /// pass can make it is not counted, because it was not touched.
  final int files;

  /// Bytes the rewritten files no longer carry.
  final int saved;

  /// Nothing to report, for a build that asked not to be minified.
  static const DVMinifyReport none = DVMinifyReport(files: 0, saved: 0);
}

/// Minifies every page, stylesheet and script under [web] that the build
/// itself wrote, and reports what that came to.
///
/// What it leaves alone is as much of the contract as what it rewrites: the
/// compiler's own output, which dart2js has already minified and which is
/// large enough that a second pass could only cost time or correctness, and
/// the application's bundled assets, which are its files rather than the
/// page's -- a `.css` under assets/ may be a sample the app reads back and
/// compares.
DVMinifyReport dvMinifyWebOutput(Directory web) {
  if (!web.existsSync()) return DVMinifyReport.none;
  int files = 0;
  int saved = 0;

  for (final FileSystemEntity entity in web.listSync(recursive: true)) {
    if (entity is! File) continue;
    final String relative = p.relative(entity.path, from: web.path);
    if (_leaveAlone(relative)) continue;
    final String extension = p.extension(relative).toLowerCase();

    String source;
    try {
      source = entity.readAsStringSync();
    } on FileSystemException {
      // Not text, whatever it is named. A build that stops here has minified
      // nothing and broken something.
      continue;
    } on FormatException {
      continue;
    }

    final String minified = switch (extension) {
      '.html' || '.htm' => dvMinifyHtml(source),
      '.css' => dvMinifyCss(source),
      '.js' || '.mjs' => dvMinifyJs(source),
      _ => source,
    };
    if (minified.length >= source.length) continue;

    entity.writeAsStringSync(minified);
    files++;
    saved += source.length - minified.length;
  }
  return DVMinifyReport(files: files, saved: saved);
}

/// The build's own step: build/web under [root], minified unless [enabled] is
/// false.
///
/// Both web targets go through it. `dartvel build web` writes a file per route
/// and this is the last thing to touch them; `dartvel build web-server` builds
/// its pages from build/web/index.html on request, so minifying the shell
/// minifies every page the server will ever answer with.
DVMinifyReport dvMinifyBuildOutput(String root, {bool enabled = true}) {
  if (!enabled) return DVMinifyReport.none;
  return dvMinifyWebOutput(Directory(p.join(root, 'build', 'web')));
}

/// [report] as the build prints it.
String dvMinifySummary(DVMinifyReport report) {
  if (report.files == 0) return 'Nothing left to minify.';
  final String files = report.files == 1 ? '1 file' : '${report.files} files';
  final String size = report.saved < 1024
      ? '${report.saved} bytes'
      : '${(report.saved / 1024).toStringAsFixed(1)} KB';
  return 'Minified $files, $size smaller.';
}

/// Whether [relative] is a file the pass does not own.
bool _leaveAlone(String relative) {
  final List<String> parts = p.split(relative);
  // The application's own files, and the engine's.
  if (parts.first == 'assets') return true;
  if (parts.contains('canvaskit') || parts.contains('skwasm')) return true;

  final String name = parts.last;
  if (name.endsWith('.min.js') || name.endsWith('.min.css')) return true;
  // dart2js output, including the deferred parts it splits off.
  if (name.startsWith('main.dart.')) return true;
  // The loader and the bootstrap belong to the Flutter tool.
  // flutter_service_worker.js is not in this list on purpose: the name is
  // Flutter's, the file is Dartvel's, written over theirs by the PWA pass.
  if (name == 'flutter.js' || name == 'flutter_bootstrap.js') return true;
  return false;
}
