// A release build must not contain the dev client.
//
// The specification's reason for a separate artifact: a dev menu compiled
// into a release build behind a runtime check is one condition away from
// shipping. Dart compiles what is reachable from the entrypoint, so the
// property that matters is reachability -- nothing an application imports
// through `package:dartvel_flutter/dartvel_flutter.dart` may lead to the dev
// client library, and only the generated dev-client entrypoint imports it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final RegExp _directive = RegExp(
  r'^\s*(?:import|export|part)\s+([^;]*);',
  multiLine: true,
);
final RegExp _literal = RegExp(r"""['"]([^'"]+)['"]""");

/// Every file under lib/ reachable from [entry] through imports, exports,
/// parts and every branch of a conditional import.
Set<String> reachableFrom(String lib, String entry) {
  final Set<String> seen = <String>{};
  final List<String> queue = <String>[p.normalize(p.join(lib, entry))];
  while (queue.isNotEmpty) {
    final String file = queue.removeLast();
    if (!seen.add(file)) continue;
    final File source = File(file);
    if (!source.existsSync()) continue;
    for (final RegExpMatch directive
        in _directive.allMatches(source.readAsStringSync())) {
      for (final RegExpMatch uri in _literal.allMatches(directive.group(1)!)) {
        final String target = uri.group(1)!;
        if (target.startsWith('dart:')) continue;
        if (target.startsWith('package:dartvel_flutter/')) {
          queue.add(p.normalize(p.join(
              lib, target.substring('package:dartvel_flutter/'.length))));
        } else if (!target.startsWith('package:')) {
          queue.add(p.normalize(p.join(p.dirname(file), target)));
        }
      }
    }
  }
  return seen;
}

void main() {
  final String lib = p.normalize(p.absolute('lib'));
  final String devDir = '${p.separator}src${p.separator}devclient${p.separator}';

  test('the walk sees the library it is walking', () {
    // Without this a broken walk that found nothing would pass the check
    // below vacuously.
    final Set<String> reachable = reachableFrom(lib, 'dartvel_flutter.dart');
    expect(reachable, contains(p.join(lib, 'src/studio/page_document.dart')));
    expect(reachable.length, greaterThan(50));
  });

  test('the walk would see the dev client if it were imported', () {
    final Set<String> dev = reachableFrom(lib, 'dev_client.dart');
    expect(dev.where((String f) => f.contains(devDir)), isNotEmpty);
  });

  test('nothing the application barrel reaches leads to the dev client', () {
    final Set<String> reachable = reachableFrom(lib, 'dartvel_flutter.dart');
    final List<String> leaked = <String>[
      for (final String file in reachable)
        if (file == p.join(lib, 'dev_client.dart') || file.contains(devDir))
          p.relative(file, from: lib),
    ];
    expect(leaked, isEmpty,
        reason: 'a release build would compile the dev menu in');
  });
}
