// DV.Auth knows who is signed in from the moment the app starts.
//
// After a full page load the session cookie was still valid and
// DV.Auth.currentUser was null: nothing asked the server who the cookie
// belonged to, so every application wrote its own DV.Auth.account() call at
// start -- or showed a signed-in person a "Sign in" button until they
// navigated. The silent failures:
//  * a signed-in person shown as signed out after a reload;
//  * a signed-out person's start-up check reported as an error, or thrown;
//  * more than one request at start for one answer;
//  * nothing an application can watch, so a header showing the account has
//    to poll.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Map<String, Object?> _session() => <String, Object?>{
      'id': 'ses_1',
      'userId': 'acc_1',
      'tenant': 'default',
      'createdAt': '2026-11-13T12:00:00.000Z',
      'lastSeenAt': '2026-11-13T12:00:00.000Z',
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': null,
      'isCurrent': true,
    };

void main() {
  late List<DVHttpRequest> requests;
  late DVHttpResponse Function(DVHttpRequest request) answer;

  DVSessionClient install({required bool web, DVSessionTokenStore? tokens}) {
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      onToken: (_) {},
      tokens: tokens,
      web: web,
      send: (DVHttpRequest request) async {
        requests.add(request);
        return answer(request);
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    return client;
  }

  setUp(() {
    requests = <DVHttpRequest>[];
    DV.Test.resetAuthProvider();
    answer = (_) => DVHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'session': _session(),
            'user': <String, Object?>{
              'id': 'acc_1',
              'email': 'ada@example.test',
              'name': 'Ada',
            },
          }),
        );
  });

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  test('a browser with a live session cookie is signed in on start, with '
      'one request', () async {
    install(web: true);
    expect(DV.Auth.currentUser, isNull);
    final DVAuthUser? user = await DV.Auth.restore();
    expect(user?.id, 'acc_1');
    expect(DV.Auth.currentUser?.email, 'ada@example.test');
    expect(DV.Session.current?.id, 'ses_1');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/auth/session');
    // The cookie is the session in a browser: nothing else is sent.
    expect(requests.single.headers.keys.map((String k) => k.toLowerCase()),
        isNot(contains('authorization')));
  });

  test('asking again while it is in flight sends nothing more', () async {
    install(web: true);
    final Future<DVAuthUser?> first = DV.Auth.restore();
    final Future<DVAuthUser?> second = DV.Auth.restore();
    await Future.wait(<Future<DVAuthUser?>>[first, second]);
    expect(requests, hasLength(1));
    expect((await DV.Auth.restored)?.email, 'ada@example.test');
  });

  test('somebody signed out stays signed out quietly', () async {
    install(web: true);
    answer = (_) => DVHttpResponse(statusCode: 401, body: 'Unauthorized');
    expect(await DV.Auth.restore(), isNull);
    expect(DV.Auth.currentUser, isNull);
    expect(DV.Auth.restoring, isFalse);
  });

  test('an unreachable server leaves the person signed out, not an error',
      () async {
    install(web: true);
    answer = (_) => throw const SocketLikeFailure();
    expect(await DV.Auth.restore(), isNull);
    expect(DV.Auth.currentUser, isNull);
  });

  test('a server that does not describe the user still restores the session',
      () async {
    install(web: true);
    answer = (_) => DVHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{'session': _session()}),
        );
    await DV.Auth.restore();
    expect(DV.Auth.currentUser?.id, 'acc_1');
  });

  test('a device restores its stored token and the person with it', () async {
    final DVMemorySessionTokenStore tokens = DVMemorySessionTokenStore();
    await tokens.write(_token);
    install(web: false, tokens: tokens);
    await DV.Auth.restore();
    expect(DV.Auth.currentUser?.email, 'ada@example.test');
    expect(requests.single.headers['authorization'], 'Bearer $_token');
  });

  test('the signed-in person is a signal an application can watch', () async {
    install(web: true);
    final List<DVAuthUser?> seen = <DVAuthUser?>[];
    final StreamSubscription<DVAuthUser?> subscription =
        DV.Auth.user.changes.listen(seen.add);
    await DV.Auth.restore();
    answer = (_) => DVHttpResponse(statusCode: 204, body: '');
    await DV.Auth.signOut();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(seen.map((DVAuthUser? u) => u?.id), <String?>['acc_1', null]);
    expect(DV.Auth.user.value, isNull);
  });

  testWidgets('a widget watching it rebuilds when the person is restored',
      (WidgetTester tester) async {
    install(web: true);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) =>
            Text(DV.Auth.user.watch(context)?.email ?? 'signed out'),
      ),
    ));
    expect(find.text('signed out'), findsOneWidget);
    await tester.runAsync(() => DV.Auth.restore());
    await tester.pump();
    expect(find.text('ada@example.test'), findsOneWidget);
  });

  test('a provider the application configured is not second-guessed',
      () async {
    install(web: true);
    DV.Auth.configure(DVLocalAuthProvider());
    DVAuth.servedByOwnServer = false;
    expect(await DV.Auth.restore(), isNull);
    expect(requests, isEmpty);
  });
}

/// What a transport throws when the network is down.
class SocketLikeFailure implements Exception {
  const SocketLikeFailure();
}
