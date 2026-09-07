// Every key the annotation declares, in exactly one of the sets.
//
// The sets are what the generator builds its supported list from, so a key
// on DVMiddlewares and in none of them is refused as unsupported. That is
// what happened to csp: the edit meant to add it to the built set found no
// match and did nothing, and the generator answered "unsupported middleware
// DVMiddlewares.csp" for a key it had a switch case, a setting, a generated
// assignment and a build-time refusal for.
//
// Read out of annotations.dart rather than listed here. A list written next
// to the check is a second copy of the thing being checked, and the two
// agreeing proves only that somebody updated both.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// The keys `DVMiddlewares` declares.
Set<String> _declared() {
  final File source = File(
    '../dartvel_core/lib/src/annotations/annotations.dart',
  );
  expect(source.existsSync(), isTrue,
      reason: 'annotations.dart is not where this test expects it');

  final String text = source.readAsStringSync();
  final int at = text.indexOf('class DVMiddlewares {');
  expect(at, greaterThan(-1));
  final String body = text.substring(at, text.indexOf('\n}', at));

  return RegExp(r"DVMiddlewareKey\('([A-Za-z_][A-Za-z0-9_]*)'\)")
      .allMatches(body)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

void main() {
  test('every declared key is in one of the sets', () {
    final Set<String> declared = _declared();
    expect(declared, isNotEmpty);

    expect(
      declared.difference(dvMiddlewareKeysAll),
      isEmpty,
      reason: 'a key on DVMiddlewares that no set claims is refused by the '
          'generator as unsupported, however much of it is implemented',
    );
  });

  test('no set claims a key the annotation does not declare', () {
    // The other direction: a set entry with no constant behind it is a key
    // nobody can write, and a typo in one of these sets would look exactly
    // like a feature.
    expect(dvMiddlewareKeysAll.difference(_declared()), isEmpty);
  });

  test('and no key is in two sets', () {
    final List<Set<String>> sets = <Set<String>>[
      dvMiddlewareKeysBuilt,
      dvMiddlewareKeysAtRequest,
      dvMiddlewareKeysWrapping,
      dvMiddlewareKeysAlwaysOn,
      dvMiddlewareKeysUnbuilt,
    ];
    var total = 0;
    for (final Set<String> set in sets) {
      total += set.length;
    }
    expect(total, dvMiddlewareKeysAll.length,
        reason: 'a key in two sets is enforced twice, or refused while '
            'working, depending on the order the generator reads them');
  });
}
