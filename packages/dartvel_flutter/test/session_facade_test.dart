// DV.Session and DV.Auth.sessions, revoke and revokeOthers.
//
// The server answers for the signed-in person's own sessions; this is the
// facade an account page is written against. The silent failures here:
//  * DV.Session something application code can assign, so a page shows a
//    session the server never issued;
//  * revoking this device's own session from the list, and the device going
//    on as signed in with a token that no longer works;
//  * revokeOthers taking this device's session with the others;
//  * a refused revoke reported as done.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Map<String, Object?> _session(String id, {bool current = true, String? device}) =>
    <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': '2026-09-15T12:30:00.000Z',
      if (device != null) 'device': device,
      'claims': <String, Object?>{'plan': 'pro'},
      'mfaSatisfiedAt': null,
      'isCurrent': current,
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

  Map<String, String> headersOfLast() => <String, String>{
        for (final MapEntry<String, String> e in requests.last.headers.entries)
          e.key.toLowerCase(): e.value,
      };
}

void main() {
  late _Server server;
  late DVSessionClient client;
  late List<String?> handed;

  setUp(() async {
    handed = <String?>[];
    server = _Server((DVHttpRequest request) => _json(200, <String, Object?>{
          'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
          'mfaRequired': false,
          'session': _session('ses_here'),
          'token': _token,
        }));
    client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      onToken: handed.add,
      tokens: DVMemorySessionTokenStore(),
      web: false,
      send: server.send,
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
  });

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  Future<void> signIn() => DV.Auth.signInWithEmailAndPassword(
      email: 'ada@example.com', password: 'lovelace-1843');

  group('DV.Session', () {
    test('is this device\'s session as a read-only signal that only the '
        'server\'s answers change', () async {
      final List<String?> seen = <String?>[];
      final sub = DV.Session.listen((DVSession? s) => seen.add(s?.id));
      expect(DV.Session.current, isNull);

      await signIn();
      expect(DV.Session.current?.id, 'ses_here');
      expect(DV.Session.id, 'ses_here');
      expect(DV.Session.value?.id, 'ses_here');
      expect(DV.Session.claims, <String, Object?>{'plan': 'pro'});

      server.answer = (DVHttpRequest request) =>
          const DVHttpResponse(statusCode: 204, body: '');
      await DV.Auth.signOut();
      await pumpEventQueue();
      expect(DV.Session.current, isNull);
      expect(seen, <String?>['ses_here', null]);
      await sub.cancel();

      expect(DV.Session, isA<DVLifecycleSignal<DVSession?>>());
      expect(DV.Session, isNot(isA<DVMutableLifecycleSignal<DVSession?>>()));
    });

    test('is empty, and DV.Auth.sessions says what is missing, with no '
        'session client', () async {
      DVSessionClient.uninstall();
      DV.Test.resetAuthProvider();
      expect(DV.Session.current, isNull);
      expect(DV.Session.claims, isEmpty);
      expect(DV.Auth.sessions(), throwsStateError);
    });
  });

  group('DV.Auth.sessions', () {
    test('lists every device, newest first, asking with this session', () async {
      await signIn();
      server.answer = (DVHttpRequest request) => _json(200, <String, Object?>{
            'sessions': <Object?>[
              _session('ses_here', device: 'Pixel 9; Android 16'),
              _session('ses_laptop', current: false),
            ],
          });

      final List<DVSession> sessions = await DV.Auth.sessions();

      expect(server.requests.last.method, 'GET');
      expect(server.requests.last.url.path, '/api/auth/sessions');
      expect(server.headersOfLast()['authorization'], 'Bearer $_token');
      expect(sessions.map((DVSession s) => s.id), <String>['ses_here', 'ses_laptop']);
      expect(sessions.first.isCurrent, isTrue);
      expect(sessions.first.device, 'Pixel 9; Android 16');
      expect(sessions.last.isCurrent, isFalse);
    });
  });

  group('DV.Auth.revoke', () {
    test('another device: asks the server, and this one stays signed in',
        () async {
      await signIn();
      server.answer = (DVHttpRequest request) =>
          const DVHttpResponse(statusCode: 204, body: '');

      await DV.Auth.revoke('ses_laptop');

      expect(server.requests.last.method, 'POST');
      expect(server.requests.last.url.path, '/api/auth/sessions/revoke');
      expect(jsonDecode(utf8.decode(server.requests.last.body)),
          <String, Object?>{'id': 'ses_laptop'});
      expect(server.headersOfLast()[DVCSRF.headerName], isNotNull);
      expect(DV.Session.current?.id, 'ses_here');
      expect(DV.Auth.currentUser, isNotNull);
      expect(handed.last, _token);
    });

    test('this device: it is signed out here too', () async {
      await signIn();
      server.answer = (DVHttpRequest request) =>
          const DVHttpResponse(statusCode: 204, body: '');

      await DV.Auth.revoke('ses_here');

      expect(DV.Session.current, isNull);
      expect(DV.Auth.currentUser, isNull);
      expect(handed.last, isNull);
    });

    test('that the server refused throws and changes nothing', () async {
      await signIn();
      server.answer = (DVHttpRequest request) =>
          const DVHttpResponse(statusCode: 404, body: 'Not Found');

      await expectLater(
          DV.Auth.revoke('ses_somebody_else'), throwsA(isA<DVSessionRequestFailed>()));
      expect(DV.Session.current?.id, 'ses_here');
      expect(handed.last, _token);
    });
  });

  group('DV.Auth.revokeOthers', () {
    test('answers how many, and keeps this session', () async {
      await signIn();
      server.answer = (DVHttpRequest request) =>
          _json(200, <String, Object?>{'revoked': 2});

      expect(await DV.Auth.revokeOthers(), 2);

      expect(server.requests.last.method, 'POST');
      expect(server.requests.last.url.path, '/api/auth/sessions/revoke-others');
      expect(server.headersOfLast()['authorization'], 'Bearer $_token');
      expect(server.headersOfLast()[DVCSRF.headerName], isNotNull);
      expect(DV.Session.current?.id, 'ses_here');
      expect(handed.last, _token);
    });
  });
}
