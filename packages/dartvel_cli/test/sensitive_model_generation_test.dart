import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('model generator excludes @DVModel.sensitiveField from public surfaces',
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
  @DVModel.sensitiveField()
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

  test('the deprecated @DVSensitiveModelField spelling still generates',
      () async {
    // The annotation moved under DVModel, but the old spelling is only
    // deprecated, not removed. It must keep working until it is dropped.
    final root =
        await Directory.systemTemp.createTemp('dartvel_sensitive_legacy_');
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
  @DVSensitiveModelField()
  final String nationalId;

  const _User({required this.id, required this.nationalId});
}
''');

      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'legacy_app',
        buildId: 'test-build',
      );

      final content = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      ).readAsStringSync();

      expect(
        content,
        contains(
            "static const Set<String> sensitiveFields = <String>{'nationalId'};"),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('generated exports omit sensitive fields unless asked for them',
      () async {
    final root = await Directory.systemTemp.createTemp('dartvel_export_test_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'account.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Account {
  final String id;
  final String name;
  @DVModel.sensitiveField()
  final String taxNumber;

  const _Account({
    required this.id,
    required this.name,
    required this.taxNumber,
  });
}
''');

      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'export_app',
        buildId: 'test-build',
      );

      final content = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      ).readAsStringSync();

      // An export is a file that leaves the system, so the sensitive column
      // is written only behind the flag — header and cells alike.
      expect(
        content,
        contains("buffer.writeln(includeSensitive ? 'id,name,taxNumber' "
            ": 'id,name');"),
      );
      expect(
        content,
        contains('if (includeSensitive) _escapeCsvValue(item.taxNumber),'),
      );
      // JSON exports go through toPublicJson, which already drops the field.
      expect(
        content,
        contains('options.includeSensitiveFields ? item.toJson() '
            ': item.toPublicJson()'),
      );
      // The unconditional forms must be gone: they were the leak.
      expect(
        content,
        isNot(contains("buffer.writeln('id,name,taxNumber');")),
      );
      expect(
        content,
        isNot(contains('convert.jsonEncode(item.toJson())')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a model with no sensitive fields keeps a plain export', () async {
    // The flag should not add a branch where nothing can be hidden.
    final root = await Directory.systemTemp.createTemp('dartvel_export_test_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'tag.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Tag {
  final String id;
  final String label;

  const _Tag({required this.id, required this.label});
}
''');

      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'export_app',
        buildId: 'test-build',
      );

      final content = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      ).readAsStringSync();

      expect(content, contains("buffer.writeln('id,label');"));
      expect(content, isNot(contains('includeSensitive')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
