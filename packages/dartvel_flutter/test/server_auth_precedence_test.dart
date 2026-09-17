// A build served by its own generated server signs in there, even when the
// application configured the in-memory development provider.
//
// The example configures DVLocalAuthProvider so it runs anywhere Flutter
// does. Built with `dartvel build web-server`, the same code shipped inside a
// binary whose server keeps real accounts -- and /login checked the password
// against a map in the browser tab, never calling the server. An owner granted
// Studio could not sign in through the application's own sign-in page.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

/// An identity service the application wrote, which refuses everyone.
class _NamedProvider implements DVAuthProvider {
  @override
  Future<DVAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async =>
      throw AuthException.invalidCredentials;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> paths;

  setUp(() {
    paths = <String>[];
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      onToken: (_) {},
      tokens: DVMemorySessionTokenStore(),
      web: false,
      send: (DVHttpRequest request) async {
        paths.add(request.url.path);
        return DVHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'user': <String, Object?>{
              'id': 'acc_1',
              'email': 'owner@example.test',
            },
            'mfaRequired': false,
            'session': <String, Object?>{
              'id': 'ses_1',
              'userId': 'acc_1',
              'tenant': 'default',
              'createdAt': '2026-09-17T12:00:00.000Z',
              'lastSeenAt': '2026-09-17T12:00:00.000Z',
              'claims': <String, Object?>{},
              'mfaSatisfiedAt': null,
              'isCurrent': true,
            },
            'token': _token,
          }),
        );
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
  });

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  test('served with server auth, the development provider yields to the server',
      () async {
    DVAuth.servedWithServerAuth = true;
    DV.Auth.configure(DVLocalAuthProvider());

    await DV.Auth.signInWithEmailAndPassword(
      email: 'owner@example.test',
      password: 'correct horse battery staple',
    );

    expect(paths, contains('/api/auth/sign-in'));
    expect(DV.Auth.currentUser?.email, 'owner@example.test');
    expect(DV.Auth.currentUser?.id, 'acc_1');
  });

  test('without a server, the configured development provider is used',
      () async {
    DVAuth.servedWithServerAuth = false;
    DV.Auth.configure(DVLocalAuthProvider());

    await expectLater(
      DV.Auth.signInWithEmailAndPassword(
        email: 'owner@example.test',
        password: 'correct horse battery staple',
      ),
      throwsA(isA<AuthException>()),
    );
    expect(paths, isEmpty);
  });

  test('a provider the application wrote is still the one used', () async {
    // Only the development adapter yields: an identity service the
    // application configured is its decision, server or not.
    DVAuth.servedWithServerAuth = true;
    DV.Auth.configure(_NamedProvider());

    await expectLater(
      DV.Auth.signInWithEmailAndPassword(
        email: 'owner@example.test',
        password: 'correct horse battery staple',
      ),
      throwsA(isA<AuthException>()),
    );
    expect(paths, isEmpty);
  });

  test('resetting the auth provider forgets the served flag', () {
    DVAuth.servedWithServerAuth = true;
    DV.Test.resetAuthProvider();
    expect(DVAuth.servedWithServerAuth,
        const bool.fromEnvironment('DARTVEL_SERVER_AUTH'));
  });
}
