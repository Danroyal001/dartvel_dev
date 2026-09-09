// @DVModel.sensitiveField(encrypted: true) once meant nothing: the generator
// never read the argument, so a field marked encrypted got a plain column and
// no warning. It then refused generation outright, because there was no
// server-side key to wire the flag to.
//
// There is one now (DVFieldCipher, keyed from the server process environment),
// so the flag has to reach the two places a value crosses into and out of the
// database, and has to refuse the two shapes where honouring it would produce
// a table that looks encrypted and behaves wrongly.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<void> _writeModel(String root, String source) async {
  Directory(p.join(root, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root, 'lib', 'models', 'user.dart')).writeAsStringSync(source);
}

Future<String> _generate(String source, {required String pkgName}) async {
  final root = await Directory.systemTemp.createTemp('dartvel_encrypted_');
  addTearDown(() => root.deleteSync(recursive: true));
  await _writeModel(root.path, source);
  await ModelGenerator.generate(
    root: root.path,
    pkgName: pkgName,
    buildId: 'test-build',
  );
  return File(
    p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
  ).readAsStringSync();
}

/// The body of one generated member, so an assertion about the write path
/// cannot be satisfied by something in the read path.
String _member(String source, String signature) {
  final int start = source.indexOf(signature);
  expect(start, isNot(-1), reason: 'no $signature in the generated model');
  final int end = source.indexOf('\n  }', start);
  return source.substring(start, end == -1 ? source.length : end);
}

/// The expressions bound to the INSERT, in column order.
///
/// Split at bracket depth zero rather than matched as substrings: the
/// plaintext `model.taxNumber` is a substring of the encrypted
/// `...encrypt('User', 'taxNumber', model.taxNumber)`, so a `contains` check
/// cannot tell the safe emission from the unsafe one.
List<String> _insertBindings(String saveBody) {
  final Match? match = RegExp(
    r"INSERT INTO .*?\)', <Object\?>\[(.*)\]\);",
  ).firstMatch(saveBody);
  expect(match, isNotNull, reason: 'no INSERT statement in save()');
  return _splitTopLevel(match!.group(1)!);
}

/// The expression the constructor is handed for [field] in `_fromRow`.
String _rowBinding(String fromRowBody, String field) {
  final Match? match = RegExp('\\s$field: (.*),\\n').firstMatch(fromRowBody);
  expect(match, isNotNull, reason: 'no $field in _fromRow');
  return match!.group(1)!;
}

List<String> _splitTopLevel(String arguments) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  var inString = false;
  for (var i = 0; i < arguments.length; i++) {
    final String character = arguments[i];
    if (character == "'") inString = !inString;
    if (!inString) {
      if (character == '(' || character == '[') depth++;
      if (character == ')' || character == ']') depth--;
      if (character == ',' && depth == 0) {
        parts.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }
    }
    buffer.write(character);
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString().trim());
  return parts;
}

const String _encryptedUser = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String id;
  final String name;
  @DVModel.sensitiveField(encrypted: true)
  final String taxNumber;
  @DVModel.sensitiveField(encrypted: true)
  final String? recoveryToken;

  const _User({
    required this.id,
    required this.name,
    required this.taxNumber,
    this.recoveryToken,
  });
}
''';

void main() {
  test(
    'an encrypted field is never bound into the insert as plaintext',
    () async {
      final String generated = await _generate(
        _encryptedUser,
        pkgName: 'encrypted_app',
      );
      final List<String> bound = _insertBindings(
        _member(generated, 'static Future<User> save('),
      );

      // Binding `model.taxNumber` would put the value in the column the flag
      // says it is not in, and in any statement log the driver keeps.
      expect(bound, isNot(contains('model.taxNumber')));
      expect(bound, isNot(contains('model.recoveryToken')));
      expect(
        bound,
        contains(
          "DVFieldEncryption.encrypt('User', 'taxNumber', model.taxNumber)",
        ),
      );
      expect(
        bound,
        contains(
          "DVFieldEncryption.encrypt('User', 'recoveryToken', model.recoveryToken)",
        ),
      );
      // Fields with no encryption flag stay as they were.
      expect(bound, contains('model.name'));
    },
  );

  test('an encrypted column is decrypted on the way back out of a row', () async {
    final String generated = await _generate(
      _encryptedUser,
      pkgName: 'encrypted_app',
    );
    final String fromRow = _member(generated, 'static User _fromRow(');

    // Reading the column straight through would hand back the ciphertext,
    // which is a plausible-looking String and so fails silently: the caller
    // gets a value, just not the one that was stored.
    expect(
      _rowBinding(fromRow, 'taxNumber'),
      "DVFieldEncryption.decrypt('User', 'taxNumber', row['taxNumber'] as String?)!",
    );
    expect(
      _rowBinding(fromRow, 'recoveryToken'),
      "DVFieldEncryption.decrypt('User', 'recoveryToken', row['recoveryToken'] as String?)",
    );
    expect(_rowBinding(fromRow, 'name'), "row['name'] as String");
  });

  test('the model reports which of its fields are encrypted, so a migration '
      'or an export can tell a ciphertext column apart', () async {
    final String generated = await _generate(
      _encryptedUser,
      pkgName: 'encrypted_app',
    );
    expect(
      generated,
      contains(
        "static const Set<String> encryptedFields = "
        "<String>{'taxNumber', 'recoveryToken'};",
      ),
    );
  });

  test('an encrypted field must be sensitive as well, since the ciphertext '
      'would otherwise be serialized to clients', () async {
    final String generated = await _generate(
      _encryptedUser,
      pkgName: 'encrypted_app',
    );
    expect(
      generated,
      contains(
        "static const Set<String> sensitiveFields = "
        "<String>{'taxNumber', 'recoveryToken'};",
      ),
    );
  });

  test('encrypting a non-String field is refused rather than silently '
      'changing the column type', () async {
    await expectLater(
      _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String id;
  @DVModel.sensitiveField(encrypted: true)
  final int salary;

  const _User({required this.id, required this.salary});
}
''', pkgName: 'wrong_type_app'),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(
            contains('salary'),
            contains('_User'),
            contains('int'),
            contains('String'),
          ),
        ),
      ),
    );
  });

  test('encrypting the field rows are looked up by is refused, because the '
      'query would compare a ciphertext', () async {
    await expectLater(
      _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Token {
  @DVModel.sensitiveField(encrypted: true)
  final String id;
  final int uses;

  const _Token({required this.id, required this.uses});
}
''', pkgName: 'key_field_app'),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(contains('id'), contains('_Token'), contains('find')),
        ),
      ),
    );
  });

  test(
    '@DVModel.sensitiveField() without encrypted keeps a plain column',
    () async {
      final String generated = await _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String id;
  @DVModel.sensitiveField()
  final String taxNumber;

  const _User({required this.id, required this.taxNumber});
}
''', pkgName: 'plain_app');

      expect(
        generated,
        contains(
          "static const Set<String> sensitiveFields = <String>{'taxNumber'};",
        ),
      );
      expect(
        generated,
        contains('static const Set<String> encryptedFields = <String>{};'),
      );
      expect(generated, isNot(contains('DVFieldEncryption')));
    },
  );
}
