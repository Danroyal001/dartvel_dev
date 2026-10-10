// Every @DVModel.sensitiveField() name reaches DV.log's redaction.
//
// The logger can only redact a field it has been told about. Before this the
// generated models declared their sensitive fields as a constant and nothing
// told the logger, so `DV.log('x', context: {'nationalId': ...})` wrote the
// value through.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('registerDartvelModels registers every sensitive field with DV.log',
      () async {
    final Directory root =
        await Directory.systemTemp.createTemp('dartvel_sensitive_log_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'models.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Patient {
  final String id;
  @DVModel.sensitiveField()
  final String nationalId;
  @DVModel.sensitiveField()
  final String diagnosis;
  const _Patient({required this.id, required this.nationalId, required this.diagnosis});
}

@DVModel()
class _Invoice {
  final String id;
  @DVModel.sensitiveField()
  final String cardLast4;
  const _Invoice({required this.id, required this.cardLast4});
}
''');

    await ModelGenerator.generate(
        root: root.path, pkgName: 'clinic', buildId: 'test-build');

    for (final String library in <String>['models.g.dart', 'models_server.g.dart']) {
      final String content =
          File(p.join(root.path, 'lib', 'dartvel_client', library))
              .readAsStringSync();
      final int start = content.indexOf('void registerDartvelModels() {');
      expect(start, isNonNegative, reason: library);
      final String body = content.substring(start, content.indexOf('\n}', start));
      final RegExpMatch? call =
          RegExp(r'dvRegisterSensitiveLogFields\(<String>\{([^}]*)\}\);')
              .firstMatch(body);
      expect(call, isNotNull, reason: '$library registers nothing with DV.log');
      expect(
          call!.group(1)!.split(',').map((String name) => name.trim()).toSet(),
          <String>{"'nationalId'", "'diagnosis'", "'cardLast4'"},
          reason: library);
    }
  });
}
