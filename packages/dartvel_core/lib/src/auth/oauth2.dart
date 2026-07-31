/// OAuth 2.0 authorization-code flow with PKCE.
library dartvel_core.auth.oauth2;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../http/transport.dart';

class DVOAuth2Exception implements Exception {
  final String stage;
  final String message;
  final int? statusCode;
  final String? responseBody;

  const DVOAuth2Exception(
    this.stage,
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    return 'DVOAuth2Exception[$stage]$status: $message';
  }
}

/// Endpoints and client identity for one identity provider.
class DVOAuth2Config {
  final String clientId;

  /// Omitted for public clients, where PKCE alone protects the exchange.
  final String? clientSecret;

  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri? userInfoEndpoint;
  final Uri redirectUri;
  final List<String> scopes;

  const DVOAuth2Config({
    required this.clientId,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.redirectUri,
    this.clientSecret,
    this.userInfoEndpoint,
    this.scopes = const <String>[],
  });

  /// Endpoints for the identity providers the spec names. Each still needs a
  /// `clientId` and `redirectUri`.
  static DVOAuth2Config google({
    required String clientId,
    required Uri redirectUri,
    String? clientSecret,
    List<String> scopes = const <String>['openid', 'email', 'profile'],
  }) =>
      DVOAuth2Config(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
        scopes: scopes,
        authorizationEndpoint:
            Uri.https('accounts.google.com', '/o/oauth2/v2/auth'),
        tokenEndpoint: Uri.https('oauth2.googleapis.com', '/token'),
        userInfoEndpoint:
            Uri.https('openidconnect.googleapis.com', '/v1/userinfo'),
      );

  static DVOAuth2Config github({
    required String clientId,
    required Uri redirectUri,
    String? clientSecret,
    List<String> scopes = const <String>['read:user', 'user:email'],
  }) =>
      DVOAuth2Config(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
        scopes: scopes,
        authorizationEndpoint: Uri.https('github.com', '/login/oauth/authorize'),
        tokenEndpoint: Uri.https('github.com', '/login/oauth/access_token'),
        userInfoEndpoint: Uri.https('api.github.com', '/user'),
      );

  static DVOAuth2Config gitlab({
    required String clientId,
    required Uri redirectUri,
    String? clientSecret,
    Uri? host,
    List<String> scopes = const <String>['read_user'],
  }) {
    final base = host ?? Uri.https('gitlab.com');
    return DVOAuth2Config(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes,
      authorizationEndpoint: base.replace(path: '/oauth/authorize'),
      tokenEndpoint: base.replace(path: '/oauth/token'),
      userInfoEndpoint: base.replace(path: '/api/v4/user'),
    );
  }

  static DVOAuth2Config bitbucket({
    required String clientId,
    required Uri redirectUri,
    String? clientSecret,
    List<String> scopes = const <String>['account'],
  }) =>
      DVOAuth2Config(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
        scopes: scopes,
        authorizationEndpoint:
            Uri.https('bitbucket.org', '/site/oauth2/authorize'),
        tokenEndpoint: Uri.https('bitbucket.org', '/site/oauth2/access_token'),
        userInfoEndpoint: Uri.https('api.bitbucket.org', '/2.0/user'),
      );

  static DVOAuth2Config microsoft({
    required String clientId,
    required Uri redirectUri,
    String tenant = 'common',
    String? clientSecret,
    List<String> scopes = const <String>['openid', 'email', 'profile'],
  }) =>
      DVOAuth2Config(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
        scopes: scopes,
        authorizationEndpoint: Uri.https(
            'login.microsoftonline.com', '/$tenant/oauth2/v2.0/authorize'),
        tokenEndpoint:
            Uri.https('login.microsoftonline.com', '/$tenant/oauth2/v2.0/token'),
        userInfoEndpoint: Uri.https('graph.microsoft.com', '/oidc/userinfo'),
      );
}

/// A started authorization. Hold this until the provider redirects back: the
/// [state] proves the callback belongs to this attempt and the
/// [codeVerifier] proves the exchange comes from whoever started it.
class DVOAuth2Authorization {
  final Uri url;
  final String state;
  final String codeVerifier;

  const DVOAuth2Authorization({
    required this.url,
    required this.state,
    required this.codeVerifier,
  });
}

class DVOAuth2Tokens {
  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final String tokenType;
  final Duration? expiresIn;
  final List<String> scopes;

  const DVOAuth2Tokens({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.tokenType = 'Bearer',
    this.expiresIn,
    this.scopes = const <String>[],
  });
}

/// Drives the authorization-code flow with PKCE.
class DVOAuth2Client {
  final DVOAuth2Config config;
  final DVHttpSend transport;
  final Random _random;

  DVOAuth2Client({
    required this.config,
    this.transport = dvSendHttpRequest,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Builds the URL to send the user to, plus the secrets needed to finish.
  DVOAuth2Authorization createAuthorization({List<String>? scopes}) {
    final state = _randomToken();
    final verifier = _randomToken(64);
    final challenge = codeChallengeFor(verifier);
    final requested = scopes ?? config.scopes;

    return DVOAuth2Authorization(
      url: config.authorizationEndpoint.replace(
        queryParameters: <String, String>{
          ...config.authorizationEndpoint.queryParameters,
          'response_type': 'code',
          'client_id': config.clientId,
          'redirect_uri': config.redirectUri.toString(),
          'state': state,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          if (requested.isNotEmpty) 'scope': requested.join(' '),
        },
      ),
      state: state,
      codeVerifier: verifier,
    );
  }

  /// Exchanges the callback code for tokens.
  ///
  /// [returnedState] must equal the state from [pending]; a mismatch means the
  /// callback did not come from the authorization this client started, which
  /// is the CSRF case, and the exchange is refused before any request is made.
  Future<DVOAuth2Tokens> exchangeCode({
    required String code,
    required String returnedState,
    required DVOAuth2Authorization pending,
  }) async {
    if (!_constantTimeEquals(returnedState, pending.state)) {
      throw const DVOAuth2Exception(
        'callback',
        'The state returned by the provider did not match this '
            'authorization. The callback was not initiated here.',
      );
    }
    if (code.isEmpty) {
      throw const DVOAuth2Exception('callback', 'The callback carried no code.');
    }

    final response = await transport(DVHttpRequest(
      url: config.tokenEndpoint,
      headers: <String, String>{
        'content-type': 'application/x-www-form-urlencoded',
        'accept': 'application/json',
      },
      body: dvEncodeFormBody(<(String, String)>[
        ('grant_type', 'authorization_code'),
        ('code', code),
        ('client_id', config.clientId),
        ('redirect_uri', config.redirectUri.toString()),
        ('code_verifier', pending.codeVerifier),
        // Public clients have no secret; PKCE carries the proof instead.
        if (config.clientSecret case final secret?) ('client_secret', secret),
      ]),
    ));

    final payload = _decode(response, 'token');
    if (payload['error'] != null) {
      throw DVOAuth2Exception(
        'token',
        'The provider refused the exchange: ${payload['error']}'
            '${payload['error_description'] == null ? '' : ' — '
                '${payload['error_description']}'}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final accessToken = payload['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw DVOAuth2Exception(
        'token',
        'The response carried no access_token.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final expires = payload['expires_in'];
    final scope = payload['scope'];
    return DVOAuth2Tokens(
      accessToken: accessToken,
      refreshToken: payload['refresh_token'] as String?,
      idToken: payload['id_token'] as String?,
      tokenType: payload['token_type'] as String? ?? 'Bearer',
      expiresIn: expires is num ? Duration(seconds: expires.toInt()) : null,
      scopes: scope is String && scope.isNotEmpty
          ? List<String>.unmodifiable(scope.split(RegExp(r'[\s,]+')))
          : const <String>[],
    );
  }

  /// Fetches the profile from the configured user-info endpoint.
  Future<Map<String, Object?>> fetchUserInfo(DVOAuth2Tokens tokens) async {
    final endpoint = config.userInfoEndpoint;
    if (endpoint == null) {
      throw const DVOAuth2Exception(
        'userinfo',
        'This configuration has no userInfoEndpoint.',
      );
    }
    final response = await transport(DVHttpRequest(
      url: endpoint,
      method: 'GET',
      headers: <String, String>{
        'authorization': '${tokens.tokenType} ${tokens.accessToken}',
        'accept': 'application/json',
      },
    ));
    return _decode(response, 'userinfo');
  }

  Map<String, Object?> _decode(DVHttpResponse response, String stage) {
    if (!response.isSuccess && response.body.isEmpty) {
      throw DVOAuth2Exception(
        stage,
        'The provider rejected the request.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      // Some providers answer form-encoded unless asked for JSON.
      final parsed = Uri.splitQueryString(response.body);
      if (parsed.isEmpty) {
        throw DVOAuth2Exception(
          stage,
          'The response was neither JSON nor form-encoded.',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
      return Map<String, Object?>.from(parsed);
    }
    if (decoded is! Map<String, Object?>) {
      throw DVOAuth2Exception(
        stage,
        'Expected a JSON object.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    if (!response.isSuccess && decoded['error'] == null) {
      throw DVOAuth2Exception(
        stage,
        'The provider rejected the request.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    return decoded;
  }

  /// RFC 7636 S256 challenge: base64url(sha256(verifier)), unpadded.
  static String codeChallengeFor(String verifier) =>
      _base64Url(sha256.convert(ascii.encode(verifier)).bytes);

  String _randomToken([int bytes = 32]) => _base64Url(
        List<int>.generate(bytes, (_) => _random.nextInt(256)),
      );

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return difference == 0;
  }
}
