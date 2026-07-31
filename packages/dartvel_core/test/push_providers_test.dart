import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Recorder {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];
  final DVHttpResponse response;

  _Recorder([
    this.response = const DVHttpResponse(statusCode: 200, body: '{}'),
  ]);

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return response;
  }

  DVHttpRequest get single {
    expect(requests, hasLength(1));
    return requests.single;
  }

  Map<String, Object?> get json =>
      jsonDecode(utf8.decode(single.body)) as Map<String, Object?>;
}

const message = DVNotificationMessage(
  title: 'Order shipped',
  body: 'Your order is on the way',
  data: <String, String>{'orderId': '42'},
  channels: <DVNotificationChannel>[DVNotificationChannel.push],
);

void main() {
  group('FirebasePushProvider', () {
    test('posts the FCM HTTP v1 payload', () async {
      final recorder = _Recorder();
      await FirebasePushProvider(
        projectId: 'demo-project',
        accessToken: () async => 'ya29.token',
        transport: recorder.send,
      ).send('device-token', message);

      expect(
        recorder.single.url.toString(),
        'https://fcm.googleapis.com/v1/projects/demo-project/messages:send',
      );
      expect(recorder.single.headers['authorization'], 'Bearer ya29.token');

      final envelope = recorder.json['message']! as Map<String, Object?>;
      expect(envelope['token'], 'device-token');
      expect(envelope['notification'], <String, Object?>{
        'title': 'Order shipped',
        'body': 'Your order is on the way',
      });
      expect(envelope['data'], <String, Object?>{'orderId': '42'});
    });

    test('omits data when the message carries none', () async {
      final recorder = _Recorder();
      await FirebasePushProvider(
        projectId: 'p',
        accessToken: () async => 't',
        transport: recorder.send,
      ).send('device', const DVNotificationMessage(title: 'a', body: 'b'));

      final envelope = recorder.json['message']! as Map<String, Object?>;
      expect(envelope.containsKey('data'), isFalse);
    });

    test('fetches a token per send, so an expired one is never reused',
        () async {
      final recorder = _Recorder();
      var minted = 0;
      final provider = FirebasePushProvider(
        projectId: 'p',
        accessToken: () async => 'token-${++minted}',
        transport: recorder.send,
      );

      await provider.send('device', message);
      await provider.send('device', message);

      expect(minted, 2);
      expect(recorder.requests[0].headers['authorization'], 'Bearer token-1');
      expect(recorder.requests[1].headers['authorization'], 'Bearer token-2');
    });

    test('reports itself as the firebase provider kind', () {
      expect(
        FirebasePushProvider(projectId: 'p', accessToken: () async => 't').kind,
        DVNotificationProviderKind.firebase,
      );
    });

    test('rejects an empty registration token before any request', () async {
      final recorder = _Recorder();
      await expectLater(
        FirebasePushProvider(
          projectId: 'p',
          accessToken: () async => 't',
          transport: recorder.send,
        ).send('   ', message),
        throwsArgumentError,
      );
      expect(recorder.requests, isEmpty);
    });

    test('surfaces a rejection with the status and body', () async {
      final recorder = _Recorder(
        const DVHttpResponse(
          statusCode: 400,
          body: '{"error":{"status":"INVALID_ARGUMENT"}}',
        ),
      );

      await expectLater(
        FirebasePushProvider(
          projectId: 'p',
          accessToken: () async => 't',
          transport: recorder.send,
        ).send('device', message),
        throwsA(
          isA<DVPushProviderException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.provider, 'provider', 'firebase')
              .having((error) => error.responseBody, 'responseBody',
                  contains('INVALID_ARGUMENT'))
              .having((error) => error.isUnregisteredToken,
                  'isUnregisteredToken', isFalse),
        ),
      );
    });

    test('flags a stale device token so callers can prune it', () async {
      // FCM answers 404/UNREGISTERED once a token is no longer valid. Retrying
      // that forever is the classic push bug, so it must be distinguishable.
      for (final response in <DVHttpResponse>[
        const DVHttpResponse(statusCode: 404, body: '{}'),
        DVHttpResponse(
          statusCode: 400,
          body: jsonEncode(<String, Object?>{
            'error': <String, Object?>{'status': 'UNREGISTERED'},
          }),
        ),
      ]) {
        await expectLater(
          FirebasePushProvider(
            projectId: 'p',
            accessToken: () async => 't',
            transport: _Recorder(response).send,
          ).send('stale', message),
          throwsA(
            isA<DVPushProviderException>().having(
              (error) => error.isUnregisteredToken,
              'isUnregisteredToken',
              isTrue,
            ),
          ),
        );
      }
    });

    test('satisfies the DVNotificationProvider contract', () {
      expect(
        FirebasePushProvider(projectId: 'p', accessToken: () async => 't'),
        isA<DVNotificationProvider>(),
      );
    });
  });
}
