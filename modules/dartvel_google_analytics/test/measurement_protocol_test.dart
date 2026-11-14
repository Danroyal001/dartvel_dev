// The Measurement Protocol, against a faked www.google-analytics.com.
//
// What is asserted is what Google's reference states (fetched 14 Nov 2026):
// POST https://www.google-analytics.com/mp/collect (region1.google-analytics.com
// for data collected in the EU) with `api_secret` and `measurement_id` as
// query parameters and a JSON body holding `client_id` and `events`, each
// with a `name` and `params`; at most 25 events a request; `session_id` and
// `engagement_time_msec` in each event's params; `timestamp_micros` for an
// event in the past, up to 72 hours. A 2xx answer says the request arrived,
// not that the events were valid; the validation server at /debug/mp/collect
// says that.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_google_analytics/dartvel_google_analytics.dart';
import 'package:test/test.dart';

const String secret = 'mp-secret-0123456789abcdef';

Map<String, Object?> body(DVHttpCall call) =>
    jsonDecode(utf8.decode(call.body)) as Map<String, Object?>;

void main() {
  late DVHttpFake fake;

  setUp(() {
    DVHttp.reset();
    DVSecrets.reset();
    DVSecrets.configure(<String, String>{
      GoogleAnalyticsConfig.defaultApiSecretName: secret,
    });
    fake = const DVHttp().fake(<String, DVHttpStub>{
      'www.google-analytics.com': DVHttpStub.status(204),
      'region1.google-analytics.com': DVHttpStub.status(204),
    });
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  GoogleAnalyticsMeasurementProtocol protocol({bool eu = false}) =>
      GoogleAnalyticsMeasurementProtocol(
        GoogleAnalyticsConfig(measurementId: 'G-ABC123XYZ9', collectInEu: eu),
        clock: () => DateTime.utc(2026, 11, 14, 12),
      );

  test('events are posted with the stream\'s id and secret as Google names '
      'them', () async {
    final GoogleAnalyticsResult result = await protocol().send(
      clientId: '123456789.1700000000',
      events: <GoogleAnalyticsEvent>[
        GoogleAnalyticsEvent.purchase(
          transactionId: '981',
          value: 45000,
          currency: 'NGN',
          items: const <GoogleAnalyticsItem>[
            GoogleAnalyticsItem(itemId: 'SKU-1', itemName: 'Audit', price: 45000, quantity: 1),
          ],
        ),
      ],
      sessionId: '1700000123',
    );

    expect(result.sent, isTrue);
    final DVHttpCall call = fake.calls.single;
    expect(call.method, 'POST');
    expect(call.url.host, 'www.google-analytics.com');
    expect(call.url.path, '/mp/collect');
    expect(call.url.queryParameters, <String, String>{
      'measurement_id': 'G-ABC123XYZ9',
      'api_secret': secret,
    });
    final Map<String, Object?> sent = body(call);
    expect(sent['client_id'], '123456789.1700000000');
    final Map<String, Object?> event =
        (sent['events']! as List<Object?>).single! as Map<String, Object?>;
    expect(event['name'], 'purchase');
    final Map<String, Object?> params =
        event['params']! as Map<String, Object?>;
    expect(params['transaction_id'], '981');
    expect(params['value'], 45000);
    expect(params['currency'], 'NGN');
    expect(params['session_id'], '1700000123');
    expect(params['engagement_time_msec'], isA<int>());
    expect(params['items'], <Object?>[
      <String, Object?>{
        'item_id': 'SKU-1',
        'item_name': 'Audit',
        'price': 45000,
        'quantity': 1,
      },
    ]);
  });

  test('the EU endpoint is used when asked for', () async {
    await protocol(eu: true).send(
      clientId: '1.2',
      events: <GoogleAnalyticsEvent>[GoogleAnalyticsEvent.login()],
    );
    expect(fake.calls.single.url.host, 'region1.google-analytics.com');
  });

  test('a user id, an address and a past time are sent when given',
      () async {
    await protocol().send(
      clientId: '1.2',
      userId: 'user-7',
      ipOverride: '203.0.113.9',
      occurredAt: DateTime.utc(2026, 11, 14, 11),
      events: <GoogleAnalyticsEvent>[GoogleAnalyticsEvent.login()],
    );
    final Map<String, Object?> sent = body(fake.calls.single);
    expect(sent['user_id'], 'user-7');
    expect(sent['ip_override'], '203.0.113.9');
    expect(sent['timestamp_micros'],
        DateTime.utc(2026, 11, 14, 11).microsecondsSinceEpoch);
  });

  test('a time more than 72 hours ago is left out: Google would move it',
      () async {
    await protocol().send(
      clientId: '1.2',
      occurredAt: DateTime.utc(2026, 11, 1),
      events: <GoogleAnalyticsEvent>[GoogleAnalyticsEvent.login()],
    );
    expect(body(fake.calls.single).containsKey('timestamp_micros'), isFalse);
  });

  test('more than 25 events go in more than one request', () async {
    await protocol().send(
      clientId: '1.2',
      events: <GoogleAnalyticsEvent>[
        for (int i = 0; i < 26; i++) GoogleAnalyticsEvent('step_$i'),
      ],
    );
    expect(fake.calls, hasLength(2));
    expect((body(fake.calls.first)['events']! as List<Object?>).length, 25);
  });

  test('with no measurement id nothing is sent and nothing throws', () async {
    final GoogleAnalyticsResult result =
        await GoogleAnalyticsMeasurementProtocol(const GoogleAnalyticsConfig())
            .send(clientId: '1.2', events: <GoogleAnalyticsEvent>[
      GoogleAnalyticsEvent.login(),
    ]);
    expect(result.sent, isFalse);
    expect(fake.calls, isEmpty);
  });

  test('with no API secret nothing is sent and nothing throws', () async {
    DVSecrets.reset();
    final GoogleAnalyticsResult result = await protocol().send(
        clientId: '1.2',
        events: <GoogleAnalyticsEvent>[GoogleAnalyticsEvent.login()]);
    expect(result.sent, isFalse);
    expect(result.reason, contains(GoogleAnalyticsConfig.defaultApiSecretName));
    expect(fake.calls, isEmpty);
  });

  test('a failure is reported without the secret or the address it is in',
      () async {
    const DVHttp().fake(<String, DVHttpStub>{
      'www.google-analytics.com': DVHttpStub.status(403),
    });
    final GoogleAnalyticsResult refused = await protocol().send(
        clientId: '1.2',
        events: <GoogleAnalyticsEvent>[GoogleAnalyticsEvent.login()]);
    expect(refused.sent, isFalse);
    expect(refused.reason, isNot(contains(secret)));

    const DVHttp().fake(<String, DVHttpStub>{
      'www.google-analytics.com':
          DVHttpStub.error(StateError('failed: https://x/?api_secret=$secret')),
    });
    final GoogleAnalyticsResult unreachable = await protocol().send(
        clientId: '1.2',
        events: <GoogleAnalyticsEvent>[GoogleAnalyticsEvent.login()]);
    expect(unreachable.sent, isFalse);
    expect(unreachable.reason, isNot(contains(secret)));
  });

  test('the validation server says what is wrong with an event', () async {
    final DVHttpFake validation = const DVHttp().fake(<String, DVHttpStub>{
      'www.google-analytics.com': DVHttpStub.json(<String, Object?>{
        'validationMessages': <Object?>[
          <String, Object?>{
            'fieldPath': 'events',
            'description': 'Event at index: [0] has invalid name [x].',
            'validationCode': 'NAME_INVALID',
          },
        ],
      }),
    });
    final List<String> problems = await protocol().validate(
        clientId: '1.2',
        events: <GoogleAnalyticsEvent>[GoogleAnalyticsEvent.login()]);
    expect(validation.calls.single.url.path, '/debug/mp/collect');
    expect(problems.single, contains('NAME_INVALID'));
  });

  group('an event Google Analytics would drop is refused when it is made', () {
    test('a reserved name', () {
      expect(() => GoogleAnalyticsEvent('session_start'), throwsArgumentError);
      expect(() => GoogleAnalyticsEvent('ga_thing'), throwsArgumentError);
      expect(() => GoogleAnalyticsEvent('screen_view'), throwsArgumentError);
    });

    test('a name that is too long or not a name', () {
      expect(() => GoogleAnalyticsEvent('a' * 41), throwsArgumentError);
      expect(() => GoogleAnalyticsEvent('has space'), throwsArgumentError);
      expect(() => GoogleAnalyticsEvent('1st'), throwsArgumentError);
    });

    test('more than 25 parameters', () {
      expect(
        () => GoogleAnalyticsEvent('big', params: <String, Object?>{
          for (int i = 0; i < 26; i++) 'p$i': i,
        }),
        throwsArgumentError,
      );
    });
  });
}
