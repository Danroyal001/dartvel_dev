// A status label on a docs page is the status the repository records.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_site/components/docs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final Map<String, String> recorded = <String, String>{
    for (final Object? entry in (jsonDecode(
            File('../../docs/spec-status.json').readAsStringSync())
        as Map<String, Object?>)['sections']! as List<Object?>)
      if (entry is Map && entry['status'] != null)
        siteName(entry['section']! as String): entry['status']! as String,
  };

  test('every label matches docs/spec-status.json', () {
    final List<String> wrong = <String>[
      for (final MapEntry<String, String> e in kDocsSpecStatus.entries)
        if (recorded[e.key] != e.value)
          '${e.key}: the docs say ${e.value}, the index says ${recorded[e.key]}',
    ];
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('every section a page labels has a recorded status', () {
    final RegExp label = RegExp(r"DocsStatus\(\s*'([^']+)'");
    final List<String> missing = <String>[
      for (final FileSystemEntity e
          in Directory('lib/pages/docs').listSync(recursive: true))
        if (e is File)
          for (final Match m in label.allMatches(e.readAsStringSync()))
            if (!kDocsSpecStatus.containsKey(m[1])) '${e.path}: ${m[1]}',
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}

/// A section title as the site writes it: site copy has no em dashes.
String siteName(String section) => section.replaceAll(' — ', ': ');
