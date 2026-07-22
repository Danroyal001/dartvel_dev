import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('model generator emits typed search facade for searchable models',
      () async {
    final root = await Directory.systemTemp.createTemp('dartvel_search_test_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'user.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(searchable: true)
class _User {
  final String id;
  @DVSearchable()
  final String name;
  final String role;

  const _User({
    required this.id,
    required this.name,
    required this.role,
  });
}
''');

      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'search_app',
        buildId: 'test-build',
      );

      final models = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      );
      final content = models.readAsStringSync();
      expect(content,
          isNot(contains("export 'package:search_app/models/user.dart'")));
      expect(content, contains('class User {'));
      expect(content, contains('const User({'));
      expect(content, contains('static Widget Form(User model)'));
      expect(content, contains('static Widget List('));
      expect(content, contains('static Widget Table('));
      expect(content, contains('static Widget Page('));
      expect(content, contains('class UserSearchFacets'));
      expect(content, contains('final List<String>? name;'));
      expect(content, contains('class UserSearch'));
      expect(content, contains('DVUnconfiguredSearchProvider<User'));
      expect(content, contains('Widget UserForm(User model)'));
      expect(content, contains('Widget UserList('));
      expect(content, contains('Widget UserTable('));
      expect(content, contains('Widget UserPage('));
      expect(
          content, contains('static Future<DVSearchResultPage<User>> query'));
      expect(content, contains('static void useProvider'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
