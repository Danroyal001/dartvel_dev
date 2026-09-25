// dartvel.capture is checked against the data models that are captured.
//
// A destination naming a data model that is not @DVModel(capture: true) is
// delivered nothing, and nothing says so -- which looks exactly like a quiet
// day. The build stops on it instead (DV-CDC-008).
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _order = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(capture: true)
class _Order {
  final String id;
  final int total;
  const _Order({required this.id, required this.total});
}
''';

Directory _project(String destinationModels) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_capture_build_');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: capture_build_probe
publish_to: none
environment:
  sdk: ^3.12.0
dartvel:
  prodBackendHost: https://example.com
  capture:
    destinations:
      warehouse:
        type: database
        connection: WAREHOUSE_URL
        models: $destinationModels
''');
  File(p.join(dir.path, 'lib', 'models', 'order.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(_order);
  return dir;
}

void main() {
  test('a destination taking a model that is not captured stops the build',
      () async {
    final Directory dir = _project('[Order, Invoice]');

    await expectLater(
      routes.generate(root_: dir.path),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        allOf(contains('DV-CDC-008'), contains('Invoice')),
      )),
    );
  });

  test('a destination taking captured models generates', () async {
    final Directory dir = _project('[Order]');

    await routes.generate(root_: dir.path);

    final String backend = File(
      p.join(dir.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
    ).readAsStringSync();
    // The declaration reaches the server as the build checked it.
    expect(backend, contains('WAREHOUSE_URL'));
    expect(backend, isNot(contains('postgres://')));
  });
}
