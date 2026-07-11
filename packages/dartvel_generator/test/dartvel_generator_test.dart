import 'package:dartvel_generator/dartvel_generator.dart';
import 'package:test/test.dart';

void main() {
  group('dartvel_generator exports', () {
    test('builders are available', () {
      expect(routeBuilder, isA<Function>());
      expect(routerBuilder, isA<Function>());
    });
  });
}
