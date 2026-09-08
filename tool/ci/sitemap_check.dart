/// Asserts that a built sitemap.xml says what the pages and the project said.
///
/// Every link in this chain has been separately correct while the chain did
/// nothing: the annotation held its value, the generator emitted a constant,
/// the writer had a parameter for it. What was missing was any of them
/// talking to the next, so this reads the file at the end.
///
/// Usage:
///   dart tool/ci/sitemap_check.dart <sitemap.xml> <route>=<priority>,<freq> ...
///
/// A route given with no expectations must be present and carry neither.
library;

import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart tool/ci/sitemap_check.dart <sitemap.xml> '
      '<path>=<priority>,<changefreq> ...',
    );
    exit(2);
  }

  final File file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('sitemap: ${file.path} was not written');
    exit(1);
  }
  final Map<String, _Entry> entries = _parse(file.readAsStringSync());
  if (entries.isEmpty) {
    stderr.writeln('sitemap: ${file.path} lists no URLs at all');
    exit(1);
  }

  final List<String> problems = <String>[];
  for (final String expectation in args.skip(1)) {
    final int at = expectation.indexOf('=');
    final String path = at < 0 ? expectation : expectation.substring(0, at);
    final _Entry? entry = entries[path];
    if (entry == null) {
      problems.add(
        '$path is not in the sitemap. It lists: ${entries.keys.join(', ')}',
      );
      continue;
    }
    if (at < 0) {
      // Present, and deliberately bare.
      if (entry.priority != null || entry.changeFrequency != null) {
        problems.add(
          '$path was expected to carry nothing and carries '
          'priority=${entry.priority} changefreq=${entry.changeFrequency}',
        );
      }
      continue;
    }
    final List<String> want = expectation.substring(at + 1).split(',');
    final String priority = want.first;
    final String frequency = want.length > 1 ? want[1] : '';
    if (entry.priority != priority) {
      problems.add(
        '$path has priority ${entry.priority ?? '(none)'}, expected $priority',
      );
    }
    if (frequency.isNotEmpty && entry.changeFrequency != frequency) {
      problems.add(
        '$path has changefreq ${entry.changeFrequency ?? '(none)'}, '
        'expected $frequency',
      );
    }
  }

  if (problems.isNotEmpty) {
    for (final String problem in problems) {
      stderr.writeln('sitemap: $problem');
    }
    stderr.writeln('--- ${file.path} ---');
    stderr.writeln(file.readAsStringSync());
    exit(1);
  }

  stdout.writeln(
    'sitemap: ${entries.length} URLs, and the '
    '${args.length - 1} checked say what was declared',
  );
}

class _Entry {
  const _Entry({this.priority, this.changeFrequency});
  final String? priority;
  final String? changeFrequency;
}

/// Keyed by path, so an expectation does not have to repeat the site URL.
Map<String, _Entry> _parse(String xml) {
  final Map<String, _Entry> entries = <String, _Entry>{};
  for (final RegExpMatch block
      in RegExp(r'<url>(.*?)</url>', dotAll: true).allMatches(xml)) {
    final String body = block.group(1)!;
    final String? loc = _tag(body, 'loc');
    if (loc == null) continue;
    final Uri? url = Uri.tryParse(loc);
    final String path = url == null || url.path.isEmpty ? '/' : url.path;
    entries[path] = _Entry(
      priority: _tag(body, 'priority'),
      changeFrequency: _tag(body, 'changefreq'),
    );
  }
  return entries;
}

String? _tag(String body, String name) =>
    RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(body)?.group(1);
