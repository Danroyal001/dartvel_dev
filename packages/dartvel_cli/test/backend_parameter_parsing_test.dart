// A backend function's parameter list is split at the commas that separate
// parameters, not at the ones inside a generic type. `Map<String, Object?>`
// was cut in two, which produced a parameter named `MapString`.
library;

import 'package:dartvel_cli/src/generators/route_utils.dart';
import 'package:test/test.dart';

List<(String, String)> _parse(String list) {
  final List<(String, String)> found = <(String, String)>[];
  RouteUtils.extractParams(
    list,
    (String name, String type) => found.add((name, type)),
  );
  return found;
}

void main() {
  test('a comma inside a generic type does not split the parameter', () {
    expect(
      _parse('Map<String, Object?> meta, int count'),
      <(String, String)>[('meta', 'Map<String, Object?>'), ('count', 'int')],
    );
  });

  test('nested generics and record types stay whole', () {
    expect(
      _parse('Map<String, List<Map<String, int>>> deep, (int, int) pair, String tail'),
      <(String, String)>[
        ('deep', 'Map<String, List<Map<String, int>>>'),
        ('pair', '(int, int)'),
        ('tail', 'String'),
      ],
    );
  });

  test('named parameters with a generic type keep their names', () {
    expect(
      _parse('{required Map<String, Object?> meta, OrderDraft? draft}'),
      <(String, String)>[('meta', 'Map<String, Object?>'), ('draft', 'OrderDraft?')],
    );
  });

  test('splitTopLevel splits the stored type list the same way', () {
    expect(
      RouteUtils.splitTopLevel('Map<String, Object?>,int,List<Map<String, int>>'),
      <String>['Map<String, Object?>', 'int', 'List<Map<String, int>>'],
    );
  });
}
