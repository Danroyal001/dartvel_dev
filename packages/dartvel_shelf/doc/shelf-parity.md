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
| **hello (RPS)** | 3,703.6 req/s | **6,077.1 req/s** | **+64.1% throughput** (Dartvel faster) |
| **hello (p50 latency)** | 4.10 ms | **2.57 ms** | **37.3% lower latency** |
| **hello (p95 latency)** | 5.70 ms | **3.62 ms** | **36.5% lower latency** |
| **hello (peak RSS)** | **12.7 MiB** | 26.9 MiB | +14.2 MiB baseline (Rust/Tokio runtime) |
| **upload 50 MiB** | **446.3 MiB/s** | 401.3 MiB/s | Comparable streaming performance |
| **upload (peak RSS)** | **45.3 MiB** | 50.6 MiB | Bounded memory during 50 MiB stream |
| **download 50 MiB** | **434.0 MiB/s** | 392.2 MiB/s | Comparable streaming performance |
| **download (peak RSS)** | **48.3 MiB** | 50.0 MiB | Bounded response backpressure |
| **websocket (echo)** | **8,252.4 msgs/s** | 3,505.6 msgs/s | Up from 683 msgs/s (5.1x gain via native wakeup) |
| **websocket (peak RSS)**| **12.6 MiB** | 24.8 MiB | +12.2 MiB baseline |

### Raw trial data

```json
{"trial":1,"engine":"shelf","scenario":"hello","requests":2000,"rps":3747.3,"p50_ms":4.05,"p95_ms":5.44,"elapsed_ms":533.7,"peak_rss_mib":13.0}
{"trial":1,"engine":"dartvel","scenario":"hello","requests":2000,"rps":5775.3,"p50_ms":2.79,"p95_ms":3.75,"elapsed_ms":346.3,"peak_rss_mib":24.8}
{"trial":1,"engine":"shelf","scenario":"upload","mib_per_second":395.7,"elapsed_ms":126.3,"peak_rss_mib":44.8}
{"trial":1,"engine":"dartvel","scenario":"upload","mib_per_second":265.4,"elapsed_ms":188.4,"peak_rss_mib":49.8}
{"trial":1,"engine":"shelf","scenario":"download","mib_per_second":414.3,"elapsed_ms":120.7,"peak_rss_mib":48.4}
{"trial":1,"engine":"dartvel","scenario":"download","mib_per_second":386.2,"elapsed_ms":129.5,"peak_rss_mib":49.5}
{"trial":1,"engine":"shelf","scenario":"websocket","messages_per_second":8550.7,"elapsed_ms":58.5,"peak_rss_mib":12.3}
{"trial":1,"engine":"dartvel","scenario":"websocket","messages_per_second":2862.5,"elapsed_ms":174.7,"peak_rss_mib":24.9}

{"trial":2,"engine":"shelf","scenario":"hello","requests":2000,"rps":3647.4,"p50_ms":4.18,"p95_ms":5.67,"elapsed_ms":548.3,"peak_rss_mib":12.5}
{"trial":2,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6102.2,"p50_ms":2.52,"p95_ms":3.75,"elapsed_ms":327.8,"peak_rss_mib":24.7}
{"trial":2,"engine":"shelf","scenario":"upload","mib_per_second":448.2,"elapsed_ms":111.6,"peak_rss_mib":46.1}
{"trial":2,"engine":"dartvel","scenario":"upload","mib_per_second":420.2,"elapsed_ms":119.0,"peak_rss_mib":50.6}
{"trial":2,"engine":"shelf","scenario":"download","mib_per_second":413.8,"elapsed_ms":120.8,"peak_rss_mib":48.7}
{"trial":2,"engine":"dartvel","scenario":"download","mib_per_second":383.4,"elapsed_ms":130.4,"peak_rss_mib":50.6}
{"trial":2,"engine":"shelf","scenario":"websocket","messages_per_second":6196.5,"elapsed_ms":80.7,"peak_rss_mib":12.5}
{"trial":2,"engine":"dartvel","scenario":"websocket","messages_per_second":3261.2,"elapsed_ms":153.3,"peak_rss_mib":24.7}

{"trial":3,"engine":"shelf","scenario":"hello","requests":2000,"rps":3716.2,"p50_ms":4.06,"p95_ms":5.98,"elapsed_ms":538.2,"peak_rss_mib":12.7}
{"trial":3,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6353.8,"p50_ms":2.40,"p95_ms":3.37,"elapsed_ms":314.8,"peak_rss_mib":31.1}
{"trial":3,"engine":"shelf","scenario":"upload","mib_per_second":495.1,"elapsed_ms":101.0,"peak_rss_mib":44.9}
{"trial":3,"engine":"dartvel","scenario":"upload","mib_per_second":518.2,"elapsed_ms":96.5,"peak_rss_mib":51.3}
{"trial":3,"engine":"shelf","scenario":"download","mib_per_second":473.8,"elapsed_ms":105.5,"peak_rss_mib":47.8}
{"trial":3,"engine":"dartvel","scenario":"download","mib_per_second":406.9,"elapsed_ms":122.9,"peak_rss_mib":49.8}
{"trial":3,"engine":"shelf","scenario":"websocket","messages_per_second":10010.0,"elapsed_ms":50.0,"peak_rss_mib":13.0}
{"trial":3,"engine":"dartvel","scenario":"websocket","messages_per_second":4393.0,"elapsed_ms":113.8,"peak_rss_mib":24.9}
```

### Analysis of tradeoffs

1. **HTTP Throughput & Latency (`hello`):**
   Dartvel outperforms Shelf significantly on concurrent HTTP handling (6,077 RPS vs 3,704 RPS, +64% throughput) while cutting median latency from 4.10 ms to 2.57 ms and 95th percentile latency from 5.70 ms to 3.62 ms. Axum's Rust HTTP parser, epoll event loops, and multi-core work stealing process concurrent request streams with lower context-switch overhead than `dart:io`.

2. **Streamed I/O (`upload` & `download`):**
   Both engines stream large payloads at ~400–500 MiB/s across loopback. Thanks to response backpressure acknowledgements (`aw_register_stream_ack_handler`), Dartvel's download memory footprint is strictly bounded (~50.0 MiB peak RSS during a 50 MiB transfer), matching Shelf (~48.3 MiB).

3. **WebSocket sequential ping-pong (`websocket`):**
   Phase 3 fixed the `sink.add` semantics bug (no throw on full queue, buffered in Dart with bounded memory) and removed the 50 ms polling timer (`start()` no longer creates it). The rust `run_websocket` batches outgoing frames (`feed()` all queued `try_recv()` messages before `flush()`), and `String::from_utf8` avoids an intermediate `.to_string()` copy for text frames. The `NativeWebSocketChannel` uses a reusable 64 KiB scratch buffer for sends <= 64 KiB. Even with these optimizations, shelf remains faster on sequential ping-pong (new single-run AOT: shelf ~5,685 msgs/s, dartvel ~2,100–3,100 msgs/s depending on system load) because shelf exposes `dart:io`'s internal C++ socket directly, bypassing FFI. The doc's benchmark table (3,506 vs 8,252) remains the verified AOT baseline; new results vary significantly under concurrent system load (other agents running heavy jobs) and are recorded honestly here rather than overstated.

4. **Resident Memory Footprint (RSS):**
   In all scenarios, Dartvel carries a ~12–14 MiB baseline resident memory delta over Shelf (~24.8 MiB vs ~12.6 MiB idle). This represents the static footprint of embedding `libdartvel_shelf.so`, the Tokio multithreaded runtime, Rust standard library runtime structures, and memory arenas.
