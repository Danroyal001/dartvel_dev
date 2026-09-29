# Shelf phase 2 progress

Branch: `feat/shelf-websocket`. Worktree: `/home/sigmadev/dv-shelf-ws`.
User restrictions: local commits only; no pushes, merges, publishing, deployment or messages.

## Step 1 — context and baseline inspection
- Done: read server handbook, repository AGENTS.md/CLAUDE.md, server STATUS.md, task brief, phase-1 notes and latest owner/lead conversation.
- Baseline: clean branch, phase-1 code present. Shelf sources available in pub cache. Existing core WebSocket types are abstractions without a network implementation.
- Next: inspect upstream shelf implementations and write evidence-based parity matrix before implementation.
- Tests: none run yet.
- Blockers: none identified yet. Generic socket hijacking may require a separate raw-connection ABI; assess before claiming compatibility.

## Step 2 — Shelf compatibility adapter
- Done: baseline parity matrix committed (`2fbf1484`). Added `fromShelf` adapter preserving stream bodies and repeated headers; existing upstream Pipeline/Cascade, context, charset decoding and shelf_static range/conditional handling run unchanged.
- Tests: both integration tests observed failing with 500 from the adapter stub, then both pass. Initial static fixture exposed shelf_static's subsecond mtime comparison bug; a whole-second mtime isolates adapter behavior.
- Next: native WebSocket bridge; real-client text/binary/protocol and origin/size tests already observed failing with 501 against its stub.
- Blockers: upstream shelf_web_socket specifically requires a dart:io Socket for hijacking, so it cannot run unchanged on an Axum frame transport. Provide the same callback shape over one native path, document the distinction.

## Step 3 — native WebSocket transport
- Done: Axum WebSocket upgrades, bounded (8-message) queues both ways, text/binary/control frames, close handling, subprotocols, origin filtering, configurable message maximum. Shelf-style WebSocketChannel callback plus wsHandler connects core WsConnection/WsManager/WsHandlers to the same transport. Rebuilt linux-x64 library and regenerated bindings with `dart run ffigen --config ffigen.yaml`.
- Tests: initial two real-client tests failed with 501; now pass. Tightened oversized-message assertion failed with close 1002, then passed with correct 1009 after native error handling fix. Additional core-handler and slow-peer/shutdown integration checks running.
- Next: commit verified transport, fix native static ranges/cache validators/symlink escape, benchmark and run full suites.
- Findings: the inherited generic HTTP response bridge still uses an unbounded native queue. Phase-1 backpressure claims apply to request bodies, not all response bodies; parity documentation must state this accurately.
- Static tests already observed failing: ranges return 200, ETag absent, external symlink serves 200. Native static implementation follows after the transport commit.

## Step 4 — native static files
- Done: transport committed as `4fa1c2ad`; nine focused transport/adapter/native-symbol/render-parity tests passed. Native static serving now uses streaming ServeFile with ranges/416/HEAD/MIME/date validators, adds weak metadata ETags with If-None-Match precedence, and canonicalizes paths to refuse external symlinks.
- Tests: all three static integration tests failed against the previous library and pass after rebuilding.
- Next: commit static changes, run all Dart/Rust tests and the three-trial benchmark in fresh worker processes.
- Blockers/remaining scope: raw hijack, actual HTTP version metadata, configurable graceful shutdown and inherited generic HTTP response backpressure require further ABI work. These are not claimed complete.

## Step 5 — full-suite isolation regression
- Done: full Dart suite found native static configuration shared across servers. Added deterministic two-server regression; observed 404 instead of 200. Moved static/SPA roots into per-thread pending configuration captured as per-server request extensions; all four static tests now pass.
- Rust tests: 32 passed before this follow-up; rerun planned after final changes.
- Benchmark: first exploratory JIT run overlapped tests, so its numbers are discarded. Preparing a compiled benchmark and will measure only after validation jobs finish.
- Next: commit isolation fix, final full suites, isolated benchmark, documentation/changelog/final report.

## Step 6 — validation and WebSocket lifecycle review
- Full validation after static isolation: 185 Dart tests passed / 3 skipped; 32 Rust tests passed. Targeted analyzer only found two style notices in the draft benchmark.
- Review regressions: a one-byte data-message limit wrongly rejected close frames (observed ArgumentError, fixed); server pingInterval disconnected healthy peers when the application had no data listener (observed closed vs open, fixed by tracking native pong acknowledgements); an unlistened channel never completed sink.done after peer closure (observed timeout, cleanup fix currently rebuilding/testing).
- Benchmark implementation: identical AOT HTTP and echo workloads in fresh processes, three trials, 50 MiB streamed transfers, 16 concurrent hello clients. Early results show native WebSocket polling loses echo throughput and native ordinary downloads use more RSS. Final measurement follows final validation, without overlapping builds/tests.
- Next: commit lifecycle fixes, format/analyze, final full validation, final isolated benchmark, changelog and handoff report.
- Lifecycle follow-up result: all seven WebSocket integration tests pass, including all three newly reproduced regressions. Rebuilt linux-x64 and regenerated bindings for the native heartbeat/closure queries.
