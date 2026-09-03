// The site's feature list must match what the repository says is Shipped.
//
//   dart run tool/site_features_check.dart
//
// sites/dartvel_site/lib/pages/features.dart is a hand-written list. It says
// of itself that it is "every section the repository records as Shipped, and
// nothing else", and when this check was written it listed 29 sections
// against 40 in docs/spec-status.json, under a heading that said thirty-three.
// Nothing compared them, so the page that promises not to get ahead of the
// code had instead fallen behind it, which is the same kind of untruth.
//
// Every entry names its spec section in the first tuple element, exactly as
// the section is titled in the index. Missing and extra are both failures:
// missing is a shipped feature the site does not mention, extra is the site
// claiming something the index does not.
//
// Exits non-zero and prints every problem rather than the first.
import 'dart:convert';
import 'dart:io';

int main(List<String> arguments) {
  final Directory root = _repoRoot();
  final File index = File('${root.path}/docs/spec-status.json');
  final File page =
      File('${root.path}/sites/dartvel_site/lib/pages/features.dart');
  if (!index.existsSync()) return _fail(<String>['docs/spec-status.json not found']);
  if (!page.existsSync()) return _fail(<String>['features.dart not found']);

  final Map<String, Object?> decoded =
      jsonDecode(index.readAsStringSync()) as Map<String, Object?>;
  final Set<String> shipped = <String>{
    for (final Object? entry in decoded['sections']! as List)
      if (entry is Map && entry['status'] == 'Shipped')
        entry['section']! as String,
  };

  // The first string of each `(area, surface, body)` tuple in the list.
  final RegExp tuple = RegExp(r"^  \(\n    '((?:[^'\\]|\\.)+)',", multiLine: true);
  final String source = page.readAsStringSync();
  // Two lists, one per status. The page is what is built and what is half
  // built, and a name in the wrong list is the lie this tool exists to catch.
  final List<String> listed = _tuplesIn(_listSource(source, 'shipped'), tuple);
  final List<String> listedPartial =
      _tuplesIn(_listSource(source, 'partial'), tuple);
  if (listed.isEmpty) {
    return _fail(<String>['found no feature tuples in features.dart; the '
        'scan no longer matches the file']);
  }
  final List<String> problems = <String>[];
  final Set<String> partialSections = <String>{
    for (final Object? entry in decoded['sections']! as List)
      if (entry is Map && entry['status'] == 'Partial')
        entry['section']! as String,
  };
  if (listedPartial.isEmpty && partialSections.isNotEmpty) {
    problems.add('the page says partial sections are listed, and lists none');
  }
  for (final String section in partialSections) {
    if (!listedPartial.contains(section)) {
      problems.add('partial but not on the site: $section');
    }
  }
  for (final String area in listedPartial) {
    if (!partialSections.contains(area)) {
      problems.add('listed as partial on the site but not partial: $area');
    }
  }
  for (final String section in shipped) {
    if (!listed.contains(section)) {
      problems.add('shipped but not on the site: $section');
    }
  }
  for (final String area in listed) {
    if (!shipped.contains(area)) {
      problems.add('on the site but not shipped: $area');
    }
  }
  final Set<String> seen = <String>{};
  for (final String area in listed) {
    if (!seen.add(area)) problems.add('listed twice: $area');
  }

  // The heading states a number; it has to be the number.
  final RegExp heading = RegExp(r"Heading\('([A-Za-z-]+) shipped sections?\.'");
  final RegExpMatch? h = heading.firstMatch(source);
  if (h == null) {
    problems.add('the page heading no longer states the shipped count');
  } else if (_word(shipped.length) != h.group(1)!.toLowerCase()) {
    problems.add('the heading says "${h.group(1)}" shipped sections; the '
        'index has ${shipped.length} (${_word(shipped.length)})');
  }

  // The sentence about partial sections states a number too.
  final int partial = (decoded['sections']! as List)
      .where((Object? e) => e is Map && e['status'] == 'Partial')
      .length;
  final RegExpMatch? p =
      RegExp(r"'([A-Za-z-]+) more sections are partial").firstMatch(source);
  if (p == null) {
    problems.add('the page no longer states the partial count');
  } else if (_word(partial) != p.group(1)!.toLowerCase()) {
    problems.add('the page says "${p.group(1)}" partial sections; the index '
        'has $partial (${_word(partial)})');
  }

  if (problems.isNotEmpty) return _fail(problems);
  stdout.writeln('site features: ${listed.length} listed, '
      '${shipped.length} shipped, in agreement.');
  return 0;
}

/// The source of the `const List<...> [name] = <...>[ ... ];` literal.
String _listSource(String source, String name) {
  final int start = source.indexOf(RegExp('> $name = <[^\\n]*\\[\\n'));
  if (start < 0) return '';
  final int end = source.indexOf('\n];', start);
  return end < 0 ? '' : source.substring(start, end);
}

List<String> _tuplesIn(String source, RegExp tuple) => <String>[
      for (final RegExpMatch m in tuple.allMatches(source))
        m.group(1)!.replaceAll(r"\'", "'"),
    ];

int _fail(List<String> problems) {
  stderr.writeln('site features: ${problems.length} problem(s)');
  for (final String p in problems) {
    stderr.writeln('  $p');
  }
  return 1;
}

/// 40 as "forty", for the heading.
String _word(int n) {
  const List<String> ones = <String>['zero', 'one', 'two', 'three', 'four',
    'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
    'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen',
    'nineteen'];
  const List<String> tens = <String>['', '', 'twenty', 'thirty', 'forty',
    'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
  if (n < 20) return ones[n];
  if (n < 100) {
    return n % 10 == 0 ? tens[n ~/ 10] : '${tens[n ~/ 10]}-${ones[n % 10]}';
  }
  return '$n';
}

Directory _repoRoot() {
  Directory dir = Directory.current;
  while (true) {
    if (File('${dir.path}/NEW_SPEC.md').existsSync()) return dir;
    final Directory parent = dir.parent;
    if (parent.path == dir.path) return Directory.current;
    dir = parent;
  }
}
