// A server built without Studio still answers the published pages list.
//
// The web app asks for /_dartvel/pages on every page load. With Studio off the
// generated server had no handler for it, so every visitor's console showed a
// 404 (seen on Media-Bits' site). Nothing is published without Studio, so the
// answer is an empty list -- from the same DVPublishedPages, with no database.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String page = '''
import 'package:flutter/widgets.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const SizedBox();
''';

Future<String> backendFor(String dartvel) async {
  final Directory root = Directory.systemTemp.createTempSync('dv_pages_off_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: pages_off\ndartvel:\n$dartvel');
  File(p.join(root.path, 'lib', 'pages', 'index.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(page);
  await routes.generate(root_: root.path);
  return File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart')).readAsStringSync();
}

void main() {
  test('Studio switched off: the handler answers the list before the application', () async {
    final String server = await backendFor('  admin:\n    enabled: false\n');
    expect(server, contains('final core.DVPublishedPages noPublishedPages = core.DVPublishedPages(database: () => null);'));
    expect(server, contains('await noPublishedPages.respond(request) ?? await application(request)'));
  });

  test('Studio compiled out of a release: the same answer', () async {
    final String server = await backendFor('  backendPort: 3000\n');
    expect(server, contains('await noPublishedPages.respond(request) ?? await withAdmin(request)'));
  });
}
