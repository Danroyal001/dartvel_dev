import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('model generator excludes @DVSensitiveModelField from public surfaces',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_sensitive_test_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'user.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String id;
  final String name;
  @DVSensitiveModelField()
  final String nationalId;

  const _User({
    required this.id,
    required this.name,
    required this.nationalId,
  });
}
''');

      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'sensitive_app',
        buildId: 'test-build',
      );

      final content = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      ).readAsStringSync();

      // Sensitive fields metadata is emitted.
      expect(
        content,
        contains("static const Set<String> sensitiveFields = <String>{'nationalId'};"),
      );

      // The field is still a real field: constructor, DB, and internal
      // toJson keep it.
      expect(content, contains('final String nationalId;'));

      // toJson (internal/persistence) keeps the field; toPublicJson drops it.
      // The pair "'nationalId': nationalId," therefore appears exactly once.
      final occurrences =
          RegExp(r"'nationalId': nationalId,").allMatches(content).length;
      expect(occurrences, 1);
      expect(content, contains('Map<String, Object?> toPublicJson()'));

      // Generated Card display omits the sensitive field but keeps others.
      expect(content, isNot(contains('DVText(model.nationalId.toString())')));
      expect(content, contains('DVText(model.name.toString())'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
