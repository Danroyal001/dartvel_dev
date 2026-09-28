/// The data API of the models designed in Studio.
///
/// A model written in code gets its typed class, its `Model.find` and
/// `save()`, from the generator. A model designed in Studio on a running
/// server has no generator to wait for, so this is how an application, a
/// page or anybody else reaches its records: `/_dartvel/data/<Model>` for
/// the list and a new record, `/_dartvel/data/<Model>/<key>` for one, and
/// `/_dartvel/data/<Model>/schema` for its fields and rules, as a headless
/// content system serves them.
///
/// Every write goes through the same checks Studio's own does -- the field
/// types, the rules, uniqueness, relations, the version it was read at --
/// because it is the same code. Who may do what is the model's access: the
/// rules its definition carries, unless the application registered a policy
/// for `<Model>.<action>` in code, which is then asked instead.
library;

import 'dart:convert';

import '../../dartvel.dart' show DVAuthAuthorization;
import '../annotations/model_access.dart';
import '../auth/api_scopes.dart' show DVApiScopes;
import '../auth/session_authentication.dart';
import '../auth/sessions.dart' show DVSessionCookie;
import '../database/adapter.dart';
import '../http/wintercg.dart';
import '../middleware/middleware.dart' show dvWithRequestTenant;
import 'admin_server.dart' show dvAdminAuthorized;
import 'studio_api.dart';

/// Where the data API answers.
const String dvModelDataPath = '/_dartvel/data';

/// Answers [dvModelDataPath] for the models designed in Studio.
class DVModelDataApi {
  DVModelDataApi({
    required DVDatabaseAdapter? Function() database,
    Future<bool> Function(Request request)? team,
  })  : _database = database,
        _team = team ?? dvAdminAuthorized;

  final DVDatabaseAdapter? Function() _database;

  /// Whether the caller may open Studio: the `team` rule.
  final Future<bool> Function(Request request) _team;

  static const Map<String, String> _headers = <String, String>{
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  };

  /// The answer to [request], or null for a request that is not the data
  /// API's -- including one for a model that is not designed in Studio,
  /// which the application answers as any path it does not serve.
  Future<Response?> respond(Request request) async {
    final String path = request.url.path;
    if (path != dvModelDataPath && !path.startsWith('$dvModelDataPath/')) {
      return null;
    }
    final List<String> segments = path
        .substring(dvModelDataPath.length)
        .split('/')
        .where((String s) => s.isNotEmpty)
        .map(Uri.decodeComponent)
        .toList(growable: false);
    if (segments.isEmpty || segments.length > 2) return null;
    final DVDatabaseAdapter? database = _database();
    if (database == null) return null;
    return dvWithRequestTenant(request, () async {
      final DVStudioApi api = DVStudioApi(database: database);
      final DVStudioModelSpec? spec = (await api.storedModels())
          .where((DVStudioModelSpec m) => m.id == segments.first)
          .firstOrNull;
      if (spec == null) return null;
      final String method = request.method.toUpperCase();
      final String action = switch (method) {
        'GET' || 'HEAD' => 'view',
        'POST' => 'create',
        'PUT' || 'PATCH' => 'update',
        'DELETE' => 'delete',
        _ => '',
      };
      if (action.isEmpty) return _reply(405, 'method', 'Not answered here.');
      // Refused reading is not found: a model's records are not enumerated
      // to somebody who may not see them, and neither is whether there are
      // any.
      final bool may = await _allowed(request, spec, action);
      if (!may) {
        if (action == 'view') return null;
        final bool signedIn = await _signedIn(request);
        return _reply(
          signedIn ? 403 : 401,
          signedIn ? 'forbidden' : 'sign_in',
          signedIn
              ? 'You may not $action ${spec.model} records.'
              : 'Sign in to $action ${spec.model} records.',
        );
      }
      if (action != 'view' && !_carriesCsrf(request)) {
        return _reply(
          403,
          'csrf',
          'A write has to carry the x-dartvel-csrf-token header.',
        );
      }
      if (segments.length == 2 && segments[1] == 'schema') {
        if (action != 'view') return _reply(405, 'method', 'Not answered here.');
        return Response(
          200,
          headers: Headers(_headers),
          body: Stream<List<int>>.value(utf8.encode(jsonEncode(spec.toJson()))),
        );
      }
      return api.respondRecords(
        request,
        spec,
        segments.sublist(1),
        method: method == 'PATCH'
            ? 'PUT'
            : method == 'HEAD'
                ? 'GET'
                : method,
      );
    });
  }

  Response _reply(int status, String code, String message) => Response(
    status,
    headers: Headers(_headers),
    body: Stream<List<int>>.value(
      utf8.encode(jsonEncode(<String, Object?>{'error': code, 'message': message})),
    ),
  );

  static bool _carriesCsrf(Request request) =>
      (request.headers.get('x-dartvel-csrf-token') ?? '').trim().length >= 16;

  Future<DVSessionAuthenticationResult> _session(Request request) =>
      DVSessionAuthentication.authenticateRequest(
        plainLocal: DVSessionCookie.plainLocal(
          request.url,
          forwardedProto: request.headers.get('x-forwarded-proto'),
          host: request.headers.get('host'),
        ),
        authorization: request.headers.get('authorization'),
        cookie: request.headers.get('cookie'),
      );

  Future<bool> _signedIn(Request request) async {
    final DVSessionAuthenticationResult result = await _session(request);
    return !result.refused && result.principal != null;
  }

  /// Whether the caller may [action] records of [spec].
  ///
  /// A policy the application registered for `<Model>.<action>` answers
  /// first; the model's own access answers otherwise.
  Future<bool> _allowed(
    Request request,
    DVStudioModelSpec spec,
    String action,
  ) async {
    const DVAuthAuthorization authorization = DVAuthAuthorization();
    final String named = '${spec.model}.$action';
    if (authorization.registeredPolicies
        .contains(DVApiScopes.policyKeyOf(named))) {
      final DVSessionAuthenticationResult result = await _session(request);
      final Object? caller = result.refused
          ? null
          : (result.principal?.user ?? result.principal);
      return authorization.canAction(caller, named);
    }
    final DVModelAccess access = spec.access ?? const DVModelAccess();
    return switch (access.of(action)) {
      DVAccess.anyone => true,
      DVAccess.signedIn => _signedIn(request),
      DVAccess.team => _team(request),
      DVAccess.nobody => false,
    };
  }
}
