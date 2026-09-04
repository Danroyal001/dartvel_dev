/// Checks the pages a server rendered for a crawler.
///
///     dart tool/ci/prerendered_pages_check.dart /tmp/diag 4
///
/// Three things, and each of them has been wrong at some point. There have to
/// be as many pages as routes asked for; no two of them may share a title,
/// because that is what a server rendering one page for every route looks
/// like; and each has to carry text inside its noscript, because a page that
/// renders only under JavaScript is a page a crawler sees empty.
library;

import 'dart:io';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

int _run(List<String> arguments) {
  final String directory = arguments.isEmpty ? '/tmp/diag' : arguments.first;
  final int expected =
      arguments.length > 1 ? int.tryParse(arguments[1]) ?? 4 : 4;

  final List<File> files = Directory(directory)
      .listSync()
      .whereType<File>()
      .where((File f) {
        final String name = f.uri.pathSegments.last;
        return name.startsWith('page') && name.endsWith('.html');
      })
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  final List<String?> titles = <String?>[];
  int failures = 0;
  for (final File file in files) {
    final String html = file.readAsStringSync();
    final String? title = RegExp(r'<title>(.*?)</title>', dotAll: true)
        .firstMatch(html)
        ?.group(1)
        ?.trim();
    final int noscript = RegExp(r'<noscript>(.*?)</noscript>', dotAll: true)
            .firstMatch(html)
            ?.group(1)
            ?.length ??
        0;
    titles.add(title);
    stdout.writeln('${file.path.padRight(34)} '
        '${(title ?? 'null').padRight(34)} noscript:$noscript');
    if (noscript == 0) {
      stdout.writeln('::error::a route came back with no crawler-visible text');
      failures++;
    }
  }

  if (files.length != expected) {
    stdout.writeln('::error::expected $expected pages, got ${files.length}');
    failures++;
  }
  if (titles.toSet().length != titles.length) {
    stdout.writeln('::error::two routes share a title, so they are not being '
        'rendered per route: $titles');
    failures++;
  }
  return failures == 0 ? 0 : 1;
}
