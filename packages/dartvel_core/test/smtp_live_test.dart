// The SMTP provider against a real SMTP server.
//
// The unit tests for this talk to a connection this repository wrote, which
// proves the client speaks the protocol it was written against and nothing
// about whether a server agrees. What only a real one shows is the part that
// is accepted and wrong:
//
//   * a subject with a non-ASCII character, written as raw bytes into a
//     header RFC 5322 says is ASCII. Most servers take it, and it arrives as
//     mojibake in the clients that do not guess the encoding.
//   * a body of raw UTF-8 with no Content-Transfer-Encoding, which declares
//     itself 7bit by default and is not.
//   * a line over the 998 octets RFC 5321 allows, where what happens next is
//     the server's choice and none of the choices are good.
//
// None of those is an error at the point it is made, which is why they need a
// server that keeps what it was given. Mailpit hands back the raw source, so
// these check what went down the wire rather than what a lenient parser was
// willing to make of it.
@Tags(<String>['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final String? _host = Platform.environment['DARTVEL_SMTP_HOST'];
final int _port =
    int.tryParse(Platform.environment['DARTVEL_SMTP_PORT'] ?? '') ?? 1025;
final String _api =
    Platform.environment['DARTVEL_SMTP_API'] ?? 'http://localhost:8025';

/// Everything Mailpit currently holds, newest first.
Future<List<Map<String, Object?>>> _inbox() async {
  final Map<String, Object?> body = await _json('GET', '/api/v1/messages');
  return <Map<String, Object?>>[
    for (final Object? m in body['messages'] as List<Object?>? ?? const <Object?>[])
      if (m is Map<String, Object?>) m,
  ];
}

Future<Map<String, Object?>> _json(String method, String path) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.openUrl(method, Uri.parse('$_api$path'));
    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 300) {
      throw StateError('$method $path -> ${response.statusCode}: $text');
    }
    return text.trim().isEmpty
        ? const <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

/// The message exactly as it was received, headers and all.
Future<String> _raw(String id) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client
        .openUrl('GET', Uri.parse('$_api/api/v1/message/$id/raw'));
    final HttpClientResponse response = await request.close();
    // Latin-1, deliberately: the point of several of these is whether a byte
    // above 0x7F reached a header at all, and decoding as UTF-8 would either
    // hide it or throw.
    return await response.transform(latin1.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> _clear() async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(
        'DELETE', Uri.parse('$_api/api/v1/messages'));
    await (await request.close()).drain<void>();
  } finally {
    client.close();
  }
}

/// Sends [message] and hands back the raw source of what arrived.
Future<String> _send(DVMailMessage message, {bool authenticated = false}) async {
  await _clear();
  final SmtpMailProvider provider = SmtpMailProvider(
    host: _host!,
    port: _port,
    username: authenticated ? 'dartvel' : null,
    password: authenticated ? 'anything' : null,
  );
  await provider.send(message);

  final List<Map<String, Object?>> arrived = await _inbox();
  expect(arrived, hasLength(1), reason: 'the server should have exactly one');
  return _raw('${arrived.single['ID']}');
}

DVMailMessage _message({
  String subject = 'Order 4182',
  String text = 'Your order is on its way.',
  String? html,
}) =>
    DVMailMessage(
      from: const DVMailAddress('shop@dartvel.dev', name: 'Dartvel'),
      to: const <DVMailAddress>[DVMailAddress('buyer@dartvel.dev')],
      subject: subject,
      text: text,
      html: html,
    );

/// The value of [name] as it appears on the wire, unfolded.
String? _header(String raw, String name) {
  final List<String> lines = const LineSplitter().convert(raw);
  final StringBuffer value = StringBuffer();
  bool found = false;
  for (final String line in lines) {
    if (line.trim().isEmpty) break;
    if (found && (line.startsWith(' ') || line.startsWith('\t'))) {
      value.write(line.trim());
      continue;
    }
    if (found) break;
    if (line.toLowerCase().startsWith('${name.toLowerCase()}:')) {
      found = true;
      value.write(line.substring(name.length + 1).trim());
    }
  }
  return found ? value.toString() : null;
}

void main() {
  if (_host == null) {
    test('smtp live (skipped: no server)', () {},
        skip: 'Set DARTVEL_SMTP_HOST to run against a real SMTP server.');
    return;
  }

  test('an ordinary message is accepted and arrives intact', () async {
    final String raw = await _send(_message());

    expect(_header(raw, 'Subject'), 'Order 4182');
    expect(_header(raw, 'From'), contains('shop@dartvel.dev'));
    expect(_header(raw, 'To'), contains('buyer@dartvel.dev'));
    expect(raw, contains('Your order is on its way.'));
  });

  test('the AUTH exchange completes where the server offers it', () async {
    // Not a password check -- the server accepts any. What is under test is
    // that the client performs AUTH at all when it is configured with
    // credentials, against a server that really runs the exchange rather
    // than a fake that answers 235 to anything.
    final String raw =
        await _send(_message(subject: 'Authenticated'), authenticated: true);

    expect(_header(raw, 'Subject'), 'Authenticated');
  });

  test('a non-ASCII subject reaches the header as ASCII', () async {
    // RFC 5322 headers are ASCII. Written as raw UTF-8 they are accepted by
    // most servers and shown as mojibake by the clients that do not guess,
    // which is a bug nobody sees until somebody sends a message with a name
    // in it.
    final String raw = await _send(_message(subject: 'Café — order réf 4182'));
    final String subject = _header(raw, 'Subject')!;

    for (final int unit in subject.codeUnits) {
      expect(unit, lessThan(0x80),
          reason: 'the subject header carries a byte above 0x7F: $subject');
    }
    // And the encoding has to be reversible, or it is ASCII and wrong.
    expect(subject, contains('=?'));
  });

  test('a non-ASCII subject is still readable at the other end', () async {
    // The other half. An encoded header that decodes to something else is
    // worse than an unencoded one, because it looks correct on the wire.
    await _send(_message(subject: 'Café — order réf 4182'));
    final Map<String, Object?> stored =
        await _json('GET', '/api/v1/message/${(await _inbox()).single['ID']}');

    expect(stored['Subject'], 'Café — order réf 4182');
  });

  test('a non-ASCII body says how it is encoded', () async {
    // A body of raw UTF-8 under no Content-Transfer-Encoding declares itself
    // 7bit by default and is not. Servers without 8BITMIME may refuse it or
    // strip the high bit, and the message arrives readable-ish, which is the
    // worst outcome to debug.
    final String raw = await _send(_message(text: 'Votre commande — 4182 €'));

    expect(_header(raw, 'Content-Transfer-Encoding'), isNotNull);
  });

  test('a line of a single dot does not end the message', () async {
    // The oldest bug in SMTP. A body line that is exactly "." terminates
    // DATA, and everything after it is lost while the server reports
    // success.
    final String raw =
        await _send(_message(text: 'before\n.\nafter the dot line'));

    expect(raw, contains('after the dot line'));
  });

  test('a line longer than the protocol allows still arrives whole', () async {
    // RFC 5321 caps a line at 998 octets and what a server does past that is
    // its own choice. The message has to be wrapped or encoded before it
    // gets there.
    final String long = 'x' * 2000;
    final String raw = await _send(_message(text: 'start $long end'));

    expect(raw, contains('start'));
    expect(raw, contains('end'),
        reason: 'the tail of an over-long line was lost');
  });

  test('text and html arrive as both parts of one message', () async {
    final String raw = await _send(_message(
        text: 'Your order is on its way.',
        html: '<p>Your order is on its way.</p>'));

    expect(_header(raw, 'Content-Type'), contains('multipart/alternative'));
    expect(raw, contains('text/plain'));
    expect(raw, contains('text/html'));
    expect(raw, contains('<p>Your order is on its way.</p>'));
  });
}
