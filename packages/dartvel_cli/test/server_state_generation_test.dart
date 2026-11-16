// Server state reaches the generated router: a page that names its backend
// function gets that function's result before it is shown, through the same
// loader and companions every page already has, and it runs again when the
// route's params or query change -- not on every rebuild.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _routerFor(Directory root) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'state_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'State App',
    seoTitle: 'State App',
    seoDesc: 'State App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(<String, Object?>{}),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart')).readAsStringSync();
}

Directory _project(Map<String, String> pages) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_server_state_');
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  for (final MapEntry<String, String> page in pages.entries) {
    final File file = File(p.join(root.path, 'lib', 'pages', page.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

${page.value}
''');
  }
  return root;
}

/// The generated wrapper class for [name], up to the next class.
String _wrapper(String router, String name) {
  final int start = router.indexOf('class $name extends DartvelPage');
  expect(start, isNot(-1), reason: 'no $name in the router');
  final int next = router.indexOf('\nclass ', start + 1);
  return router.substring(start, next == -1 ? router.length : next);
}

void main() {
  test('a function page with initServerState loads its code, then its state', () async {
    final Directory root = _project(<String, String>{
      'dashboard.dart': '''
@DVPage()
@DVFunctionalWidget(initServerState: getDashboard)
Widget _dashboardPage(BuildContext context) => DVText('\${context.serverState}');
''',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final String router = await _routerFor(root);
    expect(router, contains("import 'functions.g.dart' as dvServerState;"));
    final String wrapper = _wrapper(router, 'DashboardPageGeneratedPage');
    expect(wrapper, contains('loadLibrary().then((_) => dvServerState.getDashboard())'));
  });

  test('a class page uses its own initServerState, else its loadData', () async {
    final Directory root = _project(<String, String>{
      'counts.dart': '''
@DVPage()
class const CountsPage({super.key}) extends DVClassWidget<int> {
  @override
  Future<int> initServerState() async => 3;

  @override
  Widget build(BuildContext context) => DVText('\${context.serverState}');
}
''',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final String router = await _routerFor(root);
    final String wrapper = _wrapper(router, 'CountsPageGeneratedPage');
    expect(wrapper, contains('page.initServerState() ?? page.loadData(params, query)'));
  });

  test('the loader runs again when params or query change, not on a rebuild', () async {
    final Directory root = _project(<String, String>{
      'index.dart': "@DVPage()\nWidget _indexPage(BuildContext context) => const DVText('Home');",
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final String router = await _routerFor(root);
    expect(router, contains(r"dependsOn: '$params|$query',"));
  });

  test('a page with no server state imports no client functions for it', () async {
    final Directory root = _project(<String, String>{
      'index.dart': "@DVPage()\nWidget _indexPage(BuildContext context) => const DVText('Home');",
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final String router = await _routerFor(root);
    expect(router, isNot(contains('as dvServerState')));
  });
}
