// Every part of Dartvel that is built has somewhere to live on the site.
//
// docs/spec-status.json records a status for each section of NEW_SPEC.md.
// A section marked Shipped or Partial is something a developer can use today,
// and a developer who cannot find it on dartvel.dev does not know it exists.
//
// Coverage is declared in lib/components/spec_coverage.dart: a section maps
// to a page and a heading on it. This test holds the declaration to the site.
// The page has to be a route, and the heading has to be written in that
// page's source, so an entry cannot point at nothing.
//
// The features page is not coverage. It lists every section by construction
// (tool/site_features_check.dart keeps it in step with the index), so
// counting it would make this check pass for a section nobody has written up.
//
// Sections with no page yet are in kSpecKnownGaps. That list may only shrink:
// a new built section must be mapped or listed, and a listed section that a
// page now labels must move to the mapping.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_site/components/docs.dart';
import 'package:dartvel_site/components/spec_coverage.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every section docs/spec-status.json records as Shipped or Partial.
final Map<String, String> built = <String, String>{
  for (final Object? entry in (jsonDecode(
          File('../../docs/spec-status.json').readAsStringSync())
      as Map<String, Object?>)['sections']! as List<Object?>)
    if (entry is Map &&
        entry['kind'] != 'narrative' &&
        (entry['status'] == 'Shipped' || entry['status'] == 'Partial'))
      entry['section']! as String: entry['status']! as String,
};

/// The source file that declares the page served at [path].
File? pageSource(String path) {
  for (final DVRouteInfo route in dartvelRouteManifest) {
    if (route.path != path) continue;
    final String name =
        path == '/' ? 'index' : path.substring(path.lastIndexOf('/') + 1);
    for (final String candidate in <String>[
      '${route.directory}/$name.dart',
      '${route.directory}/$name/index.dart',
      '${route.directory}/index.dart',
    ]) {
      final File file = File(candidate);
      if (file.existsSync()) return file;
    }
  }
  return null;
}

/// [text] as it is written in Dart source inside single or double quotes.
bool hasLiteral(String source, String text) =>
    source.contains("'${text.replaceAll("'", r"\'")}'") ||
    source.contains('"${text.replaceAll('"', r'\"')}"');

void main() {
  test('the index has built sections to check', () {
    expect(built.length, greaterThan(50));
  });

  test('every built section is mapped to a page or listed as a known gap', () {
    final List<String> missing = <String>[
      for (final String section in built.keys)
        if (!kSpecCoverage.any((SpecCoverage c) => c.section == section) &&
            !kSpecKnownGaps.containsKey(section))
          section,
    ];
    expect(missing, isEmpty,
        reason: 'Add these to kSpecCoverage in lib/components/spec_coverage.dart, '
            'pointing at the page that covers them:\n${missing.join('\n')}');
  });

  test('no section is both mapped and a gap, or mapped twice', () {
    final List<String> both = <String>[
      for (final SpecCoverage c in kSpecCoverage)
        if (kSpecKnownGaps.containsKey(c.section)) c.section,
    ];
    expect(both, isEmpty,
        reason: 'Covered now, so remove from kSpecKnownGaps:\n${both.join('\n')}');
    final List<String> sections = <String>[
      for (final SpecCoverage c in kSpecCoverage) c.section,
    ];
    expect(sections.toSet().length, sections.length);
  });

  test('every entry names a section that is built', () {
    final List<String> stale = <String>[
      for (final SpecCoverage c in kSpecCoverage)
        if (!built.containsKey(c.section)) c.section,
      for (final String gap in kSpecKnownGaps.keys)
        if (!built.containsKey(gap)) gap,
    ];
    expect(stale, isEmpty,
        reason: 'Not Shipped or Partial in docs/spec-status.json, so the site '
            'must not list them as built:\n${stale.join('\n')}');
  });

  test('every mapping points at a real page and a heading on it', () {
    final List<String> wrong = <String>[];
    for (final SpecCoverage c in kSpecCoverage) {
      final String path = c.target.path;
      if (path == '/features') {
        wrong.add('${c.section}: /features lists every section, so it covers none');
        continue;
      }
      final File? file = pageSource(path);
      if (file == null) {
        wrong.add('${c.section}: $path is not a route with a source file');
        continue;
      }
      final String source = file.readAsStringSync();
      if (!hasLiteral(source, c.heading)) {
        wrong.add('${c.section}: "${c.heading}" is not written in ${file.path}');
      }
      final String? anchor = c.anchor;
      // The anchor has to be the id of the section under that heading, so a
      // link lands on the part of the page the entry names.
      if (anchor != null &&
          !RegExp("id: '${RegExp.escape(anchor)}',\\s*title: "
                  "'${RegExp.escape(c.heading.replaceAll("'", r"\'"))}'")
              .hasMatch(source)) {
        wrong.add('${c.section}: no section with id \'$anchor\' and title '
            '"${c.heading}" in ${file.path}');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('a known gap that a page labels is not a gap', () {
    final List<String> covered = <String>[];
    for (final FileSystemEntity e
        in Directory('lib/pages').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String source = e.readAsStringSync();
      for (final String gap in kSpecKnownGaps.keys) {
        if (source.contains("DocsStatus('${gap.replaceAll("'", r"\'")}'")) {
          covered.add('$gap: labelled in ${e.path}');
        }
      }
    }
    expect(covered, isEmpty,
        reason: 'Move these from kSpecKnownGaps to kSpecCoverage:\n'
            '${covered.join('\n')}');
  });

  test('every section sits in a docs group', () {
    final List<String> wrong = <String>[
      for (final SpecCoverage c in kSpecCoverage)
        if (!kDocsGroupOrder.contains(c.group)) '${c.section}: ${c.group}',
      for (final MapEntry<String, String> gap in kSpecKnownGaps.entries)
        if (!kDocsGroupOrder.contains(gap.value)) '${gap.key}: ${gap.value}',
    ];
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('every built section has the status the index records', () {
    final List<String> wrong = <String>[
      for (final MapEntry<String, String> e in built.entries)
        if (kDocsSpecStatus[e.key] != e.value)
          '${e.key}: the site says ${kDocsSpecStatus[e.key]}, the index says ${e.value}',
    ];
    expect(wrong, isEmpty,
        reason: 'Update kDocsSpecStatus in lib/components/docs.dart:\n'
            '${wrong.join('\n')}');
  });
}
