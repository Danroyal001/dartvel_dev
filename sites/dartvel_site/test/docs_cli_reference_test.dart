// The CLI reference is the CLI's own command table.
//
// lib/components/docs_cli_reference.dart is generated from
// dartvelCommandRunner(), the object `dartvel --help` prints. When a command
// or a flag changes, this fails and names the script that rewrites the page.
import 'dart:io';

import 'package:dartvel_site/components/docs_cli_command.dart';
import 'package:dartvel_site/components/docs_cli_reference.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/cli_reference.dart';

void main() {
  test('the reference matches the command table', () {
    expect(File(kCliReferenceOutput).readAsStringSync(), cliReferenceSource(),
        reason: 'Run: dart run tool/cli_reference.dart');
  });

  test('the reference lists the commands a new user reaches for first', () {
    final Set<String> names = <String>{
      for (final DocsCliCommand c in kCliCommands) c.name,
    };
    expect(names, containsAll(<String>['create', 'dev', 'build', 'routes', 'db']));
    expect(names, isNot(contains('help')), reason: 'hidden commands stay out');
  });
}
