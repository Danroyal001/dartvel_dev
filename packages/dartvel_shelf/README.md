# dartvel_shelf

An HTTP server for Dart whose network side is Rust: Axum on Tokio, with hyper
for HTTP and rustls for TLS, loaded as a native library over FFI. Your handlers
are ordinary Dart functions that take a `Request` and return a `Response`, in
the style of `package:shelf`, with Fetch-shaped types (`Request`, `Response`,
`Headers`, `Body`). There is no second process and no IPC: the native library
runs inside the Dart process.

It is the server [Dartvel](https://dartvel.dev) generates backends onto, and it
works on its own. Nothing below needs the rest of Dartvel.

What the server does before your handler runs:

- enforces a request body limit (1 MiB by default, per route if you ask), so an
  oversized or endless upload is refused without being buffered;
- bounds every request with a timeout, from the first header byte to the
  moment your handler answers;
- answers a request it cannot parse with 400 itself, so one bad request line
  cannot take the process down;
- compresses responses, applies CORS, serves static files and terminates TLS.

## When to use it, and when to use `package:shelf`

| | `dartvel_shelf` | `package:shelf` + `dart:io` |
|---|---|---|
| Network stack | Rust (hyper, rustls) in a native library | Dart's `HttpServer` |
| Body limits and timeouts | Built in, enforced before the body reaches Dart | Mostly yours to write |
| Compression, CORS, static files | Built in | Separate packages |
| Middleware ecosystem | Plain functions; shelf middleware does not plug in | `shelf_router`, `shelf_static` and many more |
| Request body | Buffered whole, up to the limit | Streamed |
| WebSockets | No | `shelf_web_socket` |
| Platforms | Six desktop/server targets with a shipped library (below) | Anywhere `dart:io` runs |
| Size | Adds a 5-7 MB native library | Pure Dart |

Choose `dartvel_shelf` for a JSON API or web backend that should refuse abuse
by default and be deployed as a compiled executable. Choose `package:shelf` when
you need WebSockets, streamed uploads larger than you want to hold in memory,
the shelf middleware ecosystem, or a platform without a shipped library.

## Requirements

- **Dart SDK 3.13 or later.**
- **No Rust toolchain.** The package ships a prebuilt library for each
  supported platform under `lib/native/`, and `serve()` loads it from there.
  The package has a native-assets build hook, but it does nothing unless an
  application opts in to rebuilding the library from source, so `cargo` is
  never needed to install, run or compile a server. See
  [doc/building-from-source.md](doc/building-from-source.md) if you want to
  rebuild it anyway.

| Platform | Library shipped |
|---|---|
| Linux x64 | `lib/native/linux-x64/libdartvel_shelf.so` |
| Linux arm64 | `lib/native/linux-arm64/libdartvel_shelf.so` |
| macOS arm64 | `lib/native/macos-arm64/libdartvel_shelf.dylib` |
| macOS x64 | `lib/native/macos-x64/libdartvel_shelf.dylib` |
| Windows x64 | `lib/native/windows-x64/dartvel_shelf.dll` |
| Windows arm64 | `lib/native/windows-arm64/dartvel_shelf.dll` |

The Linux libraries need glibc 2.34 or newer (Debian 12, Ubuntu 22.04, RHEL 9
and later) and `libgcc_s`; they do not load on musl, so not on Alpine.
Anywhere else (Android, iOS, other architectures) `serve()` throws
`UnsupportedError`. On the web, where there is no `dart:ffi`, the import still
resolves and `serve()` throws a `StateError`.

## Install

```sh
dart pub add dartvel_shelf
```

```dart
import 'package:dartvel_shelf/dartvel_shelf.dart';
```

That one import gives you `serve`, `ServerHandle`, `TlsConfig`, `CorsOptions`,
`embedNativeServerLibrary`, `Router`, `Request`, `Response`, `Headers`, `Body`,
`URLPattern`, `DVRouteBodyLimit` and `DVPeerAddress`.

## Quick start

```dart
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main() async {
  final router = Router()
    ..get('/hello', (req) async => Response.text('Hello from dartvel_shelf!\n'))
    ..get('/json', (req) async => Response.json({'ok': true}));

  final server = await serve(router.call, host: '127.0.0.1', port: 8080);
  print('Listening on http://${server.host}:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
  exit(0);
}
```

Save it as `bin/server.dart` in your package, then:

```sh
dart run bin/server.dart
curl http://127.0.0.1:8080/hello     # Hello from dartvel_shelf!
curl http://127.0.0.1:8080/json      # {"ok":true}
curl http://127.0.0.1:8080/health    # {"status":"up","uptime":0}
```

This is [example/hello.dart](example/hello.dart). `host` defaults to
`127.0.0.1`, which only accepts connections from the same machine; pass
`0.0.0.0` (or `::` for IPv6) to listen on every interface. `port: 0` lets the
OS choose, and `server.port` then tells you which it chose.

The server writes one JSON log line per request to stdout. Set
`DARTVEL_LOG_LEVEL=warn` to keep only warnings and errors.

## Routing

```dart
final router = Router()
  ..get('/todos', listTodos)
  ..get('/todos/:id', showTodo)
  ..post('/todos', createTodo)
  ..put('/todos/:id', replaceTodo)
  ..delete('/todos/:id', deleteTodo)
  ..head('/todos', countTodos)
  ..any('/echo', echo); // every method
```

A handler is any `Future<Response> Function(Request)`. `router.call` is one
too, which is what `serve()` takes.

- `:name` matches one path segment. The value is in `req.params['name']`,
  still percent-encoded: `/todos/a%20b` gives `a%20b`, so use
  `Uri.decodeComponent` when the value can contain escapes.
- Matching is exact. `/todos/` does not match `/todos`, and there are no
  wildcards.
- Routes are tried in the order you registered them; the first whose method
  and pattern match wins.
- An unmatched path, **or a matched path with the wrong method**, is answered
  `404 Not Found`. The router does not answer 405, and a `HEAD` request is
  not routed to a `get` route: register `head` (or `any`) if you need it.
- There is no `patch` or `options` helper. Use `any` and check `req.method`.
- A handler that throws is answered `500 Internal Server Error` in plain text,
  and the error is logged with its stack trace.

## Reading a request

```dart
Future<Response> createTodo(Request req) async {
  req.method;                          // 'POST'
  req.url.path;                        // '/todos'
  req.url.queryParameters['sort'];     // last value of ?sort=
  req.url.queryParametersAll['tag'];   // every value of ?tag=
  req.headers.get('content-type');     // case-insensitive, first value
  req.headers.getAll('accept');        // every value
  req.peerAddress;                     // the socket's address, never a header

  final data = await req.body.jsonDecode();
  if (data is! Map || data['title'] is! String) {
    return Response.json({'error': 'expected {"title": "..."}'}, status: 400);
  }
  return Response.json({'title': data['title']}, status: 201);
}
```

- The body can be read once, with `text()`, `bytes()`, `bytesU8()`,
  `jsonDecode()` or `stream`. A second read throws `StateError`.
- `jsonDecode()` does not throw on invalid JSON: it returns the body as a
  `String`. Check the type of what you get back, as above.
- The body has already been read in full by the native side, within the body
  limit, by the time your handler runs.

## Writing a response

```dart
Response.text('plain text');                     // 200, text/plain
Response.json({'id': 1}, status: 201);           // application/json
Response.redirect('/login');                     // 302 with Location
Response.redirect('/new-home', 308);
Response(204);                                   // no body
Response.json(
  {'error': 'not found'},
  status: 404,
  headers: Headers()..set('cache-control', 'no-store'),
);
```

`Headers` has `set`, `append`, `get`, `getAll`, `has` and `delete`, and names
are case-insensitive. `Response.text` and `Response.json` set `content-type`
only when you have not. A header value HTTP does not allow (a newline, for
instance) makes the server answer 500 rather than send it.

### Streaming and server-sent events

A normal response is collected in full and then sent. A streamed one is sent
as you produce it:

```dart
router.get('/count', (req) async => Response.stream((sink) async {
      for (var i = 1; i <= 5; i++) {
        sink.add(utf8.encode('$i\n'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await sink.close();
    }));
```

Any response whose `content-type` is `text/event-stream` is streamed, which is
all server-sent events need. Use a `StreamController` when you have to know
the client has gone: its `onCancel` runs when the connection closes.

```dart
router.get('/events', (req) async {
  late final Timer timer;
  var n = 0;
  final events = StreamController<List<int>>(onCancel: () => timer.cancel());
  timer = Timer.periodic(const Duration(seconds: 1), (_) {
    events.add(utf8.encode('event: tick\ndata: ${n++}\n\n'));
  });
  return Response(
    200,
    headers: Headers()
      ..set('content-type', 'text/event-stream')
      ..set('cache-control', 'no-cache'),
    body: events.stream,
    isStream: true,
  );
});
```

The request timeout stops applying once the response has started, so a stream
can stay open for as long as the client keeps it. See
[example/streaming.dart](example/streaming.dart).

## Middleware

Middleware is a function from one handler to another. There is no special
type, and `package:shelf` middleware does not plug in, but the shape is the
same:

```dart
typedef Handler = Future<Response> Function(Request request);

Handler requireApiKey(String key, Handler inner) => (req) async {
      // Let the load balancer's health check through.
      if (req.url.path == '/health') return inner(req);
      if (req.headers.get('x-api-key') != key) {
        return Response.json({'error': 'unauthorized'}, status: 401);
      }
      return inner(req);
    };

final server = await serve(
  requireApiKey('secret', router.call),
  routeBodyLimits: router.bodyLimits,
);
```

Wrap `router.call`, not the router, and keep passing `router.bodyLimits` (see
below). [example/middleware.dart](example/middleware.dart) composes several:
timing, authentication and JSON error bodies.

## Limits and timeouts

Both are enforced by the native side, before your handler is called or while
the request is still arriving.

```dart
final router = Router()
  ..post('/uploads', upload, maxBodyBytes: 8 * 1024 * 1024);

final server = await serve(
  router.call,
  maxBodyBytes: 256 * 1024,                    // every other route; default 1 MiB
  routeBodyLimits: router.bodyLimits,          // tells the native side about /uploads
  requestTimeout: const Duration(seconds: 30), // default 60 seconds
);
```

The native side reads the body before any Dart runs, so it has to be told each
route's limit up front: a `maxBodyBytes` on a route has no effect unless you
pass `router.bodyLimits` as `routeBodyLimits`. Both values must be positive.

What a client sees:

| Situation | Answer |
|---|---|
| `Content-Length` over the limit | `413`, before any of the body is read; connection closed |
| Body grows past the limit while arriving (chunked or not) | `413` at that point; connection closed |
| Headers not finished within `requestTimeout` | Connection closed, no response |
| Body not finished within `requestTimeout` | `408`; connection closed |
| Handler has not answered within `requestTimeout` | `504`; connection closed |
| Handler throws | `500 Internal Server Error` |
| Request target that is not a valid path (bad `%` escape, `OPTIONS *`) | `400 Bad Request` |

The 413 body is `Request body too large. This endpoint accepts at most N
bytes.` The timeout covers the whole request, headers, body and handler
together, not each phase separately. A streamed response is not bounded by it
once it has started.

## Built-in endpoints

A `Router` answers these itself, unless you register a route for the same path:

| Path | Answer |
|---|---|
| `GET /health` | Health report as JSON; `200` while up or degraded, `503` when a check reports down |
| `GET /healthz`, `GET /healths` | `308` redirect to `/health` |
| `GET /metrics` | Request counts and durations in Prometheus text format |
| `GET /_dartvel/logs`, `GET /_dartvel/traces` | Recent log records and spans as NDJSON, only when `DARTVEL_DIAGNOSTICS=1`; `404` otherwise |

These are not counted in the metrics or logged. `/metrics` is public by
default; if the server faces the internet, block it with a middleware or put
the scrape behind your proxy.

To make `/health` check something, register a check. The API lives in
`dartvel_core`, which this package depends on; add it to your own pubspec
(`dart pub add dartvel_core`) to import it:

```dart
import 'package:dartvel_core/dartvel.dart' show DVHealthResult;
import 'package:dartvel_core/dv.dart';

DV.ObservabilityAndLogging.health.register('database', () async {
  return await db.ping()
      ? DVHealthResult.up()
      : DVHealthResult.down('database did not answer');
});
```

If you pass `serve()` a plain function rather than a router, the native side
still answers `/health` with `{"status":"ok"}` (and redirects `/healthz` and
`/healths`) whenever your handler answers those paths with 404.

## Static files, CORS and compression

```dart
final server = await serve(
  router.call,
  staticDir: 'public', // GET /static/app.css serves public/app.css
  cors: cors,          // see below; no CORS headers without it
  compression: true,   // the default
);
```

- **Static files** are served by the native side, only under `/static/`, and
  checked before your router. A file that does not exist falls through to the
  router. The directory is resolved against the working directory. Content
  types cover html, css, js, json, wasm, png, jpeg, gif and svg; anything else
  is sent as `application/octet-stream`. No caching headers are set.
- **Compression** uses whatever the client accepts (gzip, br, deflate, zstd).
  Pass `compression: false` to turn it off, for instance behind a proxy that
  compresses already.
- **CORS** is off unless you pass `cors`. Preflight requests are answered by
  the native side.

```dart
// ignore_for_file: undefined_named_parameter, argument_type_not_assignable
final cors = CorsOptions(
  origins: ['https://app.example.com'],
  methods: ['GET', 'POST'],
  headers: ['content-type'],
  maxAge: const Duration(hours: 1),
);
```

`allowAnyOrigin`, `allowAnyMethod` and `allowAnyHeader` allow everything in
that category, and `exposeHeaders` and `allowCredentials` are also available.
Credentials cannot be combined with any origin.

The `ignore_for_file` line is needed in 0.7.0. `CorsOptions` has two
definitions behind a conditional export, one for platforms with `dart:ffi` and
a stub for the web, and the analyzer (and so your IDE and the API reference)
reads the stub, whose fields are named differently (`allowedOrigins`,
`allowedMethods`, `allowedHeaders`, `maxAge` in seconds). The code above is
what compiles and runs on the VM; code written against the stub's names does
not compile under `dart run`.

## TLS and HTTP/2

```dart
final server = await serve(
  router.call,
  host: '0.0.0.0',
  port: 8443,
  tls: TlsConfig(
    certPem: await File('cert.pem').readAsString(),
    keyPem: await File('key.pem').readAsString(),
  ),
);
```

`certPem` is the certificate chain; `keyPem` may be PKCS#8, PKCS#1 or SEC1.
PEM that cannot be used makes `serve()` throw
`StateError('TLS config failed (code=N)')`: 2 when no certificate could be
read, 3 when no private key could be read, 4 when rustls refuses the pair.

- Over TLS, this release speaks **HTTP/1.1 only**. The server does not offer
  HTTP/2 through ALPN, so browsers and `curl` fall back to HTTP/1.1.
- Plaintext HTTP/2 (h2c with prior knowledge, which is what a proxy such as
  Envoy or a gRPC-style client uses) is always accepted alongside HTTP/1.1.
  The `h2c` parameter of `serve()` has no effect; you do not need to set it.

For a development certificate, `scripts/generate_dev_certs.sh` in this
package uses `mkcert` when installed and a self-signed OpenSSL certificate
otherwise. See [example/https_demo.dart](example/https_demo.dart).

## Stopping the server

`serve()` returns a `ServerHandle` with `host`, `port` and `stop()`. `stop()`
stops accepting connections, gives open ones up to five seconds, and returns
once the server has closed; calling it twice is harmless.

It is a blocking call into the native side, so while it runs your isolate
cannot finish a handler that is still awaiting something: such a request is
answered 504 or cut off. To let running requests finish, count them in a
middleware and wait for the count to reach zero before calling `stop()`.
[example/graceful_shutdown.dart](example/graceful_shutdown.dart) does this and
also answers `/health` with 503 while draining, so a load balancer stops
sending new requests.

## Deploying as a compiled executable

A compiled executable (`dart build cli` or `dart compile exe`) has no packages
to find the native library in, so it must be handed the library's bytes with
`embedNativeServerLibrary()` before `serve()` is called. The simplest way is
to ship the library next to the executable:

```dart
Future<void> main() async {
  final library = File.fromUri(File(Platform.resolvedExecutable)
      .parent
      .uri
      .resolve('libdartvel_shelf.so')); // .dylib on macOS, dartvel_shelf.dll on Windows
  if (library.existsSync()) embedNativeServerLibrary(library.readAsBytesSync());

  final server = await serve(router.call, host: '0.0.0.0', port: 8080);
  // ...
}
```

```sh
dart build cli                                  # build/cli/linux_x64/bundle/bin/server
dart run tool/copy_native_library.dart build/cli/linux_x64/bundle/bin
```

`copy_native_library.dart` is [example/copy_native_library.dart](example/copy_native_library.dart):
it copies the library for the current machine out of the resolved
`dartvel_shelf` package. Ship the whole `bundle/` directory. On Linux the
library is loaded from an in-memory file; elsewhere it is written to a fresh
private temporary directory first. A compiled program that was not handed the
library fails at `serve()` with a `StateError` saying so.

[doc/deployment.md](doc/deployment.md) covers this in more detail, with a
container image and cross-platform notes.

## Environment variables

| Variable | Effect |
|---|---|
| `DARTVEL_LOG_LEVEL` | `trace`, `debug`, `info` (default), `warn`, `error` |
| `DARTVEL_DIAGNOSTICS` | `1`/`true`/`yes`/`on` enables `/_dartvel/logs` and `/_dartvel/traces` |
| `DARTVEL_ENVIRONMENT` | `preview` puts every response behind Dartvel's preview access gate. Leave it unset for a standalone server |

## Troubleshooting

**`dartvel: could not bind 127.0.0.1:8080 — in use, or not permitted`.**
Another process has the port, or it is below 1024 without the privilege. Pick
another port, or `port: 0` for any free one.

**`dartvel: the native server library is not in this program`** (mentions
`dartvel build web-server`). You are running a compiled executable that was
not given the library. Ship it next to the binary and call
`embedNativeServerLibrary()` as shown above. `dartvel build web-server` is
Dartvel's own build, which embeds it for you; you do not need it for a
standalone server.

**`UnsupportedError: dartvel: no native server library is built for ...`.**
The platform is not one of the six above.

**`Invalid argument(s): Failed to load dynamic library ... GLIBC_2.34 not found`**,
or the library fails to load in an Alpine image. The Linux library needs glibc
2.34 or newer. Use a Debian 12 or Ubuntu 22.04 based image.

**`... speaks ABI 1 and this package speaks 2`, or `cannot limit a request
body`.** An older native library is being loaded, usually one copied beside a
binary from a previous version. Copy it again from the version you resolved.

**My route with `maxBodyBytes` still gets 413 at 1 MiB.** Pass
`routeBodyLimits: router.bodyLimits` to `serve()`.

**`POST` to a `get` route returns 404, not 405.** That is how the router
behaves; see [Routing](#routing).

**Requests hang for a minute and then get 504.** A handler is awaiting
something that never completes. Lower `requestTimeout` to find it sooner.

## Known limitations in 0.7.0

- No HTTP/2 over TLS (see above).
- Some configuration is process-wide rather than per server. If you start more
  than one server in the same process: the first TLS configuration applies to
  every server started after it, including ones started without `tls`; and
  `staticDir` is shared, so the last `serve()` call's value (including none)
  applies to all of them. One server per process avoids both.
- `URLPattern` accepts a regular-expression constraint in its syntax
  (`/items/:id(\d+)`, `/items/<id|\d+>`), but a route written that way never
  matches in this release. Validate the parameter in the handler instead.
- The analyzer, and so the API reference, sees the web stub of `CorsOptions`
  rather than the one that runs; see
  [Static files, CORS and compression](#static-files-cors-and-compression).
- Request bodies are buffered, not streamed; there are no WebSockets.

## Examples

Each is a complete program; run it from the package root with
`dart run example/<name>.dart`.

| File | Shows |
|---|---|
| [hello.dart](example/hello.dart) | The quick start |
| [main.dart](example/main.dart) | A JSON API: params, query, bodies, a per-route body limit |
| [middleware.dart](example/middleware.dart) | Composing middleware |
| [streaming.dart](example/streaming.dart) | Chunked responses and server-sent events |
| [static_files.dart](example/static_files.dart) | `staticDir` |
| [health_checks.dart](example/health_checks.dart) | Registering a health check |
| [https_demo.dart](example/https_demo.dart) | TLS |
| [graceful_shutdown.dart](example/graceful_shutdown.dart) | Draining before `stop()` |
| [compiled.dart](example/compiled.dart), [copy_native_library.dart](example/copy_native_library.dart) | A compiled executable |

## More

- API reference: <https://pub.dev/documentation/dartvel_shelf/latest/>
- Source, issues and the rest of Dartvel: <https://github.com/Danroyal001/dartvel_dev>
  (this package is `packages/dartvel_shelf`)
- [CHANGELOG](CHANGELOG.md)
