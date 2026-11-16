// Class widgets have their own docs page at /docs/class-widgets, and what the
// docs teach passes the build's own conventions check: a class is a
// DVClassWidget, never a StatelessWidget or StatefulWidget, which
// `dartvel build` flags as DV-CONV-012 in an application.
import 'package:dartvel_site/components/docs.dart';
import 'package:dartvel_site/components/docs_page_info.dart';
import 'package:dartvel_site/components/docs_samples.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('/docs/class-widgets is a docs page in the sidebar', () {
    expect(
      <String>[for (final DocsPageInfo page in kDocsPages) page.path],
      contains('/docs/class-widgets'),
    );
    expect(
      <String>[for (final DVRouteInfo route in dartvelRouteManifest) route.path],
      contains('/docs/class-widgets'),
    );
  });

  test('no docs sample teaches a Flutter widget class (DV-CONV-012)', () {
    final RegExp flutterClass = RegExp(
      r'\b(?:StatelessWidget|StatefulWidget|ListenableBuilder|ValueListenableBuilder)\b',
    );
    final List<String> offenders = <String>[
      for (final MapEntry<String, List<String>> sample in kDocsSamples.entries)
        if (sample.value.any(flutterClass.hasMatch)) sample.key,
    ];
    expect(offenders, isEmpty);
  });

  test('the class-widgets page shows a page and a component as classes', () {
    for (final String key in <String>[
      'class-widgets-page',
      'class-widgets-component',
      'class-widgets-state',
    ]) {
      final String code = kDocsSamples[key]!.join('\n');
      expect(code, contains('extends DVClassWidget'), reason: key);
    }
  });
}
