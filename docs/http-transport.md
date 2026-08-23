# Outbound HTTP: HTTP/2, HTTP/3, and Early Hints

What Dartvel's outbound HTTP can do, what it cannot, and — where it cannot —
whether that is our gap or an upstream one. Capability claims here name the
source that was checked, in the same spirit as `docs/build-targets.md`:
verified means looked at, not assumed.

## Why this exists

Dartvel's outbound HTTP was `package:http` and nothing else. On native that is
`dart:io`'s `HttpClient`, which speaks **HTTP/1.1 only**. That is not a
performance footnote — it is why APNS was unimplemented, because Apple's
provider API is HTTP/2-only and there was no way to reach it at all.

## The Dart contract

`packages/dartvel_core/lib/src/http/protocol.dart` and `transport.dart`.

- `DVHttpProtocol` identifies a protocol by its **ALPN token**, because
  selection happens during the TLS handshake and that is what is actually
  negotiated.
- `DVHttpProtocolChain` is an ordered preference. `standard` is
  h3 → h2 → http/1.1. `http2Only` exists for peers that require a protocol,
  where a silent downgrade would turn a configuration problem into a
  connection error that cannot explain itself.
- `DVHttpTransport` declares what it can speak **here**, which depends on the
  platform and not only on the implementation.
- `DVHttpFallbackClient` walks the chain. Keeping the walk out of the
  transports means the fallback rules live in one place instead of once per
  backend, and a transport only has to answer "can you speak this, and what
  happened".
- A failure can be marked non-retryable. A refused QUIC handshake is worth
  trying another protocol; a 404 is not, since the request reached the origin
  and was answered.
- `dvUseHttpTransport` is the seam a faster client attaches through.

## Verified capability of the Rust ecosystem

The interesting constraint is **not** HTTP/2 or HTTP/3, both of which are
well served. It is Early Hints, which almost nothing surfaces.

| Layer | Crate | HTTP/2 | HTTP/3 | 103 Early Hints |
|---|---|---|---|---|
| Client, high level | `reqwest` | ✅ | ✅ (unstable cfg) | ❌ — built on hyper |
| Client, mid level | `hyper` | ✅ | — | ❌ — see below |
| Client, HTTP/2 frames | `h2` | ✅ | — | ✅ `poll_informational()` |
| Client, HTTP/3 frames | `h3` + `h3-quinn` | — | ✅ | ❌ `recv_response()` only |
| Server | `axum` / `hyper` | ✅ | — | ❌ sending unsupported |

**hyper does not support 103 Early Hints in either direction.** HTTP/2 support
is an open pull request ([hyperium/hyper#4114], opened June 2026) against an
open issue ([#3980], November 2025), and server-side sending has been open and
blocked awaiting design input since 2021 ([#2426]). Everything built on hyper
inherits this — which means `reqwest` cannot receive early hints and Dartvel's
own Axum server cannot send them.

**The `h2` crate can.** `h2::client::ResponseFuture` exposes
`poll_informational()`, documented as polling for 1xx responses and intended to
be called before polling the main response future. This is the only place in
the Rust ecosystem where informational responses surface, and it is the reason
the HTTP/2 client below is built on `h2` directly rather than on `reqwest`.

**The `h3` crate cannot.** `h3::client::RequestStream` offers `recv_response()`
and no informational path. HTTP/3 permits 1xx responses at the protocol level,
so this is a crate gap rather than a protocol limit.

[hyperium/hyper#4114]: https://github.com/hyperium/hyper/pull/4114
[#3980]: https://github.com/hyperium/hyper/issues/3980
[#2426]: https://github.com/hyperium/hyper/issues/2426

## What this means for "early hints support"

Stated plainly, because the honest answer is narrower than the request:

- **Receiving early hints over HTTP/2: available**, via `h2` directly.
- **Receiving early hints over HTTP/3: not currently possible** with any Rust
  crate. Fallback to HTTP/2 gets them; HTTP/3 does not.
- **Sending early hints from Dartvel's server: not currently possible.**
  Blocked on hyper, and Axum sits on top of it.

The third is the one worth caring about most. Early Hints are principally a
*browser* optimisation: a 103 tells a browser to start fetching stylesheets
and scripts while the origin is still deciding what the page is. A Flutter app
calling a JSON API has no subresources to preload, so *receiving* 103 buys it
very little. Dartvel serving SSR pages that *emit* 103 is where real page loads
get faster — and that is the half currently blocked upstream.

This is a fork-shaped problem, which is the pattern this project already uses
for embedders: the capability exists in the protocol and is missing from the
library.

## Only Linux gets the fast transport for free

`packages/dartvel_shelf/lib/native/` contains a prebuilt `linux-x64` library
and nothing else. The build hook compiles the crate wherever cargo and cbindgen
are present, so a developer with a Rust toolchain gets HTTP/2 and HTTP/3 on any
platform — but without one, only Linux does. On macOS and Windows
`DVRustHttpTransport.tryLoad()` finds no library, returns null, and
`package:http` is what remains: HTTP/1.1 only.

That is a real limit rather than a theoretical one, because **APNS is
HTTP/2-only**. It fails loudly rather than downgrading, since it asks for
`DVHttpProtocolChain.http2Only` — but until recently the message was
`http cannot speak h2`, which is accurate and unactionable. `dvHttpTransportHint`
now carries the reason into `DVHttpProtocolExhausted`: where the library was
looked for, whether it was missing or unloadable, and what produces one.

Committing binaries for all three hosts, or for none, are both defensible. The
current arrangement is the one that quietly makes Linux special.

## Platform split

**Web needs nothing.** The browser negotiates HTTP/2 and HTTP/3 by itself and
acts on early hints before script is told anything — it starts the preloads.
Neither the negotiated protocol nor the hints are visible to JavaScript, so
`DVBrowserHttpTransport` declares the capability and reports a null protocol
rather than guessing. Compiling a Rust client to wasm would be strictly worse
here: it would add a download to reimplement what the host already does better.

**Native uses Rust over FFI.** `dartvel_shelf` already carries a Rust crate, an
FFI convention and a native-asset build hook, so the client belongs there
rather than in a new mechanism. This also satisfies the native-integration
rule: FFI, never platform channels.

## Status

| Piece | State |
|---|---|
| Dart protocol/transport contract | ✅ Implemented, 17 tests |
| `package:http` transport declaring HTTP/1.1 only | ✅ Implemented |
| Browser transport declaring all three | ✅ Implemented |
| Rust HTTP/2 client with early hints | ✅ Implemented, 8 unit tests + a live check |
| `DVRustHttpTransport` Dart binding | ✅ Implemented, declares h3 and h2 |
| Rust HTTP/3 client | ✅ Implemented, verified against a live server |
| APNS provider | ✅ Implemented, 17 tests |
| Web Push provider (RFC 8291 + 8292) | ✅ Implemented, 15 tests |

Nothing above is marked done on the strength of a plan.

**Both clients are verified against a real server**, not only compiled.
`cargo test -- --ignored` performs an actual request and asserts on what comes
back: TCP, TLS, ALPN negotiating `h2`, an HTTP/2 request, and a response whose
headers are unmistakably live (`cf-ray`, `server: cloudflare`, current date).
Those tests are `#[ignore]` by default so an offline or firewalled build is not
a failing one — a network test that fails without a network trains people to
ignore red.

## The HTTP/3 client

`quinn` carries QUIC, `h3` the HTTP semantics above it, `h3-quinn` the adapter.
It shares the Dart contract, the FFI event pump and the failure classification
with the HTTP/2 client, and shares none of the connection path: QUIC is UDP,
brings its own TLS 1.3 handshake, and opens no TCP socket at all. An h3 request
is therefore routed before the TCP connect rather than after it.

Three things were worth getting right and are easy to get wrong silently:

- **TLS 1.3 only.** QUIC forbids TLS 1.2, and `QuicClientConfig::try_from`
  rejects a config that permits it rather than negotiating down. The QUIC path
  builds its own rustls config with `builder_with_protocol_versions` instead of
  sharing the TCP path's.
- **The socket is bound in the peer's address family.** Resolution happens
  first, then the bind is `0.0.0.0` or `[::]` to match. Binding IPv4 and
  dialling an IPv6 peer fails with an error that reads like a network problem.
- **`recv_data` yields a `Buf`, not a contiguous slice.** Treating it as one
  truncates bodies that span more than one segment — the kind of wrong answer
  that still looks like a body.

**Version pinning is not free here.** `h3-quinn` 0.0.7 does not compile against
current `quinn`: it reads `StreamId`'s tuple field, which became private. The
working pairing is `h3` 0.0.8 with `h3-quinn` 0.0.10, and `quinn` is declared
with `default-features = false` so it cannot reintroduce `aws-lc-rs` as
rustls's provider through its own defaults — the same trap `axum-server`'s
`tls-rustls` feature set earlier in this file.

Early hints do not survive an HTTP/3 request, and a test asserts that rather
than leaving it as a comment: if `h3` ever grows an informational path, the
live check fails and sends someone back to this document.

## Two crypto-provider problems found on the way

`aws-lc-rs` arrived as rustls's default provider through `axum-server`'s
`tls-rustls` feature, while this crate uses `ring` everywhere. It caused two
distinct problems and is now gone, via `tls-rustls-no-provider`.

**A latent panic.** With two providers compiled in, rustls 0.23 will not guess:
`ClientConfig::builder()` and `ServerConfig::builder()` panic unless a
process-level provider has been installed. That applied to the **existing TLS
server path** as much as to the new client and had simply never been reached.
Both pin the ring provider before building a config, which stays as
belt-and-braces now that only one provider is compiled in.

**A broken macOS build, and a red herring.** `aws-lc-sys` failed to compile on
macOS, which looked like the cause of `dartvel build macos` failing. Removing
it proved otherwise: `ring` and `zstd-sys` then failed identically. The real
fault was `cc-rs` being invoked with no `-isysroot` because `SDKROOT` was
unset, so no C crate could find its headers. The build hook now supplies it
from `xcrun`, chosen from the target rather than the host.

Removing `aws-lc-rs` stays regardless — it was compiling a large C codebase for
nothing on every platform — and a CI check fails the build if it returns, since
it comes back silently through any dependency enabling a rustls default feature.
