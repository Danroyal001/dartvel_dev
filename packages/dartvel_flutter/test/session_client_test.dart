// DV.Auth signing in through the generated backend.
//
// The generated server issues a session; this is the half on the device. What
// goes wrong here still looks signed in:
//  * a native token written where anything that reads the disk reads it;
//  * a browser that asks for the token in a body, where a script can read it;
//  * a sign-out that forgets the token on the device while the server still
//    honours it -- the only sign-out a stolen token cannot survive is the
//    server's;
//  * a session waiting for its second factor kept, restored or handed to the
//    generated client as if it were a signed-in person;
//  * a session revoked elsewhere restored at launch as if it were live.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _rotated = 'dvs_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const String _pending = 'dvs_PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP';

Map<String, Object?> _session(String id, {bool mfa = false}) => <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': '2026-09-15T12:00:00.000Z',
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': mfa ? '2026-09-15T12:01:00.000Z' : null,
      'isCurrent': true,
    };

const Map<String, Object?> _user = <String, Object?>{
  'id': 'local_1',
  'email': 'ada@example.com',
};

DVHttpResponse _json(int status, Object body) =>
    DVHttpResponse(statusCode: status, body: jsonEncode(body));

/// A backend answering from [answer], recording every request.
class _Server {
  _Server(this.answer);

  DVHttpResponse Function(DVHttpRequest request) answer;
  final List<DVHttpRequest> requests = <DVHttpRequest>[];

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return answer(request);
  }

  Map<String, String> headersOf(int i) => <String, String>{
        for (final MapEntry<String, String> e in requests[i].headers.entries)
          e.key.toLowerCase(): e.value,
      };
}

/// Counts what reaches the disk, so "never written" is asserted rather than
/// inferred from a file being absent.
class _CountingSink implements DVSessionTokenSink {
  _CountingSink(this.inner);

  final DVSessionTokenSink inner;
  int writes = 0;

  @override
  Future<String?> read() => inner.read();

  @override
  Future<void> write(String? value) {
    writes++;
    return inner.write(value);
  }
}

void main() {
  late Directory dir;
  late File file;
  late DVMemoryAppKeyStore keys;
  late List<String?> handed;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dv_session_client_');
    file = File('${dir.path}/sessions/app.token');
    keys = DVMemoryAppKeyStore();
    handed = <String?>[];
  });

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
    DVAuth.installDefaultProvider(null);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  DVSessionClient client(
    _Server server, {
    bool web = false,
    DVSessionTokenStore? tokens,
  }) =>
      DVSessionClient(
        api: (String path) => Uri.parse('https://app.example.test/api$path'),
        onToken: handed.add,
        tokens: web
            ? null
            : tokens ??
                DVSealedSessionTokenStore(
                  sink: DVFileSessionTokenSink(file.path),
                  keys: () async => keys,
                ),
        web: web,
        send: server.send,
      );

  DVHttpResponse signedIn(DVHttpRequest request) =>
      _json(200, <String, Object?>{
        'user': _user,
        'mfaRequired': false,
        'session': _session('ses_1'),
        'token': _token,
      });

  group('a native client', () {
    test('asks for the token, keeps it sealed under the application key, and '
        'hands it to the generated client', () async {
      final _Server server = _Server(signedIn);
      final DVSessionClient c = client(server);

      final DVAuthUser user =
          await c.signIn(email: 'ada@example.com', password: 'lovelace-1843');

      expect(user.id, 'local_1');
      expect(server.requests.single.url.toString(),
          'https://app.example.test/api/auth/sign-in');
      final Map<String, String> headers = server.headersOf(0);
      expect(headers['x-dartvel-session-delivery'], 'token');
      expect(headers[DVCSRF.headerName]!.length, greaterThanOrEqualTo(32));
      expect(headers, isNot(contains('authorization')));

      expect(handed.last, _token);
      expect(c.current?.id, 'ses_1');

      final Uint8List onDisk = file.readAsBytesSync();
      expect(latin1.decode(onDisk), isNot(contains(_token)));
      expect(latin1.decode(onDisk), isNot(contains(_token.substring(4, 20))));
      expect(latin1.decode(onDisk), startsWith('dv1:'));
    });

    test('a launch restores the sealed session and asks the server whether it '
        'is still live', () async {
      await client(_Server(signedIn))
          .signIn(email: 'ada@example.com', password: 'lovelace-1843');
      handed.clear();

      final _Server server = _Server((DVHttpRequest request) =>
          _json(200, <String, Object?>{'session': _session('ses_1')}));
      final DVSessionClient relaunched = client(server);
      final DVSession? restored = await relaunched.restore();

      expect(restored?.id, 'ses_1');
      expect(server.requests.single.method, 'GET');
      expect(server.requests.single.url.path, '/api/auth/session');
      expect(server.headersOf(0)['authorization'], 'Bearer $_token');
      expect(handed, <String?>[_token]);
    });

    test('a session revoked elsewhere is forgotten at launch, not restored',
        () async {
      await client(_Server(signedIn))
          .signIn(email: 'ada@example.com', password: 'lovelace-1843');
      handed.clear();

      final DVSessionClient relaunched = client(_Server((DVHttpRequest request) =>
          const DVHttpResponse(statusCode: 401, body: 'Unauthorized')));
      expect(await relaunched.restore(), isNull);
      expect(relaunched.current, isNull);
      expect(handed.last, isNull);
      expect(file.existsSync(), isFalse);
    });

    test('with no key custody the token is used and never written down',
        () async {
      final _CountingSink sink = _CountingSink(DVFileSessionTokenSink(file.path));
      final DVSessionClient c = client(
        _Server(signedIn),
        tokens: DVSealedSessionTokenStore(
          sink: sink,
          keys: () async => const DVUnavailableAppKeyStore(
              'the test keyring', 'nothing answers in this test'),
        ),
      );

      await c.signIn(email: 'ada@example.com', password: 'lovelace-1843');

      expect(handed.last, _token);
      expect(c.current?.id, 'ses_1');
      expect(sink.writes, 0);
      expect(file.existsSync(), isFalse);
    });

    test('an unreadable sealed token is discarded rather than sent', () async {
      file
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(_token);
      final _Server server = _Server(signedIn);
      expect(await client(server).restore(), isNull);
      expect(server.requests, isEmpty);
      expect(handed, isNot(contains(_token)));
    });
  });

  group('a browser', () {
    test('never asks for the token and stores nothing: the cookie is the '
        'session', () async {
      final _Server server = _Server((DVHttpRequest request) =>
          _json(200, <String, Object?>{
            'user': _user,
            'mfaRequired': false,
            'session': _session('ses_1'),
          }));
      final DVSessionClient c = client(server, web: true);

      await c.signIn(email: 'ada@example.com', password: 'lovelace-1843');

      final Map<String, String> headers = server.headersOf(0);
      expect(headers, isNot(contains('x-dartvel-session-delivery')));
      expect(headers, isNot(contains('authorization')));
      expect(headers[DVCSRF.headerName], isNotNull);
      expect(handed.whereType<String>(), isEmpty);
      expect(c.current?.id, 'ses_1');
      expect(file.existsSync(), isFalse);
    });
  });

  group('sign-out', () {
    test('revokes on the server with this session, then forgets it', () async {
      final _Server server = _Server(signedIn);
      final DVSessionClient c = client(server);
      await c.signIn(email: 'ada@example.com', password: 'lovelace-1843');

      server.answer =
          (DVHttpRequest request) => const DVHttpResponse(statusCode: 204, body: '');
      await c.signOut();

      expect(server.requests.last.url.path, '/api/auth/sign-out');
      expect(server.requests.last.method, 'POST');
      expect(server.headersOf(1)['authorization'], 'Bearer $_token');
      expect(server.headersOf(1)[DVCSRF.headerName], isNotNull);
      expect(handed.last, isNull);
      expect(c.current, isNull);
      expect(file.existsSync(), isFalse);
    });

    test('that the server did not confirm leaves the device signed in and '
        'says so', () async {
      final _Server server = _Server(signedIn);
      final DVSessionClient c = client(server);
      await c.signIn(email: 'ada@example.com', password: 'lovelace-1843');

      server.answer = (DVHttpRequest request) =>
          const DVHttpResponse(statusCode: 503, body: 'Service Unavailable');
      await expectLater(c.signOut(), throwsA(isA<DVSessionRequestFailed>()));

      expect(handed.last, _token);
      expect(c.current?.id, 'ses_1');
      expect(file.existsSync(), isTrue);
    });
  });

  group('a second factor', () {
    test('the pending session is neither kept nor handed out, and the rotated '
        'one is', () async {
      final _Server server = _Server((DVHttpRequest request) =>
          _json(200, <String, Object?>{
            'user': _user,
            'mfaRequired': true,
            'session': _session('ses_pending'),
            'token': _pending,
          }));
      final DVSessionClient c = client(server);

      await expectLater(
        c.signIn(email: 'ada@example.com', password: 'lovelace-1843'),
        throwsA(isA<DVMfaRequired>()),
      );
      expect(handed, isEmpty);
      expect(file.existsSync(), isFalse);
      expect(c.current, isNull);

      server.answer = (DVHttpRequest request) => _json(200, <String, Object?>{
            'mfaRequired': false,
            'session': _session('ses_2', mfa: true),
            'token': _rotated,
          });
      final DVAuthUser user = await c.completeSecondFactor(code: '123456');

      expect(user.id, 'local_1');
      expect(server.requests.last.url.path, '/api/auth/second-factor');
      expect(server.headersOf(1)['authorization'], 'Bearer $_pending');
      expect(jsonDecode(utf8.decode(server.requests.last.body)),
          <String, Object?>{'code': '123456'});
      expect(handed, <String?>[_rotated]);
      expect(c.current?.mfaSatisfiedAt, isNotNull);
      expect(latin1.decode(file.readAsBytesSync()), isNot(contains(_rotated)));
    });
  });

  group('refusals', () {
    test('keep their meaning and carry nothing from the server\'s body',
        () async {
      final DVSessionClient c = client(_Server((DVHttpRequest request) => _json(
          400, <String, Object?>{
            'error': 'invalid_credentials',
            'message': 'something the server said',
          })));
      final Object error = await c
          .signIn(email: 'ada@example.com', password: 'nope-nope')
          .then<Object>((_) => fail('signed in'), onError: (Object e) => e);
      expect(error, same(AuthException.invalidCredentials));

      final DVSessionClient breached = client(_Server((DVHttpRequest request) =>
          _json(400, <String, Object?>{'error': 'breached_password'})));
      await expectLater(
          breached.signUp(email: 'ada@example.com', password: 'password1234'),
          throwsA(isA<DVBreachedPasswordRefusal>()));
    });
  });

  group('DV.Auth and the prebuilt page', () {
    test('the generated runtime\'s provider signs DV.Auth in, and a configured '
        'provider still wins', () async {
      final DVSessionClient c = client(_Server(signedIn));
      DVAuth.installDefaultProvider(DVSessionAuthProvider(c));

      await DV.Auth.signInWithEmailAndPassword(
          email: 'ada@example.com', password: 'lovelace-1843');
      expect(DV.Auth.currentUser?.id, 'local_1');

      DV.Auth.configure(DVLocalAuthProvider());
      await DV.Auth.signUp(email: 'grace@example.com', password: 'hopper-1906');
      expect(DV.Auth.currentUser?.email, 'grace@example.com');
    });

    testWidgets('the sign-in page shows the refusal, then asks for the second '
        'factor and completes it', (WidgetTester tester) async {
      int attempt = 0;
      final _Server server = _Server((DVHttpRequest request) {
        if (request.url.path.endsWith('/auth/second-factor')) {
          return _json(200, <String, Object?>{
            'mfaRequired': false,
            'session': _session('ses_2', mfa: true),
            'token': _rotated,
          });
        }
        attempt++;
        return attempt == 1
            ? _json(400, <String, Object?>{'error': 'invalid_credentials'})
            : _json(200, <String, Object?>{
                'user': _user,
                'mfaRequired': true,
                'session': _session('ses_pending'),
                'token': _pending,
              });
      });
      final DVSessionClient c = client(server, tokens: DVMemorySessionTokenStore());
      DVAuth.installDefaultProvider(DVSessionAuthProvider(c));

      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: DV.Auth.SignInWithEmailAndPasswordPage())));
      await tester.enterText(find.byKey(const ValueKey<String>('dv-auth-email')),
          'ada@example.com');
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-password')), 'wrong-password');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text(AuthException.invalidCredentials.message), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-password')), 'lovelace-1843');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('dv-auth-code')), findsOneWidget);
      expect(DV.Auth.currentUser, isNull);

      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-code')), '123456');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await tester.pumpAndSettle();
      expect(DV.Auth.currentUser?.id, 'local_1');
      expect(handed.last, _rotated);
    });
  });
}
