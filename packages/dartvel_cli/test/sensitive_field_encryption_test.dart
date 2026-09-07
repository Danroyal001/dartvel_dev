// @DVModel.sensitiveField(encrypted: true) documents itself as requesting
// at-rest encryption. Nothing in the generator reads `encrypted` at all, so a
// model declaring it got a plain, unencrypted column and no warning — the
// worst outcome for a flag with that name. Until Dartvel has a real
// server-side field-encryption key surface, generation must refuse rather
// than silently accept the flag and store plaintext.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<void> _writeModel(String root, String source) async {
  Directory(p.join(root, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root, 'lib', 'models', 'user.dart')).writeAsStringSync(source);
}

void main() {
  test(
      '@DVModel.sensitiveField(encrypted: true) refuses generation, naming '
      'the field and what is missing', () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_encrypted_field_');
    addTearDown(() => root.deleteSync(recursive: true));
    await _writeModel(root.path, '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String id;
  @DVModel.sensitiveField(encrypted: true)
  final String taxNumber;

  const _User({required this.id, required this.taxNumber});
}
''');

    await expectLater(
      ModelGenerator.generate(
        root: root.path,
        pkgName: 'encrypted_app',
        buildId: 'test-build',
      ),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        allOf(
          contains('taxNumber'),
          contains('_User'),
          contains('encrypted: true'),
          contains('no at-rest field encryption'),
        ),
      )),
    );
  });

  test('@DVModel.sensitiveField() without encrypted still generates',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_unencrypted_field_');
    addTearDown(() => root.deleteSync(recursive: true));
    await _writeModel(root.path, '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String id;
  @DVModel.sensitiveField()
  final String taxNumber;

  const _User({required this.id, required this.taxNumber});
}
''');

    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'plain_app',
      buildId: 'test-build',
    );

    final content = File(
      p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
    ).readAsStringSync();
    expect(
      content,
      contains("static const Set<String> sensitiveFields = <String>{'taxNumber'};"),
    );
  });
}
