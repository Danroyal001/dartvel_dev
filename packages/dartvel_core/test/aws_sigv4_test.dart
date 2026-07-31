import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// The AWS documentation's example credentials. Not a real key.
const credentials = DVAwsCredentials(
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
);

final timestamp = DateTime.utc(2026, 7, 31, 12, 34, 56);
final url = Uri.https('email.us-east-1.amazonaws.com', '/v2/email/outbound-emails');
final body = utf8.encode('{"hello":"world"}');

Map<String, String> signFixture({
  DVAwsCredentials creds = credentials,
  String region = 'us-east-1',
  String service = 'ses',
  DateTime? at,
  List<int>? payload,
  Uri? target,
}) =>
    DVAwsSigV4.signedHeaders(
      method: 'POST',
      url: target ?? url,
      headers: const <String, String>{'content-type': 'application/json'},
      body: payload ?? body,
      credentials: creds,
      region: region,
      service: service,
      timestamp: at ?? timestamp,
    );

String signatureOf(Map<String, String> headers) =>
    RegExp(r'Signature=([0-9a-f]+)')
        .firstMatch(headers['authorization']!)!
        .group(1)!;

void main() {
  group('DVAwsSigV4', () {
    test('matches a signature computed by an independent implementation', () {
      // Cross-checked against a Python hmac/hashlib implementation of the AWS
      // SigV4 spec for exactly these inputs. If this fails, the Dart signer
      // and the specification have diverged.
      expect(
        signatureOf(signFixture()),
        '77b8f340abdee8f5d823dcc40635113bf7fa8cafbaf55565b7ec9d8a66df8575',
      );
    });

    test('hashes the payload into x-amz-content-sha256', () {
      expect(
        signFixture()['x-amz-content-sha256'],
        '93a23971a914e5eacbf0a8d25154cda309c3c1c72fbb9914d47c60f3cb681588',
      );
    });

    test('formats x-amz-date as yyyyMMddTHHmmssZ in UTC', () {
      expect(signFixture()['x-amz-date'], '20260731T123456Z');
      // A local-time input must be converted, not truncated.
      expect(
        signFixture(at: timestamp.toLocal())['x-amz-date'],
        '20260731T123456Z',
      );
    });

    test('builds the credential scope and signed header list', () {
      final authorization = signFixture()['authorization']!;
      expect(authorization, startsWith('AWS4-HMAC-SHA256 '));
      expect(
        authorization,
        contains('Credential=AKIDEXAMPLE/20260731/us-east-1/ses/aws4_request'),
      );
      expect(
        authorization,
        contains(
          'SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date',
        ),
      );
    });

    test('is deterministic for identical inputs', () {
      expect(signatureOf(signFixture()), signatureOf(signFixture()));
    });

    test('changes when any signed input changes', () {
      final baseline = signatureOf(signFixture());

      expect(
        signatureOf(signFixture(
          creds: const DVAwsCredentials(
            accessKeyId: 'AKIDEXAMPLE',
            secretAccessKey: 'a-different-secret',
          ),
        )),
        isNot(baseline),
        reason: 'a different secret must produce a different signature',
      );
      expect(signatureOf(signFixture(region: 'eu-west-1')), isNot(baseline));
      expect(signatureOf(signFixture(service: 's3')), isNot(baseline));
      expect(
        signatureOf(signFixture(at: DateTime.utc(2026, 7, 31, 12, 34, 57))),
        isNot(baseline),
      );
      expect(
        signatureOf(signFixture(payload: utf8.encode('{"hello":"other"}'))),
        isNot(baseline),
        reason: 'the body is signed, so tampering invalidates the signature',
      );
    });

    test('includes a session token in the signature when present', () {
      final headers = signFixture(
        creds: const DVAwsCredentials(
          accessKeyId: 'AKIDEXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
          sessionToken: 'session-token',
        ),
      );

      expect(headers['x-amz-security-token'], 'session-token');
      expect(headers['authorization'], contains('x-amz-security-token'));
      expect(signatureOf(headers), isNot(signatureOf(signFixture())));
    });

    test('signs the port when the url carries a non-default one', () {
      final signed = signFixture(
        target: Uri.parse('https://localhost:4566/v2/email/outbound-emails'),
      );
      expect(signed['authorization'], contains('host'));
      expect(signatureOf(signed), isNot(signatureOf(signFixture())));
    });

    test('canonicalises query parameters in sorted order', () {
      final unsorted = signFixture(
        target: url.replace(queryParameters: <String, String>{
          'b': '2',
          'a': '1',
        }),
      );
      final sorted = signFixture(
        target: url.replace(queryParameters: <String, String>{
          'a': '1',
          'b': '2',
        }),
      );

      expect(signatureOf(unsorted), signatureOf(sorted),
          reason: 'parameter order in the Uri must not change the signature');
    });
  });
}
