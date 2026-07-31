import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Recorder {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];
  final DVHttpResponse response;

  _Recorder(
      {this.response = const DVHttpResponse(statusCode: 200, body: '{}')});

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

  String get text => utf8.decode(single.body);
}

const message = DVMailMessage(
  from: DVMailAddress('support@example.com', name: 'Support'),
  to: <DVMailAddress>[
    DVMailAddress('ada@example.com', name: 'Ada Lovelace'),
    DVMailAddress('grace@example.com'),
  ],
  subject: 'Welcome',
  text: 'Thanks for joining',
  html: '<p>Thanks for joining</p>',
  headers: <String, String>{'X-Campaign': 'welcome'},
);

void main() {
  group('ResendMailProvider', () {
    test('posts the Resend payload', () async {
      final recorder = _Recorder();
      await ResendMailProvider(apiKey: 're_key', transport: recorder.send)
          .send(message);

      expect(recorder.single.url.toString(), 'https://api.resend.com/emails');
      expect(recorder.single.headers['authorization'], 'Bearer re_key');
      expect(recorder.json['from'], '"Support" <support@example.com>');
      expect(recorder.json['to'], <String>[
        '"Ada Lovelace" <ada@example.com>',
        'grace@example.com',
      ]);
      expect(recorder.json['subject'], 'Welcome');
      expect(recorder.json['text'], 'Thanks for joining');
      expect(recorder.json['html'], '<p>Thanks for joining</p>');
      expect(
          recorder.json['headers'], <String, Object?>{'X-Campaign': 'welcome'});
    });
  });

  group('SendGridMailProvider', () {
    test('posts the v3 personalizations payload', () async {
      final recorder = _Recorder();
      await SendGridMailProvider(apiKey: 'sg_key', transport: recorder.send)
          .send(message);

      expect(recorder.single.url.toString(),
          'https://api.sendgrid.com/v3/mail/send');
      expect(recorder.single.headers['authorization'], 'Bearer sg_key');

      final personalizations =
          recorder.json['personalizations']! as List<Object?>;
      final to = (personalizations.single as Map<String, Object?>)['to']!
          as List<Object?>;
      expect(to, <Object?>[
        <String, Object?>{'email': 'ada@example.com', 'name': 'Ada Lovelace'},
        <String, Object?>{'email': 'grace@example.com'},
      ]);
      expect(recorder.json['from'],
          <String, Object?>{'email': 'support@example.com', 'name': 'Support'});
      expect(recorder.json['content'], <Object?>[
        <String, Object?>{'type': 'text/plain', 'value': 'Thanks for joining'},
        <String, Object?>{
          'type': 'text/html',
          'value': '<p>Thanks for joining</p>',
        },
      ]);
    });

    test('omits the html part when there is none', () async {
      final recorder = _Recorder();
      await SendGridMailProvider(apiKey: 'sg_key', transport: recorder.send)
          .send(const DVMailMessage(
        from: DVMailAddress('a@example.com'),
        to: <DVMailAddress>[DVMailAddress('b@example.com')],
        subject: 'Plain',
        text: 'Body',
      ));

      expect(recorder.json['content'], hasLength(1));
    });
  });

  group('PostmarkMailProvider', () {
    test('posts the Postmark payload with its token header', () async {
      final recorder = _Recorder();
      await PostmarkMailProvider(apiKey: 'pm_token', transport: recorder.send)
          .send(message);

      expect(
          recorder.single.url.toString(), 'https://api.postmarkapp.com/email');
      expect(recorder.single.headers['x-postmark-server-token'], 'pm_token');
      expect(recorder.json['From'], '"Support" <support@example.com>');
      expect(
        recorder.json['To'],
        '"Ada Lovelace" <ada@example.com>, grace@example.com',
      );
      expect(recorder.json['TextBody'], 'Thanks for joining');
      expect(recorder.json['HtmlBody'], '<p>Thanks for joining</p>');
      expect(recorder.json['MessageStream'], 'outbound');
      expect(recorder.json['Headers'], <Object?>[
        <String, Object?>{'Name': 'X-Campaign', 'Value': 'welcome'},
      ]);
    });

    test('honours a custom message stream', () async {
      final recorder = _Recorder();
      await PostmarkMailProvider(
        apiKey: 'pm_token',
        messageStream: 'broadcast',
        transport: recorder.send,
      ).send(message);

      expect(recorder.json['MessageStream'], 'broadcast');
    });
  });

  group('MailgunMailProvider', () {
    test('posts a form-encoded body with basic auth', () async {
      final recorder = _Recorder();
      await MailgunMailProvider(
        apiKey: 'mg_key',
        domain: 'mail.example.com',
        transport: recorder.send,
      ).send(message);

      expect(
        recorder.single.url.toString(),
        'https://api.mailgun.net/v3/mail.example.com/messages',
      );
      expect(
        recorder.single.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('api:mg_key'))}',
      );
      expect(
        recorder.single.headers['content-type'],
        'application/x-www-form-urlencoded',
      );

      final body = recorder.text;
      // Multiple recipients are repeated keys, not a joined string.
      expect('to='.allMatches(body), hasLength(2));
      expect(body, contains('subject=Welcome'));
      expect(body, contains('h%3AX-Campaign=welcome'));
    });

    test('escapes values that would otherwise break the form body', () async {
      final recorder = _Recorder();
      await MailgunMailProvider(
        apiKey: 'mg_key',
        domain: 'mail.example.com',
        transport: recorder.send,
      ).send(const DVMailMessage(
        from: DVMailAddress('a@example.com'),
        to: <DVMailAddress>[DVMailAddress('b@example.com')],
        subject: 'Ampersand & equals = trouble',
        text: 'a=b&c=d',
      ));

      final body = recorder.text;
      // & and = inside a value must be percent-encoded, or they would be read
      // as a field separator and a key/value split.
      expect(body, contains('%26'));
      expect(body, contains('%3D'));
      expect(Uri.splitQueryString(body)['subject'],
          'Ampersand & equals = trouble');
      expect(Uri.splitQueryString(body)['text'], 'a=b&c=d');
    });
  });

  group('shared provider behaviour', () {
    test('a rejected message throws with the status and body', () async {
      final recorder = _Recorder(
        response: const DVHttpResponse(
          statusCode: 422,
          body: '{"message":"invalid from address"}',
        ),
      );

      await expectLater(
        ResendMailProvider(apiKey: 'k', transport: recorder.send).send(message),
        throwsA(
          isA<DVMailProviderException>()
              .having((error) => error.statusCode, 'statusCode', 422)
              .having((error) => error.provider, 'provider', 'resend')
              .having((error) => error.responseBody, 'responseBody',
                  contains('invalid from address')),
        ),
      );
    });

    test('a message with no recipient is rejected before any request',
        () async {
      final recorder = _Recorder();

      await expectLater(
        SendGridMailProvider(apiKey: 'k', transport: recorder.send)
            .send(const DVMailMessage(
          from: DVMailAddress('a@example.com'),
          to: <DVMailAddress>[],
          subject: 's',
          text: 't',
        )),
        throwsArgumentError,
      );
      expect(recorder.requests, isEmpty);
    });

    test('every provider satisfies DVMailProvider', () {
      final providers = <DVMailProvider>[
        ResendMailProvider(apiKey: 'k'),
        SendGridMailProvider(apiKey: 'k'),
        PostmarkMailProvider(apiKey: 'k'),
        MailgunMailProvider(apiKey: 'k', domain: 'd'),
        DVMemoryMailProvider(),
      ];
      expect(providers, everyElement(isA<DVMailProvider>()));
    });

    test('an address with no name is sent bare', () {
      expect(
        DVHttpMailProvider.formatAddress(const DVMailAddress('a@example.com')),
        'a@example.com',
      );
      expect(
        DVHttpMailProvider.formatAddress(
          const DVMailAddress('a@example.com', name: '  '),
        ),
        'a@example.com',
      );
    });
  });
}
