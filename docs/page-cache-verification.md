# Public page cache verification — 2026-10-08

The cache wraps the existing core renderer in both the deployed native server
and `dartvel dev --release`. No page document, route URL or Flutter bootstrap
changes. Its scope and invalidation limits are in
[the binary policy](web-server-binary.md#rendered-public-page-cache).

## Built application

NaijaLife was copied read-only from the owner's checkout into the worktree's
ignored `.private/page-cache/naijalife`, excluding secrets and runtime data.
The copy's package paths pointed at this framework branch. The existing
NaijaLife server executable supplied the baseline.

`dartvel build web-server` completed on Linux x64 with Flutter 3.47.5 / Dart
3.13.4, all four public route semantics captured, and a clean accessibility
audit. The inspected ELF executable is 30 MB with two loading units and
89 packed web files. Both comparison servers used separate data directories
and loopback ports; nothing was deployed.

## HTML and browser proof

Baseline, cached and cookie-bypassed `/login` responses are byte-identical:
8,393 UTF-8 bytes, SHA-256
`c1bb5f6bb9145d22f2c395186d22bcc7923dbf93470733e4c94678b49964323d`.
The live https://naijalife.sigmadev.digital/login response also matched that
hash and those bytes in a read-only comparison. The cache adds revalidation
headers without changing the body. An actual
conditional GET returned 304; guarded `/` and `/__studio` returned 302 with
`no-store` and no ETag.

A real Chrome tab checked each binary at 1280×900, first with scripts disabled
(the server document), then with Flutter running. Browser find returned true,
first-frame selection returned “Sign in”, and Tab focused the Email input.
Headings, links, document text and Chrome's accessibility tree matched exactly
apart from the comparison ports. The tree contains the heading, Email and
Password textboxes, and Show password and Sign in buttons.

The screenshots are byte-identical before/after too:

| Capture | SHA-256 |
|---|---|
| Server first frame | `0f485c840e1ececf202de5ad8b0e54798452fca7759ac80a3e552741d61b6334` |
| Flutter running | `67fca8ea3b1879bc92ac63a49283f8f96087bf7c7390eea6593b5dca41d3222c` |

## Tests

Behavioral coverage includes immutable bytes/headers, Set-Cookie/non-200
refusal, bounded eviction, query/host/theme/locale partitioning, weak validator
comparison, purging every cache and preventing an older in-flight fill.
Studio API saves/deletes and successful OTA installation were first observed
failing to purge, then passed after the shared hook was connected.

Further tests exercise the actual preview and deployed handlers, route config
through generation and the manifest, runtime resolver bypass, content publish
and transaction rollback, native OTA apply/rollback, and HTTP page OTA.
The existing visibility, tenant and streaming behavior remains covered.

The spec evidence validator and repository language check pass.

## Throughput

Paired `npx autocannon -c 50 -d 10` against the actual binaries:

| Server | Requests/s | p50 | p99 | Errors / non-2xx |
|---|---:|---:|---:|---:|
| Baseline | 72.3 | 632 ms | 956 ms | 0 / 0 |
| Cached | 1,789.1 | 18 ms | 207 ms | 0 / 0 |

This exceeds the 1,000 requests/s target. A preceding valid paired run under
shared-server load measured 56.4 versus 980.1 requests/s, also with zero errors.
These are local ten-second measurements, not a production capacity guarantee.
Both runs used 50 connections, sequential measurements and fresh processes.
The final source adds an HTML-content-type safety guard after this binary build;
it leaves the measured HTML path unchanged and is covered by the endpoint
regression test.
Raw responses, browser JSON/screenshots and benchmark JSON are retained under
`.private/page-cache` for local review; they are not application artifacts.
