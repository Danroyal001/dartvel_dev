# Dartvel Platform Additions — Proposal

**Status: Proposal for review. Nothing in this document is part of NEW_SPEC.md.**
Each item below is a candidate section; on approval, it gets written into the
spec in house style at the placement noted. Rejected items stay here with a
note, so the reasoning isn't lost.

The ten additions cluster around two themes the current spec underweights:

1. **The passage of time** — what happens to a Dartvel app in month six:
   deployed old clients, offline devices, data retention, backups, stale flags.
2. **Trust boundaries** — secrets, PII, and third-party modules: what code and
   people are allowed to touch, enforced by the framework rather than by
   review discipline.

Everything proposed reuses existing Dartvel primitives (models, signals,
queues, source mappings, capability manifests, typed diagnostics) rather than
introducing parallel machinery.

---

## 1. Protocol Versioning and Client Compatibility

**Problem.** The backend deploys daily; installed app binaries live for weeks.
The spec handles schema change server-side (migrations) and code change
client-side (OTA), but nothing defines what happens when a three-week-old
binary calls today's backend. On mobile this is the permanent condition — the
framework doesn't control when users update. Right now this failure lands on
every application team individually, which is exactly what Dartvel exists to
prevent.

**Proposal.** Every build embeds a generated protocol version derived from
models, backend function signatures, and the sync schema. The backend declares
a compatibility window (`window: 3` — serve current plus three previous), with
serialization adapters for windowed versions generated from the same schema
diffs that already produce migrations. A generated handshake yields typed
outcomes (`compatible` / `degraded` / `upgradeRequired`); falling outside the
window fires `DV.Upgrade.required`, attempting OTA before routing to a
generated upgrade page. Deploys are gated: `dartvel compatibility-check
--against production` compares the candidate protocol against the live
client-version histogram from monitoring and refuses to strand active clients.

```dart
// sketch
switch (await DV.Protocol.handshake()) {
  case DVProtocolResult.upgradeRequired: // generated upgrade flow
}
```

**Placement.** New top-level section after OTA Updates.

**Open questions.** Default window size; precise semantics of `degraded`
(which adaptations are legal without opt-in); whether adapters are generated
eagerly per release or lazily per observed client version.

---

## 2. Offline-First Models

**Problem.** Model Sync and Presence specs the connected case; "offline"
appears only in OTA and embedded bullets, and conflict resolution appears
nowhere. For the mobile and kiosk identity, disconnected operation is core:
devices lose connectivity constantly, kiosks may run isolated for days.
Without a framework answer, every app hand-rolls caching and replay — the
highest-defect category in mobile development.

**Proposal.** Offline behavior declared on the model and generated:

```dart
@DVModel(offline: DVOffline(strategy: DVConflict.lastWriteWins, encrypt: true))
class _Order { ... }
```

Generated local store per target (SQLite native, IndexedDB web,
filesystem-backed embedded), a queued mutation log replayed in order through
the existing sync transport, conflict strategies per model (`lastWriteWins`,
`serverWins`, `fieldMerge`, typed custom resolver), and generated sync-state
signals (`order.syncState`, `Order.pendingMutations`). Application code uses
the same model API online and offline — no connectivity branching.

**Placement.** New top-level section directly after Model Sync and Presence.

**Open questions.** Local-store implementation on native (drift vs. raw
sqlite3 bindings); mutation-queue bounds and overflow policy; whether CRDT
merge for collaborative fields is v1 or a later extension of `fieldMerge`.

---

## 3. Secrets and Environments

**Problem.** `DV.Secrets.get('PAYSTACK_SECRET')` already appears in the
billing section, but the subsystem behind it is unspecified — sourcing,
scoping, rotation, and above all: what stops a server secret from being
compiled into a client bundle. Because Dartvel uniquely compiles both ends, it
can give a guarantee no glued-together stack can.

**Proposal.** Secrets are backend-scoped by default; a backend-scoped secret
reachable from client code is a **typed build error** (`DV-SECRETS-001`), with
`scope: client` as an explicit, auditable opt-in for genuinely public keys.
Per-environment resolution (env, dotenv, CI, vault/KMS adapters) behind one
API; deploy validates all required secrets resolve before shipping; rotation
hooks; values redacted from logs, traces, and diagnostics by construction.

**Placement.** New top-level section before Deployment.

**Open questions.** The reachability analysis mechanics (tree-shaking-based vs
import-graph-based, and its false-positive story); whether `scope: client`
should be named something scarier; secret access in tests.

---

## 4. Data Compliance and Lifecycle

**Problem.** GDPR, PII, and privacy have zero mentions. The day an EU user
files an erasure request, an unprepared app owner is doing archaeology across
database, storage, caches, search indexes, and backups under a legal clock.
Dartvel's model-centric design makes the right behavior nearly free to
generate — and very expensive to retrofit.

**Proposal.** `@DVField(pii: true, retention: Duration(days: 365))` drives:
generated subject-access export across models, relations, storage, and search;
generated erasure that cascades the same graph and emits a signed receipt;
retention enforced by generated scheduled jobs; an audit log (generated
capability) recording reads/writes of PII fields with actor, tenant, and
purpose — itself audited. Alongside: `dartvel db backup` / `restore` and
point-in-time-recovery adapters, since today the only "backup" in the spec is
an OTA release branch.

**Placement.** New top-level section after Multi-tenancy; backup CLI joins the
database/migration story.

**Open questions.** Erasure vs. backups tension (redaction-on-restore vs.
crypto-shredding per-user keys); legal-hold modeling; whether audit storage is
a model like any other or a sealed append-only store.

---

## 5. Feature Flags and Staged Rollout

**Problem.** Flags exist as one bullet under middleware. A platform with OTA,
Studio, and multi-tenancy needs flags as a small first-class subsystem — and
stringly-typed flags ("checkout_v2" the string) are a classic silent-failure
source.

**Proposal.** Flags generated from configuration so a typo is a compile error:
`DV.Flags.checkoutV2.enabled`, with a signal per flag. Targeting by tenant,
user, session, platform, device profile, and percentage; identical evaluation
in client, backend functions, and server rendering. Flags may gate OTA
channels — one flag controls a code path *and* which bundle ships. Studio kill
switches without deploys; `dartvel analyze` flags stale flags (100% for 90
days → remove or mark permanent).

**Placement.** New top-level section before OTA Updates.

**Open questions.** Evaluation authority (server-evaluated with client cache
vs. client-evaluated from synced rules — matters offline); whether experiments
/ A-B ships in v1 or layers on later.

---

## 6. Media Pipeline

**Problem.** File storage stores bytes; apps need images and video handled.
Image optimization and video have zero mentions, yet the spec includes SEO,
PWA, and even a performance diagnostic for "uncompressed large model images" —
a diagnostic that currently detects a problem the platform gives you no tool
to fix.

**Proposal.** Declared on model fields, generated as storage behavior plus
background jobs: `@DVField(image: DVImage(variants: [...], formats: [webp,
avif]))` → on-upload variant generation, format negotiation wired into
generated widgets and server rendering, signed transformation URLs, upload
validation with a malware-scan hook. Video as thumbnail extraction plus
transcode profiles through pluggable encoder adapters.

**Placement.** New top-level section after File Storage.

**Open questions.** v1 scope — images only, video deferred?; local processing
vs. provider offload (Cloudinary-style adapters) as default; embedded-target
constraints (no ffmpeg on a webOS TV).

---

## 7. Distributed Tracing

**Problem.** One mention of tracing in the spec. Monitoring names diagnostics
(N+1s, blocking work) but has no spine connecting a slow user action to the
queue job three hops away that caused it. Dartvel owns the entire call path —
which is precisely the position that makes tracing generatable rather than
bolted on per service.

**Proposal.** OpenTelemetry-compatible spans generated end to end — client
call → sync transport → backend function → queue → job → database — with
*model-aware* names (`User.sync`, `createOrder`, `db:User.find`), automatic
context propagation, configurable sampling with tail-based hooks for errors
and slow requests. Monitoring diagnostics link to exhibiting traces; Studio
renders traces against the same source mappings as `dartvel inspect`.

**Placement.** New top-level section after Monitoring and Observability.

**Open questions.** Sampling defaults per target (tracing overhead on a 1 GB
TV is not free); trace storage in self-hosted deployments; span cardinality
rules for generated names.

---

## 8. AI-Native Tooling Contracts

**Problem.** "AI-first" is second in the design goals but currently thinner
than the build story. If it means an AI config key, it's decoration. The
transparency machinery already in the spec (source mappings, inspectors, typed
errors) is one step from something genuinely differentiated: agents as a
supported client of the framework.

**Proposal.** Three contracts: (1) every `dartvel inspect` command supports
`--json` with a stable versioned schema — the project graph is
machine-readable by contract; (2) `dartvel mcp` exposes inspectors,
generators, migration planning, doctor, and build validation as MCP tools so
coding agents drive Dartvel natively; (3) no privileged generation path —
agent-produced code passes the same typed validation and carries provenance in
source mappings (`dartvel inspect generated --provenance`). Plus `dartvel ai
eval`: golden-path scenarios scored against an agent, so the framework
continuously measures how well AI can build with it.

**Placement.** Extends the existing AI section.

**Open questions.** Who maintains eval scenarios as the spec evolves; MCP tool
surface freeze policy (tools are an API too); whether provenance is mandatory
or advisory metadata.

---

## 9. Module Distribution and Trust

**Problem.** Modules are richly specced as units of composition, but the
ecosystem side — publish, discover, and above all *trust* — is absent. A
module can contribute backend functions, native bindings, and raw SQL. The
trust model has to exist before the marketplace does, not after the first
supply-chain incident.

**Proposal.** Publishing via pub.dev plus `dartvel module publish` attaching a
signed manifest (version, compatible Dartvel range, complete capability list).
Capability permissions extend the existing platform-capability manifest to
sensitive framework surfaces — `DV.Secrets`, raw SQL, native bindings, network
egress, filesystem, cron. The parent grants capabilities explicitly at mount;
ungranted access is a compile-time error where resolvable, a typed runtime
failure otherwise. Least privilege by default. Supply chain: module lockfile
with integrity hashes; `dartvel doctor --modules` verifies signatures and
flags capability drift between versions (a module that suddenly wants
`rawSql` in 2.2.0 requires re-grant).

**Placement.** New top-level section after Modules.

**Open questions.** Signing authority and key custody; what pub.dev can and
can't enforce vs. what Dartvel tooling must; whether network egress can be
allowlisted per-domain rather than granted wholesale.

---

## 10. Specification Status and Conformance

**Problem.** The spec's closing rule — design full contracts, implement
progressively — has no operational mechanism. Contributors (and agents)
can't tell which sections are load-bearing. The DVPlatformMemory section
already improvised a "(Proposal)" label; this formalizes it.

**Proposal.** Every section carries a status: `Vision` (direction, APIs
illustrative) → `Proposal` (concrete shape under review) → `Contract` (frozen
surface; changes require migration tooling) → `Implemented` (shipped, covered
by conformance tests). Contract sections gain versioned conformance suites run
by `dartvel conformance run`; status changes are recorded with reasoning in
the spec changelog; `dartvel inspect spec --json` exposes the section/status
index as part of the machine-readable contracts (ties into #8).

**Placement.** Short top-level section near the end of the spec, plus a
retroactive labeling pass over all existing sections.

**Open questions.** None structural — the real work is the retro-labeling
pass, which forces the useful arguments about what is actually frozen today.

---

## Recommended sequencing

- **Immediately (costless, clarifying):** #10 Status ladder, including the
  retro-labeling pass — it sharpens every other decision in this document.
- **First wave (contracts that are expensive to retrofit):** #1 Protocol
  versioning, #3 Secrets, #2 Offline-first. All three change generated wire
  and storage formats; every month of delay adds migration burden.
- **Second wave (leans on the first):** #5 Flags (gates OTA), #4 Compliance
  (needs audit + storage hooks), #7 Tracing (needs the transport hooks
  protocol work touches anyway).
- **Third wave (valuable, independent):** #6 Media, #9 Module trust, #8 AI
  tooling — #8's `--json` contract can land earlier opportunistically since
  inspectors already exist.

Approve, reject, or amend per item; approved items get drafted into
NEW_SPEC.md individually in house style.
