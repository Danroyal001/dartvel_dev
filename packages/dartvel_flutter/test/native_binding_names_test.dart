// Every native binding name Dartvel uses, declared in one place.
//
// A binding name is a bare string on both sides. `DVNativeBridge.invoke`
// returns null when nothing is registered under the name it was given, which
// is correct -- an unbound capability degrades rather than throws -- and it
// means a typo is indistinguishable from an unsupported platform.
// `window.setTitel` would compile, register nothing, invoke nothing, and
// return null forever, and the feature would simply never work on any target.
//
// So the names are declared, and this checks the source against the
// declaration. A new binding has to be added deliberately; a typo is not in
// the list.
import 'dart:io';

import 'package:dartvel_flutter/src/platform/binding_names.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every binding name literal passed to DVNativeBridge anywhere in lib/.
Set<String> namesInSource() {
  final RegExp call = RegExp(
    r'\b(?:invoke|require|isRegistered|register|unregister)'
    r"""(?:<[^)]*?>)?\(\s*'([a-zA-Z0-9_]+\.[a-zA-Z0-9_.]+)'""",
  );
  final Set<String> found = <String>{};
  for (final FileSystemEntity entity
      in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final RegExpMatch m in call.allMatches(entity.readAsStringSync())) {
      found.add(m.group(1)!);
    }
  }
  return found;
}

void main() {
  test('the scan finds names at all', () {
    // Without this the regex could stop matching -- a reformat, a rename --
    // and every assertion below would pass over an empty set.
    final Set<String> found = namesInSource();
    expect(found.length, greaterThan(20));
    expect(found, contains('window.open'));
  });

  test('every name the source uses is declared', () {
    final Set<String> undeclared =
        namesInSource().difference(dvNativeBindingNames);

    expect(undeclared, isEmpty,
        reason: 'these binding names are used but not declared in '
            'dvNativeBindingNames. A name that is not in the list is more '
            'often a typo than a new binding, and a typo returns null for '
            'ever instead of failing: $undeclared');
  });

  test('every declared name is used', () {
    // A declaration nothing calls is either a binding that was removed or one
    // that was never wired up, and both read as support that exists.
    final Set<String> unused =
        dvNativeBindingNames.difference(namesInSource());

    expect(unused, isEmpty,
        reason: 'declared but never used: $unused');
  });

  test('names are namespaced, which is what makes them greppable', () {
    for (final String name in dvNativeBindingNames) {
      expect(name, contains('.'), reason: name);
      expect(name, isNot(startsWith('.')), reason: name);
      expect(name, isNot(endsWith('.')), reason: name);
      expect(name.trim(), name, reason: name);
    }
  });

  test('the windowing names the specification fixes are all present', () {
    // These are the ones a desktop host has to register, and the ones most
    // likely to be typed twice in two packages.
    expect(dvNativeBindingNames, containsAll(<String>[
      'window.open',
      'window.close',
      'window.displays',
      'window.setTitle',
      'window.setSize',
    ]));
  });

  test('no two names differ only by case', () {
    // A binding registry keyed by exact string treats window.setTitle and
    // window.settitle as two capabilities, and only one of them works.
    final Set<String> lowered =
        dvNativeBindingNames.map((String n) => n.toLowerCase()).toSet();
    expect(lowered, hasLength(dvNativeBindingNames.length));
  });
}
