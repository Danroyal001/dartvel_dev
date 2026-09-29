# Shelf parity audit

Baseline audit, 2026-09-29. Sources read from the local pub cache: shelf 1.4.2,
shelf_static 1.1.3, shelf_web_socket 3.0.0, shelf_proxy 1.0.5 and
shelf_multipart 1.0.0. Paths below are relative to `packages/` unless prefixed
with an upstream package. ✅ means implemented, not a performance claim.

| Capability | Baseline | Evidence / difference |
|---|---|---|
| Request method, URI, headers, peer | partial | `dartvel_core/lib/src/http/wintercg.dart`; Fetch URI rather than Shelf's relative url/requestedUri/handlerPath; no protocolVersion |
| Repeated headers | ✅ | `wintercg.dart` Headers.multiValueMap; `dartvel_shelf/lib/src/header_codec.dart` |
| Request/Response change(), immutable context | ❌ | Shelf `lib/src/request.dart`, `response.dart`, `message.dart`; Fetch types have neither |
| read()/readAsString(), charset encoding | partial | Fetch Body.stream/text(encoding); names differ, no content-type-derived decoder |
| Streamed request/response and backpressure | ✅ | `dartvel_shelf/lib/src/request_body.dart`, `server.dart`, `rust/src/lib.rs`; phase-1 tests |
| Multipart | partial | No built-in parser (also an extension in Shelf: shelf_multipart) |
| Response constructors, statusCode, header helpers | partial | Fetch Response.status/text/json/redirect, not Shelf Response API |
| Pipeline / Middleware / createMiddleware | ❌ | Core middleware is a different type; Shelf `lib/src/pipeline.dart`, `middleware.dart` |
| Cascade (404/405/custom predicate) | ❌ | Shelf `lib/src/cascade.dart`; no compatible implementation |
| Router method matching, parameters | partial | `dartvel_core/lib/src/http/router.dart`; different mount/regex semantics; shelf_router not cached at baseline |
| logRequests | partial | Core Router records requests; Shelf logging middleware is not type-compatible |
| Error handling | ✅ | `server.dart` catches handler failures; native panic/timeout handling in `rust/src/lib.rs` |
| WebSocket upgrade, subprotocol, origin, ping, close | ❌ | shelf_web_socket `lib/src/web_socket_handler.dart`; core ws.dart has only abstract connections |
| Arbitrary connection hijack | ❌ | Shelf Request.hijack(StreamChannel<List<int>>); no raw socket ABI |
| Static file streaming | ❌ | Native serve_file_response reads the whole file |
| Static byte ranges / 416 / HEAD | partial | Native file handler lacks ranges; generic HEAD path exists |
| Static If-Modified-Since / Last-Modified | ❌ | shelf_static `lib/src/static_handler.dart` implements it |
| Static ETag / If-None-Match | ❌ | Neither native handler nor shelf_static 1.1.3 implements ETag |
| Static default document, redirects, listing | partial | Native SPA index fallback only; shelf_static has explicit options |
| Static MIME / sniffing / custom resolver | partial | Native fixed extension list; shelf_static uses mime resolver |
| Static traversal / symlinks | partial | Native rejects '..' but does not canonicalize symlinks; shelf_static checks resolved root |
| Streaming HTTP proxy | ❌ | shelf_proxy `lib/shelf_proxy.dart`; no compatible adapter; upstream itself does not proxy WebSockets |
| TLS | ✅ | `server.dart` TlsConfig, native rustls; Shelf uses dart:io serve/securityContext |
| HTTP/2 | ✅ | Native axum HTTP/2 + ALPN; Shelf's dart:io adapter is HTTP/1.x |
| Compression | ✅ | Native tower-http compression; opt-out serve(compression:false) |
| Keep-alive | ✅ | Native hyper connections; Shelf uses dart:io persistent connections |
| Graceful stop | partial | Native aw_stop drains for 5 seconds; no configurable grace period; Shelf exposes HttpServer.close(force:) |
| Body size / request timeout | ✅ | Native preflight and incremental limit enforcement with route overrides; Shelf has no equivalent built-in limit |
| SSE / streaming cancellation | ✅ | Native streaming + cancellation ABI and stream_test.dart |

Implementation updates and measured benchmarks follow below. Raw hijacking and
exact request protocol metadata require additional ABI work; do not infer them
from ordinary middleware compatibility.

## Shelf handler adapter

`package:dartvel_shelf/shelf.dart` exports `fromShelf(handler)`. Pass a complete
upstream Shelf pipeline to it, then pass the resulting handler to `serve`.
`test/shelf_compat_test.dart` verifies Pipeline, Cascade, context changes,
charset decoding, repeated cookies, static ranges and conditional responses
through the real native server. These capabilities are now ✅ through the
adapter. Upstream static listing/default-document/MIME options, multipart
extensions and proxy handlers retain their own implementation; their broader
option sets have not all been integration-tested here. Fetch types remain
unchanged. Request protocolVersion still defaults to Shelf's 1.1.

Upstream shelf_static 1.1.3's second-resolution comparison retains file mtime
microseconds, which can miss a 304 on files with submillisecond timestamps.
This is an upstream limitation, not claimed fixed by the adapter.

## Native WebSockets

`package:dartvel_shelf/web_socket.dart` supplies `webSocketHandler` with a
`WebSocketChannel, String?` callback, protocols, allowedOrigins, pingInterval,
and maxMessageSize (1 MiB default; maximum 64 MiB). `wsHandler` adapts core
structured-message handlers and room registration to the same transport.
`test/websocket_test.dart` drives real dart:io clients, including a stalled
receiver and shutdown. Native queues hold eight messages per direction;
Dart's sink holds at most eight outstanding sends. Use `sink.addStream` or
await `NativeWebSocketChannel.send` for backpressure. `sink.add` throws when
its queue is full; this bounded behavior differs from an unlimited Dart sink.

The native bridge polls at 1 ms while consuming. This adds latency and idle
CPU overhead; benchmark results below quantify the tradeoff. Generic raw
socket hijacking remains ❌. Upstream shelf_web_socket 3.0.0 explicitly casts
the hijacked sink to dart:io Socket, so its implementation cannot run unchanged
on this transport; the provided handler matches its callback API instead.

Correction to the baseline streaming row: request streaming has backpressure;
the inherited ordinary HTTP response queue is unbounded. WebSocket queues are
bounded independently. General response backpressure remains partial.
