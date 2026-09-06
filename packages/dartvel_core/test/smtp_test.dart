import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A scripted SMTP server. Replies are handed out in order; everything the
/// client writes is recorded so the conversation can be asserted.
class FakeSmtpServer {
  final List<String> _replies;
  final StringBuffer written = StringBuffer();
  final List<String> _pending = <String>[];

  int startTlsCalls = 0;
  bool closed = false;

  FakeSmtpServer(List<String> replies) : _replies = List<String>.of(replies);

  /// Everything the client sent, as lines.
  List<String> get sentLines =>
      written.toString().split('\r\n')..removeWhere((line) => line.isEmpty);

  String get sent => written.toString();

  Future<DVSmtpConnection> connect(
    String host,
    int port, {
    required bool secure,
  }) async =>
      _Connection(this);

  String _nextLine() {
    if (_pending.isNotEmpty) return _pending.removeAt(0);
    if (_replies.isEmpty) {
      throw StateError('The scripted server ran out of replies.');
    }
    final reply = _replies.removeAt(0);
    final lines = reply.split('\r\n');
    _pending.addAll(lines.skip(1));
    return lines.first;
  }
}

class _Connection implements DVSmtpConnection {
  final FakeSmtpServer server;
  _Connection(this.server);

  @override
  Future<String> readLine() async => server._nextLine();

  @override
  Future<void> write(String data) async => server.written.write(data);

  @override
  Future<DVSmtpConnection> startTls() async {
    server.startTlsCalls++;
    return this;
  }

  @override
  Future<void> close() async => server.closed = true;
}

const message = DVMailMessage(
  from: DVMailAddress('support@example.com', name: 'Support'),
  to: <DVMailAddress>[
    DVMailAddress('ada@example.com', name: 'Ada Lovelace'),
    DVMailAddress('grace@example.com'),
  ],
  subject: 'Welcome',
  text: 'Thanks for joining',
);

/// A server that accepts the whole conversation, with the capabilities given.
List<String> happyPath({
  List<String> capabilities = const <String>[],
  int recipients = 2,
}) =>
    <String>[
      '220 smtp.example.com ESMTP',
      <String>[
        for (final capability in capabilities) '250-$capability',
        '250 OK',
      ].join('\r\n'),
      '250 OK', // MAIL FROM
      for (var i = 0; i < recipients; i++) '250 OK', // RCPT TO
      '354 Start mail input',
      '250 Queued',
    ];

void main() {
  group('DVSmtpClient conversation', () {
    test('walks the full send sequence', () async {
      final server = FakeSmtpServer(happyPath());
      await SmtpMailProvider(
        host: 'smtp.example.com',
        connect: server.connect,
      ).send(message);

      expect(server.sentLines, containsAllInOrder(<String>[
        'EHLO dartvel',
        'MAIL FROM:<support@example.com>',
        'RCPT TO:<ada@example.com>',
        'RCPT TO:<grace@example.com>',
        'DATA',
      ]));
      expect(server.sentLines, contains('QUIT'));
      expect(server.closed, isTrue, reason: 'the connection must be released');
    });

    test('sends one RCPT TO per recipient', () async {
      final server = FakeSmtpServer(happyPath());
      await SmtpMailProvider(
        host: 'smtp.example.com',
        connect: server.connect,
      ).send(message);

      expect(
        server.sentLines.where((line) => line.startsWith('RCPT TO')),
        hasLength(2),
      );
    });

    test('issues STARTTLS when the server advertises it', () async {
      final server = FakeSmtpServer(<String>[
        '220 smtp.example.com ESMTP',
        '250-STARTTLS\r\n250 OK',
        '220 Ready to start TLS',
        '250 OK', // EHLO again on the secured channel
        '250 OK',
        '250 OK',
        '250 OK',
        '354 Start mail input',
        '250 Queued',
      ]);

      await SmtpMailProvider(
        host: 'smtp.example.com',
        connect: server.connect,
      ).send(message);

      expect(server.startTlsCalls, 1);
      expect(
        server.sentLines.where((line) => line == 'EHLO dartvel'),
        hasLength(2),
        reason: 'capabilities are re-read on the secured channel',
      );
    });

    test('does not issue STARTTLS on an already secure connection', () async {
      final server = FakeSmtpServer(happyPath(
        capabilities: <String>['STARTTLS'],
      ));

      await SmtpMailProvider(
        host: 'smtp.example.com',
        port: 465,
        secure: true,
        connect: server.connect,
      ).send(message);

      expect(server.startTlsCalls, 0);
    });

    test('authenticates with AUTH LOGIN', () async {
      final server = FakeSmtpServer(<String>[
        '220 smtp.example.com ESMTP',
        '250-AUTH LOGIN\r\n250 OK',
        '334 VXNlcm5hbWU6',
        '334 UGFzc3dvcmQ6',
        '235 Authenticated',
        '250 OK',
        '250 OK',
        '250 OK',
        '354 Start mail input',
        '250 Queued',
      ]);

      await SmtpMailProvider(
        host: 'smtp.example.com',
        secure: true,
        username: 'ada',
        password: 'secret',
        connect: server.connect,
      ).send(message);

      // Credentials are base64 encoded, never sent in the clear.
      expect(server.sent, contains('AUTH LOGIN'));
      expect(server.sent, contains('YWRh'));
      expect(server.sent, contains('c2VjcmV0'));
      expect(server.sent, isNot(contains('secret')));
    });

    test('prefers AUTH PLAIN when advertised', () async {
      final server = FakeSmtpServer(<String>[
        '220 smtp.example.com ESMTP',
        '250-AUTH PLAIN LOGIN\r\n250 OK',
        '235 Authenticated',
        '250 OK',
        '250 OK',
        '250 OK',
        '354 Start mail input',
        '250 Queued',
      ]);

      await SmtpMailProvider(
        host: 'smtp.example.com',
        secure: true,
        username: 'ada',
        password: 'secret',
        connect: server.connect,
      ).send(message);

      expect(server.sent, contains('AUTH PLAIN '));
    });

    test('fails when no supported auth mechanism is advertised', () async {
      final server = FakeSmtpServer(<String>[
        '220 smtp.example.com ESMTP',
        '250-AUTH GSSAPI\r\n250 OK',
      ]);

      await expectLater(
        SmtpMailProvider(
          host: 'smtp.example.com',
          secure: true,
          username: 'ada',
          password: 'secret',
          connect: server.connect,
        ).send(message),
        throwsA(isA<DVSmtpException>()),
      );
      expect(server.closed, isTrue);
    });

    test('surfaces a rejected recipient and still closes the connection',
        () async {
      final server = FakeSmtpServer(<String>[
        '220 smtp.example.com ESMTP',
        '250 OK',
        '250 OK',
        '550 No such user',
      ]);

      await expectLater(
        SmtpMailProvider(host: 'h', connect: server.connect).send(message),
        throwsA(
          isA<DVSmtpException>()
              .having((error) => error.command, 'command', 'RCPT TO')
              .having((error) => error.code, 'code', 550)
              .having((error) => error.isTransient, 'isTransient', isFalse),
        ),
      );
      expect(server.closed, isTrue);
    });

    test('marks a 4xx reply as transient so callers can retry', () async {
      final server = FakeSmtpServer(<String>[
        '220 smtp.example.com ESMTP',
        '250 OK',
        '451 Try again later',
      ]);

      await expectLater(
        SmtpMailProvider(host: 'h', connect: server.connect).send(message),
        throwsA(
          isA<DVSmtpException>()
              .having((error) => error.isTransient, 'isTransient', isTrue),
        ),
      );
    });

    test('rejects a message with no recipient before connecting', () async {
      final server = FakeSmtpServer(const <String>[]);

      await expectLater(
        SmtpMailProvider(host: 'h', connect: server.connect).send(
          const DVMailMessage(
            from: DVMailAddress('a@example.com'),
            to: <DVMailAddress>[],
            subject: 's',
            text: 't',
          ),
        ),
        throwsArgumentError,
      );
      expect(server.sent, isEmpty);
    });
  });

  group('DVSmtpClient.buildMessage', () {
    final date = DateTime.utc(2026, 7, 31, 12, 34, 56);

    String build({String text = 'Body', String? html}) =>
        DVSmtpClient.buildMessage(
          fromHeader: '"Support" <support@example.com>',
          toHeaders: <String>['ada@example.com'],
          subject: 'Welcome',
          text: text,
          html: html,
          date: date,
        );

    test('writes the standard headers and terminator', () {
      final built = build();
      expect(built, contains('From: "Support" <support@example.com>\r\n'));
      expect(built, contains('To: ada@example.com\r\n'));
      expect(built, contains('Subject: Welcome\r\n'));
      expect(built, contains('MIME-Version: 1.0\r\n'));
      expect(built, endsWith('\r\n.\r\n'));
    });

    test('formats the date per RFC 5322', () {
      expect(build(), contains('Date: Fri, 31 Jul 2026 12:34:56 +0000\r\n'));
    });

    test('dot-stuffs a body line that would end the message early', () {
      // A bare "." on its own line is the DATA terminator. Without stuffing,
      // this body would truncate the message and desynchronise the session.
      final built = build(text: 'first\n.\nlast');
      expect(built, contains('first\r\n..\r\nlast'));
      expect(
        '\r\n.\r\n'.allMatches(built),
        hasLength(1),
        reason: 'only the real terminator may appear',
      );
    });

    test('dot-stuffs a leading dot on any line', () {
      expect(build(text: '.hidden'), contains('\r\n..hidden'));
    });

    test('uses multipart/alternative when html is present', () {
      final built = build(html: '<p>Body</p>');
      expect(built, contains('Content-Type: multipart/alternative'));
      expect(built, contains('Content-Type: text/plain; charset=utf-8'));
      expect(built, contains('Content-Type: text/html; charset=utf-8'));
      expect(built, contains('<p>Body</p>'));
    });

    test('uses text/plain when there is no html', () {
      expect(build(), isNot(contains('multipart')));
    });
  });

  _encoding();
}

// ---------------------------------------------------------------------------
// Encoding, which is where a message is accepted and wrong.
//
// Found by sending through a real server and reading back the source: the
// subject went down the wire as raw UTF-8 in a header RFC 5322 says is ASCII,
// and the body declared no transfer encoding at all, which means 7bit, which
// it was not. Mailpit took both without complaint. So does almost everything
// else, and the message arrives looking broken to whoever was sent it.

void _encoding() {
  group('header encoding', () {
    test('ASCII is left exactly as it was', () {
      // Encoding what does not need it would make every ordinary subject
      // unreadable in the source for no gain.
      expect(DVSmtpClient.encodeHeaderValue('Order 4182'), 'Order 4182');
    });

    test('an accent becomes an encoded word that decodes back', () {
      final String encoded = DVSmtpClient.encodeHeaderValue('Café réf 4182');

      expect(encoded, startsWith('=?UTF-8?B?'));
      expect(encoded, endsWith('?='));
      expect(_decodeWords(encoded), 'Café réf 4182');
    });

    test('nothing above 0x7F survives into the header', () {
      // The assertion the live suite makes against a real server, made here
      // where it is cheap.
      for (final int unit
          in DVSmtpClient.encodeHeaderValue('Café — réf').codeUnits) {
        expect(unit, lessThan(0x80));
      }
    });

    test('a long value is split into words no wider than 75', () {
      // RFC 2047 caps an encoded word at 75 characters. A single long one is
      // accepted by servers and folded by some of them in the middle of the
      // base64, which decodes to nothing anybody wants.
      final String encoded =
          DVSmtpClient.encodeHeaderValue('Café ${'réf ' * 40}');

      for (final String word in encoded.split('\r\n ')) {
        expect(word.length, lessThanOrEqualTo(75), reason: word);
      }
    });

    test('no word ends in the middle of a character', () {
      // The quiet one. Base64 split by bytes puts half of a two-byte
      // character at the end of one word and half at the start of the next,
      // and each decodes to a replacement character -- so the subject is
      // wrong in exactly two places and right everywhere else.
      final String encoded =
          DVSmtpClient.encodeHeaderValue('café ' * 30);

      expect(_decodeWords(encoded), 'café ' * 30);
      expect(_decodeWords(encoded), isNot(contains('�')));
    });

    test('an address keeps its angle brackets and encodes only the name', () {
      // Encoding the whole thing encodes the brackets with it, and the
      // result is a header no server can route.
      final String encoded =
          DVSmtpClient.encodeAddressHeader('"Café" <shop@dartvel.dev>');

      expect(encoded, endsWith('<shop@dartvel.dev>'));
      expect(encoded, contains('=?UTF-8?B?'));
    });

    test('an ASCII display name is not touched', () {
      expect(DVSmtpClient.encodeAddressHeader('"Support" <a@b.c>'),
          '"Support" <a@b.c>');
    });
  });

  group('the body', () {
    test('plain ASCII within the line limit needs no encoding', () {
      expect(DVSmtpClient.bodyIsSevenBit('hello\nworld'), isTrue);
    });

    test('an accent is not seven bit, however the header describes it', () {
      expect(DVSmtpClient.bodyIsSevenBit('café'), isFalse);
    });

    test('a line past 998 octets is not seven bit either', () {
      // RFC 5321's limit. What a server does past it is its own choice and
      // none of the choices leave the message as it was sent.
      expect(DVSmtpClient.bodyIsSevenBit('x' * 999), isFalse);
      expect(DVSmtpClient.bodyIsSevenBit('x' * 998), isTrue);
    });

    test('quoted-printable round-trips', () {
      const String body = 'Votre commande — 4182 €\nligne deux';

      expect(_decodeQuotedPrintable(DVSmtpClient.quotedPrintable(body)), body);
    });

    test('an equals sign is escaped, or it reads as an escape', () {
      expect(DVSmtpClient.quotedPrintable('a=b'), contains('=3D'));
      expect(_decodeQuotedPrintable(DVSmtpClient.quotedPrintable('a=b')), 'a=b');
    });

    test('trailing whitespace is encoded rather than left to be stripped', () {
      // A server may trim it, and then the message that arrives is not the
      // message that was sent.
      expect(DVSmtpClient.quotedPrintable('two  '), endsWith('=20'));
    });

    test('no line is longer than the 76 quoted-printable allows', () {
      final String encoded = DVSmtpClient.quotedPrintable('x' * 5000);

      for (final String line in encoded.split('\r\n')) {
        expect(line.length, lessThanOrEqualTo(76), reason: line);
      }
    });

    test('a long line survives the wrapping intact', () {
      // Soft breaks are removed by the reader. If they were hard the message
      // would arrive with newlines nobody typed.
      final String body = 'start ${'x' * 2000} end';

      expect(_decodeQuotedPrintable(DVSmtpClient.quotedPrintable(body)), body);
    });
  });
}

/// Decodes a run of RFC 2047 encoded words, folding and all.
String _decodeWords(String value) {
  final StringBuffer out = StringBuffer();
  for (final String word in value.split('\r\n ')) {
    final RegExpMatch? match =
        RegExp(r'^=\?UTF-8\?B\?(.*)\?=$').firstMatch(word);
    out.write(match == null ? word : utf8.decode(base64.decode(match.group(1)!)));
  }
  return out.toString();
}

/// Decodes quoted-printable: soft breaks away, `=XX` back to bytes.
String _decodeQuotedPrintable(String value) {
  final String joined = value.replaceAll('=\r\n', '');
  final List<int> bytes = <int>[];
  for (int i = 0; i < joined.length; i++) {
    if (joined[i] == '=' && i + 2 < joined.length) {
      bytes.add(int.parse(joined.substring(i + 1, i + 3), radix: 16));
      i += 2;
      continue;
    }
    if (joined[i] == '\r' && i + 1 < joined.length && joined[i + 1] == '\n') {
      bytes.add(0x0A);
      i += 1;
      continue;
    }
    bytes.addAll(utf8.encode(joined[i]));
  }
  return utf8.decode(bytes);
}
