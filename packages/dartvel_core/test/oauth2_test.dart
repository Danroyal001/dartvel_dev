import 'dart:convert';
import 'dart:math';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Recorder {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];
  final List<DVHttpResponse> _responses;

  Recorder([List<DVHttpResponse>? responses])
      : _responses = List<DVHttpResponse>.of(
          responses ??
              const <DVHttpResponse>[
                DVHttpResponse(statusCode: 200, body: '{}'),
              ],
        );

  factory Recorder.json(Object? payload, {int statusCode = 200}) =>
      Recorder(<DVHttpResponse>[
        DVHttpResponse(statusCode: statusCode, body: jsonEncode(payload)),
      ]);

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return _responses.length == 1 ? _responses.first : _responses.removeAt(0);
  }

  DVHttpRequest get single {
    expect(requests, hasLength(1));
    return requests.single;
  }

  Map<String, String> get form =>
      Uri.splitQueryString(utf8.decode(single.body));
}

final config = DVOAuth2Config(
  clientId: 'client-123',
  clientSecret: 'shhh',
  authorizationEndpoint: Uri.https('id.example.com', '/authorize'),
  tokenEndpoint: Uri.https('id.example.com', '/token'),
  userInfoEndpoint: Uri.https('id.example.com', '/userinfo'),
  redirectUri: Uri.https('app.example.com', '/callback'),
  scopes: const <String>['openid', 'email'],
);

DVOAuth2Client client(Recorder recorder, {DVOAuth2Config? using}) =>
    DVOAuth2Client(
      config: using ?? config,
      transport: recorder.send,
      // Seeded so authorization values are reproducible in assertions.
      random: Random(7),
    );

void main() {
  group('createAuthorization', () {
    test('builds an authorization-code URL with PKCE', () {
      final started = client(Recorder()).createAuthorization();
      final query = started.url.queryParameters;

      expect(started.url.host, 'id.example.com');
      expect(started.url.path, '/authorize');
      expect(query['response_type'], 'code');
      expect(query['client_id'], 'client-123');
      expect(query['redirect_uri'], 'https://app.example.com/callback');
      expect(query['scope'], 'openid email');
      expect(query['code_challenge_method'], 'S256');
      expect(query['state'], started.state);
    });

    test('the challenge is the S256 hash of the verifier, not the verifier',
        () {
      final started = client(Recorder()).createAuthorization();

      expect(
        started.url.queryParameters['code_challenge'],
        DVOAuth2Client.codeChallengeFor(started.codeVerifier),
      );
      expect(
        started.url.toString(),
        isNot(contains(started.codeVerifier)),
        reason: 'the verifier must never leave the client',
      );
    });

    test('produces base64url values with no padding', () {
      final started = client(Recorder()).createAuthorization();
      for (final value in <String>[
        started.state,
        started.codeVerifier,
        started.url.queryParameters['code_challenge']!,
      ]) {
        expect(value, isNot(contains('=')));
        expect(value, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      }
    });

    test('gives every attempt a distinct state and verifier', () {
      final unseeded = DVOAuth2Client(config: config);
      final first = unseeded.createAuthorization();
      final second = unseeded.createAuthorization();

      expect(first.state, isNot(second.state));
      expect(first.codeVerifier, isNot(second.codeVerifier));
    });

    test('honours a per-call scope override', () {
      final started =
          client(Recorder()).createAuthorization(scopes: <String>['repo']);
      expect(started.url.queryParameters['scope'], 'repo');
    });
  });

  group('exchangeCode', () {
    test('posts the code, verifier and secret, and reads the tokens', () async {
      final recorder = Recorder.json(<String, Object?>{
        'access_token': 'at-1',
        'refresh_token': 'rt-1',
        'id_token': 'idt-1',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': 'openid email',
      });
      final oauth = client(recorder);
      final started = oauth.createAuthorization();

      final tokens = await oauth.exchangeCode(
        code: 'the-code',
        returnedState: started.state,
        pending: started,
      );

      expect(recorder.single.url.toString(), 'https://id.example.com/token');
      expect(recorder.form['grant_type'], 'authorization_code');
      expect(recorder.form['code'], 'the-code');
      expect(recorder.form['code_verifier'], started.codeVerifier);
      expect(recorder.form['client_id'], 'client-123');
      expect(recorder.form['client_secret'], 'shhh');

      expect(tokens.accessToken, 'at-1');
      expect(tokens.refreshToken, 'rt-1');
      expect(tokens.idToken, 'idt-1');
      expect(tokens.expiresIn, const Duration(hours: 1));
      expect(tokens.scopes, <String>['openid', 'email']);
    });

    test('refuses a callback whose state does not match, before any request',
        () async {
      final recorder = Recorder();
      final oauth = client(recorder);
      final started = oauth.createAuthorization();

      await expectLater(
        oauth.exchangeCode(
          code: 'the-code',
          returnedState: 'attacker-supplied-state',
          pending: started,
        ),
        throwsA(
          isA<DVOAuth2Exception>()
              .having((error) => error.stage, 'stage', 'callback')
              .having((error) => error.message, 'message',
                  contains('did not match')),
        ),
      );
      expect(recorder.requests, isEmpty,
          reason: 'a forged callback must never reach the token endpoint');
    });

    test('rejects an empty code', () async {
      final oauth = client(Recorder());
      final started = oauth.createAuthorization();

      await expectLater(
        oauth.exchangeCode(
          code: '',
          returnedState: started.state,
          pending: started,
        ),
        throwsA(isA<DVOAuth2Exception>()),
      );
    });

    test('omits client_secret for a public client', () async {
      final recorder = Recorder.json(<String, Object?>{'access_token': 'at'});
      final oauth = client(
        recorder,
        using: DVOAuth2Config(
          clientId: 'public-client',
          authorizationEndpoint: config.authorizationEndpoint,
          tokenEndpoint: config.tokenEndpoint,
          redirectUri: config.redirectUri,
        ),
      );
      final started = oauth.createAuthorization();

      await oauth.exchangeCode(
        code: 'c',
        returnedState: started.state,
        pending: started,
      );

      expect(recorder.form.containsKey('client_secret'), isFalse);
      expect(recorder.form['code_verifier'], isNotNull,
          reason: 'PKCE carries the proof when there is no secret');
    });

    test('surfaces an OAuth error payload', () async {
      final recorder = Recorder.json(
        <String, Object?>{
          'error': 'invalid_grant',
          'error_description': 'code already used',
        },
        statusCode: 400,
      );
      final oauth = client(recorder);
      final started = oauth.createAuthorization();

      await expectLater(
        oauth.exchangeCode(
          code: 'c',
          returnedState: started.state,
          pending: started,
        ),
        throwsA(
          isA<DVOAuth2Exception>().having(
            (error) => error.message,
            'message',
            allOf(contains('invalid_grant'), contains('code already used')),
          ),
        ),
      );
    });

    test('reads a form-encoded token response', () async {
      // GitHub answers form-encoded unless asked for JSON.
      final recorder = Recorder(const <DVHttpResponse>[
        DVHttpResponse(
          statusCode: 200,
          body: 'access_token=at-form&token_type=bearer&scope=read%3Auser',
        ),
      ]);
      final oauth = client(recorder);
      final started = oauth.createAuthorization();

      final tokens = await oauth.exchangeCode(
        code: 'c',
        returnedState: started.state,
        pending: started,
      );

      expect(tokens.accessToken, 'at-form');
      expect(tokens.scopes, <String>['read:user']);
    });

    test('rejects a success response with no access token', () async {
      final recorder = Recorder.json(<String, Object?>{'token_type': 'Bearer'});
      final oauth = client(recorder);
      final started = oauth.createAuthorization();

      await expectLater(
        oauth.exchangeCode(
          code: 'c',
          returnedState: started.state,
          pending: started,
        ),
        throwsA(isA<DVOAuth2Exception>().having(
          (error) => error.message,
          'message',
          contains('no access_token'),
        )),
      );
    });
  });

  group('fetchUserInfo', () {
    test('sends the bearer token and returns the profile', () async {
      final recorder = Recorder.json(<String, Object?>{
        'sub': '42',
        'email': 'ada@example.com',
      });

      final profile = await client(recorder).fetchUserInfo(
        const DVOAuth2Tokens(accessToken: 'at-1'),
      );

      expect(recorder.single.method, 'GET');
      expect(recorder.single.url.toString(), 'https://id.example.com/userinfo');
      expect(recorder.single.headers['authorization'], 'Bearer at-1');
      expect(profile['email'], 'ada@example.com');
    });

    test('fails clearly when no userinfo endpoint is configured', () async {
      final oauth = DVOAuth2Client(
        config: DVOAuth2Config(
          clientId: 'c',
          authorizationEndpoint: config.authorizationEndpoint,
          tokenEndpoint: config.tokenEndpoint,
          redirectUri: config.redirectUri,
        ),
      );

      await expectLater(
        oauth.fetchUserInfo(const DVOAuth2Tokens(accessToken: 'at')),
        throwsA(isA<DVOAuth2Exception>()
            .having((error) => error.stage, 'stage', 'userinfo')),
      );
    });
  });

  group('provider presets', () {
    test('carry the documented endpoints', () {
      final redirect = Uri.https('app.example.com', '/callback');

      expect(
        DVOAuth2Config.google(clientId: 'c', redirectUri: redirect)
            .authorizationEndpoint
            .toString(),
        'https://accounts.google.com/o/oauth2/v2/auth',
      );
      expect(
        DVOAuth2Config.github(clientId: 'c', redirectUri: redirect)
            .tokenEndpoint
            .toString(),
        'https://github.com/login/oauth/access_token',
      );
      expect(
        DVOAuth2Config.bitbucket(clientId: 'c', redirectUri: redirect)
            .userInfoEndpoint
            .toString(),
        'https://api.bitbucket.org/2.0/user',
      );
      expect(
        DVOAuth2Config.microsoft(
          clientId: 'c',
          redirectUri: redirect,
          tenant: 'contoso',
        ).tokenEndpoint.toString(),
        'https://login.microsoftonline.com/contoso/oauth2/v2.0/token',
      );
    });

    test('gitlab honours a self-hosted host', () {
      final selfHosted = DVOAuth2Config.gitlab(
        clientId: 'c',
        redirectUri: Uri.https('app.example.com', '/callback'),
        host: Uri.https('git.internal'),
      );

      expect(selfHosted.authorizationEndpoint.host, 'git.internal');
      expect(selfHosted.tokenEndpoint.path, '/oauth/token');
    });
  });
}
