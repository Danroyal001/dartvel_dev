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
  test('the import card names a member the generator writes', () {
    final String generator = File(
            '../../packages/dartvel_cli/lib/src/generators/model_generator.dart')
        .readAsStringSync();
    final String surface = card('Data Import, Export, and Reporting').$2;
    // Importing is a member of the data model, so the card names
    // Order.importCsv. It used to name OrderImport.csv, a companion class
    // the reader had to learn a second name for; that class is private
    // machinery behind the member now.
    final Match? member =
        RegExp(r'^[A-Z][A-Za-z]*\.((?:import|export)[A-Z][A-Za-z]*)$')
            .firstMatch(surface);
    expect(member, isNotNull,
        reason: '"$surface" is not a generated member of a data model');
    expect(generator, contains('static ')); // the generator, not a stub
    expect(generator, contains('${member![1]}('),
        reason: 'the generator writes no ${member[1]} member');
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
