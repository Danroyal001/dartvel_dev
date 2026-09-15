// A route's body limit is something the native server has to know.
//
// The native side reads a request's body before Dart sees any of it, so a
// limit Dart checks afterwards is too late to be a limit: the body is already
// in memory. The server therefore caps every body itself, and a route that
// needs more -- an upload -- has to say so where the server can learn it.
// The router is where routes are declared, so it is where the limit is
// declared too, and `bodyLimits` is what serve() hands the native side.
//
// Every route is listed, not only the limited ones, and in order. The native
// side matches the way the router dispatches, first match wins, so a route
// with no limit of its own that comes first keeps the server's limit for the
// requests it takes rather than letting a later upload route's number apply
// to them.
import 'package:dartvel_core/dartvel.dart'
    show dvDefaultBodyLimitBytes, dvDefaultMaxBodyBytes;
import 'package:dartvel_core/http.dart';
import 'package:test/test.dart';

Future<Response> _ok(Request req) async => Response.text('ok');

void main() {
  test('every route is listed in order, with its own limit or none', () {
    final Router router = Router()
      ..get('/notes', _ok)
      ..post('/notes', _ok)
      ..post('/files/:id', _ok, maxBodyBytes: 32 * 1024 * 1024)
      ..put('/avatar', _ok, maxBodyBytes: 4096)
      ..delete('/notes/:id', _ok)
      ..head('/notes', _ok)
      ..any('/raw/<path>', _ok, maxBodyBytes: 10);

    expect(
      router.bodyLimits
          .map((DVRouteBodyLimit l) => '${l.method} ${l.pattern} ${l.maxBytes}')
          .toList(),
      <String>[
        'GET /notes null',
        'POST /notes null',
        'POST /files/:id ${32 * 1024 * 1024}',
        'PUT /avatar 4096',
        'DELETE /notes/:id null',
        'HEAD /notes null',
        '* /raw/<path> 10',
      ],
    );
  });

  test('a limit that is not positive is refused where it is declared', () {
    // Zero or less is no body at all, which is not what anybody declaring a
    // limit meant; accepted, it would read as the server's limit and the
    // route would take what it was declared to refuse.
    expect(() => Router().post('/x', _ok, maxBodyBytes: 0), throwsArgumentError);
    expect(() => Router().any('/x', _ok, maxBodyBytes: -1), throwsArgumentError);
  });

  test('the list cannot be edited to change what the server was told', () {
    final Router router = Router()..post('/upload', _ok, maxBodyBytes: 99);
    expect(() => router.bodyLimits.clear(), throwsUnsupportedError);
  });

  test('the server limit and a declared bodyLimit agree by default', () {
    // A route that declares bodyLimit and one that declares nothing get the
    // same number unless somebody moves one of them.
    expect(dvDefaultMaxBodyBytes, 1024 * 1024);
    expect(dvDefaultMaxBodyBytes, dvDefaultBodyLimitBytes);
  });
}
