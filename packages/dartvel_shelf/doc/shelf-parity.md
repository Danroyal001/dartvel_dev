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

## Structural round: per-request cost (18 November 2026, evening)

User-space instructions per `/plaintext` request, `perf stat -e
instructions:u` on the server during a 5 s, 64-connection oha run, three
alternating runs each, main (#280) against this change. Box load 11-14.

| | main | this change |
|---|---|---|
| whole server, as fast as it goes | 37,816 / 37,840 / 37,107 | 24,753 / 24,214 / 24,140 |
| whole server, held at 8,000 requests a second | 39,338 / 38,484 / 38,524 | 26,882 / 26,957 / 27,335 |
| the native library alone (below) | 10,889 / 11,457 / 11,258 | 7,381 / 6,992 / 7,373 |

About 36% fewer instructions per request; Relic's server spent about 20,000
in the last round's measurement. "The native library alone" is a test
(`native_only_server` in `rust/src/lib.rs`) that drives a server the way the
isolate's request queue does -- drive, take up to 64, answer each with the
benchmark's plaintext answer, park when idle -- with no Dart at all, under
the same load. It is what showed where the cost was: sampled profiles on
this virtual machine put most of it in the native library, because the
counter interrupt arrives late and lands on the instructions after a
system call; counting the library alone puts it at a third.

**Requests a second** (`compare.dart`, compiled servers, three trials,
medians; 18 Nov 2026 19:39-19:48 CEST, load 9.3-20.8, median 14.5;
`dartvel_before` is main at 878342e0c):

| scenario | metric | relic_native | relic_native4 | dartvel_before | dartvel | dartvel4 |
|---|---|---|---|---|---|---|
| plaintext | rps | 15005 | 34139 | 14043 | 17763 | 18147 |
| plaintext | cpu_us_per_req | 71.9 | 78.6 | 78.0 | 61.2 | 117 |
| json | rps | 19185 | 27257 | 11350 | 13355 | 25857 |
| headers | rps | 21972 | 32046 | 14530 | 17693 | 27753 |
| static | rps | 1454 | 2144 | 3096 | 3528 | 6474 |
| websocket | messages_per_second | 2362 | 1459 | 1094 | 1070 | 1825 |
| websocket_pipelined | messages_per_second | 197747 | 172459 | 106654 | 153346 | 159541 |

On one isolate this server now answers plaintext faster than
`relic_native` in this run, with less CPU a request; Relic is still ahead on
json and headers, on four isolates, and on both WebSocket rows (pipelined
WebSocket rose from 107k to 153k with the WebSocket code unchanged, because
the box was less loaded or the request path freed time; not claimed as a
WebSocket win). Static files stay well ahead.

**Native side** (about 11,200 to about 7,400):

- *A direct write path.* A whole answer on the lean HTTP/1 path is written
  to the socket by `aw_complete` itself, from Dart's buffer, with a
  non-blocking write. It used to be copied into two new buffers, sent down a
  oneshot channel, and the connection's task woken, polled and made to write
  it. The task is now woken only when something is left for it: the rest of
  an answer the socket would not take, a connection to close, or an answer
  the generic path writes (streamed, compressed, an upgrade). One wakeup per
  request is left: the client's next request.
- *A response-head cache.* A route answers with the same status, fields and
  body length request after request, so within one second (the Date) its
  head is the same bytes. Each thread keeps the last head and what it was
  written from; an answer whose head matches costs a comparison and a copy,
  404 instructions where checking and formatting it cost 1,405.
- *Timers armed once per connection.* The header and answer timeouts were a
  Tokio timer per read and per answer, each put into the wheel and taken out
  again for every request. Each kind is now one timer per connection that is
  re-armed only when it rings before its deadline; a deadline still passes
  exactly when due.
- *The queue keeps a request's bytes.* A queued request's bytes were held in
  a table until Dart acknowledged the request: an insert, an acknowledgement
  call from Dart, and two locked removes per request. The queue now hands
  each batch's bytes to the taking thread, which frees them at its next
  take, by when the isolate has read them all; Dart makes no
  acknowledgement call for a queued request (`aw_queue_holds_requests`).
- The server's default fields are rendered once per server, and a field
  name is checked and lowercased with one table lookup a byte.

**Dart side** (about 26,000 to about 17,000: the whole server less the library alone):

- *Two async functions fewer per request.* `Router._dispatch` returns the
  route's own future instead of awaiting it in an async function of its own,
  and `serve()` passes the router's future through when it has nothing to add
  to a response (the library adds the default fields and there is no page
  policy). Each was a suspend state, a future and a resumption per request.
- *A request's URL is parsed once per target.* Uri is immutable, so the
  requests for one target share one: every request built its URL again --
  a concatenation and a whole parse -- which was the largest single cost of
  reading a request. Bounded (512 targets of up to 256 characters); a
  target that is not a URL is refused every time, as before.
- *A smaller function around the await every request makes.* The upgrade
  and streaming paths are functions of their own, so the function that
  awaits the handler no longer saves and restores all their locals.
- `Router.call` times a request without the async `measure` around it, on
  one clock read at the start and one at the end, which the access-log
  budget reuses.
- *The recent-records buffer is a ring.* Once full, it dropped the oldest
  record by moving every other record down by one, for every record written:
  an access line cost 107,000 instructions, 26,000 of them that move. It
  costs 81,000 now.

**Not done, and why.** The access log was not moved off the isolate: it is
capped at 100 lines a second, so at 13,000 requests a second it costs about
600 instructions a request in all, and moving the JSON encoding and the
write to another isolate would save part of that while adding a copy of
every record between isolates and losing lines at exit. The Dart side is
still above the 13,000 aimed for; what is left is spread thin (the request
and response objects, the one remaining measuring zone hop, the metrics).
The lean single-threaded WebSocket path is the next piece of work.

**Tests added:** `test/lean_direct_write_test.dart` (answers in order on a
pipelined connection; 2.4 MB of whole answers to a client that reads late,
every byte in place; a handler's `Connection: close`),
`test/request_url_reuse_test.dart`, three timeout tests in
`test/request_failure_answered_test.dart` (a reused connection's request gets
its own full timeout; a never-answered one is answered 504 a full timeout
after it was sent; the next head is timed from the answer), and Rust tests
for the head cache, more than 64 default fields, the name table, and the
queue's hold on a batch (which must outlive the server's queue).

## Per-request cost, counted in instructions (18 November 2026, afternoon)

Requests per second on this shared machine move by up to 2x between trials,
which hides a change worth a few percent. User-space instructions per
request do not move with load, so this round measured those: `perf stat -e
instructions:u` on the server process during a 5 s, 64-connection oha run of
`/plaintext`, divided by the requests answered, three alternating runs, the
same native library under both Dart sides.

| server | instructions per plaintext request (three runs) |
|---|---|
| `relic_native`, one isolate | 19,892 / 20,637 / 20,600 |
| dartvel_shelf, main (#277) | 37,604 / 38,242 / 37,879 |
| dartvel_shelf, this change | 35,832 / 35,151 / 36,389 |

The change (a request with no body gets no body stream; `Router.measure`
without its tracing closures when nothing traces; method names not
allocated) takes off about 5%. Relic's server spends a little over half of
what this one does. By the profiles, the rest is on both sides: the Dart
side of a request (about 18,000 here against about 13,000 in Relic: the
request and response objects, the router's measuring, the async calls
between them) and the native one (about 12,000 against about 7,000: Tokio's
scheduling, the request and answer tables, copies). Closing it is the work
still ahead, with a lean WebSocket path.

## WebSocket round (18 November 2026, 10:00-11:00)

**What changed:** `sink.addStream` no longer awaits each frame. Awaiting
paused the incoming stream after every frame, so each frame was drained,
queued and flushed (a system call) on its own: a burst of 1,000 frames
echoed through `addStream` cost 1,000 writes. It now takes frames while the
native queue has room and pauses only when full; the same burst costs a few
writes (`test/websocket_add_stream_test.dart`, which failed with 1,000
before the change). Order, completion and errors are as before.

**Follow-up: a burst stays one batch on a loaded machine.** Under a loaded
test run the same burst still cost 127 to 566 writes, for three reasons,
each fixed: the native reader woke Dart at the first frame of a burst (now
when it would block, or when Dart's queue is full); a Dart drain stopped
whenever it caught up with the reader mid-burst (it now keeps taking while
the reader reports it is partway through one -- `aw_ws_reader_busy`, only
when another thread runs the reader); and addStream paused at 256 waiting
frames even when they were only waiting for the pump that runs right after
the drain, which made the rest arrive a microtask, a pump and a write at a
time (it now pauses only when the native queue is full). The test starts
its echo once the whole burst is in the server's socket, so it measures the
server's batching and not the machine's load, and holds the bound it had,
fewer than 100 writes for 1,000 frames: it passed every one of the loaded
runs (`-j 4` beside the other server tests) it had failed before.

**What was tried and not kept** (measured, then reverted):

- Receiving many frames per native call (`aw_ws_receive_batch`): fewer calls
  and allocations, but the isolate then drained faster than the native
  reader filled the queue, so frames went out in smaller batches (716-748
  writes for the 1,000-frame burst under a loaded test run).
- Letting the isolate own the runtime while WebSocket traffic flows, with a
  short wait for the next frame on its own thread, as Relic does: ping-pong
  drew level with `relic_native` (2,312 vs 1,555 msgs/s in one trial, 1,373
  vs 1,496 in the next) but pipelined throughput fell from about 120k to
  80-100k msgs/s, because reading, handling and writing then share one
  thread where the helper used to read in parallel. Switching between the
  two by burst size gave neither.

Beating Relic on both WebSocket rows at once needs a single-threaded path
cheap enough per frame -- a lean frame codec in Rust and a cheaper Dart frame
path -- which is the next piece of work, not part of this change.

**Numbers:** `compare.dart`, compiled servers, three trials each, medians, 18
Nov 2026 10:07-10:25 CEST (load 10.9-27.3) for the HTTP rows; the WebSocket
rows are a three-trial run at 10:5x (load 7.1-12.6) of the final code.
`dartvel_before` is `origin/main` at 2ac69fff8 (#272). The HTTP code is the
same as main's, so the HTTP rows of `dartvel` and `dartvel_before` differ by
noise only.

| scenario | metric | shelf | relic_io | relic_native | relic_native4 | dartvel_before | dartvel | dartvel4 |
|---|---|---|---|---|---|---|---|---|
| plaintext | rps | 3504 | 4091 | 20370 | 40998 | 12352 | 12087 | 17046 |
| plaintext | p50_ms | 12.9 | 10.6 | 1.67 | 0.63 | 2.65 | 2.57 | 1.08 |
| plaintext | p99_ms | 101 | 75.1 | 27.1 | 17.4 | 47.9 | 41.0 | 39.3 |
| plaintext | cpu_us_per_req | 392 | 357 | 54.8 | 61.3 | 70.4 | 76.4 | 120 |
| plaintext | peak_rss_mib | 20.1 | 20.5 | 17.0 | 27.1 | 22.5 | 23.1 | 25.3 |
| json | rps | 3274 | 3478 | 15775 | 32600 | 12974 | 13715 | 14812 |
| json | p50_ms | 13.3 | 12.5 | 1.84 | 0.69 | 2.98 | 2.74 | 1.17 |
| json | p99_ms | 110 | 123 | 29.3 | 20.5 | 39.1 | 38.8 | 52.4 |
| json | cpu_us_per_req | 363 | 400 | 57.1 | 84.2 | 80.6 | 67.7 | 127 |
| json | peak_rss_mib | 20.3 | 20.9 | 16.9 | 27.0 | 23.0 | 22.9 | 25.3 |
| headers | rps | 2507 | 2991 | 20794 | 34239 | 12144 | 9689 | 15238 |
| headers | p50_ms | 17.3 | 16.2 | 1.86 | 0.65 | 2.57 | 3.04 | 1.20 |
| headers | p99_ms | 144 | 90.7 | 26.0 | 19.2 | 44.3 | 58.1 | 45.3 |
| headers | cpu_us_per_req | 540 | 490 | 56.0 | 68.0 | 65.7 | 75.5 | 108 |
| headers | peak_rss_mib | 21.3 | 22.6 | 16.9 | 27.0 | 23.1 | 23.0 | 26.0 |
| static | rps | 1004 | 937 | 1343 | 2083 | 3942 | 3039 | 6809 |
| static | p50_ms | 40.6 | 47.7 | 41.3 | 24.1 | 12.7 | 13.2 | 4.05 |
| static | p99_ms | 417 | 328 | 154 | 115 | 79.4 | 121 | 100 |
| static | cpu_us_per_req | 1369 | 1021 | 578 | 761 | 448 | 469 | 424 |
| static | peak_rss_mib | 52.0 | 52.4 | 31.9 | 65.0 | 18.5 | 18.5 | 20.3 |
| many | rps | 1431 | 3347 | 9012 | 29996 | 11780 | 12910 | 26216 |
| many | p50_ms | 62.7 | 46.7 | 18.4 | 20.0 | 65.2 | 66.1 | 27.9 |
| many | p99_ms | 1806 | 1862 | 988 | 219 | 378 | 330 | 164 |
| many | cpu_us_per_req | 366 | 329 | 84.1 | 58.3 | 79.8 | 77.4 | 67.3 |
| many | peak_rss_mib | 45.0 | 47.8 | 37.0 | 46.7 | 61.8 | 62.0 | 68.1 |
| many | non_200 | - | - | - | - | - | - | - |
| startup | startup_ms | 22.2 | 31.1 | 49.6 | 101 | 24.4 | 35.0 | 36.2 |
| startup | peak_rss_mib | 9.00 | 9.85 | 12.4 | 16.0 | 12.0 | 12.1 | 12.8 |
| upload | mib_per_second | 230 | 303 | 551 | 295 | 165 | 231 | 171 |
| upload | peak_rss_mib | 43.6 | 54.8 | 15.5 | 24.4 | 47.3 | 47.8 | 48.1 |
| download | mib_per_second | 200 | 270 | 201 | 404 | 276 | 313 | 184 |
| download | peak_rss_mib | 12.1 | 13.0 | 13.4 | 16.8 | 15.1 | 15.1 | 15.6 |
| websocket | messages_per_second | 776 | 619 | 1427 | 1062 | 1168 | 1286 | 1365 |
| websocket | p50_us | 372 | 567 | 178 | 351 | 227 | 199 | 220 |
| websocket | p99_us | 13993 | 18036 | 9004 | 8904 | 8439 | 8789 | 7500 |
| websocket | peak_rss_mib | 12.0 | 13.0 | 14.9 | 17.6 | 14.9 | 14.9 | 15.4 |
| websocket_pipelined | messages_per_second | 33054 | 32609 | 156044 | 182099 | 50511 | 96870 | 69128 |
| websocket_pipelined | peak_rss_mib | 81.6 | 81.2 | 15.6 | 25.3 | 22.0 | 16.0 | 16.4 |

load1 during rows: median 16.97, min 7.06, max 27.28; rows 210

- Pipelined WebSocket: 50,511 to 84,738 msgs/s against main (+68%);
  `relic_native` 156,044, still 1.8x ahead.
- WebSocket ping-pong: `dartvel` 1,286 msgs/s (p50 199 us) against
  `relic_native` 1,427 (178 us); on four isolates `dartvel4` 1,365 against
  `relic_native4` 1,062.
- HTTP (code unchanged from main): `relic_native` ahead on plaintext and
  browser headers; in this run `dartvel` answered more at 1,024 connections
  (12,910 vs 9,012) and on static files (3,039 vs 1,343), and started faster
  (35 vs 50 ms), each a single run on a loaded machine.

## Against Relic 2 with the lean HTTP/1 path (18 November 2026, later)

The server below reads plain HTTP/1.1 itself (`rust/src/h1.rs`): a `GET`
with no body over HTTP/1.1 is parsed with httparse, handed to the isolate's
request queue from the bytes it arrived in, and answered from the bytes Dart
gave, in one write. Every other request moves its connection, with the bytes
already read, to hyper and axum as before, so the 400s, bodies, upgrades,
HTTP/1.0, TLS and CORS behave exactly as they did. All 313 dartvel_shelf
tests pass unchanged.

Safety evidence: `h1.rs` is `#![forbid(unsafe_code)]`. Its 23 unit and
property tests cover the classifier (any bytes never panic, and a request
served here has exactly one reading: no `Transfer-Encoding`, at most one
`Content-Length: 0`, no `Upgrade`/`Expect`; conflicting lengths,
`Transfer-Encoding` in any spelling, obsolete line folds, heads past 64 KiB
and over 64 fields go to hyper) and the answer writer (no answer Dart gives
can add a header line; what hyper refuses is refused). All 22 that existed when it ran pass under Miri (the upgrade-recognition
test added after it has not been run there), and the whole Rust
suite (70 tests) passes under AddressSanitizer. A head still incomplete when
the header timeout ends closes the connection, as hyper's did.

Measured as in the section after this one (`compare.dart`, compiled servers,
oha 1.17.0, 64 connections, three trials each, medians), 18 Nov 2026
07:40-07:58 CEST, load average 8.0-24.9 (median 16.6). The WebSocket,
static and download rows are a second three-trial run at 08:3x (load
6.0-14.1) after one fix (an upgraded connection keeps Nagle; the first run
had turned it off and halved pipelined WebSocket). `dartvel_before` is
`origin/main` at e109ec558 (#269 and #270 merged); the server opens its
library from the file it is in, which a library given as a whole file now
does.

| scenario | metric | shelf | relic_io | relic_native | relic_native4 | dartvel_before | dartvel | dartvel4 |
|---|---|---|---|---|---|---|---|---|
| plaintext | rps | 2724 | 4163 | 21307 | 35621 | 10350 | 16513 | 19348 |
| plaintext | p50_ms | 13.4 | 10.5 | 1.64 | 0.56 | 3.63 | 2.27 | 1.02 |
| plaintext | p99_ms | 130 | 92.0 | 23.9 | 17.4 | 45.6 | 29.3 | 35.1 |
| plaintext | cpu_us_per_req | 340 | 290 | 45.8 | 63.9 | 102 | 61.8 | 107 |
| plaintext | peak_rss_mib | 20.2 | 20.7 | 17.2 | 27.0 | 31.0 | 23.2 | 25.6 |
| json | rps | 2532 | 2552 | 15059 | 16350 | 8770 | 11138 | 23391 |
| json | p50_ms | 13.3 | 12.0 | 1.73 | 0.73 | 3.85 | 2.71 | 0.95 |
| json | p99_ms | 190 | 178 | 44.6 | 62.0 | 65.4 | 53.5 | 30.2 |
| json | cpu_us_per_req | 493 | 343 | 56.1 | 86.1 | 116 | 68.3 | 93.9 |
| json | peak_rss_mib | 20.2 | 20.8 | 17.0 | 27.0 | 31.3 | 22.9 | 26.0 |
| headers | rps | 2022 | 2496 | 17037 | 30820 | 9250 | 9663 | 16440 |
| headers | p50_ms | 20.0 | 15.4 | 1.98 | 0.62 | 4.13 | 2.99 | 1.21 |
| headers | p99_ms | 148 | 179 | 34.2 | 25.9 | 47.2 | 49.8 | 45.7 |
| headers | cpu_us_per_req | 428 | 409 | 48.1 | 68.1 | 113 | 81.3 | 119 |
| headers | peak_rss_mib | 21.3 | 23.3 | 17.0 | 27.1 | 31.6 | 23.0 | 26.0 |
| many | rps | 2970 | 4815 | 15814 | 32155 | 10252 | 14589 | 33585 |
| many | p50_ms | 51.1 | 42.4 | 10.5 | 16.1 | 83.1 | 53.4 | 18.3 |
| many | p99_ms | 2211 | 1654 | 483 | 199 | 269 | 317 | 191 |
| many | cpu_us_per_req | 424 | 324 | 60.3 | 59.5 | 109 | 76.0 | 72.9 |
| many | peak_rss_mib | 48.8 | 48.8 | 37.0 | 47.3 | 83.0 | 63.2 | 67.6 |
| many | non_200 | - | - | - | - | - | - | - |
| startup | startup_ms | 26.0 | 30.7 | 33.5 | 40.4 | 48.6 | 35.9 | 28.9 |
| startup | peak_rss_mib | 8.97 | 9.93 | 12.4 | 16.1 | 18.8 | 12.1 | 12.6 |
| upload | mib_per_second | 154 | 133 | 212 | 621 | 224 | 223 | 238 |
| upload | peak_rss_mib | 53.8 | 52.5 | 16.0 | 24.5 | 48.9 | 48.2 | 47.3 |
| websocket | messages_per_second | 1009 | 738 | 1803 | 1147 | 1021 | 1047 | 1130 |
| websocket | p50_us | 550 | 519 | 296 | 396 | 457 | 498 | 477 |
| websocket | p99_us | 6472 | 9446 | 5112 | 8106 | 7147 | 8407 | 6477 |
| websocket | peak_rss_mib | 12.6 | 13.0 | 15.0 | 17.9 | 21.5 | 15.5 | 15.9 |
| websocket_pipelined | messages_per_second | 34280 | 35752 | 202920 | 220015 | 77123 | 100676 | 101883 |
| websocket_pipelined | peak_rss_mib | 78.0 | 77.2 | 15.5 | 25.5 | 28.2 | 22.5 | 22.6 |
| static | rps | 1963 | 1897 | 1883 | 3365 | 1350 | 4774 | 10913 |
| static | p50_ms | 27.5 | 27.8 | 28.5 | 15.1 | 45.5 | 11.4 | 3.37 |
| static | p99_ms | 113 | 98.3 | 115 | 96.7 | 133 | 64.4 | 44.0 |
| static | cpu_us_per_req | 918 | 914 | 765 | 851 | 771 | 452 | 465 |
| static | peak_rss_mib | 52.8 | 52.2 | 31.8 | 36.5 | 23.2 | 19.9 | 20.6 |
| download | mib_per_second | 353 | 289 | 378 | 315 | 355 | 270 | 336 |
| download | peak_rss_mib | 12.4 | 12.5 | 13.4 | 16.7 | 21.8 | 15.5 | 16.0 |

load1 during rows: median 12.82, min 5.98, max 24.91; rows 210

What the numbers say:

- **Ahead of `relic_native`:** static files on one isolate (4,774 vs 1,883
  req/s, p50 11 vs 29 ms, p99 64 vs 115 ms, 452 vs 765 us of CPU, 20 vs 32
  MiB) and on four (10,913 vs 3,365). `dartvel4` was level with
  `relic_native4` at 1,024 connections (33,585 vs 32,155) and ahead on JSON
  (23,391 vs 16,350; Relic's four isolates answered fewer JSON than plaintext
  requests in this run, so treat that one with care).
- **Behind `relic_native`:** plaintext (16,513 vs 21,307 on one isolate,
  19,348 vs 35,621 on four), browser headers (9,663 vs 17,037), JSON on one
  isolate, 1,024 connections on one isolate (14,589 vs 15,814), pipelined
  WebSocket (about half: 100,676 vs 202,920), WebSocket ping-pong, download,
  and resident memory (23 vs 17 MiB for plaintext). Start-up is a single
  sample per trial and moved more between trials than between engines.
- **Against main:** plaintext 10,350 to 16,513 req/s and 102 to 62 us of CPU
  per request; memory 31 to 23 MiB; static files 1,350 to 4,774 req/s (a
  latency bug went with it: the hyper path left Nagle on, and a streamed
  answer waited about 40 ms for a delayed ACK); pipelined WebSocket 77,123
  to 100,676 msgs/s.

With Relic's own `http_load.dart` (Relic's servers inside that tool under
`dart run`, ours compiled, as URL targets; 50% and 100% of saturation,
07:58-08:04), rows at 100%:

| target | workload | load | offered rps | rps | p50 | p99 | p99.9 | errors |
|---|---|---|---|---|---|---|---|---|
| native | plaintext | 100% | 16473 | 15072 | 2.71 | 28.29 | 78.22 | - |
| native | json | 100% | 15126 | 7410 | 3.68 | 96.97 | 229.80 | - |
| native | headers | 100% | 13806 | 11497 | 3.05 | 46.78 | 158.16 | - |
| native | browser | 100% | 11428 | 11082 | 3.69 | 32.79 | 77.12 | - |
| native4 | plaintext | 100% | 32525 | 26729 | 1.23 | 18.06 | 56.46 | - |
| native4 | json | 100% | 36264 | 6596 | 1.91 | 173.06 | 436.50 | - |
| native4 | headers | 100% | 17795 | 13550 | 2.46 | 42.64 | 97.58 | - |
| native4 | browser | 100% | 14658 | 8892 | 3.09 | 58.38 | 594.59 | - |
| dartvel_before | plaintext | 100% | 11799 | 10282 | 3.74 | 38.08 | 83.47 | - |
| dartvel_before | json | 100% | 7435 | 7102 | 4.45 | 56.16 | 106.28 | - |
| dartvel_before | headers | 100% | 4369 | 3773 | 8.51 | 126.82 | 244.18 | - |
| dartvel_before | browser | 100% | 1847 | 1846 | 8.84 | 99.85 | 108.26 | - |
| dartvel | plaintext | 100% | 5081 | 4709 | 5.03 | 185.15 | 603.99 | - |
| dartvel | json | 100% | 9737 | 8552 | 3.70 | 78.48 | 187.13 | - |
| dartvel | headers | 100% | 6000 | 3217 | 6.86 | 194.28 | 498.82 | - |
| dartvel | browser | 100% | 5263 | 4676 | 6.64 | 131.89 | 418.32 | - |
| dartvel4 | plaintext | 100% | 8810 | 8146 | 3.89 | 62.94 | 166.57 | - |
| dartvel4 | json | 100% | 16828 | 12550 | 2.77 | 35.56 | 89.81 | - |
| dartvel4 | headers | 100% | 14576 | 10185 | 3.00 | 62.54 | 162.99 | - |
| dartvel4 | browser | 100% | 16002 | 5479 | 5.61 | 115.29 | 275.65 | - |

Relic was ahead on most rows there too, and `dartvel` on one isolate measured
below `dartvel_before` on plaintext and headers, the opposite of the table
above, in a window with a p99 of 185 ms; that run is too noisy to read more
into.

Where the rest goes (perf, this branch, one isolate, plaintext): the kernel's
TCP path and netfilter are now half the process's CPU, Dart (JIT for symbols)
a quarter, the native library 16% and libc 5%. The remaining gap to Relic is
the Dart side of a request (request and response objects, the router's
measuring, the sampled access log) and the per-request wakeups of the
isolate's own turns, not HTTP parsing.

## Against Relic 2 (18 November 2026)

Serverpod's Relic 2 (pub `relic` 2.0.0) publishes these numbers from its own
machine (oha, 64 connections): `relic_native` on one isolate about 94,500
req/s for plaintext, on four isolates about 148,000, Relic on dart:io about
16,700, shelf about 9,600. `relic_native` is a Zig server that parses HTTP on
each isolate's own thread and hands requests to Dart in batches.

### How it was measured

`benchmark/compare.dart`, compiled servers, each engine in a fresh process of
its own, driven from outside by oha 1.17.0 (the tool Relic's own
`http_load.dart` uses): 64 keep-alive connections, a 2 s warm-up, then 5 s
closed loop; `many` is 1,024 connections; `headers` is plaintext with Relic's
18 browser headers (cookie included); `static` a 4 KiB file through each
engine's own static handler. WebSocket, upload (50 MiB) and download use the
Dart clients in `compare.dart` in a process of their own. CPU per request is
the server process's user + system time divided by the requests it answered;
RSS is the server's own peak (VmHWM). Three trials of every row in one
`~/heavy.sh` slot, 18 Nov 2026 04:54-05:16 CEST; the table is the median.
`dartvel_before` is `origin/main` at dfbee33eb with its committed library;
`dartvel` and `dartvel4` (four isolates, `serve(shared: true)`) are this
branch with the rebuilt library. Relic's servers are
`benchmark/relic/bin/serve.dart`. An earlier full run of the same program
(04:02-04:25, before the idle-turn change) agrees on every conclusion below
unless a row says otherwise.

**The machine is a shared, busy production server** (8 vCPU, 24 GB, swap
full). The one-minute load average was 9.1-68.6 during these rows (median
18.1), so every number is far below what an idle machine gives, and trials
of one cell differ by up to 2x. Compare engines within a row, never with
Relic's published figures. `startup_ms`, upload and download moved by more
between the two runs than between engines and say nothing either way.

| scenario | metric | shelf | relic_io | relic_native | relic_native4 | dartvel_before | dartvel | dartvel4 |
|---|---|---|---|---|---|---|---|---|
| plaintext | rps | 3551 | 3906 | 20394 | 30017 | 1499 | 11796 | 17487 |
| plaintext | p50_ms | 12.6 | 11.6 | 2.01 | 0.90 | 26.5 | 3.22 | 1.53 |
| plaintext | p99_ms | 100 | 135 | 20.1 | 22.0 | 232 | 36.5 | 41.3 |
| plaintext | cpu_us_per_req | 251 | 349 | 42.8 | 55.2 | 423 | 81.9 | 115 |
| plaintext | peak_rss_mib | 19.5 | 21.0 | 16.9 | 27.0 | 61.4 | 30.7 | 34.9 |
| json | rps | 3819 | 3746 | 14449 | 37952 | 2625 | 14112 | 17838 |
| json | p50_ms | 13.0 | 11.6 | 1.95 | 0.65 | 15.7 | 3.54 | 1.50 |
| json | p99_ms | 100 | 102 | 49.6 | 15.7 | 127 | 21.9 | 34.0 |
| json | cpu_us_per_req | 385 | 323 | 51.1 | 56.0 | 468 | 81.8 | 119 |
| json | peak_rss_mib | 20.8 | 20.8 | 17.0 | 26.4 | 63.5 | 30.9 | 34.5 |
| headers | rps | 2511 | 2443 | 14974 | 29873 | 2564 | 8036 | 13033 |
| headers | p50_ms | 17.4 | 17.7 | 2.01 | 0.89 | 21.0 | 5.06 | 2.08 |
| headers | p99_ms | 116 | 141 | 38.6 | 22.2 | 120 | 67.8 | 56.6 |
| headers | cpu_us_per_req | 493 | 388 | 62.5 | 59.4 | 505 | 105 | 118 |
| headers | peak_rss_mib | 21.6 | 22.6 | 16.8 | 26.6 | 65.4 | 31.2 | 35.2 |
| static | rps | 1279 | 1288 | 1071 | 1752 | 1287 | 1550 | 1790 |
| static | p50_ms | 38.1 | 40.0 | 45.4 | 25.8 | 45.4 | 44.5 | 42.8 |
| static | p99_ms | 227 | 207 | 249 | 177 | 148 | 101 | 132 |
| static | cpu_us_per_req | 894 | 935 | 621 | 648 | 994 | 539 | 691 |
| static | peak_rss_mib | 51.4 | 53.0 | 32.1 | 36.8 | 29.8 | 23.4 | 25.1 |
| many | rps | 3409 | 3688 | 17254 | 41449 | 4060 | 11179 | 21572 |
| many | p50_ms | 56.4 | 43.2 | 8.92 | 14.8 | 181 | 82.1 | 31.2 |
| many | p99_ms | 1479 | 2154 | 468 | 136 | 1170 | 209 | 241 |
| many | cpu_us_per_req | 334 | 337 | 58.1 | 52.1 | 478 | 113 | 101 |
| many | peak_rss_mib | 46.8 | 47.7 | 37.0 | 46.9 | 94.5 | 83.6 | 92.2 |
| many | non_200 | - | - | - | - | - | - | - |
| startup | startup_ms | 72.8 | 54.8 | 75.1 | 60.5 | 102 | 73.7 | 63.7 |
| startup | peak_rss_mib | 8.91 | 9.84 | 12.4 | 16.1 | 21.4 | 18.8 | 19.4 |
| websocket | messages_per_second | 592 | 572 | 1220 | 1254 | 1043 | 722 | 1081 |
| websocket | p50_us | 557 | 807 | 263 | 362 | 331 | 486 | 343 |
| websocket | p99_us | 13929 | 16853 | 6395 | 8182 | 9278 | 11148 | 8028 |
| websocket | peak_rss_mib | 11.8 | 13.0 | 14.9 | 17.9 | 24.6 | 21.7 | 22.0 |
| websocket_pipelined | messages_per_second | 26103 | 28411 | 141992 | 176815 | 48469 | 64520 | 52895 |
| websocket_pipelined | peak_rss_mib | 85.3 | 78.9 | 15.6 | 19.0 | 24.8 | 27.8 | 23.6 |
| upload | mib_per_second | 133 | 146 | 133 | 146 | 155 | 161 | 135 |
| upload | peak_rss_mib | 45.2 | 50.4 | 15.5 | 24.6 | 48.9 | 47.1 | 49.0 |
| download | mib_per_second | 153 | 95.9 | 77.5 | 104 | 46.5 | 59.7 | 104 |
| download | peak_rss_mib | 12.0 | 12.4 | 13.4 | 16.6 | 24.1 | 21.7 | 22.5 |

load1 during rows: median 18.12, min 9.06, max 68.64; rows 210

### What the numbers say

- **Against `origin/main`** dartvel_shelf on one isolate uses a fifth to a
  quarter of the CPU per request (plaintext 423 to 82 us, JSON 468 to 82, browser
  headers 505 to 105, 1,024 connections 478 to 113) and half the memory (61
  to 31 MiB), and answers 2.8x to 5.4x as many requests per second (JSON
  2,625 to 14,112; 1,024 connections 4,060 to 11,179; browser headers 2,564
  to 8,036). Plaintext shows 7.9x, inflated by a load spike during
  `dartvel_before`'s rows; the earlier run measured 2.7x. Four isolates reach
  17,487 (plaintext), 17,838 (JSON) and 21,572 req/s (1,024 connections).
- **Against Relic 2, Relic still wins most rows.** `relic_native` on one
  isolate answered 1.7x as many plaintext requests as `dartvel` (20,394 vs
  11,796) for about half the CPU per request (43 vs 82 us); 1.9x as many with
  browser headers and 1.5x as many at 1,024 connections. JSON was even in
  this run (14,449 vs 14,112) and 1.1x for Relic in the earlier one.
  `relic_native4` answered 1.7x to 2.3x as many as `dartvel4`. Relic also
  wins pipelined WebSocket (141,992 vs 64,520 msgs/s), WebSocket ping-pong
  latency, start-up memory and resident memory (17 vs 31 MiB).
- **Where dartvel_shelf is ahead of `relic_native` in both runs:** a static
  file costs less CPU (539 vs 621 us per request; 642 vs 786 before) with a
  lower p99 (101 vs 249 ms; 103 vs 115) and less memory (23 vs 32 MiB).
  Requests per second for the static file were ahead in this run (1,550 vs
  1,071) and behind in the earlier one (1,475 vs 1,904), so that is not a
  win. dartvel_shelf is ahead of shelf and Relic on dart:io in plaintext,
  JSON, browser headers, 1,024 connections and pipelined WebSocket in both
  runs, and uses more memory than both except for static files and
  pipelined WebSocket.

### With Relic's own load method

Relic's `packages/benchmark/bin/http_load.dart` (cloned at its 2.0.0 docs
commit 49921d7, published `relic_native` 2.0.0 binaries), 64 connections,
5 s runs: a closed-loop run finds the saturation rate, then open-loop runs at
50% and 100% of it. Relic's targets are served from inside the
`http_load.dart` process under `dart run`, as that tool does; dartvel_shelf's
were this branch's compiled server given as URL targets, so the two sides
are not compiled the same way and this table cannot settle anything Relic's
own published one does not. Same machine, 05:16-05:28 CEST.
Rows at 100% of saturation:

| target | workload | load | offered rps | rps | p50 | p99 | p99.9 | errors |
|---|---|---|---|---|---|---|---|---|
| native | plaintext | 100% | 19277 | 14110 | 3.06 | 35.61 | 66.69 | - |
| native | json | 100% | 16656 | 5563 | 4.32 | 140.15 | 264.55 | - |
| native | headers | 100% | 10797 | 9198 | 3.97 | 37.95 | 94.79 | - |
| native | browser | 100% | 4155 | 4147 | 5.43 | 117.45 | 232.88 | - |
| native4 | plaintext | 100% | 12187 | 12115 | 2.57 | 39.35 | 91.91 | - |
| native4 | json | 100% | 23531 | 13512 | 2.82 | 39.13 | 188.55 | - |
| native4 | headers | 100% | 19459 | 17022 | 2.77 | 18.95 | 75.20 | - |
| native4 | browser | 100% | 17114 | 11084 | 3.79 | 33.55 | 223.87 | - |
| dartvel_before | plaintext | 100% | 4542 | 2249 | 23.58 | 107.44 | 134.63 | - |
| dartvel_before | json | 100% | 1582 | 1366 | 28.87 | 191.97 | 213.13 | - |
| dartvel_before | headers | 100% | 1559 | 1531 | 23.12 | 218.24 | 253.71 | - |
| dartvel_before | browser | 100% | 1951 | 1949 | 9.07 | 77.02 | 120.39 | - |
| dartvel | plaintext | 100% | 11290 | 7095 | 6.74 | 56.43 | 123.82 | - |
| dartvel | json | 100% | 9650 | 7217 | 6.28 | 59.13 | 101.60 | - |
| dartvel | headers | 100% | 9185 | 7651 | 5.99 | 51.11 | 103.89 | - |
| dartvel | browser | 100% | 7048 | 7002 | 7.08 | 32.14 | 190.16 | - |
| dartvel4 | plaintext | 100% | 21989 | 11777 | 2.78 | 51.55 | 167.61 | - |
| dartvel4 | json | 100% | 17535 | 6254 | 4.70 | 88.40 | 282.91 | - |
| dartvel4 | headers | 100% | 7726 | 5560 | 7.60 | 69.28 | 143.78 | - |
| dartvel4 | browser | 100% | 4522 | 4427 | 6.19 | 83.35 | 242.25 | - |

`relic_native` was ahead on plaintext and headers; `dartvel` answered more
JSON and browser-workload requests; `relic_native4` answered more than
`dartvel4` on every workload. With Relic compiled differently from
dartvel_shelf here, read it as consistent with the table above rather than
as a result of its own.

### Where the remaining time goes

Measured with `perf` on this branch's server under plaintext load (one
isolate, driven mode; the server ran under the Dart JIT so that perf could
name the library's symbols, Relic's AOT): about 37% of the process's CPU is the kernel's TCP
path, 29% the native library (hyper's HTTP/1 parse and encode, axum and tower
plumbing, Tokio's scheduler), 15% Dart, 10% libc (malloc, memcpy). Relic's
process spends about 65% in the kernel, 21% in Dart and 12% in its Zig
library. The Dart side of a request now costs less than the native side;
closing the gap to Relic means a leaner HTTP/1 path in Rust than
hyper + axum (a parser and writer of our own for plain HTTP/1, as Relic has
in Zig), which this change does not attempt.

### What changed to get here

- The isolate drives its server's connections itself (`AW_FLAG_DRIVEN`,
  `aw_drive`, `aw_linger`, `aw_park`): a current-thread Tokio runtime per
  server, turned by the isolate between its own work while it has requests,
  and by a helper thread of the server's while it is idle. A request is read,
  handled and answered on one thread with no hand-off; before, every request
  woke the isolate from a Tokio worker and every answer woke a worker back.
  An isolate with nothing to take comes back for eight more turns (each a
  message to itself, so its timers and other I/O run between them) before
  it parks. `aw_linger`, which waits in the kernel instead, is in the C ABI
  and not used: it held the event loop, so a client in the same isolate
  could not send the request being waited for.
  Answers given between turns are handed over at the next turn, inside the
  runtime, so waking their task costs no system call.
- Requests are taken in batches from a native queue (one wakeup for many).
- One server-context extension per request instead of six boxed ones; a
  request with no body skips the body reader and the route body-limit match;
  the request target is not formatted again; request and server ids hash
  with a multiply instead of SipHash.
- `securityHeaders` are added natively; responses go through one reusable
  buffer; headers are decoded only when a handler reads one;
  `Headers.forEachValue` instead of a copied map; literal route patterns are
  compared rather than run as regular expressions; the router's metric
  series and measuring zone are kept between requests; access lines are
  sampled (100 a second by default).
- Every isolate of a process opens one in-memory copy of an embedded library
  (a sealed, named memfd) instead of one each.
- `serve(shared: true)` lets several isolates listen on one port.

## Benchmarks (September 2026, in-process Dart client; superseded by the section above)

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
