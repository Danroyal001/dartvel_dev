import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// One request through the generated backend's guard, as the generator emits
/// it: the declared middleware runs, then the handler.
Future<String> _serve(
  String host, {
  List<String> keys = const <String>['tenant'],
}) {
  final Map<String, Object?> request = <String, Object?>{
    'host': host,
    'path': '/orders',
  };
  return dvWithRequestTenant(request, () async {
    await dvRunMiddlewares(keys, request);
    // The handler's first await. A server with two requests in flight runs
    // the other one's middleware here.
    await Future<void>.delayed(Duration.zero);
    return const DVTenants().currentTenant;
  });
}

void main() {
  tearDown(() {
    DVTenants.reset();
    dvResetMiddlewareRuntime();
  });

  test('two requests in flight keep the tenant each of them named', () async {
    // The failure this closes: the resolved tenant was written to a
    // process-wide field, so the second request to arrive decided what the
    // first one's handler read. Every query the first handler made after its
    // next await ran against the second request's tenant, returned rows, and
    // showed one customer another customer's data.
    final List<String> seen = await Future.wait(<Future<String>>[
      _serve('acme.example.com'),
      _serve('globex.example.com'),
    ]);

    expect(seen, <String>['acme', 'globex']);
  });

  test('a route that declares no tenant middleware is scoped anyway',
      () async {
    // A tenant-scoped model does not care which middleware the route
    // declared. Reading the process-wide field here means reading whichever
    // tenant the last request to touch it happened to be for.
    final List<String> seen = await Future.wait(<Future<String>>[
      _serve('acme.example.com', keys: const <String>[]),
      _serve('globex.example.com', keys: const <String>[]),
    ]);

    expect(seen, <String>['acme', 'globex']);
  });

  test('a request naming no tenant keeps what the process was set to',
      () async {
    // Single-tenant deployments set the tenant once at boot and serve an
    // apex domain that names nobody. Forcing those requests to the default
    // tenant would point every query at a tenant with no rows.
    const DVTenants().currentTenant = 'house';

    expect(await _serve('example.com'), 'house');
  });

  test('the scope ends with the request', () async {
    await _serve('acme.example.com');

    expect(const DVTenants().currentTenant, DVTenants.defaultTenant);
  });
}
