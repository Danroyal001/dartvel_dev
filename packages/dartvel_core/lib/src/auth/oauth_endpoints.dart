/// The OAuth provider's HTTP endpoints: authorization, token, introspection,
/// revocation and the RFC 8414 metadata document.
///
/// `DVOAuthProvider` could do each of these and nothing served them. The
/// generated backend registers these handlers when `dartvel.platformApi.oauth`
/// is on, inside the request's tenant scope. What goes wrong at an OAuth
/// endpoint still answers, so each guard says where it is:
///
/// * the token, introspection and revocation endpoints take a form POST and
///   nothing else (RFC 6749 3.2, RFC 7662 2.1, RFC 7009 2.1); a GET or a JSON
///   body is refused before any code or token in it is looked at, so a
///   refused request spends nothing;
/// * a parameter sent twice, or a client authenticating two ways, is
///   `invalid_request` rather than whichever one a parser kept;
/// * introspection answers only a confidential client or a key whose scopes
///   cover [DVOAuthEndpoints.introspectAction] -- never an anonymous or
///   public caller, for whom it would be an oracle on stolen tokens;
/// * every response carrying a token, and every error, is `no-store`;
/// * the authorization endpoint is a browser navigation and carries no CORS
///   headers, while the token and revocation endpoints and the metadata
///   document allow any origin without credentials, as a browser-based
///   client needs;
/// * nothing from a request -- a code, a token, a secret -- is logged, and
///   errors carry fixed text.
library dartvel_core.auth.oauth_endpoints;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../http/wintercg.dart';
import '../middleware/body_limit.dart';
import '../observability/observability.dart';
import '../tenancy/tenants.dart';
import 'api_scopes.dart';
import 'oauth_provider.dart';
import 'platform_api.dart';

/// Handlers for the generated OAuth routes.
class DVOAuthEndpoints {
  const DVOAuthEndpoints._();

  static const String authorizePath = '/oauth/authorize';

  /// What the consent screen reads: the client and the scope wording.
  static const String authorizationRequestPath = '/oauth/authorize/request';
  static const String tokenPath = '/oauth/token';
  static const String introspectionPath = '/oauth/introspect';
  static const String revocationPath = '/oauth/revoke';
  static const String metadataPath = '/.well-known/oauth-authorization-server';

  /// Where a valid authorization request is sent to be answered.
  static const String consentPath = '/oauth/consent';

  /// The action a scope covers for its holder to introspect tokens. Defined
  /// by the framework, so a scope naming it needs no application policy.
  static const String introspectAction = 'DVOAuthToken.introspect';

  /// The most a form body to these endpoints may be.
  static const int maxBodyBytes = 16 * 1024;

  /// Who is signed in on [request], answered by the application's own auth.
  ///
  /// Null, or an answer of null, and nobody can approve an authorization:
  /// the provider cannot grant a partner access to a person it cannot name.
  static Future<String?> Function(Request request)? resolveUser;

  static final RegExp _host = RegExp(
    r'^(?:[A-Za-z0-9.\-]+|\[[0-9A-Fa-f:.]+\])(?::\d{1,5})?$',
  );

  // --- authorization ---------------------------------------------------------

  /// `GET /oauth/authorize`: a valid request is sent to the consent screen
  /// with its parameters; an unknown client or unregistered redirect URI is
  /// shown and never redirected; any other error goes back to the client.
  static Future<Response> authorize(Request request) => _guard(() async {
    final DVOAuthProvider? provider = await _provider();
    if (provider == null) return _notServed();
    final _Validated v = await _validate(
      provider,
      request.url.queryParametersAll,
    );
    final DVOAuthError? error = v.error;
    if (error != null) {
      final String? back = v.errorRedirect;
      if (back == null) {
        return _text(
          400,
          'The authorization request is invalid (${error.error}).',
        );
      }
      return _redirect(back);
    }
    return _redirect(
      Uri(path: consentPath, queryParameters: v.query).toString(),
    );
  }, json: false);

  /// `GET /oauth/authorize/request`: the client and each scope with the
  /// words its declaration gave it, for the consent screen.
  static Future<Response> authorizationRequest(Request request) =>
      _guard(() async {
        final DVOAuthProvider? provider = await _provider();
        if (provider == null) return _notServed();
        final _Validated v = await _validate(
          provider,
          request.url.queryParametersAll,
        );
        final DVAuthorizationRequest? valid = v.request;
        if (valid == null) return _validationError(v);
        return _json(200, <String, Object?>{
          'client': <String, Object?>{
            'id': valid.client.id,
            'name': valid.client.name,
          },
          'scopes': <Object?>[
            for (final (String scope, String description) in provider.describe(
              valid,
            ))
              <String, Object?>{'scope': scope, 'description': description},
          ],
          'redirect_uri': valid.redirectUri,
          if (valid.state != null) 'state': valid.state,
        });
      });

  /// `POST /oauth/authorize`: the signed-in person's answer, as a form with
  /// the authorization parameters and `decision=approve` or `deny`. Answers
  /// `{"redirect_to": ...}` for the consent screen to navigate to, because a
  /// script following a redirect to the partner's origin could not read it.
  ///
  /// CSRF is the generated route's to check, as on every other POST.
  static Future<Response> approve(Request request) => _guard(() async {
    final DVOAuthProvider? provider = await _provider();
    if (provider == null) return _notServed();
    final _Form form = await _form(request, allow: 'GET, POST');
    final Response? refused = form.refused;
    if (refused != null) return refused;
    final String? userId = await resolveUser?.call(request);
    if (userId == null || userId.isEmpty) {
      return _json(401, const <String, Object?>{
        'error': 'login_required',
        'error_description': 'sign in to answer this request',
      });
    }
    final _Validated v = await _validate(provider, <String, List<String>>{
      for (final MapEntry<String, String> e in form.fields.entries)
        e.key: <String>[e.value],
    });
    final DVAuthorizationRequest? valid = v.request;
    if (valid == null) return _validationError(v);
    switch (form.fields['decision']) {
      case 'approve':
        final DVIssuedAuthorizationCode issued = await provider.approve(
          valid,
          userId: userId,
          tenant: const DVTenants().currentTenant,
        );
        return _json(200, <String, Object?>{
          'redirect_to': issued.redirect.toString(),
        });
      case 'deny':
        return _json(200, <String, Object?>{
          'redirect_to': _errorRedirect(
            valid.redirectUri,
            'access_denied',
            'the request was declined',
            valid.state,
          ),
        });
      default:
        return _json(400, const <String, Object?>{
          'error': 'invalid_request',
          'error_description': 'decision is approve or deny',
        });
    }
  });

  // --- token -----------------------------------------------------------------

  /// `POST /oauth/token`: `authorization_code` with PKCE, `refresh_token` and
  /// `client_credentials`, as a form.
  static Future<Response> token(Request request) => _guard(() async {
    final DVOAuthProvider? provider = await _provider();
    if (provider == null) return _notServed();
    final _Form form = await _form(request, cors: true);
    final Response? refused = form.refused;
    if (refused != null) return refused;
    final Map<String, String> f = form.fields;
    final _Client client = _client(request, f);
    try {
      client.throwIfInvalid();
      final List<String>? scopes = f['scope']
          ?.split(' ')
          .where((String s) => s.isNotEmpty)
          .toList();
      final DVOAuthTokenResponse issued;
      switch (f['grant_type']) {
        case null:
          throw const DVOAuthError('invalid_request', 'grant_type is required');
        case 'authorization_code':
          issued = await provider.exchangeCode(
            clientId: client.requireId(),
            clientSecret: client.secret,
            code: _required(f, 'code'),
            redirectUri: _required(f, 'redirect_uri'),
            codeVerifier: f['code_verifier'],
          );
        case 'refresh_token':
          issued = await provider.refresh(
            clientId: client.requireId(),
            clientSecret: client.secret,
            refreshToken: _required(f, 'refresh_token'),
            scopes: scopes,
          );
        case 'client_credentials':
          final String secret =
              client.secret ??
              (throw const DVOAuthError(
                'invalid_client',
                'client authentication failed',
              ));
          issued = await provider.clientCredentials(
            clientId: client.requireId(),
            clientSecret: secret,
            scopes: scopes,
          );
        default:
          throw const DVOAuthError(
            'unsupported_grant_type',
            'the grant type is not supported',
          );
      }
      return _json(200, issued.toJson(), cors: true);
    } on DVOAuthError catch (error) {
      return _oauthError(error, cors: true);
    }
  }, cors: true);

  // --- introspection ---------------------------------------------------------

  /// `POST /oauth/introspect` (RFC 7662). The caller authenticates as a
  /// confidential client, or with an API key or access token whose scopes
  /// cover [introspectAction]. Tokens are answered for on the request's
  /// tenant only.
  static Future<Response> introspect(Request request) => _guard(() async {
    final DVPlatformApi? platform = DVPlatformApi.installed;
    final DVOAuthProvider? provider = await _provider();
    if (platform == null || provider == null) return _notServed();
    final _Form form = await _form(request);
    final Response? refused = form.refused;
    if (refused != null) return refused;

    final String? authorization = request.headers.get('authorization');
    if (DVPlatformApi.credentialOf(authorization) != null) {
      final DVApiAuthentication auth = await platform.authenticate(
        authorization,
      );
      final DVApiPrincipal? principal = auth.principal;
      if (principal == null) {
        return _json(
          auth.status ?? 401,
          const <String, Object?>{'error': 'invalid_token'},
          headers: <String, String>{
            if (auth.challenge != null) 'www-authenticate': auth.challenge!,
          },
        );
      }
      if (!principal.permits(introspectAction)) {
        DVObservability.logger.warn(
          '${DVApiScopeRefused(introspectAction, principal.scopes)}',
        );
        return _json(
          403,
          const <String, Object?>{'error': 'insufficient_scope'},
          headers: const <String, String>{
            'www-authenticate': 'Bearer error="insufficient_scope"',
          },
        );
      }
    } else {
      final _Client client = _client(request, form.fields);
      try {
        client.throwIfInvalid();
        final DVOAuthClient caller = await provider.authenticateClient(
          client.requireId(),
          client.secret,
        );
        // A public client has nothing to authenticate with, so it is not a
        // caller introspection can answer.
        if (caller.isPublic) {
          throw const DVOAuthError(
            'invalid_client',
            'introspection needs a confidential client',
          );
        }
      } on DVOAuthError catch (error) {
        return _oauthError(error);
      }
    }
    final String? token = form.fields['token'];
    if (token == null) {
      return _oauthError(
        const DVOAuthError('invalid_request', 'token is required'),
      );
    }
    final DVOAuthIntrospection answer = await provider.introspect(
      token,
      tenant: const DVTenants().currentTenant,
    );
    return _json(200, answer.toJson());
  });

  // --- revocation ------------------------------------------------------------

  /// `POST /oauth/revoke` (RFC 7009). A token that is unknown or belongs to
  /// another client is answered like one that was revoked.
  static Future<Response> revoke(Request request) => _guard(() async {
    final DVOAuthProvider? provider = await _provider();
    if (provider == null) return _notServed();
    final _Form form = await _form(request, cors: true);
    final Response? refused = form.refused;
    if (refused != null) return refused;
    final _Client client = _client(request, form.fields);
    try {
      client.throwIfInvalid();
      final String clientId = client.requireId();
      await provider.revokeToken(
        _required(form.fields, 'token'),
        clientId: clientId,
        clientSecret: client.secret,
      );
    } on DVOAuthError catch (error) {
      return _oauthError(error, cors: true);
    }
    return Response(200, headers: Headers(_headers(cors: true)));
  }, cors: true);

  // --- metadata --------------------------------------------------------------

  /// `GET /.well-known/oauth-authorization-server` (RFC 8414).
  ///
  /// The issuer is `dartvel.platformApi.oauth.issuer` when declared, and the
  /// document may then be cached. Without one it is the origin the request
  /// named, and the document is `no-store`, so a forged Host header cannot
  /// put somebody else's endpoints in a shared cache.
  static Future<Response> metadata(
    Request request, {
    required String apiBasePath,
  }) => _guard(() async {
    final DVPlatformApi? platform = DVPlatformApi.installed;
    if (platform == null || platform.config.oauth == null) {
      return _notServed();
    }
    final String? configured = platform.config.oauth!.issuer;
    final String issuer = configured ?? _origin(request);
    final String base = '$issuer$apiBasePath';
    final List<String> scopes = platform.config.scopes.names.toList()..sort();
    return Response(
      200,
      headers: Headers(<String, Object?>{
        'content-type': 'application/json; charset=utf-8',
        'access-control-allow-origin': '*',
        'cache-control': configured == null
            ? 'no-store'
            : 'public, max-age=3600',
      }),
      body: Stream<List<int>>.value(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'issuer': issuer,
            'authorization_endpoint': '$base$authorizePath',
            'token_endpoint': '$base$tokenPath',
            'introspection_endpoint': '$base$introspectionPath',
            'revocation_endpoint': '$base$revocationPath',
            'response_types_supported': const <String>['code'],
            'response_modes_supported': const <String>['query'],
            'grant_types_supported': const <String>[
              'authorization_code',
              'refresh_token',
              'client_credentials',
            ],
            'code_challenge_methods_supported': const <String>['S256'],
            'token_endpoint_auth_methods_supported': const <String>[
              'client_secret_basic',
              'client_secret_post',
              'none',
            ],
            'introspection_endpoint_auth_methods_supported': const <String>[
              'client_secret_basic',
              'client_secret_post',
            ],
            'revocation_endpoint_auth_methods_supported': const <String>[
              'client_secret_basic',
              'client_secret_post',
              'none',
            ],
            'scopes_supported': scopes,
          }),
        ),
      ),
    );
  }, cors: true);

  /// Any method a route does not serve: a CORS preflight where the endpoint
  /// is [crossOrigin], and 405 naming [allow] otherwise.
  static Response otherMethod(
    Request request, {
    required String allow,
    bool crossOrigin = false,
  }) {
    if (crossOrigin && request.method == 'OPTIONS') {
      return Response(
        204,
        headers: Headers(<String, Object?>{
          'access-control-allow-origin': '*',
          'access-control-allow-methods': allow,
          'access-control-allow-headers': 'authorization, content-type',
          'access-control-max-age': '600',
          'cache-control': 'no-store',
        }),
      );
    }
    return Response(
      405,
      headers: Headers(<String, Object?>{
        'allow': allow,
        'content-type': 'text/plain; charset=utf-8',
        'cache-control': 'no-store',
      }),
      body: Stream<List<int>>.value(utf8.encode('Method Not Allowed')),
    );
  }

  // --- internals -------------------------------------------------------------

  static Future<DVOAuthProvider?> _provider() async {
    final DVPlatformApi? platform = DVPlatformApi.installed;
    if (platform == null || platform.config.oauth == null) return null;
    return platform.oauthProvider();
  }

  /// Runs [body], and answers a fixed 500 for anything it did not expect,
  /// logging the error's type only.
  static Future<Response> _guard(
    Future<Response> Function() body, {
    bool json = true,
    bool cors = false,
  }) async {
    try {
      return await body();
    } on Object catch (error) {
      DVObservability.logger.error(
        'OAuth endpoint failed (${error.runtimeType}); answered 500.',
      );
      return json
          ? _json(500, const <String, Object?>{
              'error': 'server_error',
            }, cors: cors)
          : _text(500, 'Internal Server Error');
    }
  }

  static Future<_Validated> _validate(
    DVOAuthProvider provider,
    Map<String, List<String>> parameters,
  ) async {
    final Map<String, String> query = <String, String>{
      for (final MapEntry<String, List<String>> e in parameters.entries)
        if (e.value.isNotEmpty && e.value.first.isNotEmpty)
          e.key: e.value.first,
    };
    if (parameters.values.any((List<String> v) => v.length > 1)) {
      // Which of two redirect URIs or client ids is meant cannot be known,
      // so the error is shown rather than sent to either.
      return _Validated.failed(
        const DVOAuthError(
          'invalid_request',
          'a parameter is repeated',
          redirectable: false,
        ),
        query,
      );
    }
    try {
      final DVAuthorizationRequest request = await provider
          .validateAuthorization(
            clientId: query['client_id'] ?? '',
            redirectUri: query['redirect_uri'] ?? '',
            scopes: (query['scope'] ?? '')
                .split(' ')
                .where((String s) => s.isNotEmpty)
                .toList(),
            codeChallenge: query['code_challenge'],
            codeChallengeMethod: query['code_challenge_method'],
            state: query['state'],
            responseType: query['response_type'] ?? '',
          );
      return _Validated(request, null, query);
    } on DVOAuthError catch (error) {
      return _Validated.failed(error, query);
    }
  }

  static Response _validationError(_Validated v) {
    final DVOAuthError error = v.error!;
    final String? back = v.errorRedirect;
    return _json(400, <String, Object?>{
      ...error.toJson(),
      if (back != null) 'redirect_to': back,
    });
  }

  static String _errorRedirect(
    String redirectUri,
    String error,
    String description,
    String? state,
  ) {
    final Uri base = Uri.parse(redirectUri);
    return base
        .replace(
          queryParameters: <String, String>{
            ...base.queryParameters,
            'error': error,
            'error_description': description,
            if (state != null) 'state': state,
          },
        )
        .toString();
  }

  static Future<_Form> _form(
    Request request, {
    bool cors = false,
    String allow = 'POST',
  }) async {
    if (request.method != 'POST') {
      return _Form.refused(otherMethod(request, allow: allow));
    }
    _Form invalid(String description) => _Form.refused(
      _oauthError(DVOAuthError('invalid_request', description), cors: cors),
    );
    final String type = (request.headers.get('content-type') ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (type != 'application/x-www-form-urlencoded') {
      return invalid('the body must be application/x-www-form-urlencoded');
    }
    final Uint8List? bytes = await dvReadCapped(
      request.body.stream,
      maxBodyBytes,
    );
    if (bytes == null) return invalid('the body is too large');
    final Map<String, String> fields = <String, String>{};
    try {
      for (final String pair in utf8.decode(bytes).split('&')) {
        if (pair.isEmpty) continue;
        final int eq = pair.indexOf('=');
        final String name = Uri.decodeQueryComponent(
          eq < 0 ? pair : pair.substring(0, eq),
        );
        final String value = eq < 0
            ? ''
            : Uri.decodeQueryComponent(pair.substring(eq + 1));
        if (fields.containsKey(name)) {
          return invalid('a parameter is repeated');
        }
        fields[name] = value;
      }
    } on Object {
      return invalid('the body is not a well-formed form');
    }
    // A parameter sent with no value is treated as omitted (RFC 6749 3.1).
    fields.removeWhere((String _, String value) => value.isEmpty);
    return _Form(fields);
  }

  static _Client _client(Request request, Map<String, String> fields) {
    final String? header = request.headers.get('authorization');
    final String? bodyId = fields['client_id'];
    final String? bodySecret = fields['client_secret'];
    if (header == null ||
        header.length < 6 ||
        header.substring(0, 6).toLowerCase() != 'basic ') {
      return _Client(bodyId, bodySecret);
    }
    if (bodySecret != null) {
      return const _Client.invalid(
        DVOAuthError(
          'invalid_request',
          'a client authenticates one way, not two',
        ),
      );
    }
    try {
      final String decoded = utf8.decode(
        base64.decode(header.substring(6).trim()),
      );
      final int colon = decoded.indexOf(':');
      if (colon < 0) throw const FormatException();
      final String id = Uri.decodeQueryComponent(decoded.substring(0, colon));
      final String secret = Uri.decodeQueryComponent(
        decoded.substring(colon + 1),
      );
      if (bodyId != null && bodyId != id) {
        return const _Client.invalid(
          DVOAuthError('invalid_request', 'client_id does not match'),
        );
      }
      return _Client(id, secret);
    } on Object {
      return const _Client.invalid(
        DVOAuthError(
          'invalid_client',
          'client authentication failed',
          redirectable: false,
        ),
      );
    }
  }

  static String _required(Map<String, String> fields, String name) =>
      fields[name] ??
      (throw DVOAuthError('invalid_request', '$name is required'));

  static Response _oauthError(DVOAuthError error, {bool cors = false}) {
    final bool client = error.error == 'invalid_client';
    return _json(
      client ? 401 : 400,
      error.toJson(),
      cors: cors,
      headers: <String, String>{
        if (client) 'www-authenticate': 'Basic realm="oauth"',
      },
    );
  }

  static Map<String, Object?> _headers({
    bool cors = false,
    Map<String, String> extra = const <String, String>{},
  }) => <String, Object?>{
    'cache-control': 'no-store',
    'pragma': 'no-cache',
    if (cors) 'access-control-allow-origin': '*',
    ...extra,
  };

  static Response _json(
    int status,
    Map<String, Object?> body, {
    bool cors = false,
    Map<String, String> headers = const <String, String>{},
  }) => Response(
    status,
    headers: Headers(<String, Object?>{
      'content-type': 'application/json; charset=utf-8',
      ..._headers(cors: cors, extra: headers),
    }),
    body: Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
  );

  static Response _text(int status, String message) => Response(
    status,
    headers: Headers(<String, Object?>{
      'content-type': 'text/plain; charset=utf-8',
      ..._headers(),
    }),
    body: Stream<List<int>>.value(utf8.encode(message)),
  );

  static Response _redirect(String location) => Response(
    302,
    headers: Headers(<String, Object?>{
      'location': location,
      'referrer-policy': 'no-referrer',
      ..._headers(),
    }),
  );

  static Response _notServed() => _text(404, 'Not Found');

  static String _origin(Request request) {
    final String? host = request.headers.get('host')?.trim();
    final String authority = host != null && _host.hasMatch(host)
        ? host
        : request.url.authority;
    return '${request.url.scheme}://$authority';
  }
}

class _Validated {
  const _Validated(this.request, this.error, this.query);

  const _Validated.failed(DVOAuthError this.error, this.query) : request = null;

  final DVAuthorizationRequest? request;
  final DVOAuthError? error;
  final Map<String, String> query;

  /// Where an error may be sent: only once the client and the redirect URI
  /// were accepted, which is what [DVOAuthError.redirectable] says.
  String? get errorRedirect {
    final DVOAuthError? e = error;
    final String? uri = query['redirect_uri'];
    if (e == null || !e.redirectable || uri == null) return null;
    return DVOAuthEndpoints._errorRedirect(
      uri,
      e.error,
      e.description,
      query['state'],
    );
  }
}

class _Form {
  const _Form(this.fields) : refused = null;

  const _Form.refused(Response this.refused)
    : fields = const <String, String>{};

  final Map<String, String> fields;
  final Response? refused;
}

class _Client {
  const _Client(this.id, this.secret) : error = null;

  const _Client.invalid(DVOAuthError this.error) : id = null, secret = null;

  final String? id;
  final String? secret;
  final DVOAuthError? error;

  void throwIfInvalid() {
    final DVOAuthError? e = error;
    if (e != null) throw e;
  }

  String requireId() =>
      id ??
      (throw const DVOAuthError(
        'invalid_client',
        'client authentication failed',
        redirectable: false,
      ));
}
