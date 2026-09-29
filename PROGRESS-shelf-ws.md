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
