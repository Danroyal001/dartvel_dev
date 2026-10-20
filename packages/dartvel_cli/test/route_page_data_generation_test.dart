// An ordinary page's request-time data: an application that has
// lib/backend/page_data/index.dart gets its own route resolvers in front of
// the generated model pages; one that has none is generated as before.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<Directory> _project({String? hooks}) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_route_page_data_');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'note.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Note {
  final String id;
  final String body;
  const _Note({required this.id, required this.body});
}
''');
  if (hooks != null) {
    File(p.join(root.path, 'lib', 'backend', 'page_data', 'index.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(hooks);
  }
  return root;
}

Future<String> _routes(Directory root) async {
  await ModelGenerator.generate(root: root.path, pkgName: 'shop', buildId: 'b');
  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'shop',
    buildId: 'b',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
  return File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart')).readAsStringSync();
}

void main() {
  test("the application's page_data resolvers answer first, model pages after", () async {
    final Directory root = await _project(hooks: '''
import 'package:dartvel_core/dartvel.dart';

final dartvelRoutePageData = <String, DVPageDataResolver>{
  '/days/:day': (request) => DVPageData(title: 'Day \${request.params['day']}'),
};
''');
    try {
      final String routes = await _routes(root);
      expect(routes, contains("import 'package:shop/backend/page_data/index.dart' as app_page_data;"));
      expect(routes, contains('core.dvRoutePageResolver(app_page_data.dartvelRoutePageData, fallback: core.dvModelPageResolver('));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('without the file, the backend is generated exactly as before', () async {
    final Directory root = await _project();
    try {
      final String routes = await _routes(root);
      expect(routes, isNot(contains('app_page_data')));
      expect(routes, contains('final core.DVPageDataResolver dartvelPageData = core.dvModelPageResolver('));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a page_data file that imports Flutter is refused: the server cannot load it', () async {
    final Directory root = await _project(hooks: '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_core/dartvel.dart';

final dartvelRoutePageData = <String, DVPageDataResolver>{};
''');
    try {
      await expectLater(_routes(root), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('DV-PAGE-010'))));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('function results encode through dvToEncodable, and the server registers its models once', () async {
    final Directory root = await _project();
    File(p.join(root.path, 'lib', 'backend', 'functions', 'notes.get.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

import '../../dartvel_client/dartvel_server.dart';

@DVBackendFunction()
Future<List<Note>> _notes() async => const <Note>[];
''');
    try {
      final String routes = await _routes(root);
      expect(routes, contains('conv.jsonEncode(core.dvToEncodable(result))'));
      expect(routes, isNot(contains('conv.jsonEncode(result)')));
      expect(routes, contains("import 'package:shop/dartvel_client/models_server.g.dart' as dv_server_models;"));
      expect(routes, contains('void dartvelRegisterServerModels() {'));
      expect(routes, contains('  dartvelRegisterServerModels();'));
      // Imports stay ahead of every declaration.
      expect(routes.indexOf('dv_server_models;'), lessThan(routes.indexOf('bool _dvServerModelsRegistered')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
