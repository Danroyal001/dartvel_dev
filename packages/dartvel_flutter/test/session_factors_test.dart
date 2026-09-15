// DV.Auth enrolling, regenerating and removing a second factor through the
// generated endpoints.
//
// The server rotates the session every time a factor changes; the device has
// to keep the rotated token and nothing else. The silent failures here:
//  * a rotated token the device does not adopt, so the next request goes out
//    with a token the server already retired and the person is signed out;
//  * a recovery code or a TOTP secret written where the token goes;
//  * a refusal that asks for a fresh second factor treated as a revoked
//    session, signing the device out instead of asking for a code;
//  * removal attempted with no factor to present.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _rotated = 'dvs_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Map<String, Object?> _session(String id, {String? mfaAt}) => <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': '2026-09-15T12:30:00.000Z',
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': mfaAt,
      'isCurrent': true,
    };

DVHttpResponse _json(int status, Object body) =>
    DVHttpResponse(statusCode: status, body: jsonEncode(body));

class _Server {
  _Server(this.answer);

  DVHttpResponse Function(DVHttpRequest request) answer;
  final List<DVHttpRequest> requests = <DVHttpRequest>[];

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return answer(request);
  }

  Map<String, String> headersOf(DVHttpRequest request) => <String, String>{
        for (final MapEntry<String, String> e in request.headers.entries)
          e.key.toLowerCase(): e.value,
      };

  Map<String, Object?> bodyOf(DVHttpRequest request) => request.body.isEmpty
      ? const <String, Object?>{}
      : jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;
}

class _RecordingStore implements DVSessionTokenStore {
  final List<String> written = <String>[];
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async {
    written.add(token);
    _token = token;
  }

  @override
  Future<void> clear() async => _token = null;
}

void main() {
  late _Server server;
  late DVSessionClient client;
  late _RecordingStore store;
  late List<String?> handed;

  Future<void> signIn({bool web = false}) async {
    handed = <String?>[];
    store = _RecordingStore();
    server = _Server((DVHttpRequest request) => _json(200, <String, Object?>{
          'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
          'mfaRequired': false,
          'session': _session('ses_here'),
          if (!web) 'token': _token,
        }));
    client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      onToken: handed.add,
      tokens: store,
      web: web,
      send: server.send,
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    await DV.Auth.signInWithEmailAndPassword(
        email: 'ada@example.com', password: 'correct horse');
    server.requests.clear();
    handed.clear();
    store.written.clear();
  }

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  test('the status is asked with this session and says what is enrolled',
      () async {
    await signIn();
    server.answer = (DVHttpRequest request) =>
        _json(200, <String, Object?>{'totp': true, 'recoveryCodes': 7});
    final DVSecondFactorStatus status = await DV.Auth.secondFactors();
    expect(status.totp, isTrue);
    expect(status.recoveryCodes, 7);
    final DVHttpRequest sent = server.requests.single;
    expect(sent.method, 'GET');
    expect(sent.url.path, '/api/auth/factors');
    expect(server.headersOf(sent)['authorization'], 'Bearer $_token');
  });

  test('beginning enrollment answers the secret and URI and changes nothing '
      'the device keeps', () async {
    await signIn();
    server.answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'secret': 'JBSWY3DPEHPK3PXP',
          'uri': 'otpauth://totp/Probe:ada@example.com?secret=JBSWY3DPEHPK3PXP'
              '&issuer=Probe',
        });
    final DVTotpEnrollment enrollment = await DV.Auth.enrollTotp();
    expect(enrollment.secret, 'JBSWY3DPEHPK3PXP');
    expect(enrollment.uri.queryParameters['secret'], 'JBSWY3DPEHPK3PXP');
    final DVHttpRequest sent = server.requests.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/auth/factors/totp');
    expect(server.headersOf(sent)[DVCSRF.headerName.toLowerCase()], isNotEmpty);
    expect(handed, isEmpty);
    expect(store.written, isEmpty);
    expect(DV.Session.id, 'ses_here');
  });

  test('confirming adopts the rotated session and keeps only its token',
      () async {
    await signIn();
    server.answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'session': _session('ses_rotated', mfaAt: '2026-09-15T12:31:00.000Z'),
          'token': _rotated,
        });
    await DV.Auth.confirmTotp('123456');
    final DVHttpRequest sent = server.requests.single;
    expect(sent.url.path, '/api/auth/factors/totp/confirm');
    expect(server.bodyOf(sent), <String, Object?>{'code': '123456'});
    expect(handed, <String?>[_rotated]);
    expect(store.written, <String>[_rotated]);
    expect(DV.Session.id, 'ses_rotated');
    expect(DV.Session.current!.mfaSatisfiedAt, isNotNull);

    // The next call goes out with the rotated token.
    server.answer = (DVHttpRequest request) =>
        _json(200, <String, Object?>{'totp': true, 'recoveryCodes': 0});
    await DV.Auth.secondFactors();
    expect(server.headersOf(server.requests.last)['authorization'],
        'Bearer $_rotated');
  });

  test('a refused confirmation throws and keeps the session', () async {
    await signIn();
    server.answer = (DVHttpRequest request) => _json(400,
        <String, Object?>{'error': 'invalid_code', 'message': 'server words'});
    await expectLater(
        DV.Auth.confirmTotp('000000'), throwsA(isA<DVSecondFactorRefused>()));
    expect(handed, isEmpty);
    expect(DV.Session.id, 'ses_here');
  });

  test('recovery codes are handed to the caller once and never to the token '
      'store', () async {
    await signIn();
    server.answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'recoveryCodes': <String>['AAAAA-BBBBB', 'CCCCC-DDDDD'],
          'session': _session('ses_rotated', mfaAt: '2026-09-15T12:31:00.000Z'),
          'token': _rotated,
        });
    final DVRecoveryCodes codes = await DV.Auth.regenerateRecoveryCodes();
    expect(codes.codes, <String>['AAAAA-BBBBB', 'CCCCC-DDDDD']);
    expect(server.requests.single.url.path, '/api/auth/factors/recovery-codes');
    expect(store.written, <String>[_rotated]);
    expect(handed, <String?>[_rotated]);
    expect('$codes', isNot(contains('AAAAA')));
  });

  test('a stale second factor asks for a code rather than signing the device '
      'out', () async {
    await signIn();
    server.answer = (DVHttpRequest request) => _json(
          401,
          <String, Object?>{'error': 'mfa_required', 'code': 'DV-SESSION-001'},
        );
    await expectLater(
        DV.Auth.regenerateRecoveryCodes(), throwsA(isA<DVMfaRequired>()));
    expect(handed, isEmpty);
    expect(DV.Session.id, 'ses_here');
    expect(await store.read(), _token);
  });

  test('removal needs a factor to present, and adopts the rotated session',
      () async {
    await signIn();
    expect(() => DV.Auth.removeSecondFactor(), throwsArgumentError);
    expect(server.requests, isEmpty);
    server.answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'session': _session('ses_rotated'),
          'token': _rotated,
        });
    await DV.Auth.removeSecondFactor(recoveryCode: 'AAAAA-BBBBB');
    final DVHttpRequest sent = server.requests.single;
    expect(sent.url.path, '/api/auth/factors/remove');
    expect(server.bodyOf(sent), <String, Object?>{'recoveryCode': 'AAAAA-BBBBB'});
    expect(handed, <String?>[_rotated]);
    expect(DV.Session.id, 'ses_rotated');
  });

  test('in a browser nothing asks for or keeps a token', () async {
    await signIn(web: true);
    server.answer = (DVHttpRequest request) => _json(200, <String, Object?>{
          'session': _session('ses_rotated', mfaAt: '2026-09-15T12:31:00.000Z'),
        });
    await DV.Auth.confirmTotp('123456');
    expect(server.headersOf(server.requests.single), isNot(contains('authorization')));
    expect(store.written, isEmpty);
    expect(DV.Session.id, 'ses_rotated');
  });
}
