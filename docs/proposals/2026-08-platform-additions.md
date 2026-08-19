# Dartvel Platform Additions — Proposal

**Status: Reviewed 2026-08-15 — all ten approved with amendments. Nothing in
this document is part of NEW_SPEC.md yet.** See [Review outcome](#review-outcome--2026-08-15)
for verdicts, the corrected drafting order, and the cross-item conflicts.
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

> **Drafted 2026-08-16 — this item is now in `NEW_SPEC.md`.** Written first per
> the review's ordering, because #2's local-store encryption, #4's erasure
> receipt signing and #9's grant list all name key material only this section
> defines. Amendments applied: a `dartvel: secrets:` declaration manifest
> carrying names and scopes but never values; `scope: client` unified with the
> shipped `PUBLIC_` prefix rather than added beside it; the guarantee split into
> three layers with their strengths stated separately, so the structural one
> (values cannot reach a bundle) is not confused with the advisory one
> (`DV-SECRETS-001` reachability analysis, which admits false negatives); and
> the shipped web backstop kept in the contract. The open questions above
> stand — the section states that layer 2 is a signal rather than a proof
> instead of resolving how its analysis is implemented.

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

> **Drafted 2026-08-19 — this item is now in `NEW_SPEC.md`.** Not as a new
> section: per the review's placement correction it edits the two places that
> already cover its ground. The project graph, `--json` and the diagnostic-code
> contract join *Generated-code transparency*, where the eight inspectors were
> already enumerated in prose; the framework-versus-application MCP registry
> separation joins the AI tools section, where `@DVAITool` opt-in and
> `@DVAIHidden()` are already defined.
>
> Reframed as the review required: the deliverable is a versioned
> `DartvelProjectGraph`, not a flag. The section says so explicitly, because
> the proposal's own sequencing had it backwards — `--json` reads like
> something to bolt onto commands that exist, and `dartvel inspect` is not a
> registered command at all. The generators share no model of the project, so
> eight inspectors would be eight partial answers that disagree at the edges.
>
> The redaction rule was added unprompted, as the review asked: `--json` output
> and MCP tool results are the same kind of surface the sensitive-field
> exclusion list already governs, so a sensitive field appears in the graph
> marked `"sensitive": true` with no value — the schema is what an agent needs,
> the data is what it must not be handed.
>
> Conformance suites and `dartvel ai eval` are not drafted; the graph is the
> prerequisite and the rest can be argued once it exists.

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

> **Drafted 2026-08-17 — this item is now in `NEW_SPEC.md`, with its checker.**
> Amendments applied. The single ladder is replaced by two orthogonal axes,
> `stability` (`Draft`/`Contract`) and `status` (`Designed`/`Partial`/`Shipped`),
> because a linear ladder ending in `Implemented` ranks a frozen, deliberately
> unbuilt contract below a shipped one and so contradicts the spec's own scope
> rule — which is why the section sits adjacent to that rule rather than
> trailing the document. `Partial` and `Shipped` must cite evidence that exists,
> borrowing `docs/build-targets.md`'s discipline, and `Partial` must additionally
> say what is absent, since otherwise it reads to a caller exactly like
> `Shipped`. The index is a checked-in `docs/spec-status.json` with no CLI
> dependency; `dart run tool/spec_status_check.dart` validates it and runs in CI
> on every push. Conformance suites are split out and not drafted.
>
> Two corrections the review forced. The item's stated premise was false —
> `NEW_SPEC.md` contains no "Proposal" label and no `DVPlatformMemory` section,
> so there was no improvised convention to formalise. And rather than adding an
> eighth copy of implementation status, the paragraph that listed it across the
> seven agent rule files is now a pointer to the index.
>
> First labelling pass: 73 sections — 22 `Shipped`, 26 `Partial`, 5 `Designed`,
> 20 narrative sections that describe no API and carry no labels.

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

---

## Review outcome — 2026-08-15

Every item was reviewed against `NEW_SPEC.md`, `CLAUDE.md`'s Public API Shape
Rules, and the code, then adversarially verified by a second pass that
re-checked each load-bearing claim with grep. **All ten verdicts survived
verification; none was overturned.** Every item is `approve-with-amendments` —
the ideas hold, the shapes need work.

| # | Item | Effort | What must change first |
|---|---|---|---|
| 1 | Protocol Versioning and Client Compatibility | large | Reconcile the `dartvel compatibility-check` name: either specify one command whose default mode is… |
| 2 | Offline-First Models | large | State explicitly that the mutation log compiles onto the DVQueues/DVDatabaseQueueAdapter layer (the existing… |
| 3 | Secrets and Environments | medium | Add a secrets declaration manifest to the spec section: secret names, scope, and per-environment requiredness… |
| 4 | Data Compliance and Lifecycle | large | Replace @DVField(pii:, retention:) with @DVModel.piiField(retention: ...) per the field-annotation shape rule |
| 5 | Feature Flags and Staged Rollout | large | Split declaration from state: the dartvel: pubspec config declares flag identity, type, and defaults (the… |
| 6 | Media Pipeline | large | Replace @DVField(image: DVImage(...)) with @DVModel.imageField(variants: [...], formats: [...]) per the… |
| 7 | Distributed Tracing | large | Change placement: make this a subsection of the existing "Monitoring and Observability" section (`##… |
| 8 | AI-Native Tooling Contracts | large | Lead with the project graph, not with `--json`. Spec a single versioned `DartvelProjectGraph` |
| 9 | Module Distribution and Trust | large | Rename the trust axis so it does not collide with the spec's existing "capability" term. Keep `capabilities:`… |
| 10 | Specification Status and Conformance | medium | Replace the single ladder with two orthogonal labels per section, so the spec's own scope rule survives:… |

### Draft in this order

Not the order this document recommends. The reasoning is dependency-driven:

- **#3 Secrets and Environments** — draft first. It is the only item whose core guarantee is already half-shipped (DVSecrets resolves from process env only, PUBLIC_-prefixed vars are the sole path into env.g.dart on both generation paths, web resolution structurally throws), so the section largely writes down and hardens an existing posture at medium effort. More importantly it is the unblocker three other items silently depend on: #2's local-store encryption, #4's erasure receipt signing, and #9's grant list all name key material or DV.Secrets surface that only #3 defines. Drafting #2/#4/#9 first bakes in names #3 would renumber. The one thing #3 must add rather than record is the pubspec secrets-declaration manifest — without an enumerable set of declared secrets there is nothing to scope, validate at deploy, or rotate.

- **#10 Specification Status and Conformance (labels + checker only, conformance suites split out)** — draft second and land it in the same commit as its checker. Every other item in this document argues from claims about what NEW_SPEC.md already promises, and the spec has no way to say which promises are built: NEW_SPEC.md:3406-3424 describes eight `dartvel inspect` commands in flat present tense that the CLI registers none of (verified — only `cache inspect` exists). That single unlabeled section is what makes items #7, #8 and #10 itself misjudge their own cost. Fix the ladder into orthogonal Stability/Status axes, bind Shipped to named evidence the way docs/build-targets.md already does, ship it as a checked-in docs/spec-status.json with no CLI dependency, and collapse the seven-file status paragraph into a pointer so this replaces drift rather than adding an eighth copy.

- **#8 AI-Native Tooling Contracts, reframed around the DartvelProjectGraph** — draft third, ahead of its third-wave slot. Its `--json` limb is not nearly free as the proposal claims, and that inversion is the reason to draft now: the real deliverable is one versioned project graph (routes, models and fields, backend functions, jobs, modules, static paths, schema, capability metadata) that generators consume instead of each re-parsing source with ~100 hand-rolled regexes across 8 files. Five other items consume that graph — #10's status index, #7's generated span names and cardinality cap, #5's stale-flag analyzer rule, #6's image-field discovery, #9's module grant introspection — so every month more generators ship private regex discovery, the retrofit gets more expensive. MCP itself is genuinely shipped (dartvel_core/lib/src/ai/mcp.dart, JSON-RPC + stdio, both directions), so `dartvel mcp` is thin once the graph exists, needing one constructor parameter to stop hardwiring the global application tool registry.

### Cross-item conflicts

Invisible from inside any single item — each is a duplicate mechanism or
vocabulary the spec would otherwise grow:

- Envelope-metadata land grab (#1, #2, #7): three items independently add fields to the same carriers. #1 stamps a protocol version into request headers and every sync/SSE/WebSocket connection; #2 requires the mutation-log entries to carry that version; #7 needs trace context on `DVJobEnvelope` (dartvel.dart:1098), `DVContext` (transaction.dart:87), and `DVModelSyncTransport` (model_sync.dart:33), none of which have any metadata slot today. Drafted separately, the spec grows three envelope extensions with three vocabularies. Fix: #1's section defines ONE envelope-metadata contract (protocol version + trace context + tenant + idempotency key) covering HTTP headers, the job envelope, and the sync transport; #2 and #7 reference it instead of defining their own.

- Item #7's stated dependency on #1 is wrong, and the proposal's sequencing repeats the error. The proposal justifies putting #7 in the second wave because it 'needs the transport hooks protocol work touches anyway' — but #1 as scoped touches only HTTP request headers (the generated client's `_dvPrepareHeaders` choke point, backend_generator.dart:591). The hops #7 actually cannot do today are queue, sync, and FFI, and #1 delivers no carrier for any of them. Either widen #1 to the full envelope contract above, or stop claiming #7 rides on it.

- `dartvel inspect` is a shared, wholly unbuilt dependency for #7, #8, and #10, and no per-item reviewer could see all three leaning on it. Verified: `dartvel inspect` is not registered anywhere in the CLI — the only `inspect` in packages/dartvel_cli is `cache inspect` (cache_command.dart:16). #10 wants `dartvel inspect spec --json`, #8 wants `dartvel inspect <thing> --json --provenance`, #7 wants traces to 'reuse the same source mappings as dartvel inspect'. This directly contradicts the proposal's sequencing, which puts #10 'immediately (costless)' and #8 in the third wave while asserting #8's `--json` can land early 'since inspectors already exist'. Fix: #8's project graph is the real prerequisite; #10 must ship as a checked-in `docs/spec-status.json` with no CLI dependency, and #7 must forward-reference rather than assume.

- Three items claim the same compatibility/drift-check surface: #1 wants `dartvel compatibility-check --against production` for client protocol gating, the spec already uses the identical command at NEW_SPEC.md:2523 and :3445 for framework-version compatibility, and #9 routes module grant drift through `dartvel doctor --modules` plus `dartvel upgrade --plan` (NEW_SPEC.md:3446-3451). Three different questions ('is my framework upgrade safe', 'is my deployed fleet inside the protocol window', 'did this module quietly ask for rawSql') with two command names between them. Fix: one `dartvel compatibility-check` with named modes, decided in #1's draft, and #9 written against whichever mode it needs rather than inventing a doctor flag.

- #3 (Secrets) is a hard prerequisite for #2, #4, and #9, but the proposal's waves put #3 alongside #2 in the first wave and #4/#9 later without stating the dependency. Concretely: #2's `DVOffline(encrypt:)` local-store encryption needs key material and custody that only #3 defines; #4's erasure receipt is 'signed' with keys #3 has not specified (its own reviewer caught this); #9's grant list enumerates `DV.Secrets` as a grantable surface, but NEW_SPEC.md mentions DV.Secrets exactly once (line 2556, in a payments example), so the grant names would be baked in before #3 fixes them. #3 must be drafted before all three, not with them.

- Four items independently extend the sensitive-field exclusion list, each in its own section: #2 adds the on-device local store, #7 adds span names/attributes, #8 adds `--json` output and MCP tool results, #4 adds the PII-vs-sensitive distinction. CLAUDE.md's enumerated list (logs, AI context, traces, analytics, public serialization, search, model pages, tables, admin) becomes authoritative in five places at once. Fix: one amendment to the Sensitive Model Fields section (NEW_SPEC.md:3004-3016) defining the surface set normatively, with #2/#4/#7/#8 cross-referencing it. #4 additionally needs the stacking rule stated there (PII drives erasure/export membership, sensitivity drives exposure redaction; a field can be both).

- #4's audit log and #7's traces are on a collision course that neither reviewer could see: both record actor, tenant, timestamp, and operation over the same data-access paths, and #7's own amendment mandates head-based sampling on by default. If the audit log is implemented as a trace consumer — the obvious economy — sampling silently drops compliance-relevant access events. Fix: #4's section must state that the audit log is a durable, unsampled, tamper-evident record and is explicitly NOT the trace exporter, while allowing an audit event to carry the ambient trace ID for correlation.

- #1 and #5 both amend the OTA section and produce an unstated interaction: #1 makes the protocol compatibility window the authority on whether a client may talk to production, while #5 lets a flag select the Shorebird channel a device pulls from. A flag can therefore route a device to a bundle whose protocol version is outside #1's window, and #5's own amendment already forbids rollback from depending on flag evaluation. Fix: state precedence explicitly in whichever section lands second — the protocol window is a hard gate evaluated before channel selection, flags are a soft selector inside it.

- Three items add generated read-only signal families under DV.* citing the same DV.lifecycle precedent: #1's protocol state, #2's `order.syncState` / `Order.pendingMutations`, #5's per-flag `DV.Flags.<name>.enabled`. Individually correct, collectively they re-justify the same rule three times. Fix: add one CLAUDE.md shape rule ('framework-owned state is exposed as generated read-only signals; application code observes, never assigns') in the same pass, and let all three cite it.

- CLI surface expansion is unmanaged across seven items: #1 (compatibility-check modes), #4 (`dartvel db backup|restore`), #5 (a `dartvel analyze` stale-flag rule), #7 (replacing the `dartvel traces` stub), #8 (`dartvel inspect` family + `dartvel mcp`), #9 (`dartvel module init|publish|verify|grants`, plus deprecating the existing hardcoded `dartvel plugin auth|analytics`), #10 (`dartvel spec status --check`). The Bun-inspired tooling rule requires one discoverable surface. Fix: one CLI-surface pass decides the groups (`db`, `module`, `inspect`, `spec`, `mcp`) and the fate of `dartvel plugin` before any individual section names a verb.

- Three items extend the `@DVModel` annotation namespace in the same window — #2's class-level `offline:`, #4's `@DVModel.piiField(...)`, #6's `@DVModel.imageField(...)` — and two of them (#4, #6) arrived proposing a nonexistent standalone `@DVField`, which the codebase already deprecated once (annotations.dart:269-289). No name collides, but the field-annotation catalog at NEW_SPEC.md:2876-2879 enumerates the permitted set and must be updated once with all three rather than three times. #2 and #4 also both touch at-rest encryption (`DVOffline(encrypt:)`, crypto-shredding via `sensitiveField(encrypted: true)`), so the encryption seam must be defined once, in #3.

### Placement corrections

- #7 Distributed Tracing — wrong placement, and the most consequential of the set. Proposed as a new top-level section after Monitoring and Observability; it must be a `## Distributed tracing` subsection INSIDE Monitoring and Observability (NEW_SPEC.md:1581-1597), whose 'Traces' and 'OpenTelemetry' built-in bullets must be rewritten in place to point at it. A sibling section leaves Monitoring still claiming tracing as a built-in while the contract lives next door — the exact fragmentation the mail-into-Notifications and authorization-into-DV.Auth rules exist to prevent. The API must likewise sit on the existing `DV.ObservabilityAndLogging`, not a new `DV.Tracing` namespace.

- #9 Module Distribution and Trust — placement too weak. Its own reviewer asked only for a forward reference from the Modules section's `federated` bullet, but NEW_SPEC.md:2765-2775 already specifies a signed module manifest verified before integration (for `federated` only) and NEW_SPEC.md:2753 already names `DV.Modules.<id>.manifest`. The manifest must be DEFINED once inside the Modules section for all four deployment modes, with the trust/grant material as a subsection there; a standalone trust section elsewhere leaves two manifest definitions in the document. The `grants:` axis must also be registered next to the existing capability metadata at NEW_SPEC.md:3426-3430 with the collision called out in the text.

- #10 Status labels — placement unstated in the proposal and it matters. The convention paragraph belongs adjacent to the spec's own scope rule at NEW_SPEC.md:3499-3502, which it directly modifies (that rule is why a linear ladder ending in `Implemented` is wrong), not as a trailing section. The per-section markup then applies to the 71 h1 sections with h2 inheritance, and the machine-readable index lives at docs/spec-status.json.

- #4 Data Compliance and Lifecycle — the section placement after Multi-tenancy is right, but the item spans three homes and the draft must edit all three rather than centralize. `@DVModel.piiField(retention:)` belongs in the field-annotation catalog at NEW_SPEC.md:2876-2879 alongside sensitiveField/searchableField/featuredImage; the PII-vs-sensitive stacking rule belongs in the Sensitive Model Fields section at 3004-3016; `dartvel db backup|restore` joins the existing db command group rather than being invented inside the compliance section.

- #2 Offline-First Models — the new section must sit adjacent to Model Sync and Presence (which specs only the connected case), not near PWA, and the four existing scattered mentions (PWA 'Offline support' and 'Background sync', the two embedded-target bullets) must be rewritten in place to cross-reference it. Leaving them as-is gives the spec five uncoordinated statements about offline behavior.

- #6 Media Pipeline — after File Storage is correct, but two existing passages must be edited in place rather than duplicated: the model-page favicon derivative at NEW_SPEC.md:2858-2861 becomes a generated variant of this pipeline (same content-hashing and caching), and the 'uncompressed large model images' diagnostic at line 3458 must link to variant declaration as its fix. The `@DVModel.imageField(...)` annotation also registers in the field-annotation catalog at 2876-2879.

- #5 Feature Flags — the new section is fine, but the middleware bullet at NEW_SPEC.md:957 ('feature flags and experiments') must be rewritten in place to name the generated featureFlags middleware as the enforcement point of DV.Flags, and the OTA section (1458-1471) must gain the boundary sentence. Otherwise the spec keeps a bullet that reads as an independent stringly-typed feature alongside the typed one.

- #1 Protocol Versioning — placement after OTA Updates is right, but the draft must edit the OTA section's existing 'minimum supported app versions' and 'forced update prompts' text (lines 1461-1462) in place to derive from the compatibility window, and must update BOTH existing `dartvel compatibility-check` occurrences (NEW_SPEC.md:2523 and 3445). Appending a section without touching those leaves two independent min-version mechanisms and two meanings of one command.

- #8 AI-Native Tooling — must not be a new standalone AI-tooling section. The inspector family is already enumerated in prose at NEW_SPEC.md:3406-3421 (including the unbacked `dartvel explain DV001`), so the graph/`--json`/diagnostic-code contract belongs there, edited in place; the framework-vs-application MCP registry separation belongs in the AI tools section at 1504-1548 where `@DVAITool` opt-in and `@DVAIHidden()` are already defined.

### Claims in this document that verification falsified

Recorded because they changed the sequencing:

- **#10's premise.** `NEW_SPEC.md` contains zero occurrences of "Proposal" and
  no `DVPlatformMemory` section exists anywhere in the repo. There is no
  improvised label to formalize, so the item stands on its own merits rather
  than as codification of existing practice.
- **#8's sequencing note** claims `--json` can land early "since inspectors
  already exist". `dartvel inspect` is not a registered command — the CLI
  registers 25 commands and the only `inspect` is `cache inspect`. The eight
  inspectors at `NEW_SPEC.md:3406-3424` are described in flat present tense and
  none is built.
- **#4 and #6 both propose `@DVField`,** which exists nowhere in the spec, in
  `CLAUDE.md`, or in `packages/` — only inside this document. The codebase
  already deprecated a standalone field annotation once.
- **#9's "existing platform-capability manifest"** is a flat, app-level,
  unvalidated `dartvel: permissions:` list, not the per-module capability
  system the item builds on.
