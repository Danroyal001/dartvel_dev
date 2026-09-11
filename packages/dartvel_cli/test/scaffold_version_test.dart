// The version a new project asks pub.dev for.
//
// `dartvel create` writes `^dartvelPackageVersion` for dartvel_core,
// dartvel_flutter and dartvel_cli. A caret on a 0.x version stops at the next
// minor, so when the constant falls one minor behind the packages, every
// project created outside this repository resolves the older release and none
// of the current one -- quietly, because the older release still resolves and
// still runs.
//
// The constant's own comment said a test asserted this. None did. It stood at
// 0.2.1 through the 0.3 and 0.4 releases, so a project created the day 0.4.0
// shipped asked for >=0.2.1 <0.3.0. This is the test the comment described.
import 'dart:io';

import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

List<int> _parts(String version) => version
    .split('+')
    .first
    .split('-')
    .first
    .split('.')
    .map(int.parse)
    .toList();

bool _below(List<int> a, List<int> b) {
  for (int i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

/// Whether `^base` admits [version], by pub's rule: the caret stops at the
/// first non-zero component, so ^0.m.p is <0.(m+1).0 and ^M.m.p is <(M+1).0.0.
bool caretAdmits(String base, String version) {
  final List<int> b = _parts(base);
  final List<int> v = _parts(version);
  if (_below(v, b)) return false;
  final List<int> upper = b[0] > 0
      ? <int>[b[0] + 1, 0, 0]
      : b[1] > 0
          ? <int>[0, b[1] + 1, 0]
          : <int>[0, 0, b[2] + 1];
  return _below(v, upper);
}

/// What [package] declares, read from its pubspec beside this one.
String declared(String package) {
  final String pubspec =
      File(p.join('..', package, 'pubspec.yaml')).readAsStringSync();
  return RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec)!
      .group(1)!;
}

void main() {
  test('the caret rule is pub\'s rule', () {
    // Checked before it is trusted: a wrong rule here would pass a stale
    // constant exactly as the missing test did.
    expect(caretAdmits('0.2.1', '0.2.9'), isTrue);
    expect(caretAdmits('0.2.1', '0.3.0'), isFalse);
    expect(caretAdmits('0.4.0', '0.3.9'), isFalse);
    expect(caretAdmits('1.2.0', '1.9.0'), isTrue);
    expect(caretAdmits('1.2.0', '2.0.0'), isFalse);
  });

  for (final String package in <String>[
    'dartvel_core',
    'dartvel_flutter',
    'dartvel_cli',
  ]) {
    test('a new project admits the $package being published', () {
      final String version = declared(package);
      expect(caretAdmits(dartvelPackageVersion, version), isTrue,
          reason: 'dartvel create writes $package: ^$dartvelPackageVersion, '
              'which does not admit $version -- a new project resolves an '
              'older release and none of this one');
    });
  }
}
