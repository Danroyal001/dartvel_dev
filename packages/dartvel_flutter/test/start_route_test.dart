// dvStartRoute: the start page a target was configured to open on.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Map<String, String> routes = <String, String>{'linux': '/editor', 'windows': '/editor'};

  test('an installed target opens on its page', () {
    expect(dvStartRoute(routes, operatingSystem: 'linux', web: false), '/editor');
    expect(dvStartRoute(routes, operatingSystem: 'windows', web: false), '/editor');
  });

  test('a target with none opens where the router starts', () {
    expect(dvStartRoute(routes, operatingSystem: 'macos', web: false), isNull);
    expect(dvStartRoute(const <String, String>{}, operatingSystem: 'linux', web: false), isNull);
  });

  test('a web page opens where its address says, never on a start route', () {
    expect(dvStartRoute(routes, operatingSystem: 'linux', web: true), isNull);
  });
}
