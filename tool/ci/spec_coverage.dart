/// Every section of the specification, against the index that records it.
///
/// `docs/spec-status.json` is where this repository says how much of each
/// section is built, and `tool/spec_status_check.dart` holds an entry to the
/// evidence it cites. Neither asks the question one step earlier: whether
/// there is an entry at all.
///
/// A section added to the specification and not to the index is invisible to
/// every check downstream. It cannot be Partial or Shipped or anything else,
/// because nothing is tracking it -- and the way that reads, to somebody
/// looking at the index, is that the feature does not exist rather than that
/// nobody recorded it.
///
/// The other direction matters too. An entry whose heading has been renamed
/// or removed goes on reporting a status for a section that is not in the
/// specification any more.
library;

import 'dart:convert';

/// The top-level headings of [markdown], in order.
///
/// `#` only. This specification uses `##` for the subsections inside a
/// feature -- Policy, Sessions, Bindings, Security, Deliberately absent --
/// and those recur under many features, so counting them would compare two
/// different things.
///
/// Fenced code blocks are skipped. A YAML sample's `# comment` is not a
/// heading, and a check that thought it was would demand an index entry for
/// somebody's comment.
List<String> dvSpecHeadings(String markdown) {
  final List<String> headings = <String>[];
  bool fenced = false;

  for (final String line in const LineSplitter().convert(markdown)) {
    final String trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;

    final RegExpMatch? match = RegExp(r'^#\s+(.+?)\s*$').firstMatch(line);
    if (match != null) headings.add(match.group(1)!);
  }
  return headings;
}

/// A section name reduced to what two spellings of it have in common.
///
/// Case and punctuation only. Nothing more aggressive: dropping words would
/// let a heading match an entry about something else, which is worse than
/// asking somebody to keep two strings the same.
String dvNormaliseSection(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Sections of the specification with no index entry, and entries with no
/// section.
({List<String> unlisted, List<String> unheaded}) dvSpecCoverage({
  required List<String> headings,
  required List<String> sections,
}) {
  final Set<String> listed = sections.map(dvNormaliseSection).toSet();
  final Set<String> written = headings.map(dvNormaliseSection).toSet();

  return (
    unlisted: headings
        .where((String h) => !listed.contains(dvNormaliseSection(h)))
        .toList(growable: false),
    unheaded: sections
        .where((String s) => !written.contains(dvNormaliseSection(s)))
        .toList(growable: false),
  );
}

/// A section's two labels, as the specification prints them.
typedef DVSpecLabel = ({String stability, String status});

/// The `Stability: X · Status: Y` line under each `#` heading of [markdown].
///
/// The specification prints the pair and `docs/spec-status.json` records it,
/// and two places holding one fact is where a fact goes stale. This is the
/// reading half of the comparison `tool/spec_status_check.dart` makes.
///
/// A label is attributed to the nearest preceding `#` heading, and only while
/// no `##` has intervened: a subsection may carry its own labels, and reading
/// one of those as its parent's would report a pair the section never claimed.
/// Fenced code blocks are skipped, for the same reason [dvSpecHeadings] skips
/// them — a sample that prints a status line is not a status.
Map<String, DVSpecLabel> dvSpecLabels(String markdown) {
  final Map<String, DVSpecLabel> labels = <String, DVSpecLabel>{};
  final RegExp label =
      RegExp(r'^Stability:\s*`(\w+)`\s*·\s*Status:\s*`(\w+)`\s*$');
  String? section;
  bool fenced = false;

  for (final String line in const LineSplitter().convert(markdown)) {
    final String trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;

    final RegExpMatch? heading = RegExp(r'^#\s+(.+?)\s*$').firstMatch(line);
    if (heading != null) {
      section = heading.group(1)!;
      continue;
    }
    // Any deeper heading ends the section's own preamble.
    if (line.startsWith('#')) {
      section = null;
      continue;
    }

    final RegExpMatch? match = label.firstMatch(line.trim());
    if (match == null || section == null) continue;
    labels.putIfAbsent(
      section,
      () => (stability: match.group(1)!, status: match.group(2)!),
    );
    section = null;
  }
  return labels;
}
