import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_shelf/src/telegram_auth.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 9);
  const token = '123:server-only-secret';
  String signed({int age = 0, String user = '{"id":42,"first_name":"Ada"}'}) {
    final fields = <String, String>{
      'auth_date': '${now.millisecondsSinceEpoch ~/ 1000 - age}',
      'user': user,
      'query_id': 'AAExample',
      'signature': 'signed-by-telegram',
    };
    final keys = fields.keys.toList()..sort();
    final secret = Hmac(
      sha256,
      utf8.encode('WebAppData'),
    ).convert(utf8.encode(token));
    fields['hash'] = Hmac(sha256, secret.bytes)
        .convert(utf8.encode(keys.map((k) => '$k=${fields[k]}').join('\n')))
        .toString();
    return Uri(queryParameters: fields).query;
  }

  test('valid signed identity is accepted', () {
    final result = DVTelegramInitDataValidator(botToken: token)
        .validate(signed(), now: now);
    expect(result.id, 'telegram:42');
    expect(result.name, 'Ada');
  });
  test('tampering, expiry, future dates and duplicate keys are refused', () {
    final validator = DVTelegramInitDataValidator(botToken: token);
    for (final input in [
      signed().replaceFirst('Ada', 'Eve'),
      signed(age: 301),
      signed(age: -1),
      '${signed()}&auth_date=1',
      'hash=bad',
      signed(user: '{"id":0}'),
    ]) {
      expect(() => validator.validate(input, now: now), throwsFormatException);
    }
  });
  test('wrong bot token cannot verify a login', () {
    expect(
      () =>
          DVTelegramInitDataValidator(botToken: 'wrong')
              .validate(signed(), now: now),
      throwsFormatException,
    );
  });
}
