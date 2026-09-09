// DVMailMessage carries a priority and every provider dropped it.
//
// The spec lists priority as part of the typed mail message, and the
// templating extensions in dartvel_flutter thread a `priority:` argument all
// the way down to the constructor. Then the six providers build their wire
// payloads out of from, to, subject, text, html and headers, and never look at
// it. Nothing warns. Marking a password reset high produced a byte-identical
// request to marking it low, so the failure is invisible unless someone opens
// a delivered message's headers, which nobody does.
//
// None of these provider APIs has a priority field. Mail clients read the
// RFC 2156 `Importance` header and the de-facto `X-Priority`, so that is what
// has to reach the wire, through whichever custom-header slot the provider
// offers. SES has such a slot and was the only provider ignoring it, so a
// custom header set on a message vanished there as well.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Recorder {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return const DVHttpResponse(statusCode: 200, body: '{}');
  }

  DVHttpRequest get single {
    expect(requests, hasLength(1));
    return requests.single;
  }

  Map<String, Object?> get json =>
      jsonDecode(utf8.decode(single.body)) as Map<String, Object?>;

  String get text => utf8.decode(single.body);
}

/// A scripted SMTP server that accepts everything, so the DATA section the
/// client wrote can be read back.
class _FakeSmtpServer {
  final StringBuffer written = StringBuffer();
  final List<String> _replies = <String>[
    '220 smtp.example.com ESMTP',
    '250 OK', // EHLO
    '250 OK', // MAIL FROM
    '250 OK', // RCPT TO
    '354 Start mail input',
    '250 Queued',
    '221 Bye',
  ];

  Future<DVSmtpConnection> connect(
    String host,
    int port, {
    required bool secure,
  }) async => _FakeSmtpConnection(this);

  String _nextLine() => _replies.isEmpty ? '221 Bye' : _replies.removeAt(0);
}

class _FakeSmtpConnection implements DVSmtpConnection {
  _FakeSmtpConnection(this.server);

  final _FakeSmtpServer server;

  @override
  Future<String> readLine() async => server._nextLine();

  @override
  Future<void> write(String data) async => server.written.write(data);

  @override
  Future<DVSmtpConnection> startTls() async => this;

  @override
  Future<void> close() async {}
}

DVMailMessage _message(
  DVMailPriority priority, {
  Map<String, String> headers = const <String, String>{},
}) => DVMailMessage(
  from: const DVMailAddress('support@example.com'),
  to: const <DVMailAddress>[DVMailAddress('ada@example.com')],
  subject: 'Reset your password',
  text: 'Use this link',
  priority: priority,
  headers: headers,
);

const _sesCredentials = DVAwsCredentials(
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'secret',
);

SesMailProvider _ses(_Recorder recorder) => SesMailProvider(
  credentials: _sesCredentials,
  region: 'eu-west-1',
  transport: recorder.send,
  now: () => DateTime.utc(2026, 1, 1),
);

Map<String, Object?> _sesSimple(_Recorder recorder) =>
    (recorder.json['Content']! as Map<String, Object?>)['Simple']!
        as Map<String, Object?>;

void main() {
  group('priority as headers', () {
    test('high priority is the headers a mail client actually reads', () {
      expect(dvMailPriorityHeaders(DVMailPriority.high), <String, String>{
        'X-Priority': '1 (Highest)',
        'Importance': 'high',
        'Priority': 'urgent',
      });
    });

    test('low priority is marked so it sorts below the rest', () {
      expect(dvMailPriorityHeaders(DVMailPriority.low), <String, String>{
        'X-Priority': '5 (Lowest)',
        'Importance': 'low',
        'Priority': 'non-urgent',
      });
    });

    test('normal adds nothing, because every message would carry it', () {
      expect(dvMailPriorityHeaders(DVMailPriority.normal), isEmpty);
    });

    test('an explicit header wins over the one priority would add', () {
      final headers = dvMailWireHeaders(
        _message(
          DVMailPriority.high,
          headers: <String, String>{'Importance': 'normal'},
        ),
      );
      expect(headers['Importance'], 'normal');
      expect(headers['X-Priority'], '1 (Highest)');
    });
  });

  group('ResendMailProvider', () {
    test('sends the priority headers', () async {
      final recorder = _Recorder();
      await ResendMailProvider(
        apiKey: 'k',
        transport: recorder.send,
      ).send(_message(DVMailPriority.high));

      expect(recorder.json['headers'], containsPair('Importance', 'high'));
      expect(
        recorder.json['headers'],
        containsPair('X-Priority', '1 (Highest)'),
      );
    });

    test('a normal message carries no headers key at all', () async {
      final recorder = _Recorder();
      await ResendMailProvider(
        apiKey: 'k',
        transport: recorder.send,
      ).send(_message(DVMailPriority.normal));

      expect(recorder.json.containsKey('headers'), isFalse);
    });
  });

  group('SendGridMailProvider', () {
    test('sends the priority headers', () async {
      final recorder = _Recorder();
      await SendGridMailProvider(
        apiKey: 'k',
        transport: recorder.send,
      ).send(_message(DVMailPriority.low));

      expect(recorder.json['headers'], containsPair('Importance', 'low'));
    });
  });

  group('PostmarkMailProvider', () {
    test('sends the priority headers in its name/value list', () async {
      final recorder = _Recorder();
      await PostmarkMailProvider(
        apiKey: 'k',
        transport: recorder.send,
      ).send(_message(DVMailPriority.high));

      final headers = (recorder.json['Headers']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        headers,
        contains(
          equals(<String, Object?>{'Name': 'Importance', 'Value': 'high'}),
        ),
      );
    });
  });

  group('MailgunMailProvider', () {
    test('sends the priority headers with the h: prefix', () async {
      final recorder = _Recorder();
      await MailgunMailProvider(
        apiKey: 'k',
        domain: 'example.com',
        transport: recorder.send,
      ).send(_message(DVMailPriority.high));

      expect(recorder.text, contains('h%3AImportance=high'));
    });
  });

  group('SesMailProvider', () {
    test('carries custom headers, which it used to drop entirely', () async {
      final recorder = _Recorder();
      await _ses(recorder).send(
        _message(
          DVMailPriority.normal,
          headers: <String, String>{'X-Campaign': 'welcome'},
        ),
      );

      expect(_sesSimple(recorder)['Headers'], <Object?>[
        <String, Object?>{'Name': 'X-Campaign', 'Value': 'welcome'},
      ]);
    });

    test('sends the priority headers', () async {
      final recorder = _Recorder();
      await _ses(recorder).send(_message(DVMailPriority.high));

      final headers = (_sesSimple(recorder)['Headers']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        headers,
        contains(
          equals(<String, Object?>{'Name': 'Importance', 'Value': 'high'}),
        ),
      );
    });

    test('a normal message with no headers omits the Headers key', () async {
      final recorder = _Recorder();
      await _ses(recorder).send(_message(DVMailPriority.normal));

      expect(_sesSimple(recorder).containsKey('Headers'), isFalse);
    });

    test(
      'the signature covers the headers, so adding one changes it',
      () async {
        final plain = _Recorder();
        await _ses(plain).send(_message(DVMailPriority.normal));
        final urgent = _Recorder();
        await _ses(urgent).send(_message(DVMailPriority.high));

        expect(
          urgent.single.headers['authorization'],
          isNot(plain.single.headers['authorization']),
          reason:
              'a body-hash signature that ignored the new headers would '
              'have SES reject every high-priority message',
        );
      },
    );
  });

  group('SmtpMailProvider', () {
    test(
      'writes the priority headers into the message it hands SMTP',
      () async {
        final server = _FakeSmtpServer();
        await SmtpMailProvider(
          host: 'smtp.example.com',
          connect: server.connect,
        ).send(_message(DVMailPriority.high));

        expect(server.written.toString(), contains('X-Priority: 1 (Highest)'));
        expect(server.written.toString(), contains('Importance: high'));
      },
    );

    test('a normal message adds no priority header', () async {
      final server = _FakeSmtpServer();
      await SmtpMailProvider(
        host: 'smtp.example.com',
        connect: server.connect,
      ).send(_message(DVMailPriority.normal));

      expect(server.written.toString(), isNot(contains('X-Priority')));
      expect(server.written.toString(), isNot(contains('Importance')));
    });
  });
}
