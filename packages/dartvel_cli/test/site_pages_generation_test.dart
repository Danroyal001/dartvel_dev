// A backend function reads the pages its server serves through
// DVSitePages.load(), which needs to know where the built site is. Only the
// generated backend knows that, so it has to say.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('the backend tells DVSitePages which site it serves', () async {
    final Directory root =
        await Directory.systemTemp.createTemp('dartvel_site_pages_gen_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, '.dart_tool')).createSync();
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'backend', 'functions'))
        .createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'backend', 'functions', 'ping.get.dart'))
        .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _ping() async => 'pong';
''');

    await BackendGenerator.generate(
      root: root.path,
      backendDir: 'lib/backend',
      pkgName: 'site_pages_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );

    final String backend = Directory(p.join(root.path, '.dart_tool'))
        .listSync()
        .whereType<File>()
        .where((File f) => p.basename(f.path).startsWith('dartvel_backend'))
        .map((File f) => f.readAsStringSync())
        .join('\n');
    final int starts = backend.indexOf('Future<dv.ServerHandle> startBackend(');
    expect(starts, greaterThan(-1));
    final int serves = backend.indexOf('return dv.serve(', starts);
    final int told = backend.indexOf('core.DVSitePages.webRoot = spaRoot;', starts);
    // Before serving: a request that arrives first must already find it.
    expect(told, allOf(greaterThan(starts), lessThan(serves)));
  });
}
