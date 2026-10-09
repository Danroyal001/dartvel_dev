import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('module onboarding leads with automatic add before configuration', () {
    final String page = File('lib/pages/docs/modules.dart').readAsStringSync();
    expect(
      page.indexOf('dartvel add ../store'),
      lessThan(page.indexOf('# pubspec.yaml')),
    );
  });

  test('public release labels match the current package release', () {
    for (final String path in <String>[
      'lib/pages/index.dart',
      'lib/pages/docs/index.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('0.10.0')),
        reason: path,
      );
      expect(
        File(path).readAsStringSync(),
        isNot(contains('Dartvel is at 0.9')),
        reason: path,
      );
    }
  });

  test('unbuilt native embedding does not teach unsupported build flags', () {
    final String page = File('lib/pages/docs/existing-native-apps.dart')
        .readAsStringSync();
    expect(page, isNot(contains('--brownfield')));
    expect(page, contains('Not yet implemented'));
  });
}
