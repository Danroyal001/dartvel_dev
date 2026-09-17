// The data cards on the features page say what the code does.
//
// A card is one sentence summarising a long record, and the record moves: a
// gap it named gets closed, and the card goes on naming it. These checks tie
// the data cards to the code they describe.
import 'dart:io';

import 'package:dartvel_site/pages/features.dart';
import 'package:flutter_test/flutter_test.dart';

(String, String, String) card(String section) => <(String, String, String)>[
      ...shipped,
      ...partial,
    ].firstWhere(((String, String, String) c) => c.$1 == section);

void main() {
  test('the import card names the class the generator writes', () {
    final String generator = File(
            '../../packages/dartvel_cli/lib/src/generators/model_generator.dart')
        .readAsStringSync();
    final String surface = card('Data Import, Export, and Reporting').$2;
    final Match? name = RegExp(r'^[A-Z][A-Za-z]*(Import|Export)\.[a-z]+$')
        .firstMatch(surface);
    expect(name, isNotNull,
        reason: '"$surface" is not a generated ModelImport or ModelExport call');
    expect(generator, contains("class \${className}${name![1]}"));
  });

  test('the tenancy card does not say a job loses its tenant', () {
    // DV.Jobs.dispatch records the tenant and the worker runs the handler in
    // it; this test is the proof.
    expect(File('../../packages/dartvel_core/test/job_tenant_test.dart')
        .existsSync(), isTrue);
    expect(card('Multi-tenancy').$3,
        isNot(contains('does not travel with a queued job')));
  });
}
