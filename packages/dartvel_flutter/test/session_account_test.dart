// DV.Auth changing the account's e-mail address and deleting the account,
// through the generated endpoints.
//
// The silent failures here:
//  * the device showing the new address before the server verified it, so a
//    person believes a change took effect that has not;
//  * a rotated session after verification that the device does not keep;
//  * deletion sent without the person's explicit confirmation;
//  * a deleted account whose device still looks signed in -- or one that
//    looks signed out when the server refused the deletion.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _rotated = 'dvs_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Map<String, Object?> _session(String id) => <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': '2026-09-15T12:30:00.000Z',
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': null,
      'isCurrent': true,
    };

DVHttpResponse _json(int status, Object body) =>
    DVHttpResponse(statusCode: status, body: jsonEncode(body));

void main() {
  late List<DVHttpRequest> requests;
  late DVHttpResponse Function(DVHttpRequest request) answer;
  late List<String?> handed;
  late DVMemorySessionTokenStore store;

  Map<String, Object?> bodyOf(DVHttpRequest request) =>
      jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;

  setUp(() async {
    requests = <DVHttpRequest>[];
    handed = <String?>[];
    store = DVMemorySessionTokenStore();
    answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
          'mfaRequired': false,
          'session': _session('ses_here'),
          'token': _token,
        });
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      onToken: handed.add,
      tokens: store,
      web: false,
      send: (DVHttpRequest request) async {
        requests.add(request);
        return answer(request);
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    await DV.Auth.signInWithEmailAndPassword(
        email: 'ada@example.com', password: 'correct horse');
    requests.clear();
    handed.clear();
  });

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  test('the account is what the server says, including a change still '
      'waiting for verification', () async {
    answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'account': <String, Object?>{
            'id': 'local_1',
            'email': 'ada@example.com',
            'pendingEmail': 'ada@new.example',
          },
        });
    final DVAccount account = await DV.Auth.account();
    expect(account.email, 'ada@example.com');
    expect(account.pendingEmail, 'ada@new.example');
    expect(requests.single.url.path, '/api/auth/account');
    expect(requests.single.method, 'GET');
  });

  test('requesting a change leaves the address as it was here', () async {
    answer = (DVHttpRequest request) =>
        _json(202, <String, Object?>{'pendingEmail': 'ada@new.example'});
    await DV.Auth.requestEmailChange('ada@new.example');
    expect(requests.single.url.path, '/api/auth/account/email');
    expect(bodyOf(requests.single), <String, Object?>{'email': 'ada@new.example'});
    expect(DV.Auth.currentUser!.email, 'ada@example.com');
    expect(handed, isEmpty);
  });

  test('confirming adopts the rotated session and only then shows the new '
      'address', () async {
    answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'account': <String, Object?>{'id': 'local_1', 'email': 'ada@new.example'},
          'session': _session('ses_rotated'),
          'token': _rotated,
        });
    await DV.Auth.confirmEmailChange('123456');
    expect(requests.single.url.path, '/api/auth/account/email/verify');
    expect(bodyOf(requests.single), <String, Object?>{'code': '123456'});
    expect(handed, <String?>[_rotated]);
    expect(await store.read(), _rotated);
    expect(DV.Session.id, 'ses_rotated');
    expect(DV.Auth.currentUser!.email, 'ada@new.example');
  });

  test('a refused confirmation keeps the old address and session', () async {
    answer = (DVHttpRequest request) =>
        _json(400, <String, Object?>{'error': 'invalid_code', 'message': 'x'});
    await expectLater(
        DV.Auth.confirmEmailChange('000000'), throwsA(isA<DVSecondFactorRefused>()));
    expect(DV.Auth.currentUser!.email, 'ada@example.com');
    expect(DV.Session.id, 'ses_here');
  });

  test('deletion is not sent without explicit confirmation', () async {
    expect(() => DV.Auth.deleteAccount(password: 'correct horse', confirmed: false),
        throwsArgumentError);
    expect(requests, isEmpty);
  });

  test('a deletion the server refused leaves the device signed in', () async {
    answer = (DVHttpRequest request) => _json(400,
        <String, Object?>{'error': 'invalid_credentials', 'message': 'x'});
    await expectLater(
        DV.Auth.deleteAccount(password: 'wrong', confirmed: true),
        throwsA(isA<AuthException>()));
    expect(DV.Session.id, 'ses_here');
    expect(await store.read(), _token);
    expect(DV.Auth.currentUser, isNotNull);
  });

  test('a deletion the server confirmed signs the device out and forgets the '
      'token', () async {
    answer = (DVHttpRequest request) =>
        _json(200, <String, Object?>{'deleted': true, 'erasure': null});
    await DV.Auth.deleteAccount(
        password: 'correct horse', confirmed: true, code: '123456');
    expect(requests.single.url.path, '/api/auth/account/delete');
    expect(bodyOf(requests.single), <String, Object?>{
      'password': 'correct horse',
      'confirm': true,
      'code': '123456',
    });
    expect(DV.Session.current, isNull);
    expect(await store.read(), isNull);
    expect(handed, <String?>[null]);
    expect(DV.Auth.currentUser, isNull);
  });
}
