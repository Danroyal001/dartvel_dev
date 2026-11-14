// The Conversions API, against a faked graph.facebook.com.
//
// What is asserted is what Meta's documentation states (fetched 14 Nov
// 2026): POST https://graph.facebook.com/{API_VERSION}/{PIXEL_ID}/events
// with a `data` array of events and the access token; `event_name`,
// `event_time` (Unix seconds), `action_source` and `user_data` required;
// `event_source_url` and `client_user_agent` required for website events;
// `event_id` matching the browser's `eventID`; email, phone, names, city,
// country and postcode hashed with SHA-256 after normalising, and the
// address, user agent, fbp and fbc not hashed.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_meta_pixel/dartvel_meta_pixel.dart';
import 'package:test/test.dart';

const String token = 'EAAB-test-access-token-0123456789';

String sha(String value) => sha256.convert(utf8.encode(value)).toString();

Map<String, String> form(DVHttpCall call) =>
    Uri.splitQueryString(utf8.decode(call.body));

void main() {
  late DVHttpFake fake;

  setUp(() {
    DVHttp.reset();
    DVSecrets.reset();
    DVSecrets.configure(<String, String>{
      MetaPixelConfig.defaultAccessTokenSecret: token,
    });
    fake = const DVHttp().fake(<String, DVHttpStub>{
      'graph.facebook.com': DVHttpStub.json(<String, Object?>{
        'events_received': 1,
        'fbtrace_id': 'trace',
      }),
    });
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  MetaConversionsApi api({String? testEventCode}) => MetaConversionsApi(
        const MetaPixelConfig(pixelId: '1234567890').copyWith(
          testEventCode: testEventCode,
        ),
      );

  MetaServerEvent event({DateTime? time}) => MetaServerEvent(
        name: 'Purchase',
        time: time ?? DateTime.utc(2026, 11, 14, 12),
        eventId: 'purchase.981',
        sourceUrl: 'https://example.com/checkout/thanks',
        user: const MetaUserData(
          email: '  Ada@Example.COM ',
          phone: '+234 (0803) 000-0000',
          firstName: 'Ada',
          lastName: "O'Neil",
          city: 'Port Harcourt',
          country: 'NG',
          postcode: '500 001',
          clientIpAddress: '203.0.113.9',
          clientUserAgent: 'Mozilla/5.0',
          fbp: 'fb.1.1700000000000.123456789',
          fbc: 'fb.1.1700000000000.AbCdEf',
        ),
        customData: const <String, Object?>{'value': 45000, 'currency': 'NGN'},
      );

  test('an event is posted to the pixel\'s events edge', () async {
    final MetaConversionsResult result =
        await api().send(<MetaServerEvent>[event()]);

    expect(result.sent, isTrue);
    expect(result.eventsReceived, 1);
    final DVHttpCall call = fake.calls.single;
    expect(call.method, 'POST');
    expect('${call.url}',
        'https://graph.facebook.com/v27.0/1234567890/events');
  });

  test('the access token travels in the body, never in the address',
      () async {
    await api().send(<MetaServerEvent>[event()]);
    final DVHttpCall call = fake.calls.single;
    expect('${call.url}', isNot(contains(token)));
    expect(call.url.query, isEmpty);
    expect(form(call)['access_token'], token);
  });

  test('the event carries the fields Meta requires, as it names them',
      () async {
    await api().send(<MetaServerEvent>[event()]);
    final List<Object?> data =
        jsonDecode(form(fake.calls.single)['data']!) as List<Object?>;
    final Map<String, Object?> sent = data.single! as Map<String, Object?>;
    expect(sent['event_name'], 'Purchase');
    expect(sent['event_time'],
        DateTime.utc(2026, 11, 14, 12).millisecondsSinceEpoch ~/ 1000);
    expect(sent['event_id'], 'purchase.981');
    expect(sent['action_source'], 'website');
    expect(sent['event_source_url'], 'https://example.com/checkout/thanks');
    expect(sent['custom_data'],
        <String, Object?>{'value': 45000, 'currency': 'NGN'});
  });

  test('what Meta wants hashed is normalised and hashed; the rest is not',
      () async {
    await api().send(<MetaServerEvent>[event()]);
    final Map<String, Object?> user = ((jsonDecode(
                form(fake.calls.single)['data']!) as List<Object?>)
            .single! as Map<String, Object?>)['user_data']!
        as Map<String, Object?>;
    expect(user['em'], sha('ada@example.com'));
    // Symbols, letters and leading zeros stripped; country code kept.
    expect(user['ph'], sha('23408030000000'));
    expect(user['fn'], sha('ada'));
    expect(user['ln'], sha('oneil'));
    expect(user['ct'], sha('portharcourt'));
    expect(user['country'], sha('ng'));
    expect(user['zp'], sha('500001'));
    expect(user['client_ip_address'], '203.0.113.9');
    expect(user['client_user_agent'], 'Mozilla/5.0');
    expect(user['fbp'], 'fb.1.1700000000000.123456789');
    expect(user['fbc'], 'fb.1.1700000000000.AbCdEf');
  });

  test('a test event code is sent only when one is set', () async {
    await api().send(<MetaServerEvent>[event()]);
    expect(form(fake.calls.single).containsKey('test_event_code'), isFalse);

    await api(testEventCode: 'TEST123').send(<MetaServerEvent>[event()]);
    expect(form(fake.calls.last)['test_event_code'], 'TEST123');
  });

  test('an event older than seven days is not sent: Meta would refuse the '
      'whole request', () async {
    final MetaConversionsApi sender = MetaConversionsApi(
      const MetaPixelConfig(pixelId: '1234567890'),
      clock: () => DateTime.utc(2026, 11, 14, 12),
    );
    final MetaConversionsResult result = await sender.send(<MetaServerEvent>[
      event(time: DateTime.utc(2026, 11, 1)),
      event(time: DateTime.utc(2026, 11, 13)),
    ]);
    expect(result.sent, isTrue);
    final List<Object?> data =
        jsonDecode(form(fake.calls.single)['data']!) as List<Object?>;
    expect(data, hasLength(1));
  });

  test('with no pixel id nothing is sent and nothing throws', () async {
    final MetaConversionsResult result =
        await MetaConversionsApi(const MetaPixelConfig())
            .send(<MetaServerEvent>[event()]);
    expect(result.sent, isFalse);
    expect(result.reason, contains('pixel id'));
    expect(fake.calls, isEmpty);
  });

  test('with no access token nothing is sent and nothing throws', () async {
    DVSecrets.reset();
    final MetaConversionsResult result =
        await api().send(<MetaServerEvent>[event()]);
    expect(result.sent, isFalse);
    expect(result.reason, contains(MetaPixelConfig.defaultAccessTokenSecret));
    expect(fake.calls, isEmpty);
  });

  test('Meta refusing the request is reported, without the token', () async {
    const DVHttp().fake(<String, DVHttpStub>{
      'graph.facebook.com': DVHttpStub.json(<String, Object?>{
        'error': <String, Object?>{
          'message': 'Invalid OAuth access token $token',
          'code': 190,
        },
      }, status: 400),
    });
    final MetaConversionsResult result =
        await api().send(<MetaServerEvent>[event()]);
    expect(result.sent, isFalse);
    expect(result.status, 400);
    expect(result.reason, isNot(contains(token)));
  });

  test('Meta being unreachable is reported and does not throw', () async {
    const DVHttp().fake(<String, DVHttpStub>{
      'graph.facebook.com': DVHttpStub.error(StateError('connection reset')),
    });
    final MetaConversionsResult result =
        await api().send(<MetaServerEvent>[event()]);
    expect(result.sent, isFalse);
  });

  test('more than a thousand events go in more than one request', () async {
    await api().send(<MetaServerEvent>[
      for (int i = 0; i < 1001; i++) event(),
    ]);
    expect(fake.calls, hasLength(2));
    expect(
      (jsonDecode(form(fake.calls.first)['data']!) as List<Object?>).length,
      1000,
    );
  });
}
