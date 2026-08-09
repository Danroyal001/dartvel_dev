// The contract between what a generated client sends and what a generated
// backend parses.
//
// These two halves are generated separately and never meet in any other test:
// the client tests read emitted text, the backend tests call the router
// directly with a body they built themselves. So an encoder change that the
// server cannot parse breaks every POST and nothing notices.
//
// This encodes with the client's encoders and parses with the parser the
// backend generates — MimeMultipartTransformer for forms, Uri.splitQueryString
// for urlencoded, jsonDecode otherwise.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:mime/mime.dart';
import 'package:test/test.dart';

/// The backend's multipart parsing, as `_parseMultipart` generates it.
Future<Map<String, Object?>> parseMultipart(
  List<int> body,
  String contentType,
) async {
  final boundary = RegExp(r'boundary=([^;]+)')
          .firstMatch(contentType)
          ?.group(1)
          ?.replaceAll('"', '') ??
      '';
  if (boundary.isEmpty) return <String, Object?>{};
  final parts = Stream<List<int>>.value(body)
      .transform(MimeMultipartTransformer(boundary));
  final out = <String, Object?>{};
  await for (final part in parts) {
    final disposition = part.headers['content-disposition'] ?? '';
    final name =
        RegExp(r'name="([^"]+)"').firstMatch(disposition)?.group(1) ?? '';
    out[name] = await utf8.decodeStream(part);
  }
  return out;
}

void main() {
  group('multipart', () {
    test('the fields a client encodes are the fields a backend reads',
        () async {
      final boundary = dvGenerateMultipartBoundary();
      final body = dvEncodeMultipartFields(
        boundary: boundary,
        fields: <String, String>{'name': 'Ada', 'role': 'admin'},
      );

      final parsed = await parseMultipart(
          body, 'multipart/form-data; boundary=$boundary');

      expect(parsed, <String, Object?>{'name': 'Ada', 'role': 'admin'});
    });

    test('a value with newlines and quotes survives', () async {
      // A delimiter appearing inside a value is how a naive encoder corrupts
      // the message, and the failure looks like a missing field.
      final boundary = dvGenerateMultipartBoundary();
      final body = dvEncodeMultipartFields(
        boundary: boundary,
        fields: <String, String>{
          'bio': 'line one\r\nline two',
          'quote': 'she said "hello"',
        },
      );

      final parsed = await parseMultipart(
          body, 'multipart/form-data; boundary=$boundary');

      expect(parsed['bio'], 'line one\r\nline two');
      expect(parsed['quote'], 'she said "hello"');
    });

    test('an empty form is still a well-formed message', () async {
      final boundary = dvGenerateMultipartBoundary();
      final body = dvEncodeMultipartFields(
          boundary: boundary, fields: const <String, String>{});

      final parsed = await parseMultipart(
          body, 'multipart/form-data; boundary=$boundary');

      expect(parsed, isEmpty);
    });

    test('a form token is cross-checked against the header, not trusted alone',
        () async {
      // The client sets the token in both places. The header is what
      // validates; the form copy exists so a request that carries a different
      // one is refused rather than accepted on the header alone.
      const token = 'abcdefghijklmnopqrstuvwxyz012345';
      final boundary = dvGenerateMultipartBoundary();
      final body = dvEncodeMultipartFields(
        boundary: boundary,
        fields: <String, String>{DVCSRF.fieldName: token, 'name': 'Ada'},
      );
      final parsed = await parseMultipart(
          body, 'multipart/form-data; boundary=$boundary');

      expect(parsed[DVCSRF.fieldName], token);
      expect(
        const DVCSRF().validateRequest(
          method: 'POST',
          headerToken: token,
          bodyToken: parsed[DVCSRF.fieldName]?.toString(),
        ),
        isTrue,
        reason: 'the encoding must carry the token the header agrees with',
      );
    });

    test('a form token disagreeing with the header is refused', () async {
      const headerToken = 'abcdefghijklmnopqrstuvwxyz012345';
      final boundary = dvGenerateMultipartBoundary();
      final body = dvEncodeMultipartFields(
        boundary: boundary,
        fields: <String, String>{
          DVCSRF.fieldName: 'ZZZZZZZZZZZZZZZZZZZZZZZZZZ012345',
        },
      );
      final parsed = await parseMultipart(
          body, 'multipart/form-data; boundary=$boundary');

      // Accepting on the header alone would make the form copy decorative.
      expect(
        const DVCSRF().validateRequest(
          method: 'POST',
          headerToken: headerToken,
          bodyToken: parsed[DVCSRF.fieldName]?.toString(),
        ),
        isFalse,
      );
    });

    test('a token too short to be genuine is refused', () {
      expect(
        const DVCSRF().validateRequest(
          method: 'POST',
          headerToken: 'short',
        ),
        isFalse,
      );
    });

    test('the boundary is unique per message', () {
      // A boundary reused across messages with different content is how one
      // request's body ends up terminating another's.
      expect(dvGenerateMultipartBoundary(),
          isNot(dvGenerateMultipartBoundary()));
    });
  });

  group('form-urlencoded', () {
    test('what the client encodes is what splitQueryString returns', () {
      final body = dvEncodeFormBody(<(String, String)>[
        ('name', 'Ada Lovelace'),
        ('role', 'admin & owner'),
      ]);

      // The backend parses this exact way.
      final parsed = Uri.splitQueryString(utf8.decode(body));

      expect(parsed, <String, String>{
        'name': 'Ada Lovelace',
        'role': 'admin & owner',
      });
    });

    test('a value containing the separators does not split the message', () {
      final body =
          dvEncodeFormBody(<(String, String)>[('q', 'a=1&b=2'), ('page', '2')]);

      final parsed = Uri.splitQueryString(utf8.decode(body));

      expect(parsed['q'], 'a=1&b=2');
      expect(parsed['page'], '2');
    });
  });

  group('json', () {
    test('a JSON body decodes to the map the handler is called with', () {
      final payload = <String, Object?>{
        'id': 'a1',
        'seats': 3,
        'active': true,
        'nested': <String, Object?>{'k': 'v'},
      };

      final body = utf8.encode(jsonEncode(payload));
      // The backend decodes with jsonDecode when the type is application/json.
      expect(jsonDecode(utf8.decode(body)), payload);
    });
  });
}
