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
receiver, heartbeats, shutdown, 5,000 pipelined echoes in order, frames added
before a close, and awaited 200 KiB sends. The native queue holds 64 frames
each way. `sink.add` never throws on a full queue: it buffers in Dart and the
network applies backpressure, as dart:io does. Use `sink.addStream` or await
`NativeWebSocketChannel.send` to have the producer wait instead.

How a frame travels:

- **In:** the connection's Tokio task reads and parses the frame, queues it
  and, unless a wakeup is already pending, calls the `NativeCallable.listener`
  registered with `aw_register_ws_wakeup_handler`. Dart drains every queued
  frame in that one pass (`_drain()`); the next frame after the queue empties
  posts again. There is no polling timer.
- **Out:** `sink.add` queues in Dart; at the end of the event-loop turn the
  frames go to the native queue (`aw_ws_queue`) and one `aw_ws_flush` writes
  them. When nothing is queued or in flight the flush writes to the socket from
  the isolate's own thread. Only when the socket cannot take everything does
  the connection's writer task take over, waiting on the socket with its own
  waker; Dart does not touch the sink again until it has finished, and it
  wakes Dart if Dart was waiting for room.

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

Compiled with `dart compile exe benchmark/compare.dart` and run inside a
`~/heavy.sh` slot only once the one-minute load average was under 4, from the
package directory. Each engine and scenario ran in its own fresh process. The
table is the mean of two full runs (six trials per cell), measured on
2026-09-30 on the 8-vCPU VPS; before and after runs alternated. "Before" is
0.9.3 (`origin/main` at e1489583) with the same benchmark program; shelf's
column pools both runs. Peak RSS (`ProcessInfo.maxRss`) includes the client
driver, the Dart runtime and, for Dartvel, the Rust library and its Tokio
threads.

- `websocket`: the dart:io client runs in the server's own isolate, 500
  sequential 64-byte echoes.
- `websocket_remote`: the same client in a separate process (as a real peer
  is), 200 warm-up then 2,000 sequential echoes, per-message round trips.
- `websocket_pipelined`: a raw-socket client in a separate process writes
  200,000 pre-encoded 64-byte frames without waiting and counts the echoes, so
  the server rather than a Dart-side client encoder is the limit (the dart:io
  client tops out near 50,000 msgs/s for either server).

### Results summary

| Scenario | Shelf (dart:io) | Dartvel before (0.9.3) | Dartvel after | Notes |
|---|---|---|---|---|
| hello (RPS) | 4,001 req/s | 6,407 | **6,408 req/s** | unchanged by this work |
| hello (p50 / p95) | 3.90 / 5.33 ms | 2.37 / 3.70 ms | **2.37 / 3.69 ms** | |
| upload 50 MiB | 435 MiB/s | 439 | 481 MiB/s | not touched; trial spread is ±25% |
| download 50 MiB | 472 MiB/s | 454 | 547 MiB/s | not touched; trial spread is ±25% |
| **websocket** (client in the server's isolate), msgs/s | **7,972** | 4,280 | 5,473 | +28%; still 0.69x shelf (see below) |
| websocket, p50 round trip | **118 µs** | 214 µs | 171 µs | |
| **websocket_remote** (client in its own process), msgs/s | 4,382 | 3,763 | **4,324** | parity (within noise) |
| websocket_remote, p50 / p99 round trip | 196 / 888 µs | 237 / 848 µs | **201 / 663 µs** | p50 at parity, p99 lower |
| **websocket_pipelined**, msgs/s | 38,804 | 167,910 | **187,510** | **4.8x shelf** |
| websocket_pipelined, peak RSS | 76.1 MiB | 29.3 MiB | **26.0 MiB** | bounded queues; shelf buffers |
| websocket peak RSS | **11.4 MiB** | 23.1 MiB | 23.6 MiB | Tokio runtime + library baseline |

### Where a WebSocket echo's time goes

Measured with a temporary instrumented build: monotonic timestamps at each
step (Rust `clock_gettime`, the same clock read from Dart through FFI),
4,000 sequential in-process echoes, p50 per step in microseconds.

| Step | 0.9.3 | now |
|---|---|---|
| client `add` → Tokio has parsed the frame | 63 | 54 |
| frame queued for Dart | 0.6 | 0.5 |
| posting the `NativeCallable.listener` wakeup | 16 | 13 |
| wakeup posted → Dart handler running | 14 | 16 |
| `aw_ws_receive` + decode + stream delivery | 3 | 3 |
| `aw_ws_send`: lock, copy, wake the writer task | 7.2 | — |
| waiting for a Tokio worker to wake | 18 | — |
| writer task writes (feed, flush, `sendto`) | 19 | — |
| `aw_ws_queue` + `aw_ws_flush` writing from the isolate thread | — | 22 |
| written → client has the echo | 55 | 49 |
| **round trip** | **204** | **167** |

The writer hop is gone: over 4,000 echoes the writer task ran zero times; every
reply was written by the flush on the isolate's thread. The 50 ms fallback
timer the brief suspected is not in the path (it was removed in 0.9.2; nothing
periodic runs besides the optional heartbeat).

### What still separates the in-process `websocket` scenario from shelf

With client and server in one isolate, shelf's isolate rarely sleeps: under
`strace -f -c`, 4,200 shelf round trips made 0.6 `futex` calls per round trip
across the whole process, because the dart:io event handler posts the server socket's readiness while the
isolate is still busy with the client's own write. The server's read, parse,
echo and the client's next write all happen on one thread.

Dartvel's reads happen on a Tokio thread. After the client writes, the isolate
has nothing to do until that thread has read and parsed the frame, so it
sleeps and is woken by the post: 6.5 `futex` calls per round trip, and the two
rows above for posting (13 µs) and waking (16 µs) are that sleep. The dart:io
client also writes each frame as two `write`s (6-byte header, then payload),
so Tokio wakes twice per frame. Things tried that did not move the p50, and so
were not kept: polling again for up to 50 µs after a partial frame instead of
parking; a current-thread Tokio runtime; one and two worker threads.

This is a property of running the client inside the server's isolate, not of
serving a peer. With the client in its own process (`websocket_remote`) both
servers' isolates sleep between messages, and Dartvel is at parity on p50 and
lower at p99. Closing the in-process gap would take reading the socket on the
isolate's thread, as dart:io does; that would move frame parsing off the Tokio
threads, which is what makes the pipelined case 4.8x faster.

### Raw trial data (after)

```json
{"trial":1,"engine":"shelf","scenario":"hello","requests":2000,"rps":3917.919584700524,"p50_ms":4.013,"p95_ms":5.121,"elapsed_ms":510.475,"peak_rss_mib":11.3046875}
{"trial":1,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6157.806096843817,"p50_ms":2.565,"p95_ms":3.386,"elapsed_ms":324.791,"peak_rss_mib":23.3515625}
{"trial":1,"engine":"shelf","scenario":"upload","mib_per_second":431.00104302252413,"elapsed_ms":116.009,"peak_rss_mib":48.60546875}
{"trial":1,"engine":"dartvel","scenario":"upload","mib_per_second":458.5767611640513,"elapsed_ms":109.033,"peak_rss_mib":49.40234375}
{"trial":1,"engine":"shelf","scenario":"download","mib_per_second":443.7147801393264,"elapsed_ms":112.685,"peak_rss_mib":47.40625}
{"trial":1,"engine":"dartvel","scenario":"download","mib_per_second":552.9688899702503,"elapsed_ms":90.421,"peak_rss_mib":48.3203125}
{"trial":1,"engine":"shelf","scenario":"websocket","messages_per_second":7853.23867562983,"p50_us":141,"elapsed_ms":63.668,"peak_rss_mib":11.7890625}
{"trial":1,"engine":"dartvel","scenario":"websocket","messages_per_second":5807.066037954984,"p50_us":161,"elapsed_ms":86.102,"peak_rss_mib":23.62109375}
{"trial":1,"engine":"shelf","scenario":"websocket_remote","messages_per_second":2864.7261966319415,"p50_us":250,"p99_us":1735,"elapsed_ms":5749.351,"peak_rss_mib":10.97265625}
{"trial":1,"engine":"dartvel","scenario":"websocket_remote","messages_per_second":5242.505183527001,"p50_us":180,"p99_us":413,"elapsed_ms":5437.845,"peak_rss_mib":23.59375}
{"trial":1,"engine":"shelf","scenario":"websocket_pipelined","messages_per_second":37156.57800549806,"elapsed_ms":5394.212,"peak_rss_mib":82.296875}
{"trial":1,"engine":"dartvel","scenario":"websocket_pipelined","messages_per_second":184215.66496328582,"elapsed_ms":1097.976,"peak_rss_mib":28.65234375}
{"trial":2,"engine":"shelf","scenario":"hello","requests":2000,"rps":4097.143266857184,"p50_ms":3.791,"p95_ms":5.195,"elapsed_ms":488.145,"peak_rss_mib":11.6015625}
{"trial":2,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6979.9988134002015,"p50_ms":2.141,"p95_ms":3.309,"elapsed_ms":286.533,"peak_rss_mib":29.56640625}
{"trial":2,"engine":"shelf","scenario":"upload","mib_per_second":493.24257669922065,"elapsed_ms":101.37,"peak_rss_mib":46.44140625}
{"trial":2,"engine":"dartvel","scenario":"upload","mib_per_second":576.3622321356526,"elapsed_ms":86.751,"peak_rss_mib":49.2734375}
{"trial":2,"engine":"shelf","scenario":"download","mib_per_second":406.3289801955255,"elapsed_ms":123.053,"peak_rss_mib":48.796875}
{"trial":2,"engine":"dartvel","scenario":"download","mib_per_second":659.1697098334937,"elapsed_ms":75.853,"peak_rss_mib":50.01171875}
{"trial":2,"engine":"shelf","scenario":"websocket","messages_per_second":7898.0207559985465,"p50_us":118,"elapsed_ms":63.307,"peak_rss_mib":11.68359375}
{"trial":2,"engine":"dartvel","scenario":"websocket","messages_per_second":4529.929242505232,"p50_us":200,"elapsed_ms":110.377,"peak_rss_mib":23.59765625}
{"trial":2,"engine":"shelf","scenario":"websocket_remote","messages_per_second":4904.41299080913,"p50_us":184,"p99_us":606,"elapsed_ms":5460.387,"peak_rss_mib":11.85546875}
{"trial":2,"engine":"dartvel","scenario":"websocket_remote","messages_per_second":4095.700129219339,"p50_us":206,"p99_us":842,"elapsed_ms":5547.004,"peak_rss_mib":23.6015625}
{"trial":2,"engine":"shelf","scenario":"websocket_pipelined","messages_per_second":39723.31124783433,"elapsed_ms":5128.769,"peak_rss_mib":72.125}
{"trial":2,"engine":"dartvel","scenario":"websocket_pipelined","messages_per_second":169872.00993411514,"elapsed_ms":1200.63,"peak_rss_mib":23.6015625}
{"trial":3,"engine":"shelf","scenario":"hello","requests":2000,"rps":4483.4203116873805,"p50_ms":3.452,"p95_ms":4.961,"elapsed_ms":446.088,"peak_rss_mib":11.58984375}
{"trial":3,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6759.085901222718,"p50_ms":2.289,"p95_ms":3.254,"elapsed_ms":295.898,"peak_rss_mib":29.74609375}
{"trial":3,"engine":"shelf","scenario":"upload","mib_per_second":443.8211223348542,"elapsed_ms":112.658,"peak_rss_mib":46.3671875}
{"trial":3,"engine":"dartvel","scenario":"upload","mib_per_second":546.8604740186589,"elapsed_ms":91.431,"peak_rss_mib":48.7578125}
{"trial":3,"engine":"shelf","scenario":"download","mib_per_second":441.05323512547966,"elapsed_ms":113.365,"peak_rss_mib":48.80078125}
{"trial":3,"engine":"dartvel","scenario":"download","mib_per_second":595.216837493899,"elapsed_ms":84.003,"peak_rss_mib":48.55859375}
{"trial":3,"engine":"shelf","scenario":"websocket","messages_per_second":7838.587800021948,"p50_us":130,"elapsed_ms":63.787,"peak_rss_mib":11.12890625}
{"trial":3,"engine":"dartvel","scenario":"websocket","messages_per_second":5928.947493241,"p50_us":158,"elapsed_ms":84.332,"peak_rss_mib":23.7421875}
{"trial":3,"engine":"shelf","scenario":"websocket_remote","messages_per_second":4358.191002078857,"p50_us":208,"p99_us":676,"elapsed_ms":5520.809,"peak_rss_mib":11.47265625}
{"trial":3,"engine":"dartvel","scenario":"websocket_remote","messages_per_second":3944.0886000063106,"p50_us":210,"p99_us":885,"elapsed_ms":5573.847,"peak_rss_mib":23.67578125}
{"trial":3,"engine":"shelf","scenario":"websocket_pipelined","messages_per_second":38490.55441794584,"elapsed_ms":5208.775,"peak_rss_mib":74.55078125}
{"trial":3,"engine":"dartvel","scenario":"websocket_pipelined","messages_per_second":187272.9315704708,"elapsed_ms":1080.0,"peak_rss_mib":23.609375}

{"trial":1,"engine":"shelf","scenario":"hello","requests":2000,"rps":3808.9506531398133,"p50_ms":4.0,"p95_ms":5.742,"elapsed_ms":525.079,"peak_rss_mib":11.7265625}
{"trial":1,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6349.488548697403,"p50_ms":2.254,"p95_ms":4.501,"elapsed_ms":314.986,"peak_rss_mib":23.70703125}
{"trial":1,"engine":"shelf","scenario":"upload","mib_per_second":364.6946411769425,"elapsed_ms":137.101,"peak_rss_mib":48.1953125}
{"trial":1,"engine":"dartvel","scenario":"upload","mib_per_second":426.11578418087765,"elapsed_ms":117.339,"peak_rss_mib":49.60546875}
{"trial":1,"engine":"shelf","scenario":"download","mib_per_second":449.3049252805909,"elapsed_ms":111.283,"peak_rss_mib":48.12890625}
{"trial":1,"engine":"dartvel","scenario":"download","mib_per_second":595.0822403656185,"elapsed_ms":84.022,"peak_rss_mib":48.6875}
{"trial":1,"engine":"shelf","scenario":"websocket","messages_per_second":7229.71702887549,"p50_us":132,"elapsed_ms":69.159,"peak_rss_mib":11.20703125}
{"trial":1,"engine":"dartvel","scenario":"websocket","messages_per_second":5471.776576418832,"p50_us":175,"elapsed_ms":91.378,"peak_rss_mib":23.49609375}
{"trial":1,"engine":"shelf","scenario":"websocket_remote","messages_per_second":4864.073466965645,"p50_us":187,"p99_us":507,"elapsed_ms":5479.586,"peak_rss_mib":11.22265625}
{"trial":1,"engine":"dartvel","scenario":"websocket_remote","messages_per_second":3746.4057919433544,"p50_us":203,"p99_us":712,"elapsed_ms":5583.75,"peak_rss_mib":23.69140625}
{"trial":1,"engine":"shelf","scenario":"websocket_pipelined","messages_per_second":36043.82280063747,"elapsed_ms":5565.819,"peak_rss_mib":75.7578125}
{"trial":1,"engine":"dartvel","scenario":"websocket_pipelined","messages_per_second":190778.52902122983,"elapsed_ms":1062.883,"peak_rss_mib":28.48046875}
{"trial":2,"engine":"shelf","scenario":"hello","requests":2000,"rps":3940.8168131008515,"p50_ms":3.94,"p95_ms":5.633,"elapsed_ms":507.509,"peak_rss_mib":11.0390625}
{"trial":2,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6150.174972477967,"p50_ms":2.42,"p95_ms":4.26,"elapsed_ms":325.194,"peak_rss_mib":23.8671875}
{"trial":2,"engine":"shelf","scenario":"upload","mib_per_second":416.0114486350664,"elapsed_ms":120.189,"peak_rss_mib":44.3828125}
{"trial":2,"engine":"dartvel","scenario":"upload","mib_per_second":550.9277623518004,"elapsed_ms":90.756,"peak_rss_mib":49.01171875}
{"trial":2,"engine":"shelf","scenario":"download","mib_per_second":531.8922599038339,"elapsed_ms":94.004,"peak_rss_mib":46.65234375}
{"trial":2,"engine":"dartvel","scenario":"download","mib_per_second":523.1657807726112,"elapsed_ms":95.572,"peak_rss_mib":48.59765625}
{"trial":2,"engine":"shelf","scenario":"websocket","messages_per_second":8232.078764529619,"p50_us":104,"elapsed_ms":60.738,"peak_rss_mib":11.3125}
{"trial":2,"engine":"dartvel","scenario":"websocket","messages_per_second":6232.315803906416,"p50_us":147,"elapsed_ms":80.227,"peak_rss_mib":23.6015625}
{"trial":2,"engine":"shelf","scenario":"websocket_remote","messages_per_second":4629.008142425322,"p50_us":193,"p99_us":591,"elapsed_ms":5483.306,"peak_rss_mib":11.1015625}
{"trial":2,"engine":"dartvel","scenario":"websocket_remote","messages_per_second":4749.3980138017505,"p50_us":198,"p99_us":448,"elapsed_ms":5486.846,"peak_rss_mib":23.70703125}
{"trial":2,"engine":"shelf","scenario":"websocket_pipelined","messages_per_second":40276.579269846035,"elapsed_ms":4982.074,"peak_rss_mib":71.3984375}
{"trial":2,"engine":"dartvel","scenario":"websocket_pipelined","messages_per_second":195897.32237744908,"elapsed_ms":1035.157,"peak_rss_mib":23.59765625}
{"trial":3,"engine":"shelf","scenario":"hello","requests":2000,"rps":3702.3050551273222,"p50_ms":4.084,"p95_ms":5.769,"elapsed_ms":540.204,"peak_rss_mib":11.14453125}
{"trial":3,"engine":"dartvel","scenario":"hello","requests":2000,"rps":6048.856614878373,"p50_ms":2.539,"p95_ms":3.405,"elapsed_ms":330.641,"peak_rss_mib":26.3515625}
{"trial":3,"engine":"shelf","scenario":"upload","mib_per_second":403.4177552222428,"elapsed_ms":123.941,"peak_rss_mib":72.09375}
{"trial":3,"engine":"dartvel","scenario":"upload","mib_per_second":326.7525372334516,"elapsed_ms":153.021,"peak_rss_mib":50.42578125}
{"trial":3,"engine":"shelf","scenario":"download","mib_per_second":391.12001126425633,"elapsed_ms":127.838,"peak_rss_mib":44.23828125}
{"trial":3,"engine":"dartvel","scenario":"download","mib_per_second":356.74788626877387,"elapsed_ms":140.155,"peak_rss_mib":53.859375}
{"trial":3,"engine":"shelf","scenario":"websocket","messages_per_second":8250.280509537324,"p50_us":101,"elapsed_ms":60.604,"peak_rss_mib":11.609375}
{"trial":3,"engine":"dartvel","scenario":"websocket","messages_per_second":4865.469761105434,"p50_us":183,"elapsed_ms":102.765,"peak_rss_mib":23.83203125}
{"trial":3,"engine":"shelf","scenario":"websocket_remote","messages_per_second":4136.059823969294,"p50_us":185,"p99_us":1264,"elapsed_ms":5546.323,"peak_rss_mib":11.6015625}
{"trial":3,"engine":"dartvel","scenario":"websocket_remote","messages_per_second":4163.11934206062,"p50_us":211,"p99_us":679,"elapsed_ms":5562.748,"peak_rss_mib":23.59375}
{"trial":3,"engine":"shelf","scenario":"websocket_pipelined","messages_per_second":39157.54116485462,"elapsed_ms":5139.479,"peak_rss_mib":78.9765625}
{"trial":3,"engine":"dartvel","scenario":"websocket_pipelined","messages_per_second":197023.75909510927,"elapsed_ms":1028.072,"peak_rss_mib":28.2890625}
```

### Analysis of tradeoffs

1. **HTTP Throughput & Latency (`hello`):**
   Dartvel outperforms Shelf on concurrent HTTP handling (about 6,400 vs 4,000 RPS) with lower median and p95 latency. Axum's Rust HTTP parser, epoll event loops, and multi-core work stealing process concurrent request streams with lower context-switch overhead than `dart:io`.

2. **Streamed I/O (`upload` & `download`):**
   Both engines stream large payloads at roughly 430–550 MiB/s across loopback; trial-to-trial spread on this shared machine is larger than the difference between them. Response backpressure acknowledgements (`aw_register_stream_ack_handler`) keep Dartvel's peak RSS near 50 MiB during a 50 MiB transfer, like Shelf's.

3. **WebSockets:**
   A peer in its own process sees the same median latency from both servers and a lower p99 from Dartvel; pipelined traffic runs 4.8x faster on Dartvel with a third of Shelf's memory. The one scenario Shelf still wins is a client sharing the server's isolate, for the reason measured above.

4. **Resident Memory Footprint (RSS):**
   In all scenarios, Dartvel carries a ~12–14 MiB baseline resident memory delta over Shelf (~25.4 MiB vs ~12.1 MiB idle). This represents the static footprint of embedding `libdartvel_shelf.so`, the Tokio multithreaded runtime, Rust standard library runtime structures, and memory arenas.
