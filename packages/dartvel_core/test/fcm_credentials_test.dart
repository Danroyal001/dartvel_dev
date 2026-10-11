// Service-account credentials for FCM HTTP v1. Shapes are from Google's
// "Using OAuth 2.0 for Server to Server Applications" (the jwt-bearer grant)
// and the service-account key file format. Nothing here reaches a Google
// endpoint: the token exchange goes through an injected transport.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

import 'fixtures/fcm_test_key.dart';

String serviceAccountJson({String? tokenUri}) =>
    jsonEncode(<String, Object?>{
      'type': 'service_account',
      'project_id': 'demo-project',
      'private_key_id': 'abc123',
      'private_key': fcmTestPrivateKeyPem,
      'client_email': 'push@demo-project.iam.gserviceaccount.com',
      'client_id': '1234567890',
      'token_uri': tokenUri ?? 'https://oauth2.googleapis.com/token',
    });

Map<String, Object?> decodeSegment(String segment) {
  final String padded = segment + '=' * ((4 - segment.length % 4) % 4);
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, Object?>;
}

void main() {
  group('DVGoogleServiceAccount', () {
    test('reads the key file Google hands out', () {
      final DVGoogleServiceAccount account =
          DVGoogleServiceAccount.fromJson(serviceAccountJson());
      expect(account.projectId, 'demo-project');
      expect(account.clientEmail, 'push@demo-project.iam.gserviceaccount.com');
      expect(account.tokenUri.toString(), 'https://oauth2.googleapis.com/token');
    });

    test('refuses a file that is not a service account', () {
      expect(
        () => DVGoogleServiceAccount.fromJson(
            jsonEncode(<String, Object?>{'type': 'authorized_user'})),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => DVGoogleServiceAccount.fromJson('not json'),
          throwsA(isA<ArgumentError>()));
      expect(
        () => DVGoogleServiceAccount.fromJson(jsonEncode(<String, Object?>{
          'type': 'service_account',
          'project_id': 'p',
          'client_email': 'a@b',
        })),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an error never carries the private key', () {
      try {
        DVGoogleServiceAccount.fromJson(jsonEncode(<String, Object?>{
          'type': 'service_account',
          'project_id': 'p',
          'client_email': 'a@b',
          'private_key': 'not a pem $fcmTestPrivateKeyPem'.substring(0, 40),
          'token_uri': 'https://oauth2.googleapis.com/token',
        })).signAssertion(scope: 'x');
        fail('a malformed key must throw');
      } on Object catch (error) {
        expect('$error', isNot(contains('PRIVATE KEY-----\nMII')));
      }
    });

    test('toString names the account and nothing secret', () {
      final DVGoogleServiceAccount account =
          DVGoogleServiceAccount.fromJson(serviceAccountJson());
      expect('$account', contains('push@demo-project'));
      expect('$account', isNot(contains('PRIVATE')));
      expect('$account', isNot(contains('MIIE')));
    });

    test('refuses a token_uri that is not https', () {
      expect(
        () => DVGoogleServiceAccount.fromJson(
            serviceAccountJson(tokenUri: 'http://evil.example/token')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the JWT assertion has the claims and an RS256 signature Google checks',
        () {
      final DVGoogleServiceAccount account =
          DVGoogleServiceAccount.fromJson(serviceAccountJson());
      final DateTime now = DateTime.utc(2026, 10, 11, 12);
      final String jwt = account.signAssertion(
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        now: now,
      );
      final List<String> parts = jwt.split('.');
      expect(parts, hasLength(3));

      expect(decodeSegment(parts[0]),
          <String, Object?>{'alg': 'RS256', 'typ': 'JWT', 'kid': 'abc123'});
      final Map<String, Object?> claims = decodeSegment(parts[1]);
      expect(claims['iss'], 'push@demo-project.iam.gserviceaccount.com');
      expect(claims['scope'], 'https://www.googleapis.com/auth/firebase.messaging');
      expect(claims['aud'], 'https://oauth2.googleapis.com/token');
      final int issuedAt = now.millisecondsSinceEpoch ~/ 1000;
      expect(claims['iat'], issuedAt);
      // Google refuses an assertion that lives longer than an hour.
      expect(claims['exp'], issuedAt + 3600);

      // The signature verifies against the matching public key: the check
      // Google runs, done here with the public half.
      final RSAPublicKey publicKey = DVPatchSigning.publicKey(fcmTestPublicKeyPem);
      final RSASigner verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
      final String signature = parts[2];
      final Uint8List bytes = Uint8List.fromList(base64Url
          .decode(signature + '=' * ((4 - signature.length % 4) % 4)));
      expect(
        verifier.verifySignature(
          Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
          RSASignature(bytes),
        ),
        isTrue,
      );
    });

    test('reads from DV Secrets, as raw JSON or base64', () {
      final DVSecretsState saved = DVSecrets.captureState();
      addTearDown(() => DVSecrets.restoreState(saved));
      DVSecrets.configure(<String, String>{
        'FCM_SERVICE_ACCOUNT_JSON': serviceAccountJson(),
      });
      expect(DVGoogleServiceAccount.fromSecrets().projectId, 'demo-project');

      DVSecrets.configure(<String, String>{
        'FCM_SERVICE_ACCOUNT_JSON':
            base64.encode(utf8.encode(serviceAccountJson())),
      });
      expect(DVGoogleServiceAccount.fromSecrets().projectId, 'demo-project');
    });

    test('the key it read from Secrets is redacted from any log line', () {
      final DVSecretsState saved = DVSecrets.captureState();
      addTearDown(() => DVSecrets.restoreState(saved));
      DVSecrets.configure(<String, String>{
        'FCM_SERVICE_ACCOUNT_JSON': serviceAccountJson(),
      });
      DVGoogleServiceAccount.fromSecrets();
      expect(
        dvRedactSecrets('failed with ${serviceAccountJson()}'),
        isNot(contains('MIIE')),
      );
    });

    test('names the missing secret when there is none', () {
      final DVSecretsState saved = DVSecrets.captureState();
      addTearDown(() => DVSecrets.restoreState(saved));
      expect(() => DVGoogleServiceAccount.fromSecrets(),
          throwsA(isA<DVSecretNotFoundException>()));
    });
  });

  group('DVGoogleAccessTokens', () {
    late DVGoogleServiceAccount account;
    late DateTime now;
    late List<DVHttpRequest> requests;
    late List<DVHttpResponse> answers;

    setUp(() {
      account = DVGoogleServiceAccount.fromJson(serviceAccountJson());
      now = DateTime.utc(2026, 10, 11, 12);
      requests = <DVHttpRequest>[];
      answers = <DVHttpResponse>[];
    });

    DVGoogleAccessTokens tokens() => DVGoogleAccessTokens(
          account: account,
          scope: 'https://www.googleapis.com/auth/firebase.messaging',
          clock: () => now,
          transport: (DVHttpRequest request) async {
            requests.add(request);
            return answers.removeAt(0);
          },
        );

    DVHttpResponse granted(String token, {int expiresIn = 3599}) =>
        DVHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'access_token': token,
            'expires_in': expiresIn,
            'token_type': 'Bearer',
          }),
        );

    test('posts the jwt-bearer grant to token_uri', () async {
      answers.add(granted('ya29.one'));
      expect(await tokens().call(), 'ya29.one');

      final DVHttpRequest request = requests.single;
      expect(request.url.toString(), 'https://oauth2.googleapis.com/token');
      expect(request.method, 'POST');
      expect(request.headers['content-type'],
          'application/x-www-form-urlencoded');
      final Map<String, String> form =
          Uri.splitQueryString(utf8.decode(request.body));
      expect(form['grant_type'], 'urn:ietf:params:oauth:grant-type:jwt-bearer');
      expect(form['assertion']!.split('.'), hasLength(3));
    });

    test('reuses the token until shortly before it expires', () async {
      answers
        ..add(granted('ya29.one'))
        ..add(granted('ya29.two'));
      final DVGoogleAccessTokens source = tokens();
      expect(await source.call(), 'ya29.one');
      now = now.add(const Duration(minutes: 30));
      expect(await source.call(), 'ya29.one');
      expect(requests, hasLength(1));

      // Inside the refresh margin: a token about to lapse is not handed out.
      now = now.add(const Duration(minutes: 29, seconds: 30));
      expect(await source.call(), 'ya29.two');
      expect(requests, hasLength(2));
    });

    test('invalidate forces a fresh exchange', () async {
      answers
        ..add(granted('ya29.one'))
        ..add(granted('ya29.two'));
      final DVGoogleAccessTokens source = tokens();
      await source.call();
      source.invalidate();
      expect(await source.call(), 'ya29.two');
    });

    test('concurrent callers share one exchange', () async {
      answers.add(granted('ya29.one'));
      final DVGoogleAccessTokens source = tokens();
      final List<String> results =
          await Future.wait(<Future<String>>[source.call(), source.call()]);
      expect(results, <String>['ya29.one', 'ya29.one']);
      expect(requests, hasLength(1));
    });

    test('an invalid_grant answer is an error that quotes no credential',
        () async {
      answers.add(const DVHttpResponse(
        statusCode: 400,
        body: '{"error":"invalid_grant","error_description":"Invalid JWT Signature."}',
      ));
      try {
        await tokens().call();
        fail('a rejected exchange must throw');
      } on DVPushProviderException catch (error) {
        expect(error.statusCode, 400);
        expect(error.errorCode, 'invalid_grant');
        expect(error.message, contains('Invalid JWT Signature'));
        expect('$error', isNot(contains('MIIE')));
        expect('$error', isNot(contains(
            Uri.splitQueryString(utf8.decode(requests.single.body))['assertion']!)));
      }
    });

    test('a failed exchange is not cached', () async {
      answers
        ..add(const DVHttpResponse(statusCode: 503, body: ''))
        ..add(granted('ya29.ok'));
      final DVGoogleAccessTokens source = tokens();
      await expectLater(source.call(), throwsA(isA<DVPushProviderException>()));
      expect(await source.call(), 'ya29.ok');
    });
  });
}
