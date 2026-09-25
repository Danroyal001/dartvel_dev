// Every prerendered page has to say something to a crawler.
//
// The site shipped for weeks with six words in every page's fallback block:
// "To the bottom To the bottom", the docs shell's scroll button and nothing
// else. The semantics capture stopped at the first tree that was not empty,
// and the shell's button is a node, so it recorded the shell while each
// page's article was still in a deferred chunk on its way.
//
// Nothing reported it. The pages render perfectly in a browser, the meta
// description is right, the sitemap is right, and a crawler that does not run
// the app sees a scroll button. That is the shape this checks: not whether a
// page exists, but whether it says anything.
//
// Usage: dart tool/ci/crawler_text_check.dart <web-root> [min-words]
import 'dart:io';

/// The text of the fallback block a prerendered page carries for a crawler.
String fallbackText(String html) {
  final RegExp block = RegExp(
    r'<div class="dv-fallback"[^>]*>([\s\S]*?)</div>\s*<!-- /dartvel:text -->',
  );
  final RegExpMatch? found = block.firstMatch(html);
  if (found == null) return '';
  return found
      .group(1)!
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// The fallback's prose, without its code blocks.
///
/// Site copy marks a command with backticks and Prose draws it as code, so a
/// backtick that reaches the prose is a string some widget drew as plain text.
/// A code block may hold one on purpose.
String proseText(String html) => fallbackText(
    html.replaceAll(RegExp(r'<pre[\s\S]*?</pre>'), ' '));

/// How many words [text] holds.
int words(String text) =>
    text.isEmpty ? 0 : text.split(' ').where((String w) => w.isNotEmpty).length;

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('usage: crawler_text_check.dart <web-root> [min-words]');
    exit(2);
  }
  final Directory root = Directory(args.first);
  final int minimum = args.length == 2 ? int.parse(args[1]) : 25;
  if (!root.existsSync()) {
    stderr.writeln('::error::${root.path} does not exist');
    exit(1);
  }

  final List<String> thin = <String>[];
  final List<String> ticked = <String>[];
  int checked = 0;
  for (final FileSystemEntity entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('index.html')) continue;
    // Studio and the admin are applications, not pages a crawler reads, and
    // the 404 and offline pages are pages nobody should be indexed onto:
    // one is an error and the other is what a service worker serves when
    // there is no network, and neither has content of its own.
    if (entity.path.contains('/__')) continue;
    if (entity.path.contains('/404/')) continue;
    if (entity.path.contains('/offline/')) continue;
    checked++;
    final String html = entity.readAsStringSync();
    final String route =
        entity.path.substring(root.path.length).replaceAll('index.html', '');
    final int count = words(fallbackText(html));
    if (count < minimum) {
      thin.add('${route.isEmpty ? '/' : route} ($count words)');
    }
    final RegExpMatch? tick = RegExp(r'.{0,40}`.{0,40}').firstMatch(proseText(html));
    if (tick != null) {
      ticked.add('${route.isEmpty ? '/' : route}: "${tick.group(0)}"');
    }
  }

  if (checked == 0) {
    stderr.writeln('::error::no pages under ${root.path}');
    exit(1);
  }

  if (ticked.isNotEmpty) {
    ticked.sort();
    stderr.writeln(
      '::error::${ticked.length} of $checked pages show a backtick as text. '
      'Copy marks a command with backticks for Prose to set as code, and '
      'these were drawn by a widget that does not: ${ticked.join(', ')}',
    );
    if (thin.isEmpty) exit(1);
  }

  if (thin.isEmpty) {
    stdout.writeln(
        '$checked pages, each with at least $minimum words for a crawler.');
    return;
  }

  thin.sort();
  stderr.writeln(
    '::error::${thin.length} of $checked pages say almost nothing to a '
    'crawler. A page that renders in a browser and carries a scroll button '
    'in its fallback is not indexed for what it is about: ${thin.join(', ')}',
  );
  exit(1);
}
