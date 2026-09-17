// Store submission is `dartvel deploy --store`, and the site says so.
//
// There was a `dartvel publish`. It is gone rather than kept as an alias,
// so a page that still names it sends somebody to an unknown-command error,
// and a page that still shows a dartvel.publish block gets their pubspec.yaml
// refused. `dartvel modules publish`, which signs a module, is a different
// command and is not what this looks for.
import 'dart:io';

import 'package:dartvel_site/components/docs_cli_command.dart';
import 'package:dartvel_site/components/docs_cli_reference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the CLI reference has no top-level publish command', () {
    expect(
      <String>[for (final DocsCliCommand c in kCliCommands) c.name],
      isNot(contains('publish')),
    );
  });

  test('no page names dartvel publish or a dartvel.publish block', () {
    final RegExp stale = RegExp(r'dartvel publish\b|dartvel\.publish\b');
    final List<String> found = <String>[
      for (final FileSystemEntity entity
          in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          for (final (int i, String line)
              in entity.readAsLinesSync().indexed)
            if (stale.hasMatch(line)) '${entity.path}:${i + 1}: ${line.trim()}',
    ];
    expect(found, isEmpty);
  });
}
