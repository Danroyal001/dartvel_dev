// FCM HTTP v1 request and error shapes, from Google's "Send a message using
// the FCM HTTP v1 API", "Build app server send requests" and the v1 error
// code table (projects.messages#errorcode). Recorded, not live.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

import 'fixtures/fcm_test_key.dart';

class _Wire {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];
  final List<DVHttpResponse> answers = <DVHttpResponse>[];

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return answers.isEmpty
        ? const DVHttpResponse(
            statusCode: 200,
            body: '{"name":"projects/demo/messages/0:1500415314455276%31bd1c9631bd1c96"}')
        : answers.removeAt(0);
  }

  Map<String, Object?> get lastMessage =>
      (jsonDecode(utf8.decode(requests.last.body))
          as Map<String, Object?>)['message']! as Map<String, Object?>;
}

// Error bodies as the v1 reference documents them.
const String unregistered = '''
{"error": {"code": 404, "message": "Requested entity was not found.",
 "status": "NOT_FOUND",
 "details": [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
              "errorCode": "UNREGISTERED"}]}}''';
const String invalidArgument = '''
{"error": {"code": 400, "message": "The registration token is not a valid FCM registration token",
 "status": "INVALID_ARGUMENT",
 "details": [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
              "errorCode": "INVALID_ARGUMENT"}]}}''';
const String senderMismatch = '''
{"error": {"code": 403, "message": "SenderId mismatch", "status": "PERMISSION_DENIED",
 "details": [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
              "errorCode": "SENDER_ID_MISMATCH"}]}}''';
const String quota = '''
{"error": {"code": 429, "message": "Quota exceeded", "status": "RESOURCE_EXHAUSTED",
 "details": [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
              "errorCode": "QUOTA_EXCEEDED"}]}}''';
const String unavailable = '''
{"error": {"code": 503, "message": "The service is currently unavailable.",
 "status": "UNAVAILABLE",
 "details": [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
              "errorCode": "UNAVAILABLE"}]}}''';
const String unauthenticated = '''
{"error": {"code": 401, "message": "Request had invalid authentication credentials.",
 "status": "UNAUTHENTICATED"}}''';

const DVNotificationMessage hello = DVNotificationMessage(
  title: 'Order shipped',
  body: 'On the way',
  data: <String, String>{'orderId': '42'},
  channels: <DVNotificationChannel>[DVNotificationChannel.push],
);

void main() {
  late _Wire wire;
  int minted = 0;

  FirebasePushProvider provider({
    FirebasePushOptions options = const FirebasePushOptions(),
    Future<void> Function()? onUnauthorized,
  }) =>
      FirebasePushProvider(
        projectId: 'demo',
        accessToken: () async => 'token-${++minted}',
        onUnauthorized: onUnauthorized,
        options: options,
        transport: wire.send,
      );

  setUp(() {
    wire = _Wire();
    minted = 0;
  });

  group('topic and data messages', () {
    test('sendTopic addresses a topic, not a token', () async {
      await provider().sendTopic('news', hello);
      expect(wire.lastMessage['topic'], 'news');
      expect(wire.lastMessage.containsKey('token'), isFalse);
      expect(wire.lastMessage['notification'],
          <String, Object?>{'title': 'Order shipped', 'body': 'On the way'});
    });

    test('a /topics/ prefix is accepted and removed', () async {
      await provider().sendTopic('/topics/news', hello);
      expect(wire.lastMessage['topic'], 'news');
    });

    test('a topic name FCM would reject is refused before any request', () async {
      for (final String bad in <String>['', 'has space', 'a/b', 'x' * 0, '!']) {
        await expectLater(
            provider().sendTopic(bad, hello), throwsArgumentError);
      }
      expect(wire.requests, isEmpty);
    });

    test('sendData sends no notification block, so the app handles it',
        () async {
      await provider().sendData('device-token', <String, String>{'sync': '1'});
      expect(wire.lastMessage['token'], 'device-token');
      expect(wire.lastMessage['data'], <String, Object?>{'sync': '1'});
      expect(wire.lastMessage.containsKey('notification'), isFalse);
    });

    test('data keys FCM reserves are refused', () async {
      for (final String key in <String>['from', 'gcm.x', 'google.sent_time', 'google']) {
        await expectLater(
          provider().sendData('t', <String, String>{key: 'v'}),
          throwsArgumentError,
          reason: key,
        );
      }
      expect(wire.requests, isEmpty);
    });

    test('a data message is high priority only when asked', () async {
      await provider().sendData('t', <String, String>{'a': '1'});
      expect((wire.lastMessage['android'] as Map?)?['priority'], isNull);
      await provider().sendData('t', <String, String>{'a': '1'}, highPriority: true);
      expect((wire.lastMessage['android']! as Map)['priority'], 'high');
    });
  });

  group('options', () {
    test('priority, ttl, collapse key and channel go in the android block',
        () async {
      await provider(
        options: const FirebasePushOptions(
          androidPriority: FirebaseAndroidPriority.high,
          timeToLive: Duration(hours: 1),
          collapseKey: 'orders',
          androidChannelId: 'orders-channel',
        ),
      ).send('t', hello);
      final Map<String, Object?> android =
          wire.lastMessage['android']! as Map<String, Object?>;
      expect(android['priority'], 'high');
      expect(android['ttl'], '3600s');
      expect(android['collapse_key'], 'orders');
      expect((android['notification']! as Map)['channel_id'], 'orders-channel');
    });

    test('dryRun sets validate_only so nothing is delivered', () async {
      await provider(options: const FirebasePushOptions(dryRun: true))
          .send('t', hello);
      expect(
          (jsonDecode(utf8.decode(wire.requests.last.body))
              as Map<String, Object?>)['validate_only'],
          true);
    });

    test('no options keeps the original, minimal payload', () async {
      await provider().send('t', hello);
      expect(wire.lastMessage.containsKey('android'), isFalse);
    });
  });

  group('errors', () {
    Future<DVPushProviderException> failWith(
        int status, String body) async {
      wire.answers.add(DVHttpResponse(statusCode: status, body: body));
      try {
        await provider().send('device', hello);
      } on DVPushProviderException catch (error) {
        return error;
      }
      throw StateError('expected a rejection');
    }

    test('UNREGISTERED means drop the token', () async {
      final DVPushProviderException error = await failWith(404, unregistered);
      expect(error.errorCode, 'UNREGISTERED');
      expect(error.isUnregisteredToken, isTrue);
      expect(error.isRetryable, isFalse);
      expect(error.message, contains('no longer valid'));
    });

    test('INVALID_ARGUMENT is a bug in the request, not a stale token', () async {
      final DVPushProviderException error = await failWith(400, invalidArgument);
      expect(error.errorCode, 'INVALID_ARGUMENT');
      expect(error.isUnregisteredToken, isFalse);
      expect(error.isRetryable, isFalse);
    });

    test('SENDER_ID_MISMATCH names the project mismatch', () async {
      final DVPushProviderException error = await failWith(403, senderMismatch);
      expect(error.errorCode, 'SENDER_ID_MISMATCH');
      expect(error.isUnregisteredToken, isFalse);
      expect(error.message, contains('different Firebase project'));
    });

    test('QUOTA_EXCEEDED, UNAVAILABLE and INTERNAL are worth retrying', () async {
      expect((await failWith(429, quota)).isRetryable, isTrue);
      expect((await failWith(503, unavailable)).isRetryable, isTrue);
      expect((await failWith(500, '{"error":{"code":500,"status":"INTERNAL"}}'))
          .isRetryable, isTrue);
    });

    test('a body that is not JSON still maps by status', () async {
      final DVPushProviderException error = await failWith(404, 'gone');
      expect(error.isUnregisteredToken, isTrue);
      final DVPushProviderException busy = await failWith(503, '<html>');
      expect(busy.isRetryable, isTrue);
    });

    test('the response body is kept for diagnosis', () async {
      final DVPushProviderException error = await failWith(404, unregistered);
      expect(error.responseBody, contains('UNREGISTERED'));
    });
  });

  group('authentication', () {
    test('a 401 invalidates the token and retries once with a fresh one',
        () async {
      var invalidated = 0;
      wire.answers.add(const DVHttpResponse(statusCode: 401, body: unauthenticated));
      await provider(onUnauthorized: () async => invalidated++)
          .send('t', hello);
      expect(invalidated, 1);
      expect(wire.requests, hasLength(2));
      expect(wire.requests[0].headers['authorization'], 'Bearer token-1');
      expect(wire.requests[1].headers['authorization'], 'Bearer token-2');
    });

    test('a second 401 is reported, not retried forever', () async {
      wire.answers
        ..add(const DVHttpResponse(statusCode: 401, body: unauthenticated))
        ..add(const DVHttpResponse(statusCode: 401, body: unauthenticated));
      await expectLater(
        provider(onUnauthorized: () async {}).send('t', hello),
        throwsA(isA<DVPushProviderException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(wire.requests, hasLength(2));
    });

    test('without onUnauthorized a 401 is simply reported', () async {
      wire.answers.add(const DVHttpResponse(statusCode: 401, body: unauthenticated));
      await expectLater(provider().send('t', hello),
          throwsA(isA<DVPushProviderException>()));
      expect(wire.requests, hasLength(1));
    });
  });

  group('fromSecrets', () {
    test('mints its own token from the service account in Secrets', () async {
      final DVSecretsState saved = DVSecrets.captureState();
      addTearDown(() => DVSecrets.restoreState(saved));
      DVSecrets.configure(<String, String>{
        'FCM_SERVICE_ACCOUNT_JSON': jsonEncode(<String, Object?>{
          'type': 'service_account',
          'project_id': 'from-secret',
          'private_key_id': 'k1',
          'private_key': fcmTestPrivateKeyPem,
          'client_email': 'push@from-secret.iam.gserviceaccount.com',
          'token_uri': 'https://oauth2.googleapis.com/token',
        }),
      });
      final _Wire tokenAndSend = _Wire()
        ..answers.add(const DVHttpResponse(
            statusCode: 200,
            body: '{"access_token":"ya29.minted","expires_in":3599,"token_type":"Bearer"}'));
      await FirebasePushProvider.fromSecrets(transport: tokenAndSend.send)
          .send('device', hello);

      expect(tokenAndSend.requests, hasLength(2));
      expect(tokenAndSend.requests[0].url.host, 'oauth2.googleapis.com');
      expect(tokenAndSend.requests[1].url.path,
          '/v1/projects/from-secret/messages:send');
      expect(tokenAndSend.requests[1].headers['authorization'],
          'Bearer ya29.minted');
    });
  });
}
