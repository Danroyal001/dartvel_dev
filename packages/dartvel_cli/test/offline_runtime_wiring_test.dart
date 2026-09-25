// The generated runtime starts the offline queue, so an application does not.
//
// Everything underneath was built -- the device store, the sender, the
// reachability signal -- and a generated model queues its writes. Without
// this wiring nothing sends the queue: the writes sit on the device, the
// model reports them pending for ever, and nothing is wrong enough to throw.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('dv_offline_runtime_');
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: offline_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  prodBackendHost: https://example.com
''');
    final File page = File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'));
    page.parent.createSync(recursive: true);
    page.writeAsStringSync('''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
    final File model = File(p.join(dir.path, 'lib', 'models', 'order.dart'));
    model.parent.createSync(recursive: true);
    model.writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(offline: DVConflict.lastWriteWins)
class _Order {
  final String id;
  final String reference;

  const _Order({required this.id, required this.reference});
}
''');
    await routes.generate(root_: dir.path);
  });

  tearDownAll(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String configure() {
    final String runtime =
        File(p.join(dir.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
            .readAsStringSync();
    final int start = runtime.indexOf('void configureDartvelRuntime(');
    expect(start, isNonNegative);
    return runtime.substring(start, runtime.indexOf('\n}\n', start));
  }

  test('the runtime installs the offline queue as it starts', () {
    final String body = configure();

    expect(body, contains('DVOfflineSync.install('));
    // After the models are registered: a queue replays at install, and a
    // model registered afterwards would have its last session's writes
    // left on the device.
    expect(body.indexOf('registerDartvelModels()'),
        lessThan(body.indexOf('DVOfflineSync.install(')));
  });

  test('the queue goes to this backend\'s replay route, as the signed-in '
      'person', () {
    final String body = configure();

    expect(body, contains('DartvelRuntime.api(DVOfflineReplay.path)'));
    expect(body, contains('DartvelClient.defaultHeaders'));
  });

  test('a reconnect is what sends it', () {
    final String body = configure();

    expect(body, contains('DV.Platform.network.changes'));
    expect(body, contains('DV.Platform.network.canReachTheServer'));
  });

  test('the device store is the platform\'s, named for this application', () {
    expect(configure(), contains("dvLocalOfflineDatabase('offline_probe'"));
  });
}
