import 'package:test/test.dart';

import 'package:dartvel_generator/src/route_generator.dart';

void main() {
  test('RouteGenerator can be constructed with Dartvel annotations loaded', () {
    final generator = RouteGenerator();
    expect(generator, isNotNull);
  });
}
