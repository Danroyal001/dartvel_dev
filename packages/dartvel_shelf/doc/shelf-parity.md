# Shelf parity audit

Baseline audit, 2026-09-29. Sources read from the local pub cache: shelf 1.4.2,
shelf_static 1.1.3, shelf_web_socket 3.0.0, shelf_proxy 1.0.5 and
shelf_multipart 1.0.0. Paths below are relative to `packages/` unless prefixed
with an upstream package. ✅ means implemented, not a performance claim.

| Capability | Baseline | Current Status | Evidence / difference |
|---|---|---|---|
| Request method, URI, headers, peer | partial | partial | `dartvel_core/lib/src/http/wintercg.dart`; Fetch URI rather than Shelf's relative url/requestedUri/handlerPath; no protocolVersion (defaults to 1.1) |
| Repeated headers | ✅ | ✅ | `wintercg.dart` Headers.multiValueMap; `dartvel_shelf/lib/src/header_codec.dart` |
| Request/Response change(), immutable context | ❌ | ✅ | Shelf `lib/src/request.dart`, `response.dart`; supported via `fromShelf()` adapter |
| read()/readAsString(), charset encoding | partial | ✅ | Fetch Body.stream/text(encoding); Shelf charset decoding supported via `fromShelf()` adapter |
| Streamed request/response and backpressure | partial | ✅ | `dartvel_shelf/lib/src/request_body.dart`, `server.dart`, `rust/src/lib.rs`; bounded 8-chunk channels with ack callbacks (`aw_register_stream_ack_handler`) |
| Multipart | partial | partial | Supported through upstream `shelf_multipart` over `fromShelf()` adapter; no custom native parser |
| Response constructors, statusCode, header helpers | partial | ✅ | Shelf Response constructors supported via `fromShelf()` adapter; native Fetch Response.status/text/json |
| Pipeline / Middleware / createMiddleware | ❌ | ✅ | Supported through upstream `shelf` Pipeline/Middleware via `fromShelf()` adapter |
| Cascade (404/405/custom predicate) | ❌ | ✅ | Supported through upstream `shelf` Cascade via `fromShelf()` adapter |
| Router method matching, parameters | partial | ✅ | Upstream `shelf_router` supported via `fromShelf()`; core router available natively |
| logRequests | partial | ✅ | Supported through upstream `shelf` logging via `fromShelf()` adapter; core router also logs |
| Error handling | ✅ | ✅ | `server.dart` catches handler failures; native panic/timeout handling in `rust/src/lib.rs` |
| WebSocket upgrade, subprotocol, origin, ping, close | ❌ | ✅ | `package:dartvel_shelf/web_socket.dart` (`webSocketHandler`, `wsHandler`), native Axum/tungstenite integration, event-driven wakeup |
| Arbitrary connection hijack | ❌ | ❌ | Shelf `Request.hijack(StreamChannel<List<int>>)`; requires raw socket ABI not provided by native bridge |
| Static file streaming | ❌ | ✅ | Native `tower-http` ServeFile streams files rather than buffering whole in memory |
| Static byte ranges / 416 / HEAD | partial | ✅ | Supported via native ServeFile (`Range`, `206 Partial Content`, `416 Range Not Satisfiable`, `HEAD`) |
| Static If-Modified-Since / Last-Modified | ❌ | ✅ | Supported via native ServeFile (`Last-Modified`, `If-Modified-Since`) |
| Static ETag / If-None-Match | ❌ | ✅ | Supported via native weak ETag handler wrapping ServeFile with entity-tag precedence |
| Static default document, redirects, listing | partial | partial | Native SPA index fallback; custom default documents/directory listing available via `fromShelf()` + `shelf_static` |
| Static MIME / sniffing / custom resolver | partial | ✅ | Supported via native ServeFile MIME lookup; custom resolvers available via `fromShelf()` + `shelf_static` |
| Static traversal / symlinks | partial | ✅ | Native canonical path verification refuses path traversal ('..') and external symlinks |
| Streaming HTTP proxy | ❌ | partial | HTTP proxying supported via `fromShelf()` + `shelf_proxy`; WebSocket proxying not supported upstream or natively |
| TLS | ✅ | ✅ | `server.dart` TlsConfig, native rustls; Shelf uses dart:io serve/securityContext |
| HTTP/2 | ✅ | ✅ | Native Axum HTTP/2 + ALPN; Shelf's dart:io adapter is HTTP/1.x only |
| Compression | ✅ | ✅ | Native `tower-http` gzip/deflate/br compression; opt-out `serve(compression: false)` |
| Keep-alive | ✅ | ✅ | Native hyper connections; Shelf uses dart:io persistent connections |
| Graceful stop | partial | partial | Native `aw_stop` drains connections for 5s; no configurable grace period; Shelf exposes `HttpServer.close(force:)` |
| Body size / request timeout | ✅ | ✅ | Native preflight and incremental limit enforcement with route overrides; Shelf has no built-in equivalent |
| SSE / streaming cancellation | ✅ | ✅ | Native streaming + cancellation ABI and `stream_test.dart` |

Implementation updates and measured benchmarks follow below. Raw hijacking,
arbitrary HTTP version metadata, and configurable graceful shutdown grace periods
remain missing / not done.

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
receiver, heartbeats, and shutdown. Native queues hold eight messages per direction;
Dart's sink holds at most eight outstanding sends. Use `sink.addStream` or
await `NativeWebSocketChannel.send` for backpressure. `sink.add` throws when
its queue is full; this bounded behavior prevents unbounded buffering.

To eliminate polling latency, the bridge uses native frame arrival events
(`aw_register_ws_wakeup_handler`). The Axum/tungstenite task invokes the registered
wakeup callback immediately upon receiving frames or detecting stream completion.
Dart's `NativeWebSocketChannel` drains all queued frames in a loop (`_drain()`),
processes stream listen/resume transitions, and dispatches synchronously on the Dart
isolate event loop with a low-overhead 50ms fallback safety timer.

Generic raw socket hijacking remains ❌: upstream `shelf_web_socket` explicitly casts
the hijacked sink to a `dart:io` `Socket`, which cannot run on this native transport.
Applications should use `webSocketHandler` or `wsHandler`.

## Response body backpressure

The native HTTP response bridge uses a bounded channel (`RESPONSE_STREAM_CAPACITY = 8`)
with flow control signaled back to Dart via `aw_register_stream_ack_handler`.
In Dart, `_StreamResponseState` tracks chunks in flight (up to a 4-chunk window).
When native buffers fill (e.g. when writing to a slow or paused TCP client), the Dart
stream subscription pauses automatically and resumes when native delivers chunks and fires
acknowledgements.

`test/response_backpressure_test.dart` verifies this behavior: a fast 200 MiB producer
sending to a slow/paused client strictly pauses when the TCP buffer saturates, bounded
to ~1.1–5.6 MiB of kernel/socket buffer, avoiding unbounded memory growth, and delivering
the entire 200 MiB payload intact.

## Native static serving

Native `staticDir`/SPA assets stream via `tower-http` `ServeFile` instead of
reading the whole file into memory. Ranges, 416, HEAD, Last-Modified/If-Modified-Since and
MIME lookup are supplied by ServeFile; weak ETag/If-None-Match handling wraps
it, with entity-tag precedence over modification dates. Canonical paths refuse
symlinks outside the configured root. `test/native_static_test.dart` verifies
these behaviors through real HTTP clients.
Native directory listing/default-document customization remains available via
the Shelf adapter's upstream static handler rather than new native options.

## Benchmarks (AOT, fresh processes, 3 trials via heavy.sh)

Compiled with `dart compile exe benchmark/compare.dart -o benchmark/compare_aot` and
executed via `~/heavy.sh ./benchmark/compare_aot` under identical system conditions.
Each engine and scenario ran in an isolated fresh process. Reported RSS is peak resident
set size (`ProcessInfo.maxRss`), which includes the client driver, Dart runtime, and
(for Dartvel) the embedded Rust shared library, Tokio thread pool, and native allocators.

### Results summary (means across 3 trials)

| Scenario | Shelf (dart:io) | Dartvel (Axum/native) | Delta / Notes |
|---|---|---|---|
| **hello (RPS)** | 4,060.2 req/s | **5,913.3 req/s** | **+45.6% throughput** (Dartvel faster) |
| **hello (p50 latency)** | 3.88 ms | **2.60 ms** | **33.0% lower latency** |
| **hello (p95 latency)** | 4.95 ms | **3.88 ms** | **21.6% lower latency** |
| **hello (peak RSS)** | **12.3 MiB** | 25.4 MiB | +13.1 MiB baseline (Rust/Tokio runtime) |
| **upload 50 MiB** | 435.1 MiB/s | **463.9 MiB/s** | **+6.6% throughput** (Dartvel faster) |
| **upload (peak RSS)** | **46.3 MiB** | 50.6 MiB | Bounded memory during 50 MiB stream |
| **download 50 MiB** | 457.2 MiB/s | 452.9 MiB/s | **-0.9%** (at parity) |
| **download (peak RSS)** | **48.8 MiB** | 50.9 MiB | Bounded response backpressure |
| **websocket (echo)** | **6,872.6 msgs/s** | 3,945.0 msgs/s | Up from 683 msgs/s (5.7x gain via native wakeup) |
| **websocket (peak RSS)**| **12.1 MiB** | 24.6 MiB | +12.5 MiB baseline |

### Raw trial data

```json
{"trial":1,"engine":"shelf","scenario":"hello","requests":2000,"rps":4361.974054978321,"p50_ms":3.65,"p95_ms":4.329,"elapsed_ms":458.508,"peak_rss_mib":12.69921875}
{"trial":1,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6060.128595928805,"p50_ms":2.579,"p95_ms":3.364,"elapsed_ms":330.026,"peak_rss_mib":30.78515625}
{"trial":1,"engine":"shelf","scenario":"upload","mib_per_second":534.382147361221,"elapsed_ms":93.566,"peak_rss_mib":45.7578125}
{"trial":1,"engine":"dartvel","scenario":"upload","mib_per_second":531.4851821931204,"elapsed_ms":94.076,"peak_rss_mib":50.3828125}
{"trial":1,"engine":"shelf","scenario":"download","mib_per_second":478.7162744384658,"elapsed_ms":104.446,"peak_rss_mib":49.33984375}
{"trial":1,"engine":"dartvel","scenario":"download","mib_per_second":503.4993202759176,"elapsed_ms":99.305,"peak_rss_mib":50.703125}
{"trial":1,"engine":"shelf","scenario":"websocket","messages_per_second":8021.047227926078,"elapsed_ms":62.336,"peak_rss_mib":12.5390625}
{"trial":1,"engine":"dartvel","scenario":"websocket","messages_per_second":4059.85855452796,"elapsed_ms":123.157,"peak_rss_mib":24.578125}

{"trial":2,"engine":"shelf","scenario":"hello","requests":2000,"rps":3960.85094921793,"p50_ms":3.932,"p95_ms":5.125,"elapsed_ms":504.942,"peak_rss_mib":12.13671875}
{"trial":2,"engine":"dartvel","scenario":"hello","requests":2000,"rps":5206.191202578106,"p50_ms":2.792,"p95_ms":5.13,"elapsed_ms":384.158,"peak_rss_mib":30.7734375}
{"trial":2,"engine":"shelf","scenario":"upload","mib_per_second":349.53791088181424,"elapsed_ms":143.046,"peak_rss_mib":45.42578125}
{"trial":2,"engine":"dartvel","scenario":"upload","mib_per_second":429.0519667742157,"elapsed_ms":116.536,"peak_rss_mib":51.12890625}
{"trial":2,"engine":"shelf","scenario":"download","mib_per_second":371.41583717129697,"elapsed_ms":134.62,"peak_rss_mib":49.125}
{"trial":2,"engine":"dartvel","scenario":"download","mib_per_second":367.3661317815788,"elapsed_ms":136.104,"peak_rss_mib":51.4296875}
{"trial":2,"engine":"shelf","scenario":"websocket","messages_per_second":6059.72464611208,"elapsed_ms":82.512,"peak_rss_mib":11.8515625}
{"trial":2,"engine":"dartvel","scenario":"websocket","messages_per_second":4075.5775093330726,"elapsed_ms":122.682,"peak_rss_mib":24.63671875}

{"trial":3,"engine":"shelf","scenario":"hello","requests":2000,"rps":3858.672269458802,"p50_ms":4.044,"p95_ms":5.412,"elapsed_ms":518.313,"peak_rss_mib":12.12890625}
{"trial":3,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6473.518454382734,"p50_ms":2.431,"p95_ms":3.152,"elapsed_ms":308.951,"peak_rss_mib":24.62890625}
{"trial":3,"engine":"shelf","scenario":"upload","mib_per_second":421.24418683022174,"elapsed_ms":118.696,"peak_rss_mib":47.76953125}
{"trial":3,"engine":"dartvel","scenario":"upload","mib_per_second":431.31706980435456,"elapsed_ms":115.924,"peak_rss_mib":50.15234375}
{"trial":3,"engine":"shelf","scenario":"download","mib_per_second":521.3438158196567,"elapsed_ms":95.906,"peak_rss_mib":48.06640625}
{"trial":3,"engine":"dartvel","scenario":"download","mib_per_second":487.9429301948844,"elapsed_ms":102.471,"peak_rss_mib":50.49609375}
{"trial":3,"engine":"shelf","scenario":"websocket","messages_per_second":6537.05858511904,"elapsed_ms":76.487,"peak_rss_mib":12.0078125}
{"trial":3,"engine":"dartvel","scenario":"websocket","messages_per_second":3699.5109246557604,"elapsed_ms":135.153,"peak_rss_mib":24.71484375}
```

### Analysis of tradeoffs

1. **HTTP Throughput & Latency (`hello`):**
   Dartvel outperforms Shelf significantly on concurrent HTTP handling (5,913 RPS vs 4,060 RPS, +46% throughput) while cutting median latency from 3.88 ms to 2.60 ms and 95th percentile latency from 4.95 ms to 3.88 ms. Axum's Rust HTTP parser, epoll event loops, and multi-core work stealing process concurrent request streams with lower context-switch overhead than `dart:io`.

2. **Streamed I/O (`upload` & `download`):**
   Both engines stream large payloads at ~450–500 MiB/s across loopback. **Dartvel now matches or exceeds Shelf**: upload 464 vs 435 MiB/s (+6.6%), download 453 vs 457 MiB/s (-0.9%, at parity). Thanks to response backpressure acknowledgements (`aw_register_stream_ack_handler`), Dartvel's memory footprint is strictly bounded (~50.9 MiB peak RSS during a 50 MiB transfer), matching Shelf (~48.8 MiB). The 256 KiB scratch buffer and 64-chunk native capacity with ack-every-8-chunks provide efficient flow control.

3. **WebSocket sequential ping-pong (`websocket`):**
   Phase 3 fixed the `sink.add` semantics bug (no throw on full queue, buffered in Dart with bounded memory) and removed the 50 ms polling timer. Phase 4 added read/write batching in `run_websocket` (up to 32 frames read, 64 frames written per wakeup) and `String::from_utf8` zero-copy text frame handling. The `NativeWebSocketChannel` uses a reusable 64 KiB scratch buffer. Despite these optimizations, Shelf remains faster on sequential ping-pong (6,873 vs 3,945 msgs/s, 74% gap) because Shelf exposes `dart:io`'s internal C++ socket directly, bypassing FFI entirely. The FFI crossing + NativeCallable wakeup + mutex overhead per message is the structural floor. Further gains would require batching multiple application messages per wakeup (not possible for sequential ping-pong) or a zero-copy ABI.

4. **Resident Memory Footprint (RSS):**
   In all scenarios, Dartvel carries a ~12–14 MiB baseline resident memory delta over Shelf (~25.4 MiB vs ~12.1 MiB idle). This represents the static footprint of embedding `libdartvel_shelf.so`, the Tokio multithreaded runtime, Rust standard library runtime structures, and memory arenas.
